#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL:-http://localhost:8080}"
KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}"
REALM_NAME="${REALM_NAME:-galaxium}"
CLIENT_ID="${CLIENT_ID:-web-app-proxy}"

EXPECTED_REDIRECT_1="${EXPECTED_REDIRECT_1:-http://localhost:6274/oauth/callback}"
EXPECTED_REDIRECT_2="${EXPECTED_REDIRECT_2:-http://localhost:6274/oauth/callback/debug}"
EXPECTED_REDIRECT_3="${EXPECTED_REDIRECT_3:-http://127.0.0.1:6274/oauth/callback}"
EXPECTED_REDIRECT_4="${EXPECTED_REDIRECT_4:-http://127.0.0.1:6274/oauth/callback/debug}"
EXPECTED_ORIGIN_1="${EXPECTED_ORIGIN_1:-http://localhost:6274}"
EXPECTED_ORIGIN_2="${EXPECTED_ORIGIN_2:-http://127.0.0.1:6274}"

TMP_ADMIN_TOKEN_BODY="/tmp/galaxium_keycloak_admin_token_sync.json"
TMP_CLIENT_LIST_BODY="/tmp/galaxium_keycloak_client_list_sync.json"
TMP_CLIENT_BODY="/tmp/galaxium_keycloak_client_body_sync.json"
TMP_CLIENT_PATCHED_BODY="/tmp/galaxium_keycloak_client_body_sync_patched.json"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: required command '${command_name}' is not available."
    exit 1
  fi
}

require_command curl
require_command jq

echo "Checking Keycloak availability..."
if ! curl -sf "${KEYCLOAK_BASE_URL}/realms/${REALM_NAME}/.well-known/openid-configuration" >/dev/null; then
  echo "ERROR: Keycloak realm '${REALM_NAME}' is not reachable at ${KEYCLOAK_BASE_URL}"
  exit 1
fi
echo "OK: Keycloak realm endpoint is reachable"

echo "Fetching admin access token..."
ADMIN_TOKEN_STATUS="$(
  curl -s -o "${TMP_ADMIN_TOKEN_BODY}" -w '%{http_code}' \
    -X POST "${KEYCLOAK_BASE_URL}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    -d "username=${KEYCLOAK_ADMIN_USER}" \
    -d "password=${KEYCLOAK_ADMIN_PASSWORD}"
)"

if [[ "${ADMIN_TOKEN_STATUS}" != "200" ]]; then
  echo "ERROR: failed to retrieve Keycloak admin token (HTTP ${ADMIN_TOKEN_STATUS})"
  cat "${TMP_ADMIN_TOKEN_BODY}"
  exit 1
fi

ADMIN_TOKEN="$(jq -r '.access_token // empty' "${TMP_ADMIN_TOKEN_BODY}")"
if [[ -z "${ADMIN_TOKEN}" ]]; then
  echo "ERROR: admin access token missing in response"
  cat "${TMP_ADMIN_TOKEN_BODY}"
  exit 1
fi
echo "OK: admin token acquired"

echo "Resolving client '${CLIENT_ID}' in realm '${REALM_NAME}'..."
CLIENT_LIST_STATUS="$(
  curl -s -o "${TMP_CLIENT_LIST_BODY}" -w '%{http_code}' \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_BASE_URL}/admin/realms/${REALM_NAME}/clients?clientId=${CLIENT_ID}"
)"

if [[ "${CLIENT_LIST_STATUS}" != "200" ]]; then
  echo "ERROR: failed to query clients (HTTP ${CLIENT_LIST_STATUS})"
  cat "${TMP_CLIENT_LIST_BODY}"
  exit 1
fi

INTERNAL_CLIENT_ID="$(jq -r '.[0].id // empty' "${TMP_CLIENT_LIST_BODY}")"
if [[ -z "${INTERNAL_CLIENT_ID}" ]]; then
  echo "ERROR: client '${CLIENT_ID}' not found in realm '${REALM_NAME}'"
  cat "${TMP_CLIENT_LIST_BODY}"
  exit 1
fi
echo "OK: found client internal id ${INTERNAL_CLIENT_ID}"

CLIENT_STATUS="$(
  curl -s -o "${TMP_CLIENT_BODY}" -w '%{http_code}' \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_BASE_URL}/admin/realms/${REALM_NAME}/clients/${INTERNAL_CLIENT_ID}"
)"

if [[ "${CLIENT_STATUS}" != "200" ]]; then
  echo "ERROR: failed to fetch client config (HTTP ${CLIENT_STATUS})"
  cat "${TMP_CLIENT_BODY}"
  exit 1
fi

jq \
  --arg r1 "${EXPECTED_REDIRECT_1}" \
  --arg r2 "${EXPECTED_REDIRECT_2}" \
  --arg r3 "${EXPECTED_REDIRECT_3}" \
  --arg r4 "${EXPECTED_REDIRECT_4}" \
  --arg o1 "${EXPECTED_ORIGIN_1}" \
  --arg o2 "${EXPECTED_ORIGIN_2}" \
  '
  .standardFlowEnabled = true
  | .directAccessGrantsEnabled = true
  | .publicClient = false
  | .protocol = "openid-connect"
  | .serviceAccountsEnabled = true
  | .redirectUris = (((.redirectUris // []) + [$r1,$r2,$r3,$r4]) | unique)
  | .webOrigins = (((.webOrigins // []) + [$o1,$o2]) | unique)
  ' "${TMP_CLIENT_BODY}" > "${TMP_CLIENT_PATCHED_BODY}"

UPDATE_STATUS="$(
  curl -s -o /tmp/galaxium_keycloak_client_update_sync.out -w '%{http_code}' \
    -X PUT "${KEYCLOAK_BASE_URL}/admin/realms/${REALM_NAME}/clients/${INTERNAL_CLIENT_ID}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "@${TMP_CLIENT_PATCHED_BODY}"
)"

if [[ "${UPDATE_STATUS}" != "204" ]]; then
  echo "ERROR: failed to update client config (HTTP ${UPDATE_STATUS})"
  cat /tmp/galaxium_keycloak_client_update_sync.out
  exit 1
fi

echo "PASS: Keycloak client '${CLIENT_ID}' synchronized for Inspector OAuth flow."
echo "Next: run 'bash verify-keycloak-inspector-client.sh' to confirm."

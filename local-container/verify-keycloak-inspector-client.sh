#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL:-http://localhost:8080}"
KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}"
REALM_NAME="${REALM_NAME:-galaxium}"
CLIENT_ID="${CLIENT_ID:-web-app-proxy}"
EXPECTED_CLIENT_SECRET="${EXPECTED_CLIENT_SECRET:-web-app-proxy-secret}"

EXPECTED_REDIRECT_1="${EXPECTED_REDIRECT_1:-http://localhost:6274/oauth/callback}"
EXPECTED_REDIRECT_2="${EXPECTED_REDIRECT_2:-http://localhost:6274/oauth/callback/debug}"
EXPECTED_REDIRECT_3="${EXPECTED_REDIRECT_3:-http://127.0.0.1:6274/oauth/callback}"
EXPECTED_REDIRECT_4="${EXPECTED_REDIRECT_4:-http://127.0.0.1:6274/oauth/callback/debug}"
EXPECTED_ORIGIN_1="${EXPECTED_ORIGIN_1:-http://localhost:6274}"
EXPECTED_ORIGIN_2="${EXPECTED_ORIGIN_2:-http://127.0.0.1:6274}"

TMP_ADMIN_TOKEN_BODY="/tmp/galaxium_keycloak_admin_token.json"
TMP_CLIENT_LIST_BODY="/tmp/galaxium_keycloak_client_list.json"
TMP_CLIENT_BODY="/tmp/galaxium_keycloak_client_body.json"
TMP_CLIENT_SECRET_BODY="/tmp/galaxium_keycloak_client_secret.json"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: required command '${command_name}' is not available."
    exit 1
  fi
}

assert_json_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "ERROR: ${label} expected '${expected}' but got '${actual}'"
    exit 1
  fi
  echo "OK: ${label} = ${actual}"
}

assert_json_contains() {
  local value="$1"
  local jq_filter="$2"
  local file="$3"
  local label="$4"
  if ! jq -e --arg v "${value}" "${jq_filter}" "${file}" >/dev/null; then
    echo "ERROR: ${label} missing expected value: ${value}"
    echo "Current payload:"
    cat "${file}"
    exit 1
  fi
  echo "OK: ${label} contains ${value}"
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
curl -s -o "${TMP_ADMIN_TOKEN_BODY}" -w '%{http_code}' \
  -X POST "${KEYCLOAK_BASE_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=${KEYCLOAK_ADMIN_USER}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" >/tmp/galaxium_admin_token_status.txt

ADMIN_TOKEN_STATUS="$(cat /tmp/galaxium_admin_token_status.txt)"
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

CLIENT_SECRET_STATUS="$(
  curl -s -o "${TMP_CLIENT_SECRET_BODY}" -w '%{http_code}' \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_BASE_URL}/admin/realms/${REALM_NAME}/clients/${INTERNAL_CLIENT_ID}/client-secret"
)"
if [[ "${CLIENT_SECRET_STATUS}" != "200" ]]; then
  echo "ERROR: failed to fetch client secret (HTTP ${CLIENT_SECRET_STATUS})"
  cat "${TMP_CLIENT_SECRET_BODY}"
  exit 1
fi

STANDARD_FLOW_ENABLED="$(jq -r '.standardFlowEnabled' "${TMP_CLIENT_BODY}")"
DIRECT_ACCESS_ENABLED="$(jq -r '.directAccessGrantsEnabled' "${TMP_CLIENT_BODY}")"
PUBLIC_CLIENT="$(jq -r '.publicClient' "${TMP_CLIENT_BODY}")"
PROTOCOL="$(jq -r '.protocol' "${TMP_CLIENT_BODY}")"
CLIENT_SECRET_VALUE="$(jq -r '.value // empty' "${TMP_CLIENT_SECRET_BODY}")"

assert_json_equals "true" "${STANDARD_FLOW_ENABLED}" "standardFlowEnabled"
assert_json_equals "true" "${DIRECT_ACCESS_ENABLED}" "directAccessGrantsEnabled"
assert_json_equals "false" "${PUBLIC_CLIENT}" "publicClient"
assert_json_equals "openid-connect" "${PROTOCOL}" "protocol"

if [[ "${CLIENT_SECRET_VALUE}" != "${EXPECTED_CLIENT_SECRET}" ]]; then
  echo "ERROR: client secret mismatch for '${CLIENT_ID}'"
  echo "Expected: ${EXPECTED_CLIENT_SECRET}"
  echo "Actual:   ${CLIENT_SECRET_VALUE}"
  echo
  echo "Recovery (local dev):"
  echo "  docker compose -f docker_compose.yaml down"
  echo "  docker compose -f docker_compose.yaml up -d --force-recreate keycloak web_app booking_system booking_system_mcp"
  echo "  bash verify-keycloak-inspector-client.sh"
  exit 1
fi
echo "OK: client secret matches expected value"

assert_json_contains "${EXPECTED_REDIRECT_1}" '(.redirectUris // []) | index($v) != null' "${TMP_CLIENT_BODY}" "redirectUris"
assert_json_contains "${EXPECTED_REDIRECT_2}" '(.redirectUris // []) | index($v) != null' "${TMP_CLIENT_BODY}" "redirectUris"
assert_json_contains "${EXPECTED_REDIRECT_3}" '(.redirectUris // []) | index($v) != null' "${TMP_CLIENT_BODY}" "redirectUris"
assert_json_contains "${EXPECTED_REDIRECT_4}" '(.redirectUris // []) | index($v) != null' "${TMP_CLIENT_BODY}" "redirectUris"
assert_json_contains "${EXPECTED_ORIGIN_1}" '(.webOrigins // []) | index($v) != null' "${TMP_CLIENT_BODY}" "webOrigins"
assert_json_contains "${EXPECTED_ORIGIN_2}" '(.webOrigins // []) | index($v) != null' "${TMP_CLIENT_BODY}" "webOrigins"

echo
echo "PASS: Keycloak client '${CLIENT_ID}' is ready for MCP Inspector OAuth flow."

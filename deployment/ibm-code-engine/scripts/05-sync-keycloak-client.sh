#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_command ibmcloud
require_command curl
require_command jq
require_var KEYCLOAK_APP_NAME
require_var KEYCLOAK_REALM
require_var KEYCLOAK_ADMIN_USER
require_var KEYCLOAK_ADMIN_PASSWORD
require_var OIDC_CLIENT_ID
require_var WEB_APP_NAME
require_var WEB_APP_MCP_APP_NAME

if [[ "${STACK_AUTH_MODE}" != "oauth2" ]]; then
  echo "Skipping Keycloak client sync because STACK_AUTH_MODE=${STACK_AUTH_MODE}."
  exit 0
fi

if [[ -n "${KEYCLOAK_BASE_URL_OVERRIDE:-}" ]]; then
  echo "Skipping Keycloak client sync because KEYCLOAK_BASE_URL_OVERRIDE is set."
  echo "If you use an external Keycloak, update the client redirect URIs and web origins there."
  exit 0
fi

select_project

keycloak_url="$(resolve_keycloak_base_url)"
web_url="$(ce_app_url "${WEB_APP_NAME}")"
web_mcp_url="$(ce_app_url "${WEB_APP_MCP_APP_NAME}")"

echo "Waiting for Keycloak realm endpoints..."
wait_for_http_ok "${keycloak_url}/realms/master/.well-known/openid-configuration"
wait_for_http_ok "${keycloak_url}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration"

admin_token="$(
  curl -fsS -X POST "${keycloak_url}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "client_id=admin-cli" \
    --data-urlencode "username=${KEYCLOAK_ADMIN_USER}" \
    --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}" | jq -r '.access_token // empty'
)"

if [[ -z "${admin_token}" ]]; then
  echo "ERROR: failed to acquire a Keycloak admin token."
  exit 1
fi

client_payload="$(
  curl -fsS "${keycloak_url}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${OIDC_CLIENT_ID}" \
    -H "Authorization: Bearer ${admin_token}"
)"

client_count="$(printf '%s' "${client_payload}" | jq 'length')"
if [[ "${client_count}" != "1" ]]; then
  echo "ERROR: expected exactly one Keycloak client for clientId=${OIDC_CLIENT_ID}, got ${client_count}."
  exit 1
fi

client_id="$(printf '%s' "${client_payload}" | jq -r '.[0].id')"

updated_client="$(
  printf '%s' "${client_payload}" | jq \
    --arg web_url "${web_url}" \
    --arg web_mcp_url "${web_mcp_url}" \
    '
      .[0]
      | .redirectUris = (((.redirectUris // []) + [$web_url + "/*", $web_mcp_url + "/*"]) | unique)
      | .webOrigins = (((.webOrigins // []) + [$web_url, $web_mcp_url]) | unique)
    '
)"

curl -fsS -X PUT "${keycloak_url}/admin/realms/${KEYCLOAK_REALM}/clients/${client_id}" \
  -H "Authorization: Bearer ${admin_token}" \
  -H "Content-Type: application/json" \
  -d "${updated_client}" >/dev/null

echo "Updated Keycloak client '${OIDC_CLIENT_ID}' with Code Engine UI URLs."
echo "REST Web UI origin: ${web_url}"
echo "MCP Web UI origin:  ${web_mcp_url}"

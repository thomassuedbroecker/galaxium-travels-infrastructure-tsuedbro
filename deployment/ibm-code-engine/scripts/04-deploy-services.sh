#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_command ibmcloud
require_var KEYCLOAK_APP_NAME
require_var HR_APP_NAME
require_var BOOKING_API_APP_NAME
require_var MCP_APP_NAME
require_var WEB_APP_NAME
require_var KEYCLOAK_REALM
require_var OIDC_AUDIENCE
require_var OIDC_CLIENT_ID
require_var OIDC_SCOPE
require_var WEB_APP_SECRET_NAME
require_var SERVICE_CPU
require_var SERVICE_MEMORY
require_var SERVICE_MIN_SCALE
require_var SERVICE_MAX_SCALE
require_var WEB_CPU
require_var WEB_MEMORY
require_var WEB_MIN_SCALE
require_var WEB_MAX_SCALE

select_project

keycloak_url="$(ce_app_url "${KEYCLOAK_APP_NAME}")"
keycloak_realm_url="${keycloak_url}/realms/${KEYCLOAK_REALM}"
jwks_url="${keycloak_realm_url}/protocol/openid-connect/certs"
token_url="${keycloak_realm_url}/protocol/openid-connect/token"

set_build_args "HR_database"
hr_args=(
  "${BUILD_ARGS[@]}"
  --port 8081
  --cpu "${SERVICE_CPU}"
  --memory "${SERVICE_MEMORY}"
  --min-scale "${SERVICE_MIN_SCALE}"
  --max-scale "${SERVICE_MAX_SCALE}"
  --visibility public
)
if [[ -n "${HR_DATA_STORE_NAME:-}" ]]; then
  hr_args+=(--mount-data-store "/app/data=${HR_DATA_STORE_NAME}")
fi
ce_upsert_application "${HR_APP_NAME}" "${hr_args[@]}"

set_build_args "booking_system_rest"
rest_args=(
  "${BUILD_ARGS[@]}"
  --port 8082
  --cpu "${SERVICE_CPU}"
  --memory "${SERVICE_MEMORY}"
  --min-scale "${SERVICE_MIN_SCALE}"
  --max-scale "${SERVICE_MAX_SCALE}"
  --visibility public
  --env AUTH_ENABLED=true
  --env "OIDC_ISSUER=${keycloak_realm_url}"
  --env "OIDC_AUDIENCE=${OIDC_AUDIENCE}"
  --env "OIDC_JWKS_URL=${jwks_url}"
)
ce_upsert_application "${BOOKING_API_APP_NAME}" "${rest_args[@]}"
booking_api_url="$(ce_app_url "${BOOKING_API_APP_NAME}")"

set_build_args "booking_system_mcp"
mcp_args=(
  "${BUILD_ARGS[@]}"
  --port 8084
  --cpu "${SERVICE_CPU}"
  --memory "${SERVICE_MEMORY}"
  --min-scale "${SERVICE_MIN_SCALE}"
  --max-scale "${SERVICE_MAX_SCALE}"
  --visibility public
  --env AUTH_ENABLED=true
  --env "OIDC_ISSUER=${keycloak_realm_url}"
  --env "OIDC_AUDIENCE=${OIDC_AUDIENCE}"
  --env "OIDC_JWKS_URL=${jwks_url}"
  --env "OIDC_AUTHORIZATION_SERVER_URL=${keycloak_realm_url}"
)
ce_upsert_application "${MCP_APP_NAME}" "${mcp_args[@]}"
mcp_url="$(ce_app_url "${MCP_APP_NAME}")"
ibmcloud ce application update --name "${MCP_APP_NAME}" --env "MCP_PUBLIC_BASE_URL=${mcp_url}" >/dev/null

set_build_args "galaxium-booking-web-app"
web_args=(
  "${BUILD_ARGS[@]}"
  --port 8083
  --cpu "${WEB_CPU}"
  --memory "${WEB_MEMORY}"
  --min-scale "${WEB_MIN_SCALE}"
  --max-scale "${WEB_MAX_SCALE}"
  --visibility public
  --env "BACKEND_URL=${booking_api_url}"
  --env OAUTH2_ENABLED=true
  --env FRONTEND_AUTH_REQUIRED=true
  --env "OIDC_TOKEN_URL=${token_url}"
  --env "OIDC_CLIENT_ID=${OIDC_CLIENT_ID}"
  --env "OIDC_SCOPE=${OIDC_SCOPE}"
  --env-from-secret "${WEB_APP_SECRET_NAME}"
)
ce_upsert_application "${WEB_APP_NAME}" "${web_args[@]}"
web_url="$(ce_app_url "${WEB_APP_NAME}")"

echo "Keycloak:    ${keycloak_url}"
echo "HR API:      $(ce_app_url "${HR_APP_NAME}")"
echo "Booking API: ${booking_api_url}"
echo "MCP API:     ${mcp_url}"
echo "Web UI:      ${web_url}"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_command ibmcloud
require_var HR_APP_NAME
require_var BOOKING_API_APP_NAME
require_var MCP_APP_NAME
require_var WEB_APP_NAME
require_var WEB_APP_MCP_APP_NAME
require_var SERVICE_CPU
require_var SERVICE_MEMORY
require_var SERVICE_MIN_SCALE
require_var SERVICE_MAX_SCALE
require_var WEB_CPU
require_var WEB_MEMORY
require_var WEB_MIN_SCALE
require_var WEB_MAX_SCALE
require_var WEB_APP_SECRET_NAME
require_var MCP_TIMEOUT_SECONDS

if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  require_var KEYCLOAK_APP_NAME
  require_var KEYCLOAK_REALM
  require_var OIDC_AUDIENCE
  require_var OIDC_CLIENT_ID
  require_var OIDC_SCOPE
else
  require_var BASIC_AUTH_SECRET_NAME
fi

select_project

deploy_hr_api() {
  set_build_args "HR_database"
  local hr_args=(
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
}

deploy_booking_api_oauth2() {
  local keycloak_realm_url="$1"
  local jwks_url="$2"

  set_build_args "booking_system_rest"
  ce_upsert_application "${BOOKING_API_APP_NAME}" \
    "${BUILD_ARGS[@]}" \
    --port 8082 \
    --cpu "${SERVICE_CPU}" \
    --memory "${SERVICE_MEMORY}" \
    --min-scale "${SERVICE_MIN_SCALE}" \
    --max-scale "${SERVICE_MAX_SCALE}" \
    --visibility public \
    --env AUTH_MODE=oauth2 \
    --env "OIDC_ISSUER=${keycloak_realm_url}" \
    --env "OIDC_AUDIENCE=${OIDC_AUDIENCE}" \
    --env "OIDC_JWKS_URL=${jwks_url}"
}

deploy_booking_api_basic() {
  set_build_args "booking_system_rest"
  ce_upsert_application "${BOOKING_API_APP_NAME}" \
    "${BUILD_ARGS[@]}" \
    --port 8082 \
    --cpu "${SERVICE_CPU}" \
    --memory "${SERVICE_MEMORY}" \
    --min-scale "${SERVICE_MIN_SCALE}" \
    --max-scale "${SERVICE_MAX_SCALE}" \
    --visibility public \
    --env AUTH_MODE=basic \
    --env-from-secret "${BASIC_AUTH_SECRET_NAME}"
}

deploy_mcp_api_oauth2() {
  local keycloak_realm_url="$1"
  local jwks_url="$2"

  set_build_args "booking_system_mcp"
  ce_upsert_application "${MCP_APP_NAME}" \
    "${BUILD_ARGS[@]}" \
    --port 8084 \
    --cpu "${SERVICE_CPU}" \
    --memory "${SERVICE_MEMORY}" \
    --min-scale "${SERVICE_MIN_SCALE}" \
    --max-scale "${SERVICE_MAX_SCALE}" \
    --visibility public \
    --env AUTH_MODE=oauth2 \
    --env "OIDC_ISSUER=${keycloak_realm_url}" \
    --env "OIDC_AUDIENCE=${OIDC_AUDIENCE}" \
    --env "OIDC_JWKS_URL=${jwks_url}" \
    --env "OIDC_AUTHORIZATION_SERVER_URL=${keycloak_realm_url}"
}

deploy_mcp_api_basic() {
  set_build_args "booking_system_mcp"
  ce_upsert_application "${MCP_APP_NAME}" \
    "${BUILD_ARGS[@]}" \
    --port 8084 \
    --cpu "${SERVICE_CPU}" \
    --memory "${SERVICE_MEMORY}" \
    --min-scale "${SERVICE_MIN_SCALE}" \
    --max-scale "${SERVICE_MAX_SCALE}" \
    --visibility public \
    --env AUTH_MODE=basic \
    --env-from-secret "${BASIC_AUTH_SECRET_NAME}"
}

deploy_rest_ui_oauth2() {
  local booking_api_url="$1"
  local token_url="$2"

  set_build_args "galaxium-booking-web-app"
  ce_upsert_application "${WEB_APP_NAME}" \
    "${BUILD_ARGS[@]}" \
    --port 8083 \
    --cpu "${WEB_CPU}" \
    --memory "${WEB_MEMORY}" \
    --min-scale "${WEB_MIN_SCALE}" \
    --max-scale "${WEB_MAX_SCALE}" \
    --visibility public \
    --env "BACKEND_URL=${booking_api_url}" \
    --env BACKEND_AUTH_MODE=oauth2 \
    --env "FRONTEND_AUTH_REQUIRED=${FRONTEND_AUTH_REQUIRED_RESOLVED}" \
    --env "OIDC_TOKEN_URL=${token_url}" \
    --env "OIDC_CLIENT_ID=${OIDC_CLIENT_ID}" \
    --env "OIDC_SCOPE=${OIDC_SCOPE}" \
    --env-from-secret "${WEB_APP_SECRET_NAME}"
}

deploy_rest_ui_basic() {
  local booking_api_url="$1"

  set_build_args "galaxium-booking-web-app"
  ce_upsert_application "${WEB_APP_NAME}" \
    "${BUILD_ARGS[@]}" \
    --port 8083 \
    --cpu "${WEB_CPU}" \
    --memory "${WEB_MEMORY}" \
    --min-scale "${WEB_MIN_SCALE}" \
    --max-scale "${WEB_MAX_SCALE}" \
    --visibility public \
    --env "BACKEND_URL=${booking_api_url}" \
    --env BACKEND_AUTH_MODE=basic \
    --env FRONTEND_AUTH_REQUIRED=false \
    --env-from-secret "${WEB_APP_SECRET_NAME}" \
    --env-from-secret "${BASIC_AUTH_SECRET_NAME}"
}

deploy_mcp_ui_oauth2() {
  local mcp_base_url="$1"
  local token_url="$2"

  set_build_args "galaxium-booking-web-app-mcp"
  ce_upsert_application "${WEB_APP_MCP_APP_NAME}" \
    "${BUILD_ARGS[@]}" \
    --port 8085 \
    --cpu "${WEB_CPU}" \
    --memory "${WEB_MEMORY}" \
    --min-scale "${WEB_MIN_SCALE}" \
    --max-scale "${WEB_MAX_SCALE}" \
    --visibility public \
    --env PORT=8085 \
    --env "MCP_SERVER_URL=${mcp_base_url}/mcp" \
    --env "MCP_TIMEOUT_SECONDS=${MCP_TIMEOUT_SECONDS}" \
    --env BACKEND_AUTH_MODE=oauth2 \
    --env "FRONTEND_AUTH_REQUIRED=${FRONTEND_AUTH_REQUIRED_RESOLVED}" \
    --env "OIDC_TOKEN_URL=${token_url}" \
    --env "OIDC_CLIENT_ID=${OIDC_CLIENT_ID}" \
    --env "OIDC_SCOPE=${OIDC_SCOPE}" \
    --env-from-secret "${WEB_APP_SECRET_NAME}"
}

deploy_mcp_ui_basic() {
  local mcp_base_url="$1"

  set_build_args "galaxium-booking-web-app-mcp"
  ce_upsert_application "${WEB_APP_MCP_APP_NAME}" \
    "${BUILD_ARGS[@]}" \
    --port 8085 \
    --cpu "${WEB_CPU}" \
    --memory "${WEB_MEMORY}" \
    --min-scale "${WEB_MIN_SCALE}" \
    --max-scale "${WEB_MAX_SCALE}" \
    --visibility public \
    --env PORT=8085 \
    --env "MCP_SERVER_URL=${mcp_base_url}/mcp" \
    --env "MCP_TIMEOUT_SECONDS=${MCP_TIMEOUT_SECONDS}" \
    --env BACKEND_AUTH_MODE=basic \
    --env FRONTEND_AUTH_REQUIRED=false \
    --env-from-secret "${WEB_APP_SECRET_NAME}" \
    --env-from-secret "${BASIC_AUTH_SECRET_NAME}"
}

echo "Phase 1: deploy application backends"
deploy_hr_api

if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  keycloak_url="$(resolve_keycloak_base_url)"
  keycloak_realm_url="${keycloak_url}/realms/${KEYCLOAK_REALM}"
  jwks_url="${keycloak_realm_url}/protocol/openid-connect/certs"
  token_url="${keycloak_realm_url}/protocol/openid-connect/token"

  deploy_booking_api_oauth2 "${keycloak_realm_url}" "${jwks_url}"
  booking_api_url="$(ce_app_url "${BOOKING_API_APP_NAME}")"

  deploy_mcp_api_oauth2 "${keycloak_realm_url}" "${jwks_url}"
  mcp_base_url="$(ce_app_url "${MCP_APP_NAME}")"
  ibmcloud ce application update \
    --name "${MCP_APP_NAME}" \
    --env "MCP_PUBLIC_BASE_URL=${mcp_base_url}" >/dev/null

  echo "Phase 2: deploy web frontends with resolved backend and Keycloak URLs"
  deploy_rest_ui_oauth2 "${booking_api_url}" "${token_url}"
  deploy_mcp_ui_oauth2 "${mcp_base_url}" "${token_url}"
else
  keycloak_url=""

  deploy_booking_api_basic
  booking_api_url="$(ce_app_url "${BOOKING_API_APP_NAME}")"

  deploy_mcp_api_basic
  mcp_base_url="$(ce_app_url "${MCP_APP_NAME}")"
  ibmcloud ce application update \
    --name "${MCP_APP_NAME}" \
    --env "MCP_PUBLIC_BASE_URL=${mcp_base_url}" >/dev/null

  echo "Phase 2: deploy web frontends with resolved backend URLs"
  deploy_rest_ui_basic "${booking_api_url}"
  deploy_mcp_ui_basic "${mcp_base_url}"
fi

web_url="$(ce_app_url "${WEB_APP_NAME}")"
web_mcp_url="$(ce_app_url "${WEB_APP_MCP_APP_NAME}")"
hr_url="$(ce_app_url "${HR_APP_NAME}")"

echo "Stack auth mode: ${STACK_AUTH_MODE}"
if [[ -n "${keycloak_url}" ]]; then
  echo "Keycloak:       ${keycloak_url}"
else
  echo "Keycloak:       not deployed for this mode"
fi
echo "HR API:         ${hr_url}"
echo "Booking API:    ${booking_api_url}"
echo "MCP base URL:   ${mcp_base_url}"
echo "MCP endpoint:   ${mcp_base_url}/mcp"
echo "REST Web UI:    ${web_url}"
echo "MCP Web UI:     ${web_mcp_url}"

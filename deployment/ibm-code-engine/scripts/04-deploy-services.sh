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
require_var BOOKING_API_CONFIGMAP_NAME
require_var MCP_CONFIGMAP_NAME
require_var WEB_APP_CONFIGMAP_NAME
require_var WEB_APP_MCP_CONFIGMAP_NAME
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

if prebuilt_image_mode_enabled; then
  require_prebuilt_image_settings
fi

select_project

deploy_hr_api() {
  set_service_artifact_args "HR_database" "hr"
  local hr_args=(
    "${ARTIFACT_ARGS[@]}"
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

upsert_booking_api_config_oauth2() {
  local keycloak_realm_url="$1"
  local jwks_url="$2"

  ce_upsert_configmap_from_env_lines \
    "${BOOKING_API_CONFIGMAP_NAME}" \
    "AUTH_MODE=oauth2" \
    "OIDC_ISSUER=${keycloak_realm_url}" \
    "OIDC_AUDIENCE=${OIDC_AUDIENCE}" \
    "OIDC_JWKS_URL=${jwks_url}"
}

upsert_booking_api_config_basic() {
  ce_upsert_configmap_from_env_lines \
    "${BOOKING_API_CONFIGMAP_NAME}" \
    "AUTH_MODE=basic"
}

deploy_booking_api_oauth2() {
  local keycloak_realm_url="$1"
  local jwks_url="$2"

  upsert_booking_api_config_oauth2 "${keycloak_realm_url}" "${jwks_url}"
  ce_remove_application_env_keys \
    "${BOOKING_API_APP_NAME}" \
    AUTH_MODE \
    OIDC_ISSUER \
    OIDC_AUDIENCE \
    OIDC_JWKS_URL

  set_service_artifact_args "booking_system_rest" "booking_api"
  ce_upsert_application "${BOOKING_API_APP_NAME}" \
    "${ARTIFACT_ARGS[@]}" \
    --port 8082 \
    --cpu "${SERVICE_CPU}" \
    --memory "${SERVICE_MEMORY}" \
    --min-scale "${SERVICE_MIN_SCALE}" \
    --max-scale "${SERVICE_MAX_SCALE}" \
    --visibility public \
    --env-from-configmap "${BOOKING_API_CONFIGMAP_NAME}"
}

deploy_booking_api_basic() {
  upsert_booking_api_config_basic
  ce_remove_application_env_keys "${BOOKING_API_APP_NAME}" AUTH_MODE

  set_service_artifact_args "booking_system_rest" "booking_api"
  ce_upsert_application "${BOOKING_API_APP_NAME}" \
    "${ARTIFACT_ARGS[@]}" \
    --port 8082 \
    --cpu "${SERVICE_CPU}" \
    --memory "${SERVICE_MEMORY}" \
    --min-scale "${SERVICE_MIN_SCALE}" \
    --max-scale "${SERVICE_MAX_SCALE}" \
    --visibility public \
    --env-from-configmap "${BOOKING_API_CONFIGMAP_NAME}" \
    --env-from-secret "${BASIC_AUTH_SECRET_NAME}"
}

upsert_mcp_api_config_oauth2() {
  local keycloak_realm_url="$1"
  local jwks_url="$2"
  local mcp_public_base_url="${3:-}"
  local env_lines=(
    "AUTH_MODE=oauth2"
    "OIDC_ISSUER=${keycloak_realm_url}"
    "OIDC_AUDIENCE=${OIDC_AUDIENCE}"
    "OIDC_JWKS_URL=${jwks_url}"
    "OIDC_AUTHORIZATION_SERVER_URL=${keycloak_realm_url}"
  )

  if [[ -n "${mcp_public_base_url}" ]]; then
    env_lines+=("MCP_PUBLIC_BASE_URL=${mcp_public_base_url}")
  fi

  ce_upsert_configmap_from_env_lines "${MCP_CONFIGMAP_NAME}" "${env_lines[@]}"
}

upsert_mcp_api_config_basic() {
  local mcp_public_base_url="${1:-}"
  local env_lines=("AUTH_MODE=basic")

  if [[ -n "${mcp_public_base_url}" ]]; then
    env_lines+=("MCP_PUBLIC_BASE_URL=${mcp_public_base_url}")
  fi

  ce_upsert_configmap_from_env_lines "${MCP_CONFIGMAP_NAME}" "${env_lines[@]}"
}

deploy_mcp_api_oauth2() {
  local keycloak_realm_url="$1"
  local jwks_url="$2"
  local mcp_public_base_url="${3:-}"

  upsert_mcp_api_config_oauth2 "${keycloak_realm_url}" "${jwks_url}" "${mcp_public_base_url}"
  ce_remove_application_env_keys \
    "${MCP_APP_NAME}" \
    AUTH_MODE \
    OIDC_ISSUER \
    OIDC_AUDIENCE \
    OIDC_JWKS_URL \
    OIDC_AUTHORIZATION_SERVER_URL \
    MCP_PUBLIC_BASE_URL

  set_service_artifact_args "booking_system_mcp" "mcp_api"
  ce_upsert_application "${MCP_APP_NAME}" \
    "${ARTIFACT_ARGS[@]}" \
    --port 8084 \
    --cpu "${SERVICE_CPU}" \
    --memory "${SERVICE_MEMORY}" \
    --min-scale "${SERVICE_MIN_SCALE}" \
    --max-scale "${SERVICE_MAX_SCALE}" \
    --visibility public \
    --env-from-configmap "${MCP_CONFIGMAP_NAME}"
}

deploy_mcp_api_basic() {
  local mcp_public_base_url="${1:-}"

  upsert_mcp_api_config_basic "${mcp_public_base_url}"
  ce_remove_application_env_keys \
    "${MCP_APP_NAME}" \
    AUTH_MODE \
    MCP_PUBLIC_BASE_URL

  set_service_artifact_args "booking_system_mcp" "mcp_api"
  ce_upsert_application "${MCP_APP_NAME}" \
    "${ARTIFACT_ARGS[@]}" \
    --port 8084 \
    --cpu "${SERVICE_CPU}" \
    --memory "${SERVICE_MEMORY}" \
    --min-scale "${SERVICE_MIN_SCALE}" \
    --max-scale "${SERVICE_MAX_SCALE}" \
    --visibility public \
    --env-from-configmap "${MCP_CONFIGMAP_NAME}" \
    --env-from-secret "${BASIC_AUTH_SECRET_NAME}"
}

upsert_rest_ui_config_oauth2() {
  local booking_api_url="$1"
  local token_url="$2"

  ce_upsert_configmap_from_env_lines \
    "${WEB_APP_CONFIGMAP_NAME}" \
    "BACKEND_URL=${booking_api_url}" \
    "BACKEND_AUTH_MODE=oauth2" \
    "FRONTEND_AUTH_REQUIRED=${FRONTEND_AUTH_REQUIRED_RESOLVED}" \
    "OIDC_TOKEN_URL=${token_url}" \
    "OIDC_CLIENT_ID=${OIDC_CLIENT_ID}" \
    "OIDC_SCOPE=${OIDC_SCOPE}"
}

upsert_rest_ui_config_basic() {
  local booking_api_url="$1"

  ce_upsert_configmap_from_env_lines \
    "${WEB_APP_CONFIGMAP_NAME}" \
    "BACKEND_URL=${booking_api_url}" \
    "BACKEND_AUTH_MODE=basic" \
    "FRONTEND_AUTH_REQUIRED=false"
}

deploy_rest_ui_oauth2() {
  local booking_api_url="$1"
  local token_url="$2"

  upsert_rest_ui_config_oauth2 "${booking_api_url}" "${token_url}"
  ce_remove_application_env_keys \
    "${WEB_APP_NAME}" \
    BACKEND_URL \
    BACKEND_AUTH_MODE \
    FRONTEND_AUTH_REQUIRED \
    OIDC_TOKEN_URL \
    OIDC_CLIENT_ID \
    OIDC_SCOPE

  set_service_artifact_args "galaxium-booking-web-app" "web_app"
  ce_upsert_application "${WEB_APP_NAME}" \
    "${ARTIFACT_ARGS[@]}" \
    --port 8083 \
    --cpu "${WEB_CPU}" \
    --memory "${WEB_MEMORY}" \
    --min-scale "${WEB_MIN_SCALE}" \
    --max-scale "${WEB_MAX_SCALE}" \
    --visibility public \
    --env-from-configmap "${WEB_APP_CONFIGMAP_NAME}" \
    --env-from-secret "${WEB_APP_SECRET_NAME}"
}

deploy_rest_ui_basic() {
  local booking_api_url="$1"

  upsert_rest_ui_config_basic "${booking_api_url}"
  ce_remove_application_env_keys \
    "${WEB_APP_NAME}" \
    BACKEND_URL \
    BACKEND_AUTH_MODE \
    FRONTEND_AUTH_REQUIRED

  set_service_artifact_args "galaxium-booking-web-app" "web_app"
  ce_upsert_application "${WEB_APP_NAME}" \
    "${ARTIFACT_ARGS[@]}" \
    --port 8083 \
    --cpu "${WEB_CPU}" \
    --memory "${WEB_MEMORY}" \
    --min-scale "${WEB_MIN_SCALE}" \
    --max-scale "${WEB_MAX_SCALE}" \
    --visibility public \
    --env-from-configmap "${WEB_APP_CONFIGMAP_NAME}" \
    --env-from-secret "${WEB_APP_SECRET_NAME}" \
    --env-from-secret "${BASIC_AUTH_SECRET_NAME}"
}

upsert_mcp_ui_config_oauth2() {
  local mcp_base_url="$1"
  local token_url="$2"

  ce_upsert_configmap_from_env_lines \
    "${WEB_APP_MCP_CONFIGMAP_NAME}" \
    "PORT=8085" \
    "MCP_SERVER_URL=${mcp_base_url}/mcp" \
    "MCP_TIMEOUT_SECONDS=${MCP_TIMEOUT_SECONDS}" \
    "BACKEND_AUTH_MODE=oauth2" \
    "FRONTEND_AUTH_REQUIRED=${FRONTEND_AUTH_REQUIRED_RESOLVED}" \
    "OIDC_TOKEN_URL=${token_url}" \
    "OIDC_CLIENT_ID=${OIDC_CLIENT_ID}" \
    "OIDC_SCOPE=${OIDC_SCOPE}"
}

upsert_mcp_ui_config_basic() {
  local mcp_base_url="$1"

  ce_upsert_configmap_from_env_lines \
    "${WEB_APP_MCP_CONFIGMAP_NAME}" \
    "PORT=8085" \
    "MCP_SERVER_URL=${mcp_base_url}/mcp" \
    "MCP_TIMEOUT_SECONDS=${MCP_TIMEOUT_SECONDS}" \
    "BACKEND_AUTH_MODE=basic" \
    "FRONTEND_AUTH_REQUIRED=false"
}

deploy_mcp_ui_oauth2() {
  local mcp_base_url="$1"
  local token_url="$2"

  upsert_mcp_ui_config_oauth2 "${mcp_base_url}" "${token_url}"
  ce_remove_application_env_keys \
    "${WEB_APP_MCP_APP_NAME}" \
    PORT \
    MCP_SERVER_URL \
    MCP_TIMEOUT_SECONDS \
    BACKEND_AUTH_MODE \
    FRONTEND_AUTH_REQUIRED \
    OIDC_TOKEN_URL \
    OIDC_CLIENT_ID \
    OIDC_SCOPE

  set_service_artifact_args "galaxium-booking-web-app-mcp" "web_app_mcp"
  ce_upsert_application "${WEB_APP_MCP_APP_NAME}" \
    "${ARTIFACT_ARGS[@]}" \
    --port 8085 \
    --cpu "${WEB_CPU}" \
    --memory "${WEB_MEMORY}" \
    --min-scale "${WEB_MIN_SCALE}" \
    --max-scale "${WEB_MAX_SCALE}" \
    --visibility public \
    --env-from-configmap "${WEB_APP_MCP_CONFIGMAP_NAME}" \
    --env-from-secret "${WEB_APP_SECRET_NAME}"
}

deploy_mcp_ui_basic() {
  local mcp_base_url="$1"

  upsert_mcp_ui_config_basic "${mcp_base_url}"
  ce_remove_application_env_keys \
    "${WEB_APP_MCP_APP_NAME}" \
    PORT \
    MCP_SERVER_URL \
    MCP_TIMEOUT_SECONDS \
    BACKEND_AUTH_MODE \
    FRONTEND_AUTH_REQUIRED

  set_service_artifact_args "galaxium-booking-web-app-mcp" "web_app_mcp"
  ce_upsert_application "${WEB_APP_MCP_APP_NAME}" \
    "${ARTIFACT_ARGS[@]}" \
    --port 8085 \
    --cpu "${WEB_CPU}" \
    --memory "${WEB_MEMORY}" \
    --min-scale "${WEB_MIN_SCALE}" \
    --max-scale "${WEB_MAX_SCALE}" \
    --visibility public \
    --env-from-configmap "${WEB_APP_MCP_CONFIGMAP_NAME}" \
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
  deploy_mcp_api_oauth2 "${keycloak_realm_url}" "${jwks_url}" "${mcp_base_url}"

  echo "Phase 2: deploy web frontends with resolved backend and Keycloak URLs"
  deploy_rest_ui_oauth2 "${booking_api_url}" "${token_url}"
  deploy_mcp_ui_oauth2 "${mcp_base_url}" "${token_url}"
else
  keycloak_url=""

  deploy_booking_api_basic
  booking_api_url="$(ce_app_url "${BOOKING_API_APP_NAME}")"

  deploy_mcp_api_basic
  mcp_base_url="$(ce_app_url "${MCP_APP_NAME}")"
  deploy_mcp_api_basic "${mcp_base_url}"

  echo "Phase 2: deploy web frontends with resolved backend URLs"
  deploy_rest_ui_basic "${booking_api_url}"
  deploy_mcp_ui_basic "${mcp_base_url}"
fi

web_url="$(ce_app_url "${WEB_APP_NAME}")"
web_mcp_url="$(ce_app_url "${WEB_APP_MCP_APP_NAME}")"
hr_url="$(ce_app_url "${HR_APP_NAME}")"

echo "Stack auth mode: ${STACK_AUTH_MODE}"
echo "Artifact mode:   ${DEPLOY_ARTIFACT_MODE}"
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

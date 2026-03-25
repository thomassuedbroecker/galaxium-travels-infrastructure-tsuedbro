#!/usr/bin/env bash
set -euo pipefail

# ************************
# Variable definition section
# ************************

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${DEPLOY_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/deploy.env}"
GENERATED_CONFIG_DIR="${DEPLOY_DIR}/generated"

if [[ -t 1 ]]; then
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  BLUE=''
  NC=''
fi

echo -e "\n${BLUE}========================================${NC}"
echo "Running ${BASH_SOURCE[0]} with environment file ${ENV_FILE}"

# ************************
# Environment definition section
# ************************

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: missing environment file: ${ENV_FILE}"
  echo "Copy ${DEPLOY_DIR}/deploy.env.template to ${ENV_FILE} and fill in the values first."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

IBM_CLOUD_API_KEY_RESOLVED="${IBM_CLOUD_API_KEY:-${IBMCLOUD_API_KEY:-}}"
ICR_REGISTRY_USERNAME_RESOLVED="${ICR_REGISTRY_USERNAME:-iamapikey}"
ICR_REGISTRY_PASSWORD_RESOLVED="${ICR_REGISTRY_PASSWORD:-${IBM_CLOUD_API_KEY_RESOLVED}}"
CE_DEBUG_RESOLVED="${CE_DEBUG:-0}"

normalize_deploy_artifact_mode() {
  local raw_mode="${1:-source_build}"
  local normalized
  normalized="$(printf '%s' "${raw_mode}" | tr '[:upper:]' '[:lower:]')"

  case "${normalized}" in
    source_build|prebuilt_images)
      printf '%s\n' "${normalized}"
      ;;
    *)
      echo "ERROR: DEPLOY_ARTIFACT_MODE must be 'source_build' or 'prebuilt_images' in ${ENV_FILE}."
      exit 1
      ;;
  esac
}

normalize_container_client() {
  local raw_client="${1:-docker}"
  local normalized
  normalized="$(printf '%s' "${raw_client}" | tr '[:upper:]' '[:lower:]')"

  case "${normalized}" in
    docker|podman)
      printf '%s\n' "${normalized}"
      ;;
    *)
      echo "ERROR: CONTAINER_CLIENT must be 'docker' or 'podman' in ${ENV_FILE}."
      exit 1
      ;;
  esac
}

normalize_stack_auth_mode() {
  local raw_mode="${1:-basic}"
  local normalized
  normalized="$(printf '%s' "${raw_mode}" | tr '[:upper:]' '[:lower:]')"

  case "${normalized}" in
    oauth2|basic)
      printf '%s\n' "${normalized}"
      ;;
    *)
      echo "ERROR: STACK_AUTH_MODE must be 'oauth2' or 'basic' in ${ENV_FILE}."
      exit 1
      ;;
  esac
}

resolve_frontend_auth_required() {
  local raw_value="${FRONTEND_AUTH_REQUIRED:-}"
  if [[ -z "${raw_value}" ]]; then
    if [[ "${STACK_AUTH_MODE}" == "basic" ]]; then
      printf 'false\n'
    else
      printf 'true\n'
    fi
    return
  fi

  case "$(printf '%s' "${raw_value}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on)
      printf 'true\n'
      ;;
    0|false|no|off)
      printf 'false\n'
      ;;
    *)
      echo "ERROR: FRONTEND_AUTH_REQUIRED must be true or false in ${ENV_FILE}."
      exit 1
      ;;
  esac
}

STACK_AUTH_MODE="$(normalize_stack_auth_mode "${STACK_AUTH_MODE:-basic}")"
FRONTEND_AUTH_REQUIRED_RESOLVED="$(resolve_frontend_auth_required)"
DEPLOY_ARTIFACT_MODE="$(normalize_deploy_artifact_mode "${DEPLOY_ARTIFACT_MODE:-source_build}")"
CONTAINER_CLIENT_RESOLVED="$(normalize_container_client "${CONTAINER_CLIENT:-docker}")"
CONTAINER_PLATFORM_RESOLVED="${CONTAINER_PLATFORM:-linux/amd64}"

if [[ "${STACK_AUTH_MODE}" == "basic" && "${FRONTEND_AUTH_REQUIRED_RESOLVED}" != "false" ]]; then
  echo "ERROR: STACK_AUTH_MODE=basic requires FRONTEND_AUTH_REQUIRED=false."
  exit 1
fi

# ************************
# Function definition section
# ************************

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: required command '${command_name}' is not installed."
    exit 1
  fi
}

debug_enabled() {
  case "$(printf '%s' "${CE_DEBUG_RESOLVED}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

run_maybe_quiet() {
  local label="$1"
  shift

  log_info "START ${label}"
  if debug_enabled; then
    if "$@"; then
      log_info "DONE  ${label}"
      return 0
    fi

    local status=$?
    log_info "FAIL  ${label} (exit ${status})"
    return "${status}"
  fi

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/ce-script.XXXXXX")"

  if "$@" >"${output_file}" 2>&1; then
    log_info "DONE  ${label}"
    rm -f "${output_file}"
    return 0
  fi

  local status=$?
  log_info "FAIL  ${label} (exit ${status})"
  if [[ -s "${output_file}" ]]; then
    cat "${output_file}"
  fi
  rm -f "${output_file}"
  return "${status}"
}

require_code_engine_plugin() {
  if ! run_maybe_quiet "ibmcloud plugin show code-engine" ibmcloud plugin show code-engine; then
    echo "ERROR: the IBM Cloud Code Engine plugin is not available."
    echo "Install it with: ibmcloud plugin install code-engine"
    exit 1
  fi
}

require_container_registry_plugin() {
  if ! run_maybe_quiet "ibmcloud plugin show container-registry" ibmcloud plugin show container-registry; then
    echo "ERROR: the IBM Cloud Container Registry plugin is not available."
    echo "Install it with: ibmcloud plugin install container-registry"
    exit 1
  fi
}

require_var() {
  local variable_name="$1"
  if [[ -z "${!variable_name:-}" ]]; then
    echo "ERROR: required variable '${variable_name}' is empty in ${ENV_FILE}."
    exit 1
  fi
}

resolve_build_source() {
  if [[ -z "${BUILD_SOURCE:-}" ]]; then
    printf '%s\n' "${REPO_ROOT}"
    return
  fi

  case "${BUILD_SOURCE}" in
    http://*|https://*|git@*)
      printf '%s\n' "${BUILD_SOURCE}"
      ;;
    /*)
      printf '%s\n' "${BUILD_SOURCE}"
      ;;
    *)
      printf '%s\n' "${REPO_ROOT}/${BUILD_SOURCE}"
      ;;
  esac
}

BUILD_SOURCE_RESOLVED="$(resolve_build_source)"
BUILD_COMMIT_RESOLVED=""
case "${BUILD_SOURCE_RESOLVED}" in
  http://*|https://*|git@*)
    BUILD_COMMIT_RESOLVED="${BUILD_COMMIT:-}"
    ;;
esac

prebuilt_image_mode_enabled() {
  [[ "${DEPLOY_ARTIFACT_MODE}" == "prebuilt_images" ]]
}

require_prebuilt_image_settings() {
  if ! prebuilt_image_mode_enabled; then
    return
  fi

  require_var ICR_REGION
  require_var ICR_REGISTRY
  require_var ICR_NAMESPACE
  require_var ICR_REGISTRY_SECRET_NAME
  require_var IMAGE_TAG
  require_var HR_IMAGE_REPOSITORY
  require_var BOOKING_API_IMAGE_REPOSITORY
  require_var MCP_IMAGE_REPOSITORY
  require_var WEB_APP_IMAGE_REPOSITORY
  require_var WEB_APP_MCP_IMAGE_REPOSITORY

  if [[ -z "${ICR_REGISTRY_PASSWORD_RESOLVED}" ]]; then
    echo "ERROR: prebuilt image mode requires ICR_REGISTRY_PASSWORD or IBM_CLOUD_API_KEY in ${ENV_FILE}."
    exit 1
  fi
}

ensure_ibmcloud_session() {
  require_command ibmcloud
  require_code_engine_plugin

  if [[ -n "${IBM_CLOUD_API_KEY_RESOLVED}" ]]; then
    require_var IBM_CLOUD_REGION
    require_var IBM_CLOUD_RESOURCE_GROUP
    run_maybe_quiet \
      "ibmcloud login --apikey <hidden> -r ${IBM_CLOUD_REGION} -g ${IBM_CLOUD_RESOURCE_GROUP}" \
      ibmcloud login \
      --apikey "${IBM_CLOUD_API_KEY_RESOLVED}" \
      -r "${IBM_CLOUD_REGION}" \
      -g "${IBM_CLOUD_RESOURCE_GROUP}"
    return
  fi

  if ! run_maybe_quiet "ibmcloud target" ibmcloud target; then
    echo "ERROR: IBM Cloud login required."
    echo "Run 'ibmcloud login' first or set IBM_CLOUD_API_KEY in ${ENV_FILE}."
    exit 1
  fi
}

ensure_container_registry_session() {
  ensure_ibmcloud_session
  require_container_registry_plugin
  require_var ICR_REGION
  run_maybe_quiet "ibmcloud cr region-set ${ICR_REGION}" ibmcloud cr region-set "${ICR_REGION}"
}

select_project() {
  local select_args=("--name" "${CE_PROJECT_NAME}")
  if [[ -n "${CE_ENDPOINT:-}" ]]; then
    select_args+=("--endpoint" "${CE_ENDPOINT}")
  fi

  ensure_ibmcloud_session
  run_maybe_quiet \
    "ibmcloud target -r ${IBM_CLOUD_REGION} -g ${IBM_CLOUD_RESOURCE_GROUP}" \
    ibmcloud target -r "${IBM_CLOUD_REGION}" -g "${IBM_CLOUD_RESOURCE_GROUP}"
  run_maybe_quiet \
    "ibmcloud ce project select ${CE_PROJECT_NAME}" \
    ibmcloud ce project select "${select_args[@]}"
}

set_build_args() {
  local context_dir="$1"
  BUILD_ARGS=(
    --build-source "${BUILD_SOURCE_RESOLVED}"
    --build-context-dir "${context_dir}"
    --build-strategy dockerfile
  )

  if [[ -n "${BUILD_COMMIT_RESOLVED}" ]]; then
    BUILD_ARGS+=(--build-commit "${BUILD_COMMIT_RESOLVED}")
  fi
}

image_repository_for_service() {
  local service_key="$1"
  case "${service_key}" in
    hr)
      printf '%s\n' "${HR_IMAGE_REPOSITORY}"
      ;;
    booking_api)
      printf '%s\n' "${BOOKING_API_IMAGE_REPOSITORY}"
      ;;
    mcp_api)
      printf '%s\n' "${MCP_IMAGE_REPOSITORY}"
      ;;
    web_app)
      printf '%s\n' "${WEB_APP_IMAGE_REPOSITORY}"
      ;;
    web_app_mcp)
      printf '%s\n' "${WEB_APP_MCP_IMAGE_REPOSITORY}"
      ;;
    *)
      echo "ERROR: unknown service key '${service_key}' for image repository resolution."
      exit 1
      ;;
  esac
}

image_ref_for_service() {
  local service_key="$1"
  local repository
  repository="$(image_repository_for_service "${service_key}")"
  printf '%s/%s/%s:%s\n' "${ICR_REGISTRY}" "${ICR_NAMESPACE}" "${repository}" "${IMAGE_TAG}"
}

set_service_artifact_args() {
  local context_dir="$1"
  local service_key="$2"

  if prebuilt_image_mode_enabled; then
    require_prebuilt_image_settings
    ARTIFACT_ARGS=(
      --image "$(image_ref_for_service "${service_key}")"
      --registry-secret "${ICR_REGISTRY_SECRET_NAME}"
    )
    return
  fi

  set_build_args "${context_dir}"
  ARTIFACT_ARGS=("${BUILD_ARGS[@]}")
}

ce_application_exists() {
  local app_name="$1"
  ibmcloud ce application get --name "${app_name}" >/dev/null 2>&1
}

ce_upsert_application() {
  local app_name="$1"
  shift

  log_info "Checking whether application '${app_name}' already exists."
  if ce_application_exists "${app_name}"; then
    run_maybe_quiet \
      "ibmcloud ce application update ${app_name}" \
      ibmcloud ce application update --name "${app_name}" "$@"
  else
    run_maybe_quiet \
      "ibmcloud ce application create ${app_name}" \
      ibmcloud ce application create --name "${app_name}" "$@"
  fi
}

ce_remove_application_env_keys() {
  local app_name="$1"
  shift

  log_info "Checking whether application '${app_name}' exists before removing environment keys."
  if ! ce_application_exists "${app_name}"; then
    return
  fi

  local update_args=()
  local env_key
  for env_key in "$@"; do
    update_args+=(--env-rm "${env_key}")
  done

  if [[ "${#update_args[@]}" -eq 0 ]]; then
    return
  fi

  run_maybe_quiet \
    "ibmcloud ce application update env ${app_name}" \
    ibmcloud ce application update \
    --name "${app_name}" \
    "${update_args[@]}"
}

ce_app_url() {
  local app_name="$1"
  ibmcloud ce application get --name "${app_name}" --output url | tr -d '\r\n'
}

ce_configmap_exists() {
  local configmap_name="$1"
  ibmcloud ce configmap get --name "${configmap_name}" >/dev/null 2>&1
}

ce_upsert_configmap() {
  local configmap_name="$1"
  shift

  log_info "Checking whether configmap '${configmap_name}' already exists."
  if ce_configmap_exists "${configmap_name}"; then
    run_maybe_quiet \
      "ibmcloud ce configmap update ${configmap_name}" \
      ibmcloud ce configmap update --name "${configmap_name}" "$@"
  else
    run_maybe_quiet \
      "ibmcloud ce configmap create ${configmap_name}" \
      ibmcloud ce configmap create --name "${configmap_name}" "$@"
  fi
}

resolve_keycloak_base_url() {
  if [[ "${STACK_AUTH_MODE}" != "oauth2" ]]; then
    echo "ERROR: resolve_keycloak_base_url only applies to STACK_AUTH_MODE=oauth2."
    exit 1
  fi

  if [[ -n "${KEYCLOAK_BASE_URL_OVERRIDE:-}" ]]; then
    printf '%s\n' "${KEYCLOAK_BASE_URL_OVERRIDE}"
    return
  fi

  ce_app_url "${KEYCLOAK_APP_NAME}"
}

config_env_file() {
  local service_slug="$1"
  local variant_slug="$2"
  printf '%s/%s.%s.env\n' "${GENERATED_CONFIG_DIR}" "${service_slug}" "${variant_slug}"
}

write_env_file() {
  local env_file="$1"
  shift
  printf '%s\n' "$@" > "${env_file}"
}

upsert_configmap_from_file() {
  local configmap_name="$1"
  local env_file="$2"
  ce_upsert_configmap "${configmap_name}" --from-env-file "${env_file}"
}

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
  local env_file
  env_file="$(config_env_file "booking-api" "oauth2")"

  write_env_file \
    "${env_file}" \
    "AUTH_MODE=oauth2" \
    "OIDC_ISSUER=${keycloak_realm_url}" \
    "OIDC_AUDIENCE=${OIDC_AUDIENCE}" \
    "OIDC_JWKS_URL=${jwks_url}"

  upsert_configmap_from_file "${BOOKING_API_CONFIGMAP_NAME}" "${env_file}"
}

upsert_booking_api_config_basic() {
  local env_file
  env_file="$(config_env_file "booking-api" "basic")"

  write_env_file "${env_file}" "AUTH_MODE=basic"
  upsert_configmap_from_file "${BOOKING_API_CONFIGMAP_NAME}" "${env_file}"
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
  local env_file
  env_file="$(config_env_file "mcp" "oauth2")"

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

  write_env_file "${env_file}" "${env_lines[@]}"
  upsert_configmap_from_file "${MCP_CONFIGMAP_NAME}" "${env_file}"
}

upsert_mcp_api_config_basic() {
  local mcp_public_base_url="${1:-}"
  local env_file
  env_file="$(config_env_file "mcp" "basic")"

  local env_lines=("AUTH_MODE=basic")
  if [[ -n "${mcp_public_base_url}" ]]; then
    env_lines+=("MCP_PUBLIC_BASE_URL=${mcp_public_base_url}")
  fi

  write_env_file "${env_file}" "${env_lines[@]}"
  upsert_configmap_from_file "${MCP_CONFIGMAP_NAME}" "${env_file}"
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
  local env_file
  env_file="$(config_env_file "web-ui" "oauth2")"

  write_env_file \
    "${env_file}" \
    "BACKEND_URL=${booking_api_url}" \
    "BACKEND_AUTH_MODE=oauth2" \
    "FRONTEND_AUTH_REQUIRED=${FRONTEND_AUTH_REQUIRED_RESOLVED}" \
    "OIDC_TOKEN_URL=${token_url}" \
    "OIDC_CLIENT_ID=${OIDC_CLIENT_ID}" \
    "OIDC_SCOPE=${OIDC_SCOPE}"

  upsert_configmap_from_file "${WEB_APP_CONFIGMAP_NAME}" "${env_file}"
}

upsert_rest_ui_config_basic() {
  local booking_api_url="$1"
  local env_file
  env_file="$(config_env_file "web-ui" "basic")"

  write_env_file \
    "${env_file}" \
    "BACKEND_URL=${booking_api_url}" \
    "BACKEND_AUTH_MODE=basic" \
    "FRONTEND_AUTH_REQUIRED=false"

  upsert_configmap_from_file "${WEB_APP_CONFIGMAP_NAME}" "${env_file}"
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
  local env_file
  env_file="$(config_env_file "web-ui-mcp" "oauth2")"

  write_env_file \
    "${env_file}" \
    "PORT=8085" \
    "MCP_SERVER_URL=${mcp_base_url}/mcp" \
    "MCP_TIMEOUT_SECONDS=${MCP_TIMEOUT_SECONDS}" \
    "BACKEND_AUTH_MODE=oauth2" \
    "FRONTEND_AUTH_REQUIRED=${FRONTEND_AUTH_REQUIRED_RESOLVED}" \
    "OIDC_TOKEN_URL=${token_url}" \
    "OIDC_CLIENT_ID=${OIDC_CLIENT_ID}" \
    "OIDC_SCOPE=${OIDC_SCOPE}"

  upsert_configmap_from_file "${WEB_APP_MCP_CONFIGMAP_NAME}" "${env_file}"
}

upsert_mcp_ui_config_basic() {
  local mcp_base_url="$1"
  local env_file
  env_file="$(config_env_file "web-ui-mcp" "basic")"

  write_env_file \
    "${env_file}" \
    "PORT=8085" \
    "MCP_SERVER_URL=${mcp_base_url}/mcp" \
    "MCP_TIMEOUT_SECONDS=${MCP_TIMEOUT_SECONDS}" \
    "BACKEND_AUTH_MODE=basic" \
    "FRONTEND_AUTH_REQUIRED=false"

  upsert_configmap_from_file "${WEB_APP_MCP_CONFIGMAP_NAME}" "${env_file}"
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

# ************************
# Execution section
# ************************

require_command ibmcloud
require_var IBM_CLOUD_REGION
require_var IBM_CLOUD_RESOURCE_GROUP
require_var CE_PROJECT_NAME
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

mkdir -p "${GENERATED_CONFIG_DIR}"
select_project

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

# ************************
# Monitoring section
# ************************

web_url="$(ce_app_url "${WEB_APP_NAME}")"
web_mcp_url="$(ce_app_url "${WEB_APP_MCP_APP_NAME}")"
hr_url="$(ce_app_url "${HR_APP_NAME}")"

echo "Rendered config files: ${GENERATED_CONFIG_DIR}"
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

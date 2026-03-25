#!/usr/bin/env bash
set -euo pipefail

# ************************
# Variable definition section
# ************************

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${DEPLOY_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/deploy.env}"

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

ensure_icr_namespace() {
  require_prebuilt_image_settings
  ensure_container_registry_session

  log_info "Checking whether ICR namespace '${ICR_NAMESPACE}' already exists."

  if ibmcloud cr namespace-list -o json | jq -e --arg ns "${ICR_NAMESPACE}" '
    .[]
    | select(
        (.namespace? // "") == $ns
        or (.name? // "") == $ns
        or (.Namespace? // "") == $ns
      )
  ' >/dev/null; then
    log_info "ICR namespace '${ICR_NAMESPACE}' already exists."
    return
  fi

  run_maybe_quiet "ibmcloud cr namespace-add ${ICR_NAMESPACE}" ibmcloud cr namespace-add "${ICR_NAMESPACE}"
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

should_deploy_keycloak() {
  [[ "${STACK_AUTH_MODE}" == "oauth2" && -z "${KEYCLOAK_BASE_URL_OVERRIDE:-}" ]]
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

ce_secret_exists() {
  local secret_name="$1"
  ibmcloud ce secret get --name "${secret_name}" >/dev/null 2>&1
}

ce_upsert_secret() {
  local secret_name="$1"
  shift

  log_info "Checking whether secret '${secret_name}' already exists."
  if ce_secret_exists "${secret_name}"; then
    run_maybe_quiet \
      "ibmcloud ce secret update ${secret_name}" \
      ibmcloud ce secret update --name "${secret_name}" "$@"
  else
    run_maybe_quiet \
      "ibmcloud ce secret create ${secret_name}" \
      ibmcloud ce secret create --name "${secret_name}" "$@"
  fi
}

# ************************
# Execution section
# ************************

require_command ibmcloud
require_var IBM_CLOUD_REGION
require_var IBM_CLOUD_RESOURCE_GROUP
require_var CE_PROJECT_NAME
require_var WEB_APP_SECRET_NAME
require_var FLASK_SECRET_KEY

if prebuilt_image_mode_enabled; then
  require_command jq
  require_prebuilt_image_settings
fi

select_project

if should_deploy_keycloak; then
  require_var KEYCLOAK_REALM_CONFIGMAP_NAME
  require_var KEYCLOAK_ADMIN_SECRET_NAME
  require_var KEYCLOAK_ADMIN_USER
  require_var KEYCLOAK_ADMIN_PASSWORD

  realm_file="${REPO_ROOT}/local-container/keycloak/realm/galaxium-realm.json"
  if [[ ! -f "${realm_file}" ]]; then
    echo "ERROR: Keycloak realm file not found at ${realm_file}"
    exit 1
  fi

  ce_upsert_configmap \
    "${KEYCLOAK_REALM_CONFIGMAP_NAME}" \
    --from-file "galaxium-realm.json=${realm_file}"

  ce_upsert_secret \
    "${KEYCLOAK_ADMIN_SECRET_NAME}" \
    --from-literal "KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN_USER}" \
    --from-literal "KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}"

  echo "Updated configmap: ${KEYCLOAK_REALM_CONFIGMAP_NAME}"
  echo "Updated secret: ${KEYCLOAK_ADMIN_SECRET_NAME}"
else
  echo "Skipping in-project Keycloak config because STACK_AUTH_MODE=${STACK_AUTH_MODE} or KEYCLOAK_BASE_URL_OVERRIDE is set."
fi

ui_secret_args=(
  --from-literal "FLASK_SECRET_KEY=${FLASK_SECRET_KEY}"
)
if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  require_var OIDC_CLIENT_SECRET
  ui_secret_args+=(
    --from-literal "OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}"
  )
fi

ce_upsert_secret \
  "${WEB_APP_SECRET_NAME}" \
  "${ui_secret_args[@]}"

echo "Updated secret: ${WEB_APP_SECRET_NAME}"

if [[ "${STACK_AUTH_MODE}" == "basic" ]]; then
  require_var BASIC_AUTH_SECRET_NAME
  require_var BASIC_AUTH_USERNAME
  require_var BASIC_AUTH_PASSWORD

  ce_upsert_secret \
    "${BASIC_AUTH_SECRET_NAME}" \
    --from-literal "BASIC_AUTH_USERNAME=${BASIC_AUTH_USERNAME}" \
    --from-literal "BASIC_AUTH_PASSWORD=${BASIC_AUTH_PASSWORD}"

  echo "Updated secret: ${BASIC_AUTH_SECRET_NAME}"
fi

if prebuilt_image_mode_enabled; then
  ensure_icr_namespace

  ce_upsert_secret \
    "${ICR_REGISTRY_SECRET_NAME}" \
    --format registry \
    --server "${ICR_REGISTRY}" \
    --username "${ICR_REGISTRY_USERNAME_RESOLVED}" \
    --password "${ICR_REGISTRY_PASSWORD_RESOLVED}"

  echo "Updated registry secret: ${ICR_REGISTRY_SECRET_NAME}"
fi

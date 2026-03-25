#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/deploy.env}"
CE_DEBUG_RESOLVED="${CE_DEBUG:-0}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: missing environment file: ${ENV_FILE}"
  echo "Copy ${DEPLOY_DIR}/deploy.env.template to ${ENV_FILE} and fill in the values first."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

IBM_CLOUD_API_KEY_RESOLVED="${IBM_CLOUD_API_KEY:-${IBMCLOUD_API_KEY:-}}"

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

STACK_AUTH_MODE="$(normalize_stack_auth_mode "${STACK_AUTH_MODE:-basic}")"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: required command '${command_name}' is not installed."
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

run_maybe_quiet() {
  local label="$1"
  shift

  if debug_enabled; then
    echo "[debug] ${label}"
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

require_code_engine_plugin() {
  if ! run_maybe_quiet "ibmcloud plugin show code-engine" ibmcloud plugin show code-engine; then
    echo "ERROR: the IBM Cloud Code Engine plugin is not available."
    echo "Install it with: ibmcloud plugin install code-engine"
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

ce_application_exists() {
  local app_name="$1"
  ibmcloud ce application get --name "${app_name}" >/dev/null 2>&1
}

ce_upsert_application() {
  local app_name="$1"
  shift

  if ce_application_exists "${app_name}"; then
    ibmcloud ce application update --name "${app_name}" "$@"
  else
    ibmcloud ce application create --name "${app_name}" "$@"
  fi
}

ce_app_url() {
  local app_name="$1"
  ibmcloud ce application get --name "${app_name}" --output url | tr -d '\r\n'
}

require_command ibmcloud
require_var IBM_CLOUD_REGION
require_var IBM_CLOUD_RESOURCE_GROUP
require_var CE_PROJECT_NAME
select_project

if ! should_deploy_keycloak; then
  if [[ "${STACK_AUTH_MODE}" == "basic" ]]; then
    echo "Skipping Keycloak deployment because STACK_AUTH_MODE=basic."
  else
    echo "Skipping Keycloak deployment because KEYCLOAK_BASE_URL_OVERRIDE is set to ${KEYCLOAK_BASE_URL_OVERRIDE}."
  fi
  exit 0
fi

require_var KEYCLOAK_APP_NAME
require_var KEYCLOAK_REALM_CONFIGMAP_NAME
require_var KEYCLOAK_ADMIN_SECRET_NAME
require_var KEYCLOAK_CPU
require_var KEYCLOAK_MEMORY
require_var KEYCLOAK_MIN_SCALE
require_var KEYCLOAK_MAX_SCALE

args=(
  --image quay.io/keycloak/keycloak:26.0
  --port 8080
  --cpu "${KEYCLOAK_CPU}"
  --memory "${KEYCLOAK_MEMORY}"
  --min-scale "${KEYCLOAK_MIN_SCALE}"
  --max-scale "${KEYCLOAK_MAX_SCALE}"
  --visibility public
  --command kc.sh
  --argument start-dev
  --argument --http-port=8080
  --argument --import-realm
  --env KC_HTTP_ENABLED=true
  --env KC_PROXY_HEADERS=xforwarded
  --env KC_HOSTNAME_STRICT=false
  --env-from-secret "${KEYCLOAK_ADMIN_SECRET_NAME}"
  --mount-configmap "/opt/keycloak/data/import=${KEYCLOAK_REALM_CONFIGMAP_NAME}"
)

if [[ -n "${KEYCLOAK_DATA_STORE_NAME:-}" ]]; then
  args+=(--mount-data-store "/opt/keycloak/data=${KEYCLOAK_DATA_STORE_NAME}")
fi

ce_upsert_application "${KEYCLOAK_APP_NAME}" "${args[@]}"

keycloak_url="$(ce_app_url "${KEYCLOAK_APP_NAME}")"
echo "Keycloak URL: ${keycloak_url}"

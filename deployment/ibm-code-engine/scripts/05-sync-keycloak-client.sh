#!/usr/bin/env bash
set -euo pipefail

# ************************
# Variable definition section
# ************************

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/deploy.env}"
CE_DEBUG_RESOLVED="${CE_DEBUG:-0}"

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

ce_app_url() {
  local app_name="$1"
  ibmcloud ce application get --name "${app_name}" --output url | tr -d '\r\n'
}

wait_for_http_ok() {
  local url="$1"
  local attempts="${2:-60}"
  local sleep_seconds="${3:-5}"
  local attempt

  for attempt in $(seq 1 "${attempts}"); do
    log_info "HTTP readiness check ${attempt}/${attempts}: ${url}"
    if curl -fsS "${url}" >/dev/null 2>&1; then
      log_info "Endpoint is ready: ${url}"
      return 0
    fi
    log_info "Endpoint not ready yet; retrying in ${sleep_seconds}s: ${url}"
    sleep "${sleep_seconds}"
  done

  echo "ERROR: timed out waiting for ${url}"
  exit 1
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

# ************************
# Execution section
# ************************

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
require_var IBM_CLOUD_REGION
require_var IBM_CLOUD_RESOURCE_GROUP
require_var CE_PROJECT_NAME

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

# ************************
# Monitoring section
# ************************

log_info "Resolving Code Engine URLs for Keycloak and the web applications."
keycloak_url="$(resolve_keycloak_base_url)"
web_url="$(ce_app_url "${WEB_APP_NAME}")"
web_mcp_url="$(ce_app_url "${WEB_APP_MCP_APP_NAME}")"

echo "Waiting for Keycloak realm endpoints..."
wait_for_http_ok "${keycloak_url}/realms/master/.well-known/openid-configuration"
wait_for_http_ok "${keycloak_url}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration"

log_info "Requesting a Keycloak admin token from ${keycloak_url}."
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

# ************************
# Test section
# ************************

log_info "Reading Keycloak client '${OIDC_CLIENT_ID}'."
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

run_maybe_quiet \
  "Keycloak client update ${OIDC_CLIENT_ID}" \
  curl -fsS -X PUT "${keycloak_url}/admin/realms/${KEYCLOAK_REALM}/clients/${client_id}" \
    -H "Authorization: Bearer ${admin_token}" \
    -H "Content-Type: application/json" \
    -d "${updated_client}"

echo "Updated Keycloak client '${OIDC_CLIENT_ID}' with Code Engine UI URLs."
echo "REST Web UI origin: ${web_url}"
echo "MCP Web UI origin:  ${web_mcp_url}"

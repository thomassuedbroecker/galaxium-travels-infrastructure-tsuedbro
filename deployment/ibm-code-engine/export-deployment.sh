#!/usr/bin/env bash
set -euo pipefail

# Exports the current IBM Code Engine deployment links and configuration.
#
# Usage:
#   ./export-deployment.sh            # every existing env file: deploy.env and deploy.env.oauth2
#   ./export-deployment.sh --basic    # only deploy.env
#   ./export-deployment.sh --oauth2   # only deploy.env.oauth2 (falls back to deploy.env, forced to oauth2,
#                                     # same as deploy-stack-oauth2.sh)
#   ENV_FILE=/path/to/file ./export-deployment.sh   # exactly that env file
#
# Output (git-ignored): generated/exports/<project>-<auth mode>-<timestamp>/ (one per env file)
#   deployment-links.md    human-readable links and settings
#   deployment-links.env   machine-readable KEY=VALUE links
#                          (includes EXPORTED_AT; the timestamp is also part of the folder name)
#   configmaps/*.json      live Code Engine configmaps (non-secret runtime settings)
#   applications/*.json    live Code Engine application definitions
#   rendered-env/*.env     env files rendered by the last deploy (if present)
#
# Secret values are never exported; only secret names are listed.

# ************************
# Variable definition section
# ************************

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${SCRIPT_DIR}"
CE_DEBUG_RESOLVED="${CE_DEBUG:-0}"

# Dispatcher: without ENV_FILE, run this script once per selected env file.
# Each run is a separate process so one stack's variables never leak into the other.
if [[ -z "${ENV_FILE:-}" ]]; then
  env_files=()
  case "${1:-}" in
    "")
      [[ -f "${DEPLOY_DIR}/deploy.env" ]] && env_files+=("${DEPLOY_DIR}/deploy.env")
      [[ -f "${DEPLOY_DIR}/deploy.env.oauth2" ]] && env_files+=("${DEPLOY_DIR}/deploy.env.oauth2")
      ;;
    --basic)
      env_files+=("${DEPLOY_DIR}/deploy.env")
      ;;
    --oauth2)
      if [[ -f "${DEPLOY_DIR}/deploy.env.oauth2" ]]; then
        env_files+=("${DEPLOY_DIR}/deploy.env.oauth2")
      else
        env_files+=("${DEPLOY_DIR}/deploy.env")
      fi
      ;;
    *)
      echo "Usage: $0 [--basic|--oauth2]"
      exit 1
      ;;
  esac

  if [[ ${#env_files[@]} -eq 0 ]]; then
    echo "ERROR: no environment file found in ${DEPLOY_DIR}."
    echo "Copy deploy.env.template to deploy.env and/or deploy.env.oauth2.template to deploy.env.oauth2 first."
    exit 1
  fi

  for env_file in "${env_files[@]}"; do
    if [[ "${1:-}" == "--oauth2" ]]; then
      FORCE_STACK_AUTH_MODE=oauth2 ENV_FILE="${env_file}" bash "${BASH_SOURCE[0]}"
    else
      ENV_FILE="${env_file}" bash "${BASH_SOURCE[0]}"
    fi
  done
  exit 0
fi

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
# --oauth2 (FORCE_STACK_AUTH_MODE) wins over the env file, like deploy-stack-oauth2.sh; otherwise the env file decides.
STACK_AUTH_MODE="$(printf '%s' "${FORCE_STACK_AUTH_MODE:-${STACK_AUTH_MODE:-basic}}" | tr '[:upper:]' '[:lower:]')"
case "${STACK_AUTH_MODE}" in
  basic|oauth2) ;;
  *) echo "ERROR: STACK_AUTH_MODE must be 'oauth2' or 'basic' in ${ENV_FILE}."; exit 1 ;;
esac

IBM_CLOUD_API_KEY_RESOLVED="${IBM_CLOUD_API_KEY:-${IBMCLOUD_API_KEY:-}}"
DEPLOY_ARTIFACT_MODE="$(printf '%s' "${DEPLOY_ARTIFACT_MODE:-source_build}" | tr '[:upper:]' '[:lower:]')"

# ************************
# Function definition section
# ************************

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command '$1' is not installed."
    exit 1
  fi
}

require_var() {
  if [[ -z "${!1:-}" ]]; then
    echo "ERROR: required variable '$1' is empty in ${ENV_FILE}."
    exit 1
  fi
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

ensure_ibmcloud_session() {
  require_command ibmcloud

  if ibmcloud target >/dev/null 2>&1; then
    return
  fi

  if [[ -n "${IBM_CLOUD_API_KEY_RESOLVED}" ]]; then
    ibmcloud login --apikey "${IBM_CLOUD_API_KEY_RESOLVED}" \
      -r "${IBM_CLOUD_REGION}" -g "${IBM_CLOUD_RESOURCE_GROUP}" >/dev/null
    return
  fi

  echo "ERROR: IBM Cloud login required."
  echo "Run 'ibmcloud login' first or set IBM_CLOUD_API_KEY in ${ENV_FILE}."
  exit 1
}

select_project() {
  local select_args=("--name" "${CE_PROJECT_NAME}")
  if [[ -n "${CE_ENDPOINT:-}" ]]; then
    select_args+=("--endpoint" "${CE_ENDPOINT}")
  fi

  ensure_ibmcloud_session
  ibmcloud target -r "${IBM_CLOUD_REGION}" -g "${IBM_CLOUD_RESOURCE_GROUP}" >/dev/null
  ibmcloud ce project select "${select_args[@]}" >/dev/null
}

ce_app_url() {
  ibmcloud ce application get --name "$1" --output url | tr -d '\r\n'
}

export_json() {
  # export_json <ce-kind> <name> <target-file>; skips (with a warning) if the resource is missing
  local kind="$1" name="$2" target="$3"
  if ibmcloud ce "${kind}" get --name "${name}" --output json >"${target}" 2>/dev/null; then
    log_info "Exported ${kind} '${name}'"
  else
    rm -f "${target}"
    log_info "WARN  ${kind} '${name}' not found, skipped"
  fi
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

log_info "Using environment file: ${ENV_FILE} (STACK_AUTH_MODE=${STACK_AUTH_MODE})"
select_project

hr_url="$(ce_app_url "${HR_APP_NAME}")"
booking_api_url="$(ce_app_url "${BOOKING_API_APP_NAME}")"
mcp_base_url="$(ce_app_url "${MCP_APP_NAME}")"
web_url="$(ce_app_url "${WEB_APP_NAME}")"
web_mcp_url="$(ce_app_url "${WEB_APP_MCP_APP_NAME}")"

keycloak_url=""
if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  if [[ -n "${KEYCLOAK_BASE_URL_OVERRIDE:-}" ]]; then
    keycloak_url="${KEYCLOAK_BASE_URL_OVERRIDE}"
  else
    require_var KEYCLOAK_APP_NAME
    keycloak_url="$(ce_app_url "${KEYCLOAK_APP_NAME}")"
  fi
fi

export_label="${CE_PROJECT_NAME}"
[[ "${export_label}" == *"${STACK_AUTH_MODE}"* ]] || export_label="${export_label}-${STACK_AUTH_MODE}"
EXPORT_DIR="${DEPLOY_DIR}/generated/exports/${export_label}-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "${EXPORT_DIR}/configmaps" "${EXPORT_DIR}/applications" "${EXPORT_DIR}/rendered-env"

# Links (machine-readable)
cat >"${EXPORT_DIR}/deployment-links.env" <<EOF
EXPORTED_AT=$(date '+%Y-%m-%dT%H:%M:%S%z')
CE_PROJECT_NAME=${CE_PROJECT_NAME}
IBM_CLOUD_REGION=${IBM_CLOUD_REGION}
STACK_AUTH_MODE=${STACK_AUTH_MODE}
DEPLOY_ARTIFACT_MODE=${DEPLOY_ARTIFACT_MODE}
KEYCLOAK_URL=${keycloak_url}
HR_API_URL=${hr_url}
BOOKING_API_URL=${booking_api_url}
MCP_BASE_URL=${mcp_base_url}
MCP_ENDPOINT=${mcp_base_url}/mcp
REST_WEB_UI_URL=${web_url}
MCP_WEB_UI_URL=${web_mcp_url}
EOF

# Links (human-readable)
cat >"${EXPORT_DIR}/deployment-links.md" <<EOF
# Galaxium deployment export

- Exported at:        $(timestamp)
- Code Engine project: ${CE_PROJECT_NAME}
- Region / group:     ${IBM_CLOUD_REGION} / ${IBM_CLOUD_RESOURCE_GROUP}
- Stack auth mode:    ${STACK_AUTH_MODE}
- Artifact mode:      ${DEPLOY_ARTIFACT_MODE}

## Links

| Service | URL |
|---|---|
| Keycloak | ${keycloak_url:-not deployed for this mode} |
| HR API | ${hr_url} |
| Booking API | ${booking_api_url} |
| MCP base | ${mcp_base_url} |
| MCP endpoint | ${mcp_base_url}/mcp |
| REST Web UI | ${web_url} |
| MCP Web UI | ${web_mcp_url} |

## Configmaps

- ${BOOKING_API_CONFIGMAP_NAME}
- ${MCP_CONFIGMAP_NAME}
- ${WEB_APP_CONFIGMAP_NAME}
- ${WEB_APP_MCP_CONFIGMAP_NAME}

## Secrets (names only, values are never exported)

- ${WEB_APP_SECRET_NAME:-<unset>}
- ${BASIC_AUTH_SECRET_NAME:-<unset>} (basic mode)
- ${KEYCLOAK_ADMIN_SECRET_NAME:-<unset>} (oauth2 mode)
EOF

# Live configuration from Code Engine
for configmap in \
  "${BOOKING_API_CONFIGMAP_NAME}" "${MCP_CONFIGMAP_NAME}" \
  "${WEB_APP_CONFIGMAP_NAME}" "${WEB_APP_MCP_CONFIGMAP_NAME}"; do
  export_json configmap "${configmap}" "${EXPORT_DIR}/configmaps/${configmap}.json"
done

apps=("${HR_APP_NAME}" "${BOOKING_API_APP_NAME}" "${MCP_APP_NAME}" "${WEB_APP_NAME}" "${WEB_APP_MCP_APP_NAME}")
if [[ "${STACK_AUTH_MODE}" == "oauth2" && -z "${KEYCLOAK_BASE_URL_OVERRIDE:-}" ]]; then
  apps+=("${KEYCLOAK_APP_NAME}")
fi
for app in "${apps[@]}"; do
  export_json application "${app}" "${EXPORT_DIR}/applications/${app}.json"
done

# Env files rendered by the last deploy (non-secret)
shopt -s nullglob
for env_file in "${DEPLOY_DIR}"/generated/*.env; do
  cp "${env_file}" "${EXPORT_DIR}/rendered-env/"
done
shopt -u nullglob

# ************************
# Monitoring section
# ************************

log_info "Export written to ${EXPORT_DIR}"
echo
cat "${EXPORT_DIR}/deployment-links.env"

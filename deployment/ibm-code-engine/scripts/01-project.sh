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

require_command ibmcloud
require_var IBM_CLOUD_REGION
require_var IBM_CLOUD_RESOURCE_GROUP
require_var CE_PROJECT_NAME

ensure_ibmcloud_session

target_args=("-r" "${IBM_CLOUD_REGION}" "-g" "${IBM_CLOUD_RESOURCE_GROUP}")
select_args=("--name" "${CE_PROJECT_NAME}")
create_args=("--name" "${CE_PROJECT_NAME}")

if [[ -n "${CE_ENDPOINT:-}" ]]; then
  select_args+=("--endpoint" "${CE_ENDPOINT}")
fi

if [[ -n "${CE_PROJECT_TAG:-}" ]]; then
  create_args+=("--tag" "${CE_PROJECT_TAG}")
fi

ibmcloud target "${target_args[@]}"

if ! ibmcloud ce project select "${select_args[@]}" >/dev/null 2>&1; then
  ibmcloud ce project create "${create_args[@]}"
fi

ibmcloud ce project select "${select_args[@]}"
echo "Active Code Engine project: ${CE_PROJECT_NAME}"

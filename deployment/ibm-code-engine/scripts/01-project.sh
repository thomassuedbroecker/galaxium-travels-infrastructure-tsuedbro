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
  YELLOW='\033[1;33m'
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  NC='\033[0m'
else
  BLUE=''
  YELLOW=''
  GREEN=''
  RED=''
  NC=''
fi

clear_output_if_interactive() {
  if [[ -t 1 && -n "${TERM:-}" ]]; then
    clear || true
  fi
}

if [[ -t 1 ]]; then
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${YELLOW} Clear output ${NC}"
  clear_output_if_interactive
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
  local target_args=("-r" "${IBM_CLOUD_REGION}" "-g" "${IBM_CLOUD_RESOURCE_GROUP}")
  local select_args=("--name" "${CE_PROJECT_NAME}")
  local create_args=("--name" "${CE_PROJECT_NAME}")

  if [[ -n "${CE_ENDPOINT:-}" ]]; then
    select_args+=("--endpoint" "${CE_ENDPOINT}")
  fi

  if [[ -n "${CE_PROJECT_TAG:-}" ]]; then
    create_args+=("--tag" "${CE_PROJECT_TAG}")
  fi

  run_maybe_quiet \
    "ibmcloud target -r ${IBM_CLOUD_REGION} -g ${IBM_CLOUD_RESOURCE_GROUP}" \
    ibmcloud target "${target_args[@]}"

  log_info "Checking whether Code Engine project '${CE_PROJECT_NAME}' already exists."
  if ! ibmcloud ce project select "${select_args[@]}" >/dev/null 2>&1; then
    run_maybe_quiet \
      "ibmcloud ce project create ${CE_PROJECT_NAME}" \
      ibmcloud ce project create "${create_args[@]}"
  else
    log_info "Code Engine project '${CE_PROJECT_NAME}' already exists."
  fi

  run_maybe_quiet \
    "ibmcloud ce project select ${CE_PROJECT_NAME}" \
    ibmcloud ce project select "${select_args[@]}"
}

# ************************
# Execution section
# ************************

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Execute commands ${NC}"

require_command ibmcloud
require_var IBM_CLOUD_REGION
require_var IBM_CLOUD_RESOURCE_GROUP
require_var CE_PROJECT_NAME

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Ensure IBM Cloud session ${NC}"
ensure_ibmcloud_session

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Ensure Code Engine project settings ${NC}"
select_project
echo "Active Code Engine project: ${CE_PROJECT_NAME}"

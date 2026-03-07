#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${DEPLOY_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/deploy.env}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: missing environment file: ${ENV_FILE}"
  echo "Copy ${DEPLOY_DIR}/deploy.env.template to ${ENV_FILE} and fill in the values first."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

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

select_project() {
  local select_args=("--name" "${CE_PROJECT_NAME}")
  if [[ -n "${CE_ENDPOINT:-}" ]]; then
    select_args+=("--endpoint" "${CE_ENDPOINT}")
  fi

  ibmcloud target -r "${IBM_CLOUD_REGION}" -g "${IBM_CLOUD_RESOURCE_GROUP}" >/dev/null
  ibmcloud ce project select "${select_args[@]}" >/dev/null
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

ce_configmap_exists() {
  local configmap_name="$1"
  ibmcloud ce configmap get --name "${configmap_name}" >/dev/null 2>&1
}

ce_upsert_configmap() {
  local configmap_name="$1"
  shift

  if ce_configmap_exists "${configmap_name}"; then
    ibmcloud ce configmap update --name "${configmap_name}" "$@"
  else
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

  if ce_secret_exists "${secret_name}"; then
    ibmcloud ce secret update --name "${secret_name}" "$@"
  else
    ibmcloud ce secret create --name "${secret_name}" "$@"
  fi
}

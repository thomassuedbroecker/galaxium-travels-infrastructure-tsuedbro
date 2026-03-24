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

IBM_CLOUD_API_KEY_RESOLVED="${IBM_CLOUD_API_KEY:-${IBMCLOUD_API_KEY:-}}"
ICR_REGISTRY_USERNAME_RESOLVED="${ICR_REGISTRY_USERNAME:-iamapikey}"
ICR_REGISTRY_PASSWORD_RESOLVED="${ICR_REGISTRY_PASSWORD:-${IBM_CLOUD_API_KEY_RESOLVED}}"
GENERATED_ENV_FILES=()

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

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: required command '${command_name}' is not installed."
    exit 1
  fi
}

require_code_engine_plugin() {
  if ! ibmcloud plugin show code-engine >/dev/null 2>&1; then
    echo "ERROR: the IBM Cloud Code Engine plugin is not available."
    echo "Install it with: ibmcloud plugin install code-engine"
    exit 1
  fi
}

require_container_registry_plugin() {
  if ! ibmcloud plugin show container-registry >/dev/null 2>&1; then
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

wait_for_http_ok() {
  local url="$1"
  local attempts="${2:-60}"
  local sleep_seconds="${3:-5}"

  for _ in $(seq 1 "${attempts}"); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  echo "ERROR: timed out waiting for ${url}"
  exit 1
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

cleanup_generated_env_files() {
  local env_file
  for env_file in "${GENERATED_ENV_FILES[@]:-}"; do
    if [[ -n "${env_file}" && -f "${env_file}" ]]; then
      rm -f "${env_file}"
    fi
  done
}

trap cleanup_generated_env_files EXIT

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
    ibmcloud login \
      --apikey "${IBM_CLOUD_API_KEY_RESOLVED}" \
      -r "${IBM_CLOUD_REGION}" \
      -g "${IBM_CLOUD_RESOURCE_GROUP}" >/dev/null
    return
  fi

  if ! ibmcloud target >/dev/null 2>&1; then
    echo "ERROR: IBM Cloud login required."
    echo "Run 'ibmcloud login' first or set IBM_CLOUD_API_KEY in ${ENV_FILE}."
    exit 1
  fi
}

ensure_container_registry_session() {
  ensure_ibmcloud_session
  require_container_registry_plugin
  require_var ICR_REGION
  ibmcloud cr region-set "${ICR_REGION}" >/dev/null
}

ensure_icr_namespace() {
  require_prebuilt_image_settings
  ensure_container_registry_session

  if ibmcloud cr namespace-list -o json | jq -e --arg ns "${ICR_NAMESPACE}" '
    .[]
    | select(
        (.namespace? // "") == $ns
        or (.name? // "") == $ns
        or (.Namespace? // "") == $ns
      )
  ' >/dev/null; then
    return
  fi

  ibmcloud cr namespace-add "${ICR_NAMESPACE}" >/dev/null
}

login_container_client_to_icr() {
  require_prebuilt_image_settings
  ensure_container_registry_session
  require_command "${CONTAINER_CLIENT_RESOLVED}"
  ibmcloud cr login --client "${CONTAINER_CLIENT_RESOLVED}" >/dev/null
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

build_and_push_service_image() {
  local service_key="$1"
  local context_dir="$2"
  local image_ref
  local build_cmd

  require_prebuilt_image_settings
  require_command "${CONTAINER_CLIENT_RESOLVED}"

  image_ref="$(image_ref_for_service "${service_key}")"
  build_cmd=("${CONTAINER_CLIENT_RESOLVED}" build)
  if [[ -n "${CONTAINER_PLATFORM_RESOLVED}" ]]; then
    build_cmd+=(--platform "${CONTAINER_PLATFORM_RESOLVED}")
  fi
  build_cmd+=(
    --tag "${image_ref}"
    "${REPO_ROOT}/${context_dir}"
  )

  echo "Building ${service_key} image: ${image_ref}"
  "${build_cmd[@]}"

  echo "Pushing ${service_key} image: ${image_ref}"
  "${CONTAINER_CLIENT_RESOLVED}" push "${image_ref}"
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

ce_remove_application_env_keys() {
  local app_name="$1"
  shift

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

  ibmcloud ce application update \
    --name "${app_name}" \
    "${update_args[@]}" >/dev/null
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

create_env_file() {
  local env_file
  env_file="$(mktemp "${TMPDIR:-/tmp}/galaxium-ce-config.XXXXXX")"
  GENERATED_ENV_FILES+=("${env_file}")
  printf '%s\n' "$@" > "${env_file}"
  printf '%s\n' "${env_file}"
}

ce_upsert_configmap_from_env_lines() {
  local configmap_name="$1"
  shift

  local env_file
  env_file="$(create_env_file "$@")"
  ce_upsert_configmap "${configmap_name}" --from-env-file "${env_file}"
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

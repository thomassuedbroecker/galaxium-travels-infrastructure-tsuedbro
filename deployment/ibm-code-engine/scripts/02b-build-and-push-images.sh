#!/usr/bin/env bash
set -euo pipefail

# ************************
# Variable definition section
# ************************

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${DEPLOY_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/deploy.env}"

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

DEPLOY_ARTIFACT_MODE="$(normalize_deploy_artifact_mode "${DEPLOY_ARTIFACT_MODE:-source_build}")"
CONTAINER_CLIENT_RESOLVED="$(normalize_container_client "${CONTAINER_CLIENT:-docker}")"
CONTAINER_PLATFORM_RESOLVED="${CONTAINER_PLATFORM:-linux/amd64}"

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

require_container_registry_plugin() {
  if ! run_maybe_quiet "ibmcloud plugin show container-registry" ibmcloud plugin show container-registry; then
    echo "ERROR: the IBM Cloud Container Registry plugin is not available."
    echo "Install it with: ibmcloud plugin install container-registry"
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

  run_maybe_quiet "ibmcloud cr namespace-add ${ICR_NAMESPACE}" ibmcloud cr namespace-add "${ICR_NAMESPACE}"
}

login_container_client_to_icr() {
  require_prebuilt_image_settings
  ensure_container_registry_session
  require_command "${CONTAINER_CLIENT_RESOLVED}"
  run_maybe_quiet \
    "ibmcloud cr login --client ${CONTAINER_CLIENT_RESOLVED}" \
    ibmcloud cr login --client "${CONTAINER_CLIENT_RESOLVED}"
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

# ************************
# Execution section
# ************************

require_command ibmcloud

if ! prebuilt_image_mode_enabled; then
  echo "Skipping local image build and push because DEPLOY_ARTIFACT_MODE=${DEPLOY_ARTIFACT_MODE}."
  echo "Use DEPLOY_ARTIFACT_MODE=prebuilt_images to enable the IBM Cloud Container Registry workflow."
  exit 0
fi

require_command jq
require_prebuilt_image_settings
ensure_icr_namespace
login_container_client_to_icr

build_and_push_service_image hr HR_database
build_and_push_service_image booking_api booking_system_rest
build_and_push_service_image mcp_api booking_system_mcp
build_and_push_service_image web_app galaxium-booking-web-app
build_and_push_service_image web_app_mcp galaxium-booking-web-app-mcp

# ************************
# Monitoring section
# ************************

cat <<EOF
Prebuilt image push summary
===========================

HR API:         $(image_ref_for_service hr)
Booking API:    $(image_ref_for_service booking_api)
MCP API:        $(image_ref_for_service mcp_api)
REST Web UI:    $(image_ref_for_service web_app)
MCP Web UI:     $(image_ref_for_service web_app_mcp)
EOF

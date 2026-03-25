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
DEPLOY_ARTIFACT_MODE="$(normalize_deploy_artifact_mode "${DEPLOY_ARTIFACT_MODE:-source_build}")"
FRONTEND_AUTH_REQUIRED_RESOLVED="$(resolve_frontend_auth_required)"

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

ce_app_url() {
  local app_name="$1"
  ibmcloud ce application get --name "${app_name}" --output url | tr -d '\r\n'
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

if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  require_var KEYCLOAK_REALM
  require_var OIDC_CLIENT_ID
fi

if prebuilt_image_mode_enabled; then
  require_prebuilt_image_settings
fi

select_project

hr_url="$(ce_app_url "${HR_APP_NAME}")"
booking_api_url="$(ce_app_url "${BOOKING_API_APP_NAME}")"
mcp_base_url="$(ce_app_url "${MCP_APP_NAME}")"
web_url="$(ce_app_url "${WEB_APP_NAME}")"
web_mcp_url="$(ce_app_url "${WEB_APP_MCP_APP_NAME}")"

if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  keycloak_url="$(resolve_keycloak_base_url)"
else
  keycloak_url=""
fi

cat <<EOF
Deployment summary
==================

Code Engine project: ${CE_PROJECT_NAME}
Stack auth mode:     ${STACK_AUTH_MODE}
Frontend login:      ${FRONTEND_AUTH_REQUIRED_RESOLVED}
Artifact mode:       ${DEPLOY_ARTIFACT_MODE}

Keycloak:            ${keycloak_url:-not deployed for this mode}
HR API:              ${hr_url}
Booking API:         ${booking_api_url}
MCP base URL:        ${mcp_base_url}
MCP endpoint:        ${mcp_base_url}/mcp
REST Web UI:         ${web_url}
MCP Web UI:          ${web_mcp_url}
Rendered config dir: ${DEPLOY_DIR}/generated
Booking API config:  ${BOOKING_API_CONFIGMAP_NAME}
MCP config:          ${MCP_CONFIGMAP_NAME}
REST UI config:      ${WEB_APP_CONFIGMAP_NAME}
MCP UI config:       ${WEB_APP_MCP_CONFIGMAP_NAME}

Important
---------

- Deployment order matters because Code Engine public URLs are only known after each application is created.
- Non-secret runtime settings are delivered through the service configmaps in this folder.
- The rendered env files are kept in ${DEPLOY_DIR}/generated so you can inspect what was sent to Code Engine.
- Keep the MCP transport on Streamable HTTP.
- Public MCP clients must use ${mcp_base_url}/mcp.
EOF

if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  cat <<EOF
- The package deploys backends first, then frontends, then syncs the Keycloak client with the final UI URLs.
EOF
else
  cat <<EOF
- This default Basic Auth path does not deploy Keycloak and does not require Keycloak client sync.
EOF
fi

cat <<EOF

Suggested checks
----------------

1. Booking API health:
   curl -i ${booking_api_url}/health

2. REST Web UI health:
   curl -i ${web_url}/api/health

3. MCP Web UI health:
   curl -i ${web_mcp_url}/api/health

4. MCP initialize without credentials:
   curl -i ${mcp_base_url}/mcp \\
     -H "Accept: application/json, text/event-stream" \\
     -H "Content-Type: application/json" \\
     -H "MCP-Protocol-Version: 2025-11-25" \\
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"code-engine-smoke","version":"1.0.0"}}}'
EOF

if prebuilt_image_mode_enabled; then
  cat <<EOF

Prebuilt image references
-------------------------

HR API image:         $(image_ref_for_service hr)
Booking API image:    $(image_ref_for_service booking_api)
MCP API image:        $(image_ref_for_service mcp_api)
REST Web UI image:    $(image_ref_for_service web_app)
MCP Web UI image:     $(image_ref_for_service web_app_mcp)
Registry secret:      ${ICR_REGISTRY_SECRET_NAME}
EOF
fi

if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  cat <<EOF

5. Keycloak realm metadata:
   curl -s ${keycloak_url}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration

6. MCP OAuth metadata:
   curl -s ${mcp_base_url}/.well-known/oauth-protected-resource
   curl -s ${mcp_base_url}/.well-known/oauth-authorization-server

7. Example token request shape:
   curl -s -X POST ${keycloak_url}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token \\
     -d "grant_type=client_credentials" \\
     -d "client_id=${OIDC_CLIENT_ID}" \\
     -d "client_secret=<OIDC_CLIENT_SECRET>"
EOF
else
  cat <<EOF

5. Basic Auth REST request:
   curl -i -u <BASIC_AUTH_USERNAME>:<BASIC_AUTH_PASSWORD> ${booking_api_url}/flights

6. Build the Basic Auth header:
   BASIC_TOKEN="\$(printf '%s' '<BASIC_AUTH_USERNAME>:<BASIC_AUTH_PASSWORD>' | base64 | tr -d '\\r\\n')"

7. Basic Auth MCP initialize:
   curl -i ${mcp_base_url}/mcp \\
     -H "Accept: application/json, text/event-stream" \\
     -H "Content-Type: application/json" \\
     -H "MCP-Protocol-Version: 2025-11-25" \\
     -H "Authorization: Basic \${BASIC_TOKEN}" \\
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"code-engine-smoke","version":"1.0.0"}}}'

8. Reuse the returned mcp-session-id for tools/list:
   curl -sS ${mcp_base_url}/mcp \\
     -H "Accept: application/json, text/event-stream" \\
     -H "Content-Type: application/json" \\
     -H "MCP-Protocol-Version: 2025-11-25" \\
     -H "MCP-Session-Id: <mcp-session-id>" \\
     -H "Authorization: Basic \${BASIC_TOKEN}" \\
     -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
EOF
fi

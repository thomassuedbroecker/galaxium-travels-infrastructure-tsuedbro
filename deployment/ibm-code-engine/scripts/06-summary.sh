#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_command ibmcloud
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

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

if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  require_var KEYCLOAK_REALM
  require_var OIDC_CLIENT_ID
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

Keycloak:            ${keycloak_url:-not deployed for this mode}
HR API:              ${hr_url}
Booking API:         ${booking_api_url}
MCP base URL:        ${mcp_base_url}
MCP endpoint:        ${mcp_base_url}/mcp
REST Web UI:         ${web_url}
MCP Web UI:          ${web_mcp_url}

Important
---------

- Deployment order matters because Code Engine public URLs are only known after each application is created.
- The package deploys backends first, then frontends, then syncs the Keycloak client with the final UI URLs.
- Keep the MCP transport on Streamable HTTP.
- Public MCP clients must use ${mcp_base_url}/mcp.

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

6. Basic Auth MCP request:
   python3 ../../local-container/mcp_test_app.py \\
     --mcp-url ${mcp_base_url}/mcp \\
     --auth-scheme basic \\
     --basic-username <BASIC_AUTH_USERNAME> \\
     --basic-password <BASIC_AUTH_PASSWORD>
EOF
fi

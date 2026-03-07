#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_command ibmcloud
require_var KEYCLOAK_APP_NAME
require_var HR_APP_NAME
require_var BOOKING_API_APP_NAME
require_var MCP_APP_NAME
require_var WEB_APP_NAME
require_var KEYCLOAK_REALM
require_var OIDC_CLIENT_ID

select_project

keycloak_url="$(ce_app_url "${KEYCLOAK_APP_NAME}")"
booking_api_url="$(ce_app_url "${BOOKING_API_APP_NAME}")"
mcp_url="$(ce_app_url "${MCP_APP_NAME}")"
web_url="$(ce_app_url "${WEB_APP_NAME}")"
hr_url="$(ce_app_url "${HR_APP_NAME}")"

cat <<EOF
Deployment summary
==================

Keycloak:    ${keycloak_url}
HR API:      ${hr_url}
Booking API: ${booking_api_url}
MCP API:     ${mcp_url}
Web UI:      ${web_url}

Suggested draft checks
----------------------

1. Keycloak realm metadata:
   curl -s ${keycloak_url}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration

2. Booking API health:
   curl -i ${booking_api_url}/health

3. Booking API auth rejection:
   curl -i ${booking_api_url}/flights

4. MCP metadata:
   curl -s ${mcp_url}/.well-known/oauth-protected-resource

5. Web login redirect:
   curl -i ${web_url}/

6. Example token request shape:
   curl -s -X POST ${keycloak_url}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token \\
     -d "grant_type=client_credentials" \\
     -d "client_id=${OIDC_CLIENT_ID}" \\
     -d "client_secret=<OIDC_CLIENT_SECRET>"
EOF

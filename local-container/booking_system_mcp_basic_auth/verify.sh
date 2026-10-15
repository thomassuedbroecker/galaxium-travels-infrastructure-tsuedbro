#!/usr/bin/env bash
# Verifies the Basic Auth MCP variant: 401 without or with wrong credentials,
# working MCP session with the configured credentials, no OAuth metadata.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../booking_system_mcp_lib.sh"
xmcp_load_env "${SCRIPT_DIR}/mcp.env"

MCP_BASE="http://localhost:${MCP_HOST_PORT:-8084}"
MCP_URL="${MCP_URL:-${MCP_BASE}/mcp}"
USERNAME="${BASIC_AUTH_USERNAME:-demo-basic-user}"
PASSWORD="${BASIC_AUTH_PASSWORD:-demo-basic-password}"
BASIC_TOKEN="$(printf '%s' "${USERNAME}:${PASSWORD}" | base64 | tr -d '\r\n')"
WRONG_TOKEN="$(printf '%s' "${USERNAME}:not-the-password" | base64 | tr -d '\r\n')"

xmcp_wait_for "${MCP_BASE}/" "MCP server" || xmcp_summary
xmcp_expect_rejected "${MCP_URL}" "" "no Authorization header" "Basic"
xmcp_expect_rejected "${MCP_URL}" "Basic ${WRONG_TOKEN}" "wrong password" "Basic"
xmcp_expect_rejected "${MCP_URL}" "Bearer some-token" "bearer token instead of Basic" "Basic"
xmcp_expect_tools "${MCP_URL}" "Basic ${BASIC_TOKEN}"
xmcp_expect_status "${MCP_BASE}/.well-known/oauth-protected-resource" 404 "OAuth metadata disabled"
xmcp_summary

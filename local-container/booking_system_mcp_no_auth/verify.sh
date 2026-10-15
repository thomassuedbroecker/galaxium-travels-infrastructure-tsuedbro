#!/usr/bin/env bash
# Verifies the no-auth MCP variant: open access, no OAuth metadata.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../booking_system_mcp_lib.sh"
xmcp_load_env "${SCRIPT_DIR}/mcp.env"

MCP_BASE="http://localhost:${MCP_HOST_PORT:-8084}"
MCP_URL="${MCP_URL:-${MCP_BASE}/mcp}"

xmcp_wait_for "${MCP_BASE}/" "MCP server" || xmcp_summary
xmcp_expect_tools "${MCP_URL}"
xmcp_expect_status "${MCP_BASE}/.well-known/oauth-protected-resource" 404 "OAuth metadata disabled"
xmcp_summary

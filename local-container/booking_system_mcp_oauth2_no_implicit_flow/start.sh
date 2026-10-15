#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../booking_system_mcp_lib.sh"

xmcp_compose "${SCRIPT_DIR}" up --build -d "$@"
xmcp_load_env "${SCRIPT_DIR}/mcp.env"
echo "MCP endpoint (OAuth 2.0 bearer): ${MCP_PUBLIC_BASE_URL:-http://localhost:8084}/mcp"
echo "Token URL: ${KEYCLOAK_PUBLIC_BASE_URL:-http://localhost:8086}/realms/galaxium/protocol/openid-connect/token"
echo "Keycloak needs ~30s on first start before tokens can be issued."

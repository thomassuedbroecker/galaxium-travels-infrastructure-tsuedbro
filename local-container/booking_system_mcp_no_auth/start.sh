#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../booking_system_mcp_lib.sh"

xmcp_compose "${SCRIPT_DIR}" up --build -d "$@"
xmcp_load_env "${SCRIPT_DIR}/mcp.env"
echo "MCP endpoint (no auth): http://localhost:${MCP_HOST_PORT:-8084}/mcp"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../booking_system_mcp_lib.sh"

if [[ ! -f "${SCRIPT_DIR}/mcp.env" ]]; then
  echo "No mcp.env found: using the demo credentials demo-basic-user / demo-basic-password."
fi
xmcp_compose "${SCRIPT_DIR}" up --build -d "$@"
xmcp_load_env "${SCRIPT_DIR}/mcp.env"
echo "MCP endpoint (Basic Auth): http://localhost:${MCP_HOST_PORT:-8084}/mcp"

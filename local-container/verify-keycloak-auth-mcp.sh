#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "Running focused MCP OAuth checks (protocol + Inspector CLI)..."
bash "${SCRIPT_DIR}/verify-keycloak-auth-e2e.sh" --scope mcp --with-inspector-cli "$@"

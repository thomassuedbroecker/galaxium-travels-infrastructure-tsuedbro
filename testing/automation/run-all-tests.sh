#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/run-rest-api-tests.sh"
bash "${SCRIPT_DIR}/run-ui-behavior-tests.sh"
bash "${SCRIPT_DIR}/run-mcp-integration-tests.sh"

echo
echo "All repository test suites completed."

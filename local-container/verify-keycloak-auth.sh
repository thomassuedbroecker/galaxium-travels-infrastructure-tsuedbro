#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "Running focused UI + REST OAuth checks (delegates to verify-keycloak-auth-e2e.sh --scope ui-rest)..."
bash "${SCRIPT_DIR}/verify-keycloak-auth-e2e.sh" --scope ui-rest "$@"

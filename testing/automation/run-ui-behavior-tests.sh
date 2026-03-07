#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ensure_docker
ensure_results_dir

trap cleanup_stack EXIT

bash "${LOCAL_CONTAINER_DIR}/verify-keycloak-auth-e2e.sh" \
  --scope ui-rest \
  --reports-dir "${GENERATED_RESULTS_DIR}/ui"

echo
echo "Saved UI behavior reports under:"
echo "  ${GENERATED_RESULTS_DIR}/ui"

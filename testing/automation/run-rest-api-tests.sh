#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ensure_docker
ensure_results_dir

trap cleanup_stack EXIT

RUN_ID="$(timestamp_utc)"
LOG_FILE="${GENERATED_RESULTS_DIR}/rest/rest-api-pytest-${RUN_ID}.log"

cd "${REPO_ROOT}"
docker compose -f "${COMPOSE_FILE}" run --rm --build booking_system \
  python -m pytest tests -q | tee "${LOG_FILE}"

echo
echo "Saved REST API test log:"
echo "  ${LOG_FILE}"

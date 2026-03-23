#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ensure_results_dir

RUN_ID="$(timestamp_utc)"
LOG_FILE="${GENERATED_RESULTS_DIR}/contracts/local-container-contracts-${RUN_ID}.log"

cd "${REPO_ROOT}"
python3 -m unittest testing.test_local_container_contracts -v | tee "${LOG_FILE}"

echo
echo "Saved local-container contract test log:"
echo "  ${LOG_FILE}"

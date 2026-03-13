#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE=""
UNITTEST_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --env-file requires a path"
        exit 1
      fi
      ENV_FILE="$2"
      shift 2
      ;;
    *)
      UNITTEST_ARGS+=("$1")
      shift
      ;;
  esac
done

cd "${REPO_ROOT}"

if [[ -n "${ENV_FILE}" ]]; then
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: env file not found: ${ENV_FILE}"
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

if [[ ${#UNITTEST_ARGS[@]} -gt 0 ]]; then
  python3 -m unittest discover -s testing/webui_matrix/tests -p 'test_*.py' -v "${UNITTEST_ARGS[@]}"
else
  python3 -m unittest discover -s testing/webui_matrix/tests -p 'test_*.py' -v
fi

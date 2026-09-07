#!/usr/bin/env bash
# stop-hr-app.sh
# Stops and removes the HR stack containers started by start-hr-app.sh.
#
# Usage:
#   ./stop-hr-app.sh                   # stop Python backend stack (default)
#   ./stop-hr-app.sh --backend python  # stop Python backend stack
#   ./stop-hr-app.sh --backend java    # stop Java backend stack
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Detect container runtime ──────────────────────────────────────────────────
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v podman-compose &>/dev/null; then
  COMPOSE="podman-compose"
else
  echo "ERROR: Neither 'docker compose' nor 'podman-compose' was found."
  exit 1
fi

# ── Parse arguments ───────────────────────────────────────────────────────────
BACKEND="python"
for arg in "$@"; do
  case "$arg" in
    --backend=python|--backend\ python) BACKEND="python" ;;
    --backend=java|--backend\ java)     BACKEND="java"   ;;
    --backend) : ;;
    python|java)
      if [[ "${PREV_ARG:-}" == "--backend" ]]; then BACKEND="$arg"; fi ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--backend python|java]"
      exit 1
      ;;
  esac
  PREV_ARG="$arg"
done

# ── Select compose file ───────────────────────────────────────────────────────
if [[ "$BACKEND" == "java" ]]; then
  COMPOSE_FILE="$SCRIPT_DIR/docker-compose.java-backend.yaml"
else
  COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yaml"
fi

echo "Stopping HR stack (backend: $BACKEND) ..."
$COMPOSE -f "$COMPOSE_FILE" down

echo "Done."

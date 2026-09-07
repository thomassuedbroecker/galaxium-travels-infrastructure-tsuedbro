#!/usr/bin/env bash
# start-hr-app.sh
# Builds and starts the HR stack (Quarkus Java frontend + chosen backend)
# using Docker Compose.
#
# Usage:
#   ./start-hr-app.sh                   # Python backend (default)
#   ./start-hr-app.sh --backend python  # Python HR backend  → http://localhost:8090
#   ./start-hr-app.sh --backend java    # Java HR backend    → http://localhost:8090
#   ./start-hr-app.sh --build           # force image rebuild
#   ./stop-hr-app.sh [--backend python|java]
#
# Ports (host-visible):
#   Frontend UI         : http://localhost:8090                   (both variants)
#   Frontend Swagger UI : http://localhost:8090/q/swagger-ui
#   Java backend        : http://localhost:8089/q/swagger-ui      (java backend only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Detect container runtime ──────────────────────────────────────────────────
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v podman-compose &>/dev/null; then
  COMPOSE="podman-compose"
else
  echo "ERROR: Neither 'docker compose' nor 'podman-compose' was found."
  echo "       Install Docker Desktop or Podman and try again."
  exit 1
fi

# ── Parse arguments ───────────────────────────────────────────────────────────
BACKEND="python"
BUILD_FLAG=""
for arg in "$@"; do
  case "$arg" in
    --backend=python|--backend\ python) BACKEND="python" ;;
    --backend=java|--backend\ java)     BACKEND="java"   ;;
    --backend)  : ;;          # value follows as next arg — handled below
    python|java)              # value after --backend
      if [[ "${PREV_ARG:-}" == "--backend" ]]; then BACKEND="$arg"; fi ;;
    --build) BUILD_FLAG="--build" ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--backend python|java] [--build]"
      exit 1
      ;;
  esac
  PREV_ARG="$arg"
done

# ── Select compose file ───────────────────────────────────────────────────────
if [[ "$BACKEND" == "java" ]]; then
  COMPOSE_FILE="$SCRIPT_DIR/docker-compose.java-backend.yaml"
  BACKEND_LABEL="Java (Quarkus, port 8089)"
else
  COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yaml"
  BACKEND_LABEL="Python (FastAPI, port 8081 internal)"
fi

echo "Starting HR stack"
echo "  Backend  : $BACKEND_LABEL"
echo "  Frontend : http://localhost:8090  (Quarkus + React)"
echo "  Compose  : $COMPOSE_FILE"
echo ""

# ── Start the stack ───────────────────────────────────────────────────────────
$COMPOSE -f "$COMPOSE_FILE" up -d $BUILD_FLAG

# ── Wait for the frontend health endpoint ─────────────────────────────────────
# Backend readiness is already gated by depends_on + healthcheck in the compose file.
echo "Waiting for HR frontend on http://localhost:8090 ..."
TIMEOUT=120
ELAPSED=0
until curl -sf http://localhost:8090/q/health >/dev/null 2>&1; do
  if (( ELAPSED >= TIMEOUT )); then
    echo ""
    # Distinguish "the app is broken" from "the container is fine but the
    # runtime does not forward published ports to the host" (seen with some
    # Rancher Desktop / Podman machine setups).
    if docker inspect -f '{{.State.Health.Status}}' hr_database_frontend_java 2>/dev/null \
         | grep -q healthy; then
      echo "WARNING: The frontend container reports HEALTHY, but http://localhost:8090"
      echo "         is not reachable from this host after ${TIMEOUT}s."
      echo "         The stack is running — your container runtime is most likely not"
      echo "         forwarding published ports to the host. Verify with:"
      echo "           docker run --rm --network <stack>_hr-java-net curlimages/curl \\"
      echo "             -s http://hr_database_frontend_java:8088/q/health"
      echo "         Then restart Docker Desktop / Rancher Desktop to restore forwarding."
      exit 1
    fi
    echo "ERROR: HR frontend did not become healthy within ${TIMEOUT}s."
    echo "       Check logs with:  $COMPOSE -f \"$COMPOSE_FILE\" logs"
    exit 1
  fi
  printf '.'
  sleep 2
  (( ELAPSED += 2 )) || true
done

echo ""
echo ""
echo "HR stack is ready:"
echo "  App:        http://localhost:8090"
echo "  Swagger UI: http://localhost:8090/q/swagger-ui"
if [[ "$BACKEND" == "java" ]]; then
  echo "  Backend Swagger UI: http://localhost:8089/q/swagger-ui"
fi
echo ""
echo "Useful commands:"
echo "  Logs (all):      $COMPOSE -f \"$COMPOSE_FILE\" logs -f"
echo "  Logs (frontend): $COMPOSE -f \"$COMPOSE_FILE\" logs -f hr_database_frontend_java"
if [[ "$BACKEND" == "java" ]]; then
  echo "  Logs (backend):  $COMPOSE -f \"$COMPOSE_FILE\" logs -f hr_database_backend_java"
else
  echo "  Logs (backend):  $COMPOSE -f \"$COMPOSE_FILE\" logs -f hr_database"
fi
echo "  Stop:            ./stop-hr-app.sh --backend $BACKEND"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/HR_database"
FRONTEND_DIR="$ROOT_DIR/hr_database_frontend"
BACKEND_VENV="$BACKEND_DIR/.venv"
BACKEND_LOG="$FRONTEND_DIR/hr_database_backend.log"
FRONTEND_LOG="$FRONTEND_DIR/hr_database_frontend.log"

cleanup() {
  if [[ -n "${FRONTEND_PID:-}" ]] && kill -0 "$FRONTEND_PID" 2>/dev/null; then
    kill "$FRONTEND_PID"
  fi
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" 2>/dev/null; then
    kill "$BACKEND_PID"
  fi
}

trap cleanup EXIT INT TERM

if [[ ! -d "$BACKEND_VENV" ]]; then
  python3 -m venv "$BACKEND_VENV"
fi

source "$BACKEND_VENV/bin/activate"
"$BACKEND_VENV/bin/pip" install -r "$BACKEND_DIR/requirements.txt" pandas

# Start the backend service in the folder, because it needs to find the database file in the current working directory.
cd "$BACKEND_DIR"
"$BACKEND_VENV/bin/python" "./app.py" >"$BACKEND_LOG" 2>&1 &
BACKEND_PID=$!
cd "$ROOT_DIR"

echo "Waiting for HR backend on http://localhost:8081 ..."
until curl -sf http://localhost:8081/employees >/dev/null; do
  sleep 1
done

echo "Starting HR frontend on http://localhost:8088 ..."
mvn -q -DskipTests package -f "$FRONTEND_DIR/pom.xml"
java -jar "$FRONTEND_DIR/target/quarkus-app/quarkus-run.jar" >"$FRONTEND_LOG" 2>&1 &
FRONTEND_PID=$!

echo "Waiting for HR frontend on http://localhost:8088 ..."
until curl -sf http://localhost:8088/q/health >/dev/null; do
  sleep 1
done

echo "HR app is ready:"
echo "  App:        http://localhost:8088"
echo "  Swagger UI: http://localhost:8088/q/swagger-ui"
echo "  Backend:    http://localhost:8081/docs"
echo ""
echo "Logs:"
echo "  Backend:  $BACKEND_LOG"
echo "  Frontend: $FRONTEND_LOG"
echo ""
echo "Press Ctrl+C to stop both services."

wait "$FRONTEND_PID"

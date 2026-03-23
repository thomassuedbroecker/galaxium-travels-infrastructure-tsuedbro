#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker_compose.basic-auth.yaml"
BASIC_AUTH_ENV_FILE="${BASIC_AUTH_ENV_FILE:-${SCRIPT_DIR}/basic-auth.env}"
REST_HEALTH_URL="http://localhost:8082/health"
REST_FLIGHTS_URL="http://localhost:8082/flights"
MCP_ROOT_URL="http://localhost:8084/"
MCP_URL="http://localhost:8084/mcp"
MCP_PAYLOAD='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"basic-auth-smoke-test","version":"1.0.0"}}}'

load_env_file_if_present() {
  local env_file="$1"
  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
  fi
}

load_env_file_if_present "${BASIC_AUTH_ENV_FILE}"

BASIC_AUTH_USERNAME="${BASIC_AUTH_USERNAME:-demo-basic-user}"
BASIC_AUTH_PASSWORD="${BASIC_AUTH_PASSWORD:-demo-basic-password}"
COMPOSE_ENV_ARGS=()
if [[ -f "${BASIC_AUTH_ENV_FILE}" ]]; then
  COMPOSE_ENV_ARGS=(--env-file "${BASIC_AUTH_ENV_FILE}")
fi

cleanup() {
  docker compose "${COMPOSE_ENV_ARGS[@]}" -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_status() {
  local expected="$1"
  local url="$2"
  shift 2

  local tmp_file
  tmp_file="$(mktemp)"
  local status
  status="$(curl -sS -o "${tmp_file}" -w "%{http_code}" "$@" "${url}" || true)"
  if [[ "${status}" != "${expected}" ]]; then
    echo "--- response body ---" >&2
    cat "${tmp_file}" >&2 || true
    rm -f "${tmp_file}"
    fail "Expected HTTP ${expected} from ${url}, got ${status}"
  fi
  rm -f "${tmp_file}"
}

wait_for_http() {
  local url="$1"
  local expected="$2"
  local attempts="${3:-30}"

  for _ in $(seq 1 "${attempts}"); do
    local status
    status="$(curl -s -o /dev/null -w "%{http_code}" "${url}" || true)"
    if [[ "${status}" == "${expected}" ]]; then
      return 0
    fi
    sleep 2
  done

  fail "Timed out waiting for ${url} to return ${expected}"
}

echo "Starting basic-auth backend stack..."
trap cleanup EXIT
docker compose "${COMPOSE_ENV_ARGS[@]}" -f "${COMPOSE_FILE}" up --build -d booking_system booking_system_mcp

wait_for_http "${REST_HEALTH_URL}" "200"
wait_for_http "${MCP_ROOT_URL}" "200"

echo "Checking REST API basic auth..."
require_status "401" "${REST_FLIGHTS_URL}"
require_status "401" "${REST_FLIGHTS_URL}" -u "${BASIC_AUTH_USERNAME}:wrong-password"
require_status "200" "${REST_FLIGHTS_URL}" -u "${BASIC_AUTH_USERNAME}:${BASIC_AUTH_PASSWORD}"

echo "Checking MCP basic auth..."
require_status \
  "401" \
  "${MCP_URL}" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d "${MCP_PAYLOAD}"

require_status \
  "401" \
  "${MCP_URL}" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -u "${BASIC_AUTH_USERNAME}:wrong-password" \
  -d "${MCP_PAYLOAD}"

python3 "${SCRIPT_DIR}/mcp_test_app.py" \
  --mcp-url "${MCP_URL}" \
  --auth-scheme basic \
  --basic-username "${BASIC_AUTH_USERNAME}" \
  --basic-password "${BASIC_AUTH_PASSWORD}"

echo "PASS: REST and MCP backends work with Basic Auth."

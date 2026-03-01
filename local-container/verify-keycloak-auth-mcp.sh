#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker_compose.yaml"

KEYCLOAK_OPENID_CONFIG_URL="http://localhost:8080/realms/galaxium/.well-known/openid-configuration"
MCP_ROOT_URL="http://localhost:8084/"
MCP_ENDPOINT_URL="http://localhost:8084/mcp"

TMP_MCP_NO_TOKEN_OUT="/tmp/galaxium_mcp_inspector_no_token.out"
TMP_MCP_WITH_TOKEN_OUT="/tmp/galaxium_mcp_inspector_with_token.out"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: required command '${command_name}' is not available."
    exit 1
  fi
}

wait_for_url() {
  local name="$1"
  local url="$2"
  local attempts="${3:-60}"
  local sleep_seconds="${4:-2}"

  for _ in $(seq 1 "${attempts}"); do
    if curl -sf "${url}" >/dev/null 2>&1; then
      echo "OK: ${name} is ready (${url})"
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  echo "ERROR: timeout waiting for ${name} at ${url}"
  return 1
}

run_mcp_inspector_cli() {
  local endpoint_url="$1"
  local output_file="$2"
  shift 2
  local extra_args=("$@")
  local status=0

  if command -v npx >/dev/null 2>&1; then
    set +e
    npx -y @modelcontextprotocol/inspector \
      --cli "${endpoint_url}" \
      --transport http \
      --method tools/list \
      --verbose \
      "${extra_args[@]}" >"${output_file}" 2>&1
    status=$?
    set -e
    return "${status}"
  fi

  local container_endpoint_url="${endpoint_url/127.0.0.1/host.docker.internal}"
  container_endpoint_url="${container_endpoint_url/localhost/host.docker.internal}"
  local docker_cmd=(docker run --rm)
  if [[ "$(uname -s)" == "Linux" ]]; then
    docker_cmd+=(--add-host host.docker.internal:host-gateway)
  fi
  docker_cmd+=(
    ghcr.io/modelcontextprotocol/inspector:latest
    --cli "${container_endpoint_url}"
    --transport http
    --method tools/list
    --verbose
    "${extra_args[@]}"
  )

  set +e
  "${docker_cmd[@]}" >"${output_file}" 2>&1
  status=$?
  set -e
  return "${status}"
}

require_command docker
require_command curl

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not running or not accessible."
  exit 1
fi

export HR_DATABASE_DOCKER_CONTEXT="${SCRIPT_DIR}/../HR_database"
export BOOKING_SYSTEM_REST_DOCKER_CONTEXT="${SCRIPT_DIR}/../booking_system_rest"
export WEB_APP_DOCKER_CONTEXT="${SCRIPT_DIR}/../galaxium-booking-web-app"
export BOOKING_SYSTEM_MCP_DOCKER_CONTEXT="${SCRIPT_DIR}/../booking_system_mcp"
export APP_USER="${APP_USER:-local}"

cd "${SCRIPT_DIR}"

docker compose -f "${COMPOSE_FILE}" build booking_system booking_system_mcp web_app
docker compose -f "${COMPOSE_FILE}" up -d --force-recreate keycloak booking_system booking_system_mcp web_app

wait_for_url "Keycloak" "${KEYCLOAK_OPENID_CONFIG_URL}"
wait_for_url "MCP server root" "${MCP_ROOT_URL}"

USER_ACCESS_TOKEN="$(
  docker exec web_app python -c 'import requests; r=requests.post("http://keycloak:8080/realms/galaxium/protocol/openid-connect/token", data={"grant_type":"password","client_id":"web-app-proxy","client_secret":"web-app-proxy-secret","username":"demo-user","password":"demo-user-password"}, timeout=10); r.raise_for_status(); print(r.json().get("access_token",""))'
)"
if [[ -z "${USER_ACCESS_TOKEN}" ]]; then
  echo "ERROR: failed to acquire Keycloak traveler token (password grant)"
  exit 1
fi

if run_mcp_inspector_cli "${MCP_ENDPOINT_URL}" "${TMP_MCP_NO_TOKEN_OUT}"; then
  echo "ERROR: MCP Inspector unexpectedly succeeded without a bearer token."
  cat "${TMP_MCP_NO_TOKEN_OUT}"
  exit 1
fi

if ! grep -Eiq "401|Missing bearer token|UNAUTHORIZED" "${TMP_MCP_NO_TOKEN_OUT}"; then
  echo "ERROR: MCP Inspector failure output without token does not show auth rejection:"
  cat "${TMP_MCP_NO_TOKEN_OUT}"
  exit 1
fi
echo "OK: MCP server rejected unauthenticated Inspector request"

if ! run_mcp_inspector_cli \
  "${MCP_ENDPOINT_URL}" \
  "${TMP_MCP_WITH_TOKEN_OUT}" \
  --header "Authorization: Bearer ${USER_ACCESS_TOKEN}"; then
  echo "ERROR: MCP Inspector call with bearer token failed."
  cat "${TMP_MCP_WITH_TOKEN_OUT}"
  exit 1
fi

if ! grep -Eq "list_flights|book_flight|get_bookings|cancel_booking|register_user|get_user_id" "${TMP_MCP_WITH_TOKEN_OUT}"; then
  echo "ERROR: MCP Inspector authenticated output does not contain expected tool names."
  cat "${TMP_MCP_WITH_TOKEN_OUT}"
  exit 1
fi
echo "OK: MCP Inspector listed MCP tools with a valid Keycloak bearer token"

echo
echo "PASS: Local containerized MCP authentication is enforced and Inspector connectivity works."
echo "Summary:"
echo "  1) MCP Inspector without token -> rejected (401)"
echo "  2) MCP Inspector with Keycloak traveler token -> tools/list succeeded"
echo "  3) MCP server is reachable locally via Docker Compose on http://localhost:8084/mcp"

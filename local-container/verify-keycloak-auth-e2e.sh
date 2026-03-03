#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker_compose.yaml"

KEYCLOAK_OPENID_CONFIG_URL="http://localhost:8080/realms/galaxium/.well-known/openid-configuration"
BOOKING_HEALTH_URL="http://localhost:8082/health"
BOOKING_FLIGHTS_URL="http://localhost:8082/flights"
WEB_APP_ROOT_URL="http://localhost:8083/"
WEB_APP_LOGIN_URL="http://localhost:8083/login"
WEB_APP_HEALTH_URL="http://localhost:8083/api/health"
WEB_APP_TRAVELER_URL="http://localhost:8083/api/traveler"
WEB_APP_FLIGHTS_URL="http://localhost:8083/api/flights"
WEB_APP_BOOKINGS_URL="http://localhost:8083/api/bookings"
WEB_APP_BOOK_URL="http://localhost:8083/api/book"
MCP_ROOT_URL="http://localhost:8084/"
MCP_ENDPOINT_URL="http://localhost:8084/mcp"

TMP_NO_TOKEN_BODY="/tmp/galaxium_e2e_no_token_body.json"
TMP_WITH_TOKEN_BODY="/tmp/galaxium_e2e_with_token_body.json"
TMP_WEB_ROOT_HEADERS="/tmp/galaxium_e2e_web_root_headers.txt"
TMP_WEB_UNAUTH_BODY="/tmp/galaxium_e2e_web_unauth_body.json"
TMP_WEB_TRAVELER_BODY="/tmp/galaxium_e2e_web_traveler_body.json"
TMP_WEB_FLIGHTS_BODY="/tmp/galaxium_e2e_web_flights_body.json"
TMP_WEB_BOOKINGS_BODY="/tmp/galaxium_e2e_web_bookings_body.json"
TMP_WEB_BOOK_BODY="/tmp/galaxium_e2e_web_book_body.json"
TMP_MCP_NO_TOKEN_BODY="/tmp/galaxium_e2e_mcp_no_token_body.json"
TMP_MCP_INIT_BODY="/tmp/galaxium_e2e_mcp_initialize_body.json"
TMP_MCP_TOOLS_BODY="/tmp/galaxium_e2e_mcp_tools_body.json"
WEB_COOKIE_FILE="/tmp/galaxium_e2e_web_cookies.txt"

MCP_INITIALIZE_PAYLOAD='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"local-e2e-auth-check","version":"1.0.0"}}}'
MCP_TOOLS_LIST_PAYLOAD='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

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

assert_status() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "ERROR: ${label} expected HTTP ${expected} but got ${actual}"
    exit 1
  fi
  echo "OK: ${label} returned HTTP ${actual}"
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -Eiq "${pattern}" "${file}"; then
    echo "ERROR: ${label} did not match expected pattern '${pattern}'"
    cat "${file}"
    exit 1
  fi
  echo "OK: ${label} matches expected pattern"
}

assert_mcp_tool_present() {
  local file="$1"
  local tool_name="$2"
  if ! jq -e --arg tool "${tool_name}" 'any(.result.tools[]?; .name == $tool)' "${file}" >/dev/null; then
    echo "ERROR: MCP tools/list response missing tool '${tool_name}'"
    cat "${file}"
    exit 1
  fi
  echo "OK: MCP tools/list contains '${tool_name}'"
}

require_command docker
require_command curl
require_command jq

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
wait_for_url "Booking API" "${BOOKING_HEALTH_URL}"
wait_for_url "Web app" "${WEB_APP_HEALTH_URL}"
wait_for_url "MCP root" "${MCP_ROOT_URL}"

bash "${SCRIPT_DIR}/sync-keycloak-inspector-client.sh"
bash "${SCRIPT_DIR}/verify-keycloak-inspector-client.sh"

USER_ACCESS_TOKEN="$(
  docker exec web_app python -c 'import requests; r=requests.post("http://keycloak:8080/realms/galaxium/protocol/openid-connect/token", data={"grant_type":"password","client_id":"web-app-proxy","client_secret":"web-app-proxy-secret","username":"demo-user","password":"demo-user-password"}, timeout=10); r.raise_for_status(); print(r.json().get("access_token",""))'
)"
USER_ACCESS_TOKEN="$(echo "${USER_ACCESS_TOKEN}" | tr -d '\r\n')"
if [[ -z "${USER_ACCESS_TOKEN}" ]]; then
  echo "ERROR: failed to acquire Keycloak traveler token (password grant)"
  exit 1
fi
echo "OK: traveler token acquired"

# UI checks
WEB_ROOT_STATUS="$(curl -s -o /tmp/galaxium_e2e_web_root_body.html -D "${TMP_WEB_ROOT_HEADERS}" -w '%{http_code}' "${WEB_APP_ROOT_URL}")"
assert_status "302" "${WEB_ROOT_STATUS}" "Web app root without login"
if ! grep -qi '^location: /login' "${TMP_WEB_ROOT_HEADERS}"; then
  echo "ERROR: web app root did not redirect to /login"
  cat "${TMP_WEB_ROOT_HEADERS}"
  exit 1
fi
echo "OK: Web app root redirects to /login when traveler is not authenticated"

WEB_UNAUTH_STATUS="$(curl -s -o "${TMP_WEB_UNAUTH_BODY}" -w '%{http_code}' "${WEB_APP_FLIGHTS_URL}")"
assert_status "401" "${WEB_UNAUTH_STATUS}" "Web app API without traveler session"
assert_contains "${TMP_WEB_UNAUTH_BODY}" "frontend_auth_required" "Web app unauthenticated API response"

rm -f "${WEB_COOKIE_FILE}"
LOGIN_STATUS="$(curl -s -o /tmp/galaxium_e2e_login_body.html -c "${WEB_COOKIE_FILE}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' \
  -X POST "${WEB_APP_LOGIN_URL}" \
  --data-urlencode "username=demo-user" \
  --data-urlencode "password=demo-user-password" \
  --data-urlencode "next=/")"
assert_status "302" "${LOGIN_STATUS}" "Traveler login via web app"

TRAVELER_STATUS="$(curl -s -o "${TMP_WEB_TRAVELER_BODY}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' "${WEB_APP_TRAVELER_URL}")"
assert_status "200" "${TRAVELER_STATUS}" "Web app traveler session endpoint"
assert_contains "${TMP_WEB_TRAVELER_BODY}" '"traveler_id"' "Web app traveler payload"

WEB_FLIGHTS_STATUS="$(curl -s -o "${TMP_WEB_FLIGHTS_BODY}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' "${WEB_APP_FLIGHTS_URL}")"
assert_status "200" "${WEB_FLIGHTS_STATUS}" "Web app flights endpoint with traveler session"
assert_contains "${TMP_WEB_FLIGHTS_BODY}" '"flight_id"' "Web app flights payload"

WEB_BOOKINGS_STATUS="$(curl -s -o "${TMP_WEB_BOOKINGS_BODY}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' "${WEB_APP_BOOKINGS_URL}")"
assert_status "200" "${WEB_BOOKINGS_STATUS}" "Web app bookings endpoint with traveler session"

WEB_BOOK_STATUS="$(curl -s -o "${TMP_WEB_BOOK_BODY}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' \
  -H "Content-Type: application/json" \
  -X POST "${WEB_APP_BOOK_URL}" \
  -d '{"flight_id":1}')"
assert_status "200" "${WEB_BOOK_STATUS}" "Web app booking endpoint with traveler session"
if grep -q 'frontend_auth_required' "${TMP_WEB_BOOK_BODY}"; then
  echo "ERROR: booking call unexpectedly returned frontend auth challenge"
  cat "${TMP_WEB_BOOK_BODY}"
  exit 1
fi
echo "OK: Web app booking action works after traveler login"

# REST checks
NO_TOKEN_STATUS="$(curl -s -o "${TMP_NO_TOKEN_BODY}" -w '%{http_code}' "${BOOKING_FLIGHTS_URL}")"
assert_status "401" "${NO_TOKEN_STATUS}" "Booking API without bearer token"
assert_contains "${TMP_NO_TOKEN_BODY}" "Missing bearer token" "Booking API unauthenticated response"

WITH_TOKEN_STATUS="$(
  curl -s -o "${TMP_WITH_TOKEN_BODY}" -w '%{http_code}' \
    -H "Authorization: Bearer ${USER_ACCESS_TOKEN}" \
    "${BOOKING_FLIGHTS_URL}"
)"
assert_status "200" "${WITH_TOKEN_STATUS}" "Booking API with Keycloak traveler token"
assert_contains "${TMP_WITH_TOKEN_BODY}" '"flight_id"' "Booking API authenticated response"

# MCP checks (protocol-first JSON-RPC)
MCP_NO_TOKEN_STATUS="$(
  curl -s -o "${TMP_MCP_NO_TOKEN_BODY}" -w '%{http_code}' \
    -X POST "${MCP_ENDPOINT_URL}" \
    -H "Content-Type: application/json" \
    -H "MCP-Protocol-Version: 2025-11-25" \
    -d "${MCP_INITIALIZE_PAYLOAD}"
)"
assert_status "401" "${MCP_NO_TOKEN_STATUS}" "MCP initialize without bearer token"
assert_contains "${TMP_MCP_NO_TOKEN_BODY}" "Missing bearer token" "MCP unauthenticated response"

MCP_INIT_STATUS="$(
  curl -s -o "${TMP_MCP_INIT_BODY}" -w '%{http_code}' \
    -X POST "${MCP_ENDPOINT_URL}" \
    -H "Content-Type: application/json" \
    -H "MCP-Protocol-Version: 2025-11-25" \
    -H "Authorization: Bearer ${USER_ACCESS_TOKEN}" \
    -d "${MCP_INITIALIZE_PAYLOAD}"
)"
assert_status "200" "${MCP_INIT_STATUS}" "MCP initialize with bearer token"
if ! jq -e '.result.serverInfo.name == "Booking System MCP"' "${TMP_MCP_INIT_BODY}" >/dev/null; then
  echo "ERROR: MCP initialize response does not contain expected serverInfo"
  cat "${TMP_MCP_INIT_BODY}"
  exit 1
fi
echo "OK: MCP initialize returned expected server info"

MCP_TOOLS_STATUS="$(
  curl -s -o "${TMP_MCP_TOOLS_BODY}" -w '%{http_code}' \
    -X POST "${MCP_ENDPOINT_URL}" \
    -H "Content-Type: application/json" \
    -H "MCP-Protocol-Version: 2025-11-25" \
    -H "Authorization: Bearer ${USER_ACCESS_TOKEN}" \
    -d "${MCP_TOOLS_LIST_PAYLOAD}"
)"
assert_status "200" "${MCP_TOOLS_STATUS}" "MCP tools/list with bearer token"

for tool_name in list_flights book_flight get_bookings cancel_booking register_user get_user_id; do
  assert_mcp_tool_present "${TMP_MCP_TOOLS_BODY}" "${tool_name}"
done

echo
echo "PASS: Local Docker Compose OAuth enforcement verified end-to-end."
echo "Validated:"
echo "  1) UI auth enforced (redirect/login/session-protected API)"
echo "  2) REST API bearer-token enforcement (401 unauthenticated, 200 authenticated)"
echo "  3) MCP bearer-token enforcement via JSON-RPC (401 unauthenticated, initialize/tools/list authenticated)"
echo "  4) Keycloak Inspector client config synced and verified before tests"

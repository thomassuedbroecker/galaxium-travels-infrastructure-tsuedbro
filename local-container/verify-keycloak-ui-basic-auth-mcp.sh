#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_COMPOSE_FILE="${SCRIPT_DIR}/docker_compose.yaml"
OVERLAY_COMPOSE_FILE="${SCRIPT_DIR}/docker_compose.mcp-ui-keycloak-basic.yaml"
BASIC_AUTH_ENV_FILE="${BASIC_AUTH_ENV_FILE:-${SCRIPT_DIR}/basic-auth.env}"
RESULTS_DIR_DEFAULT="${SCRIPT_DIR}/test-results"
REPORTS_DIR="${REPORTS_DIR:-${RESULTS_DIR_DEFAULT}}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_FILE="${REPORTS_DIR}/keycloak-ui-basic-auth-mcp-${RUN_ID}.md"

KEYCLOAK_OPENID_CONFIG_URL="http://localhost:8086/realms/galaxium/.well-known/openid-configuration"
MCP_ROOT_URL="http://localhost:8084/"
MCP_ENDPOINT_URL="http://localhost:8084/mcp"
WEB_APP_MCP_ROOT_URL="http://localhost:8085/"
WEB_APP_MCP_LOGIN_URL="http://localhost:8085/login"
WEB_APP_MCP_HEALTH_URL="http://localhost:8085/api/health"
WEB_APP_MCP_TRAVELER_URL="http://localhost:8085/api/traveler"
WEB_APP_MCP_FLIGHTS_URL="http://localhost:8085/api/flights"
WEB_APP_MCP_BOOKINGS_URL="http://localhost:8085/api/bookings"
WEB_APP_MCP_BOOK_URL="http://localhost:8085/api/book"
MCP_ACCEPT_HEADER="${MCP_ACCEPT_HEADER:-application/json, text/event-stream}"
TRAVELER_USERNAME="${TRAVELER_USERNAME:-demo-user}"
TRAVELER_PASSWORD="${TRAVELER_PASSWORD:-demo-user-password}"

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

usage() {
  cat <<'EOF'
Usage:
  bash verify-keycloak-ui-basic-auth-mcp.sh [--reports-dir <dir>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reports-dir)
      REPORTS_DIR="$2"
      REPORT_FILE="${REPORTS_DIR}/keycloak-ui-basic-auth-mcp-${RUN_ID}.md"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

cleanup() {
  docker compose "${COMPOSE_ENV_ARGS[@]}" \
    -f "${BASE_COMPOSE_FILE}" \
    -f "${OVERLAY_COMPOSE_FILE}" \
    down --remove-orphans >/dev/null 2>&1 || true
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "required command '${command_name}' is not available"
  fi
}

wait_for_http() {
  local url="$1"
  local expected="$2"
  local attempts="${3:-50}"

  for _ in $(seq 1 "${attempts}"); do
    local status
    status="$(curl -s -o /dev/null -w "%{http_code}" "${url}" || true)"
    if [[ "${status}" == "${expected}" ]]; then
      return 0
    fi
    sleep 2
  done

  fail "timed out waiting for ${url} to return ${expected}"
}

request_json() {
  local output_file="$1"
  shift

  local status
  status="$(curl -sS -o "${output_file}" -w "%{http_code}" "$@" || true)"
  printf '%s' "${status}"
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    fail "${label} expected HTTP ${expected} but got ${actual}"
  fi
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -Eq "${pattern}" "${file}"; then
    echo "--- ${label} payload ---" >&2
    cat "${file}" >&2
    fail "${label} did not match expected pattern '${pattern}'"
  fi
}

assert_jq() {
  local file="$1"
  local expr="$2"
  local label="$3"
  if ! jq -e "${expr}" "${file}" >/dev/null; then
    echo "--- ${label} payload ---" >&2
    cat "${file}" >&2
    fail "${label} did not match expected jq expression: ${expr}"
  fi
}

assert_jq_with_arg() {
  local file="$1"
  local arg_kind="$2"
  local arg_name="$3"
  local arg_value="$4"
  local expr="$5"
  local label="$6"
  if ! jq -e "${arg_kind}" "${arg_name}" "${arg_value}" "${expr}" "${file}" >/dev/null; then
    echo "--- ${label} payload ---" >&2
    cat "${file}" >&2
    fail "${label} did not match expected jq expression: ${expr}"
  fi
}

require_command docker
require_command curl
require_command jq
require_command python3

if ! docker info >/dev/null 2>&1; then
  fail "Docker is not running or not accessible"
fi

mkdir -p "${REPORTS_DIR}"

login_page_file="$(mktemp)"
health_file="$(mktemp)"
root_headers_file="$(mktemp)"
unauth_flights_file="$(mktemp)"
traveler_file="$(mktemp)"
flights_file="$(mktemp)"
book_file="$(mktemp)"
bookings_file="$(mktemp)"
cookie_file="$(mktemp)"
mcp_no_auth_file="$(mktemp)"
login_response_file="$(mktemp)"
trap 'rm -f "${login_page_file}" "${health_file}" "${root_headers_file}" "${unauth_flights_file}" "${traveler_file}" "${flights_file}" "${book_file}" "${bookings_file}" "${cookie_file}" "${mcp_no_auth_file}" "${login_response_file}"; cleanup' EXIT

echo "Starting Keycloak UI + Basic Auth MCP stack..."
docker compose "${COMPOSE_ENV_ARGS[@]}" \
  -f "${BASE_COMPOSE_FILE}" \
  -f "${OVERLAY_COMPOSE_FILE}" \
  up --build -d keycloak booking_system_mcp web_app_mcp

wait_for_http "${KEYCLOAK_OPENID_CONFIG_URL}" "200"
wait_for_http "${MCP_ROOT_URL}" "200"
wait_for_http "${WEB_APP_MCP_HEALTH_URL}" "200"

assert_status "200" "$(request_json "${health_file}" "${WEB_APP_MCP_HEALTH_URL}")" "MCP frontend health"
assert_jq "${health_file}" '.backend_auth_mode == "basic" and .frontend_auth_required == true and .auth_mode == "traveler-login-basic-backend"' "MCP frontend health"

assert_status "200" "$(request_json "${login_page_file}" "${WEB_APP_MCP_LOGIN_URL}")" "MCP login page"
assert_contains "${login_page_file}" 'Keycloak browser session \+ Basic Auth MCP calls' "MCP login page"
assert_contains "${login_page_file}" 'MCP' "MCP login page"

root_status="$(curl -sS -D "${root_headers_file}" -o /dev/null -w "%{http_code}" "${WEB_APP_MCP_ROOT_URL}" || true)"
assert_status "302" "${root_status}" "MCP root redirect"
assert_contains "${root_headers_file}" 'Location: /login' "MCP root redirect"

assert_status "401" "$(request_json "${unauth_flights_file}" "${WEB_APP_MCP_FLIGHTS_URL}")" "MCP unauthenticated flights"
assert_contains "${unauth_flights_file}" 'frontend_auth_required' "MCP unauthenticated flights"

assert_status \
  "401" \
  "$(request_json "${mcp_no_auth_file}" \
    -H "Accept: ${MCP_ACCEPT_HEADER}" \
    -H "Content-Type: application/json" \
    -H "MCP-Protocol-Version: 2025-11-25" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"mixed-auth-check","version":"1.0.0"}}}' \
    "${MCP_ENDPOINT_URL}")" \
  "MCP backend unauthenticated initialize"

login_status="$(
  curl -sS -L \
    -c "${cookie_file}" \
    -b "${cookie_file}" \
    -o "${login_response_file}" \
    -w "%{http_code}" \
    --data-urlencode "username=${TRAVELER_USERNAME}" \
    --data-urlencode "password=${TRAVELER_PASSWORD}" \
    --data-urlencode "next=/" \
    "${WEB_APP_MCP_LOGIN_URL}" || true
)"
assert_status "200" "${login_status}" "MCP login flow"
assert_contains "${login_response_file}" 'Traveler login \+ shared Basic Auth' "MCP post-login page"

assert_status "200" "$(request_json "${traveler_file}" -c "${cookie_file}" -b "${cookie_file}" "${WEB_APP_MCP_TRAVELER_URL}")" "MCP traveler session"
assert_jq "${traveler_file}" '.traveler_id and .traveler_id > 0 and (.email | length > 0)' "MCP traveler session"

assert_status "200" "$(request_json "${flights_file}" -c "${cookie_file}" -b "${cookie_file}" "${WEB_APP_MCP_FLIGHTS_URL}")" "MCP flights"
assert_jq "${flights_file}" 'type == "array" and length > 0' "MCP flights"

flight_id="$(jq -r 'map(select((.seats_available // 0) > 0)) | .[0].flight_id // empty' "${flights_file}")"
if [[ -z "${flight_id}" ]]; then
  fail "no bookable flight exposed by MCP frontend"
fi

assert_status \
  "200" \
  "$(request_json "${book_file}" \
    -c "${cookie_file}" \
    -b "${cookie_file}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "{\"flight_id\":${flight_id}}" \
    "${WEB_APP_MCP_BOOK_URL}")" \
  "MCP booking"
assert_jq_with_arg "${book_file}" --argjson flight_id "${flight_id}" '.booking_id and .booking_id > 0 and .flight_id == $flight_id' "MCP booking"

assert_status "200" "$(request_json "${bookings_file}" -c "${cookie_file}" -b "${cookie_file}" "${WEB_APP_MCP_BOOKINGS_URL}")" "MCP bookings"
assert_jq "${bookings_file}" 'type == "array" and length > 0' "MCP bookings"

python3 "${SCRIPT_DIR}/mcp_test_app.py" \
  --mcp-url "${MCP_ENDPOINT_URL}" \
  --auth-scheme basic \
  --basic-username "${BASIC_AUTH_USERNAME}" \
  --basic-password "${BASIC_AUTH_PASSWORD}" >/dev/null

cat > "${REPORT_FILE}" <<EOF
# Keycloak UI -> MCP Basic Auth Verification

- Generated at (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Compose files:
  - ${BASE_COMPOSE_FILE}
  - ${OVERLAY_COMPOSE_FILE}
- Basic Auth env file: ${BASIC_AUTH_ENV_FILE}
- Traveler login user: ${TRAVELER_USERNAME}
- MCP frontend health: ok
- Login page copy reflects the mixed mode
- Unauthenticated UI API calls are rejected
- Unauthenticated MCP initialize is rejected with Basic Auth enforcement
- Keycloak login succeeds through the MCP UI
- Traveler sync, flight listing, booking, and booking listing succeed after login
- Direct Basic Auth MCP verification via \`mcp_test_app.py\` succeeded
EOF

echo "PASS: Keycloak UI login and MCP Basic Auth backend work together."
echo "Saved report: ${REPORT_FILE}"

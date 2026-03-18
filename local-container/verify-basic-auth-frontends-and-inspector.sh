#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker_compose.basic-auth.yaml"

REST_ROOT_URL="http://localhost:8083"
MCP_ROOT_URL="http://localhost:8085"
REST_HEALTH_URL="${REST_ROOT_URL}/api/health"
MCP_HEALTH_URL="${MCP_ROOT_URL}/api/health"
REST_FLIGHTS_URL="${REST_ROOT_URL}/api/flights"
MCP_FLIGHTS_URL="${MCP_ROOT_URL}/api/flights"

BASIC_AUTH_USERNAME="${BASIC_AUTH_USERNAME:-demo-basic-user}"
BASIC_AUTH_PASSWORD="${BASIC_AUTH_PASSWORD:-demo-basic-password}"

cleanup() {
  docker compose -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true
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
  local attempts="${3:-40}"

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

run_frontend_guest_flow() {
  local label="$1"
  local base_url="$2"
  local flights_url="$3"
  local traveler_name="$4"
  local traveler_email="$5"

  local cookie_file
  cookie_file="$(mktemp)"
  local traveler_file
  traveler_file="$(mktemp)"
  local flights_file
  flights_file="$(mktemp)"
  local lookup_file
  lookup_file="$(mktemp)"
  local register_file
  register_file="$(mktemp)"
  local booking_file
  booking_file="$(mktemp)"
  local bookings_file
  bookings_file="$(mktemp)"
  trap 'rm -f "${cookie_file}" "${traveler_file}" "${flights_file}" "${lookup_file}" "${register_file}" "${booking_file}" "${bookings_file}"' RETURN

  local traveler_status
  traveler_status="$(request_json "${traveler_file}" -c "${cookie_file}" -b "${cookie_file}" "${base_url}/api/traveler")"
  assert_status "200" "${traveler_status}" "${label} traveler preflight"
  assert_jq "${traveler_file}" '.frontend_auth_required == false and (.traveler_id | not)' "${label} traveler preflight"

  local flights_status
  flights_status="$(request_json "${flights_file}" "${flights_url}")"
  assert_status "200" "${flights_status}" "${label} flights"
  assert_jq "${flights_file}" 'type == "array" and length > 0' "${label} flights"

  local flight_id
  flight_id="$(jq -r 'map(select((.seats_available // 0) > 0)) | .[0].flight_id // empty' "${flights_file}")"
  if [[ -z "${flight_id}" ]]; then
    fail "${label} did not expose any flight with available seats"
  fi

  local lookup_status
  lookup_status="$(request_json "${lookup_file}" -c "${cookie_file}" -b "${cookie_file}" "${base_url}/api/get_user?name=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "${traveler_name}")&email=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "${traveler_email}")")"
  assert_status "200" "${lookup_status}" "${label} traveler lookup"

  if jq -e '.traveler_id and .traveler_id > 0' "${lookup_file}" >/dev/null; then
    :
  elif jq -e '.success == false and .error_code == "USER_NOT_FOUND"' "${lookup_file}" >/dev/null; then
    local register_status
    register_status="$(request_json "${register_file}" \
      -c "${cookie_file}" \
      -b "${cookie_file}" \
      -H "Content-Type: application/json" \
      -X POST \
      -d "{\"name\":\"${traveler_name}\",\"email\":\"${traveler_email}\"}" \
      "${base_url}/api/register")"
    assert_status "200" "${register_status}" "${label} traveler register"
    assert_jq "${register_file}" '.traveler_id and .traveler_id > 0' "${label} traveler register"
  else
    echo "--- ${label} traveler lookup payload ---" >&2
    cat "${lookup_file}" >&2
    fail "${label} traveler lookup returned an unexpected payload"
  fi

  traveler_status="$(request_json "${traveler_file}" -c "${cookie_file}" -b "${cookie_file}" "${base_url}/api/traveler")"
  assert_status "200" "${traveler_status}" "${label} traveler session"
  assert_jq_with_arg "${traveler_file}" --arg email "${traveler_email}" '.traveler_id and .traveler_id > 0 and .email == $email' "${label} traveler session"

  local booking_status
  booking_status="$(request_json "${booking_file}" \
    -c "${cookie_file}" \
    -b "${cookie_file}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "{\"flight_id\":${flight_id}}" \
    "${base_url}/api/book")"
  assert_status "200" "${booking_status}" "${label} booking"
  assert_jq_with_arg "${booking_file}" --argjson flight_id "${flight_id}" '.booking_id and .booking_id > 0 and .flight_id == $flight_id' "${label} booking"

  local bookings_status
  bookings_status="$(request_json "${bookings_file}" -c "${cookie_file}" -b "${cookie_file}" "${base_url}/api/bookings")"
  assert_status "200" "${bookings_status}" "${label} bookings"
  assert_jq "${bookings_file}" 'type == "array" and length > 0' "${label} bookings"
}

verify_inspector_basic_auth() {
  local results_dir
  results_dir="$(mktemp -d)"
  trap 'rm -rf "${results_dir}"' RETURN

  INSPECTOR_AUTO_START=0 \
  MCP_AUTH_SCHEME=basic \
  MCP_URL="http://localhost:8084/mcp" \
  BASIC_AUTH_USERNAME="${BASIC_AUTH_USERNAME}" \
  BASIC_AUTH_PASSWORD="${BASIC_AUTH_PASSWORD}" \
  RESULTS_DIR="${results_dir}" \
  bash "${SCRIPT_DIR}/start-mcp-inspector-ui.sh" >/tmp/galaxium_basic_auth_inspector.out

  local config_file
  config_file="$(find "${results_dir}" -name 'inspector-ui-config-*.md' | head -n 1)"
  if [[ -z "${config_file}" ]]; then
    fail "inspector config file was not generated"
  fi

  grep -q 'Transport type: Streamable HTTP' "${config_file}" || fail "inspector config did not keep Streamable HTTP transport"
  grep -q '"Authorization":"Basic ' "${config_file}" || fail "inspector config did not include a Basic Authorization header"
}

require_command docker
require_command curl
require_command jq
require_command python3

if ! docker info >/dev/null 2>&1; then
  fail "Docker is not running or not accessible"
fi

trap cleanup EXIT

echo "Starting basic-auth stack with frontends..."
docker compose -f "${COMPOSE_FILE}" up --build -d booking_system booking_system_mcp web_app web_app_mcp

wait_for_http "${REST_HEALTH_URL}" "200"
wait_for_http "${MCP_HEALTH_URL}" "200"

rest_health_file="$(mktemp)"
mcp_health_file="$(mktemp)"
trap 'rm -f "${rest_health_file}" "${mcp_health_file}"' RETURN

assert_status "200" "$(request_json "${rest_health_file}" "${REST_HEALTH_URL}")" "REST frontend health"
assert_status "200" "$(request_json "${mcp_health_file}" "${MCP_HEALTH_URL}")" "MCP frontend health"
assert_jq "${rest_health_file}" '.backend_auth_mode == "basic" and .frontend_auth_required == false and .auth_mode == "basic-backend"' "REST frontend health"
assert_jq "${mcp_health_file}" '.backend_auth_mode == "basic" and .frontend_auth_required == false and .auth_mode == "basic-backend"' "MCP frontend health"

run_frontend_guest_flow "REST frontend" "${REST_ROOT_URL}" "${REST_FLIGHTS_URL}" "REST Basic Traveler" "rest-basic-traveler@example.com"
run_frontend_guest_flow "MCP frontend" "${MCP_ROOT_URL}" "${MCP_FLIGHTS_URL}" "MCP Basic Traveler" "mcp-basic-traveler@example.com"
verify_inspector_basic_auth

echo "PASS: REST frontend, MCP frontend, and MCP Inspector all work with Basic Auth and Streamable HTTP."

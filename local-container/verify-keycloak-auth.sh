#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker_compose.yaml"

KEYCLOAK_OPENID_CONFIG_URL="http://localhost:8080/realms/galaxium/.well-known/openid-configuration"
BOOKING_HEALTH_URL="http://localhost:8082/health"
BOOKING_FLIGHTS_URL="http://localhost:8082/flights"
WEB_PROXY_HEALTH_URL="http://localhost:8083/api/health"
WEB_PROXY_FLIGHTS_URL="http://localhost:8083/api/flights"

TMP_NO_TOKEN_BODY="/tmp/galaxium_no_token_body.json"
TMP_WITH_TOKEN_BODY="/tmp/galaxium_with_token_body.json"
TMP_PROXY_BODY="/tmp/galaxium_proxy_body.json"

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
docker compose -f "${COMPOSE_FILE}" up -d --no-build

wait_for_url "Keycloak" "${KEYCLOAK_OPENID_CONFIG_URL}"
wait_for_url "Booking API" "${BOOKING_HEALTH_URL}"
wait_for_url "Web proxy" "${WEB_PROXY_HEALTH_URL}"

NO_TOKEN_STATUS="$(curl -s -o "${TMP_NO_TOKEN_BODY}" -w '%{http_code}' "${BOOKING_FLIGHTS_URL}")"
assert_status "401" "${NO_TOKEN_STATUS}" "Booking API without bearer token"

if ! grep -q "Missing bearer token" "${TMP_NO_TOKEN_BODY}"; then
  echo "ERROR: expected 'Missing bearer token' response body but got:"
  cat "${TMP_NO_TOKEN_BODY}"
  exit 1
fi
echo "OK: Booking API reports missing bearer token when no token is provided"

ACCESS_TOKEN="$(
  docker exec web_app python -c "import requests; r=requests.post('http://keycloak:8080/realms/galaxium/protocol/openid-connect/token', data={'grant_type':'client_credentials','client_id':'web-app-proxy','client_secret':'web-app-proxy-secret'}, timeout=10); r.raise_for_status(); print(r.json().get('access_token',''))"
)"

if [[ -z "${ACCESS_TOKEN}" ]]; then
  echo "ERROR: failed to acquire Keycloak access token"
  exit 1
fi

WITH_TOKEN_STATUS="$(
  curl -s -o "${TMP_WITH_TOKEN_BODY}" -w '%{http_code}' \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${BOOKING_FLIGHTS_URL}"
)"
assert_status "200" "${WITH_TOKEN_STATUS}" "Booking API with Keycloak bearer token"

if ! grep -q "\"flight_id\"" "${TMP_WITH_TOKEN_BODY}"; then
  echo "ERROR: booking API token-authenticated response does not look correct:"
  cat "${TMP_WITH_TOKEN_BODY}"
  exit 1
fi
echo "OK: Booking API returned flight data with a valid Keycloak token"

WEB_PROXY_STATUS="$(curl -s -o "${TMP_PROXY_BODY}" -w '%{http_code}' "${WEB_PROXY_FLIGHTS_URL}")"
assert_status "200" "${WEB_PROXY_STATUS}" "Web proxy to Booking API"

if ! grep -q "\"flight_id\"" "${TMP_PROXY_BODY}"; then
  echo "ERROR: web proxy response does not look correct:"
  cat "${TMP_PROXY_BODY}"
  exit 1
fi
echo "OK: Web proxy can access booking API through OAuth2 client credentials"

echo
echo "PASS: Keycloak is actively used by the application."
echo "Summary:"
echo "  1) No token -> Booking API rejected request (401)"
echo "  2) Valid Keycloak token -> Booking API accepted request (200)"
echo "  3) Web proxy -> Successfully obtains token and calls Booking API (200)"

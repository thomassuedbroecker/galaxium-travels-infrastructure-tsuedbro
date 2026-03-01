#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker_compose.yaml"

KEYCLOAK_OPENID_CONFIG_URL="http://localhost:8080/realms/galaxium/.well-known/openid-configuration"
KEYCLOAK_TOKEN_URL="http://localhost:8080/realms/galaxium/protocol/openid-connect/token"
BOOKING_HEALTH_URL="http://localhost:8082/health"
BOOKING_FLIGHTS_URL="http://localhost:8082/flights"
WEB_APP_ROOT_URL="http://localhost:8083/"
WEB_APP_LOGIN_URL="http://localhost:8083/login"
WEB_APP_HEALTH_URL="http://localhost:8083/api/health"
WEB_APP_TRAVELER_URL="http://localhost:8083/api/traveler"
WEB_APP_FLIGHTS_URL="http://localhost:8083/api/flights"
WEB_APP_BOOKINGS_URL="http://localhost:8083/api/bookings"
WEB_APP_BOOK_URL="http://localhost:8083/api/book"

TMP_NO_TOKEN_BODY="/tmp/galaxium_no_token_body.json"
TMP_WITH_TOKEN_BODY="/tmp/galaxium_with_token_body.json"
TMP_WEB_ROOT_HEADERS="/tmp/galaxium_web_root_headers.txt"
TMP_WEB_UNAUTH_BODY="/tmp/galaxium_web_unauth_body.json"
TMP_WEB_TRAVELER_BODY="/tmp/galaxium_web_traveler_body.json"
TMP_WEB_FLIGHTS_BODY="/tmp/galaxium_web_flights_body.json"
TMP_WEB_BOOKINGS_BODY="/tmp/galaxium_web_bookings_body.json"
TMP_WEB_BOOK_BODY="/tmp/galaxium_web_book_body.json"
WEB_COOKIE_FILE="/tmp/galaxium_web_cookies.txt"

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

docker compose -f "${COMPOSE_FILE}" build booking_system web_app
# Force recreation to reset state (sqlite + keycloak realm import behavior)
docker compose -f "${COMPOSE_FILE}" up -d --force-recreate

wait_for_url "Keycloak" "${KEYCLOAK_OPENID_CONFIG_URL}"
wait_for_url "Booking API" "${BOOKING_HEALTH_URL}"
wait_for_url "Web app" "${WEB_APP_HEALTH_URL}"

# 1) Backend endpoints are protected
NO_TOKEN_STATUS="$(curl -s -o "${TMP_NO_TOKEN_BODY}" -w '%{http_code}' "${BOOKING_FLIGHTS_URL}")"
assert_status "401" "${NO_TOKEN_STATUS}" "Booking API without bearer token"
if ! grep -q "Missing bearer token" "${TMP_NO_TOKEN_BODY}"; then
  echo "ERROR: expected 'Missing bearer token' response body but got:"
  cat "${TMP_NO_TOKEN_BODY}"
  exit 1
fi
echo "OK: Booking API reports missing bearer token when no token is provided"

USER_ACCESS_TOKEN="$(
  docker exec web_app python -c 'import requests; r=requests.post("http://keycloak:8080/realms/galaxium/protocol/openid-connect/token", data={"grant_type":"password","client_id":"web-app-proxy","client_secret":"web-app-proxy-secret","username":"demo-user","password":"demo-user-password"}, timeout=10); r.raise_for_status(); print(r.json().get("access_token",""))'
)"
if [[ -z "${USER_ACCESS_TOKEN}" ]]; then
  echo "ERROR: failed to acquire Keycloak traveler token (password grant)"
  exit 1
fi

WITH_TOKEN_STATUS="$(
  curl -s -o "${TMP_WITH_TOKEN_BODY}" -w '%{http_code}' \
    -H "Authorization: Bearer ${USER_ACCESS_TOKEN}" \
    "${BOOKING_FLIGHTS_URL}"
)"
assert_status "200" "${WITH_TOKEN_STATUS}" "Booking API with Keycloak traveler token"
if ! grep -q '"flight_id"' "${TMP_WITH_TOKEN_BODY}"; then
  echo "ERROR: booking API token-authenticated response does not look correct:"
  cat "${TMP_WITH_TOKEN_BODY}"
  exit 1
fi
echo "OK: Booking API returned flight data with a valid traveler token"

# 2) Frontend requires traveler login
WEB_ROOT_STATUS="$(curl -s -o /tmp/galaxium_web_root_body.html -D "${TMP_WEB_ROOT_HEADERS}" -w '%{http_code}' "${WEB_APP_ROOT_URL}")"
assert_status "302" "${WEB_ROOT_STATUS}" "Web app root without login"
if ! grep -qi '^location: /login' "${TMP_WEB_ROOT_HEADERS}"; then
  echo "ERROR: web app root did not redirect to /login"
  cat "${TMP_WEB_ROOT_HEADERS}"
  exit 1
fi
echo "OK: Web app root redirects to /login when traveler is not authenticated"

WEB_UNAUTH_STATUS="$(curl -s -o "${TMP_WEB_UNAUTH_BODY}" -w '%{http_code}' "${WEB_APP_FLIGHTS_URL}")"
assert_status "401" "${WEB_UNAUTH_STATUS}" "Web app API without traveler session"
if ! grep -q 'frontend_auth_required' "${TMP_WEB_UNAUTH_BODY}"; then
  echo "ERROR: expected frontend auth challenge response but got:"
  cat "${TMP_WEB_UNAUTH_BODY}"
  exit 1
fi
echo "OK: Web app API blocks unauthenticated traveler requests"

rm -f "${WEB_COOKIE_FILE}"
LOGIN_STATUS="$(curl -s -o /tmp/galaxium_login_body.html -c "${WEB_COOKIE_FILE}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' \
  -X POST "${WEB_APP_LOGIN_URL}" \
  --data-urlencode "username=demo-user" \
  --data-urlencode "password=demo-user-password" \
  --data-urlencode "next=/")"
assert_status "302" "${LOGIN_STATUS}" "Traveler login via web app"

TRAVELER_STATUS="$(curl -s -o "${TMP_WEB_TRAVELER_BODY}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' "${WEB_APP_TRAVELER_URL}")"
assert_status "200" "${TRAVELER_STATUS}" "Web app traveler session endpoint"
if ! grep -q '"traveler_id"' "${TMP_WEB_TRAVELER_BODY}"; then
  echo "ERROR: traveler session payload missing traveler_id"
  cat "${TMP_WEB_TRAVELER_BODY}"
  exit 1
fi
echo "OK: Traveler session exists after login"

WEB_FLIGHTS_STATUS="$(curl -s -o "${TMP_WEB_FLIGHTS_BODY}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' "${WEB_APP_FLIGHTS_URL}")"
assert_status "200" "${WEB_FLIGHTS_STATUS}" "Web app flights endpoint with traveler session"

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

echo
echo "PASS: Expected traveler authentication flow is enforced."
echo "Summary:"
echo "  1) Web app root is inaccessible without login (redirects to /login)"
echo "  2) Web app API is blocked without traveler session (401)"
echo "  3) Traveler login via Keycloak succeeds"
echo "  4) Backend booking functionality requires and accepts Keycloak token"
echo "  5) Web app booking/list actions work only after traveler authentication"

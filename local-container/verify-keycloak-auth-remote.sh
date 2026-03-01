#!/usr/bin/env bash
set -euo pipefail

# Verify Keycloak-protected deployment without Docker Compose.
# Required environment variables:
# - BOOKING_API_BASE_URL (example: https://booking-api....codeengine.appdomain.cloud)
# - KEYCLOAK_TOKEN_URL (example: https://keycloak.../realms/galaxium/protocol/openid-connect/token)
# - OIDC_CLIENT_ID (example: web-app-proxy)
# - OIDC_CLIENT_SECRET
#
# Optional:
# - WEB_APP_BASE_URL (example: https://web-app....codeengine.appdomain.cloud)

BOOKING_API_BASE_URL="${BOOKING_API_BASE_URL:-}"
KEYCLOAK_TOKEN_URL="${KEYCLOAK_TOKEN_URL:-}"
OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-}"
OIDC_CLIENT_SECRET="${OIDC_CLIENT_SECRET:-}"
WEB_APP_BASE_URL="${WEB_APP_BASE_URL:-}"

TMP_NO_TOKEN_BODY="/tmp/galaxium_remote_no_token_body.json"
TMP_WITH_TOKEN_BODY="/tmp/galaxium_remote_with_token_body.json"
TMP_WEB_APP_BODY="/tmp/galaxium_remote_web_app_body.json"

require_var() {
  local name="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    echo "ERROR: ${name} is required."
    exit 1
  fi
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

require_var "BOOKING_API_BASE_URL" "${BOOKING_API_BASE_URL}"
require_var "KEYCLOAK_TOKEN_URL" "${KEYCLOAK_TOKEN_URL}"
require_var "OIDC_CLIENT_ID" "${OIDC_CLIENT_ID}"
require_var "OIDC_CLIENT_SECRET" "${OIDC_CLIENT_SECRET}"

BOOKING_FLIGHTS_URL="${BOOKING_API_BASE_URL%/}/flights"
BOOKING_HEALTH_URL="${BOOKING_API_BASE_URL%/}/health"
WEB_APP_FLIGHTS_URL="${WEB_APP_BASE_URL%/}/api/flights"

echo "Checking booking API health..."
BOOKING_HEALTH_STATUS="$(curl -s -o /dev/null -w '%{http_code}' "${BOOKING_HEALTH_URL}")"
assert_status "200" "${BOOKING_HEALTH_STATUS}" "Booking API health"

NO_TOKEN_STATUS="$(curl -s -o "${TMP_NO_TOKEN_BODY}" -w '%{http_code}' "${BOOKING_FLIGHTS_URL}")"
assert_status "401" "${NO_TOKEN_STATUS}" "Booking API without bearer token"

if ! grep -q "Missing bearer token" "${TMP_NO_TOKEN_BODY}"; then
  echo "ERROR: expected 'Missing bearer token' response body but got:"
  cat "${TMP_NO_TOKEN_BODY}"
  exit 1
fi
echo "OK: Booking API reports missing bearer token when no token is provided"

TOKEN_JSON="$(
  curl -s -X POST "${KEYCLOAK_TOKEN_URL}" \
    -d "grant_type=client_credentials" \
    -d "client_id=${OIDC_CLIENT_ID}" \
    -d "client_secret=${OIDC_CLIENT_SECRET}"
)"
ACCESS_TOKEN="$(echo "${TOKEN_JSON}" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
if [[ -z "${ACCESS_TOKEN}" ]]; then
  echo "ERROR: failed to acquire Keycloak access token"
  echo "Token response:"
  echo "${TOKEN_JSON}"
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

if [[ -n "${WEB_APP_BASE_URL}" ]]; then
  WEB_APP_STATUS="$(curl -s -o "${TMP_WEB_APP_BODY}" -w '%{http_code}' "${WEB_APP_FLIGHTS_URL}")"
  assert_status "200" "${WEB_APP_STATUS}" "Web app proxy /api/flights"
  if ! grep -q "\"flight_id\"" "${TMP_WEB_APP_BODY}"; then
    echo "ERROR: web app response does not look correct:"
    cat "${TMP_WEB_APP_BODY}"
    exit 1
  fi
  echo "OK: Web app proxy can access booking API through OAuth2"
fi

echo
echo "PASS: Keycloak authentication is enforced for the deployment."
echo "Summary:"
echo "  1) No token -> Booking API rejected request (401)"
echo "  2) Valid Keycloak token -> Booking API accepted request (200)"
if [[ -n "${WEB_APP_BASE_URL}" ]]; then
  echo "  3) Web app proxy endpoint -> returned data successfully (200)"
fi

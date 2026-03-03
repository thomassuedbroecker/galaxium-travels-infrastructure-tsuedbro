#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker_compose.yaml"
RESULTS_DIR_DEFAULT="${SCRIPT_DIR}/test-results"

SCOPE="all"
WITH_INSPECTOR_CLI="false"
REPORTS_DIR="${REPORTS_DIR:-${RESULTS_DIR_DEFAULT}}"
MCP_ACCEPT_HEADER="${MCP_ACCEPT_HEADER:-application/json, text/event-stream}"

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
MCP_OAUTH_PROTECTED_RESOURCE_URL="http://localhost:8084/.well-known/oauth-protected-resource"
MCP_OAUTH_AUTH_SERVER_URL="http://localhost:8084/.well-known/oauth-authorization-server"

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
TMP_MCP_OAUTH_PROTECTED_RESOURCE_BODY="/tmp/galaxium_e2e_mcp_oauth_protected_resource.json"
TMP_MCP_OAUTH_AUTH_SERVER_BODY="/tmp/galaxium_e2e_mcp_oauth_auth_server.json"
TMP_MCP_NO_TOKEN_OUT="/tmp/galaxium_e2e_mcp_inspector_no_token.out"
TMP_MCP_WITH_TOKEN_OUT="/tmp/galaxium_e2e_mcp_inspector_with_token.out"
WEB_COOKIE_FILE="/tmp/galaxium_e2e_web_cookies.txt"

MCP_INITIALIZE_PAYLOAD='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"local-e2e-auth-check","version":"1.0.0"}}}'
MCP_TOOLS_LIST_PAYLOAD='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

RUN_ID=""
STARTED_AT_UTC=""
LOG_FILE=""
REPORT_MD=""
REPORT_JSON=""
STEPS_FILE=""

STATUS="PASS"
FAIL_RECORDED="false"
CURRENT_STEP_ID=""
CURRENT_STEP_DESC=""
FAIL_REASON=""
USER_ACCESS_TOKEN=""

usage() {
  cat <<'EOF'
Usage:
  bash verify-keycloak-auth-e2e.sh [--scope all|ui-rest|mcp] [--with-inspector-cli] [--reports-dir <dir>]

Options:
  --scope               Select test scope (default: all)
  --with-inspector-cli  Add MCP Inspector CLI checks (mainly for MCP scope)
  --reports-dir         Directory for saved test reports (default: local-container/test-results)
  -h, --help            Show this help
EOF
}

sanitize() {
  echo "${1:-}" | tr '\n' ' ' | tr '\t' ' '
}

record_step() {
  local step_id="$1"
  local description="$2"
  local step_status="$3"
  local details="${4:-}"
  printf '%s\t%s\t%s\t%s\n' \
    "${step_id}" \
    "$(sanitize "${description}")" \
    "${step_status}" \
    "$(sanitize "${details}")" >> "${STEPS_FILE}"
}

start_step() {
  CURRENT_STEP_ID="$1"
  CURRENT_STEP_DESC="$2"
  echo
  echo "[${CURRENT_STEP_ID}] ${CURRENT_STEP_DESC}"
}

pass_step() {
  local details="${1:-}"
  record_step "${CURRENT_STEP_ID}" "${CURRENT_STEP_DESC}" "PASS" "${details}"
}

fail_step() {
  local message="$1"
  STATUS="FAIL"
  FAIL_REASON="${message}"
  if [[ "${FAIL_RECORDED}" != "true" ]]; then
    record_step "${CURRENT_STEP_ID:-UNCLASSIFIED}" "${CURRENT_STEP_DESC:-Unclassified failure}" "FAIL" "${message}"
    FAIL_RECORDED="true"
  fi
  echo "ERROR: ${message}"
  exit 1
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail_step "required command '${command_name}' is not available"
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

  fail_step "timeout waiting for ${name} at ${url}"
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    fail_step "${label} expected HTTP ${expected} but got ${actual}"
  fi
  echo "OK: ${label} returned HTTP ${actual}"
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -Eiq "${pattern}" "${file}"; then
    echo "Failed file content:"
    cat "${file}"
    fail_step "${label} did not match expected pattern '${pattern}'"
  fi
  echo "OK: ${label} matches expected pattern"
}

assert_mcp_tool_present() {
  local file="$1"
  local tool_name="$2"
  if ! jq -e --arg tool "${tool_name}" 'any(.result.tools[]?; .name == $tool)' "${file}" >/dev/null; then
    echo "Failed MCP tools/list payload:"
    cat "${file}"
    fail_step "MCP tools/list response missing tool '${tool_name}'"
  fi
  echo "OK: MCP tools/list contains '${tool_name}'"
}

run_mcp_inspector_cli() {
  local endpoint_url="$1"
  local output_file="$2"
  shift 2
  local extra_args=("$@")
  local cli_status=0

  if command -v npx >/dev/null 2>&1; then
    set +e
    npx -y @modelcontextprotocol/inspector \
      --cli "${endpoint_url}" \
      --transport http \
      --method tools/list \
      --verbose \
      "${extra_args[@]}" >"${output_file}" 2>&1
    cli_status=$?
    set -e
    return "${cli_status}"
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
  cli_status=$?
  set -e
  return "${cli_status}"
}

compose_prepare() {
  if ! docker info >/dev/null 2>&1; then
    fail_step "Docker is not running or not accessible"
  fi

  export HR_DATABASE_DOCKER_CONTEXT="${SCRIPT_DIR}/../HR_database"
  export BOOKING_SYSTEM_REST_DOCKER_CONTEXT="${SCRIPT_DIR}/../booking_system_rest"
  export WEB_APP_DOCKER_CONTEXT="${SCRIPT_DIR}/../galaxium-booking-web-app"
  export BOOKING_SYSTEM_MCP_DOCKER_CONTEXT="${SCRIPT_DIR}/../booking_system_mcp"
  export APP_USER="${APP_USER:-local}"

  cd "${SCRIPT_DIR}"
  docker compose -f "${COMPOSE_FILE}" build booking_system booking_system_mcp web_app
  docker compose -f "${COMPOSE_FILE}" up -d --force-recreate keycloak booking_system booking_system_mcp web_app
}

obtain_traveler_token() {
  USER_ACCESS_TOKEN="$(
    docker exec web_app python -c 'import requests; r=requests.post("http://keycloak:8080/realms/galaxium/protocol/openid-connect/token", data={"grant_type":"password","client_id":"web-app-proxy","client_secret":"web-app-proxy-secret","username":"demo-user","password":"demo-user-password"}, timeout=10); r.raise_for_status(); print(r.json().get("access_token",""))'
  )"
  USER_ACCESS_TOKEN="$(echo "${USER_ACCESS_TOKEN}" | tr -d '\r\n')"
  if [[ -z "${USER_ACCESS_TOKEN}" ]]; then
    fail_step "failed to acquire Keycloak traveler token (password grant)"
  fi
  echo "OK: traveler token acquired"
}

run_ui_and_rest_tests() {
  start_step "E2E-001" "Unauthenticated UI root redirects to /login"
  local web_root_status
  web_root_status="$(curl -s -o /tmp/galaxium_e2e_web_root_body.html -D "${TMP_WEB_ROOT_HEADERS}" -w '%{http_code}' "${WEB_APP_ROOT_URL}")"
  assert_status "302" "${web_root_status}" "Web app root without login"
  if ! grep -qi '^location: /login' "${TMP_WEB_ROOT_HEADERS}"; then
    fail_step "web app root did not redirect to /login"
  fi
  pass_step "UI redirect check passed"

  start_step "E2E-002" "Unauthenticated UI API is rejected"
  local web_unauth_status
  web_unauth_status="$(curl -s -o "${TMP_WEB_UNAUTH_BODY}" -w '%{http_code}' "${WEB_APP_FLIGHTS_URL}")"
  assert_status "401" "${web_unauth_status}" "Web app API without traveler session"
  assert_contains "${TMP_WEB_UNAUTH_BODY}" "frontend_auth_required" "Web app unauthenticated API response"
  pass_step "UI unauthenticated API rejection verified"

  start_step "E2E-003" "Traveler login succeeds and UI session APIs work"
  rm -f "${WEB_COOKIE_FILE}"
  local login_status traveler_status web_flights_status web_bookings_status web_book_status
  login_status="$(curl -s -o /tmp/galaxium_e2e_login_body.html -c "${WEB_COOKIE_FILE}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' \
    -X POST "${WEB_APP_LOGIN_URL}" \
    --data-urlencode "username=demo-user" \
    --data-urlencode "password=demo-user-password" \
    --data-urlencode "next=/")"
  assert_status "302" "${login_status}" "Traveler login via web app"

  traveler_status="$(curl -s -o "${TMP_WEB_TRAVELER_BODY}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' "${WEB_APP_TRAVELER_URL}")"
  assert_status "200" "${traveler_status}" "Web app traveler session endpoint"
  assert_contains "${TMP_WEB_TRAVELER_BODY}" '"traveler_id"' "Web app traveler payload"

  web_flights_status="$(curl -s -o "${TMP_WEB_FLIGHTS_BODY}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' "${WEB_APP_FLIGHTS_URL}")"
  assert_status "200" "${web_flights_status}" "Web app flights endpoint with traveler session"
  assert_contains "${TMP_WEB_FLIGHTS_BODY}" '"flight_id"' "Web app flights payload"

  web_bookings_status="$(curl -s -o "${TMP_WEB_BOOKINGS_BODY}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' "${WEB_APP_BOOKINGS_URL}")"
  assert_status "200" "${web_bookings_status}" "Web app bookings endpoint with traveler session"

  web_book_status="$(curl -s -o "${TMP_WEB_BOOK_BODY}" -b "${WEB_COOKIE_FILE}" -w '%{http_code}' \
    -H "Content-Type: application/json" \
    -X POST "${WEB_APP_BOOK_URL}" \
    -d '{"flight_id":1}')"
  assert_status "200" "${web_book_status}" "Web app booking endpoint with traveler session"
  if grep -q 'frontend_auth_required' "${TMP_WEB_BOOK_BODY}"; then
    fail_step "web app booking call unexpectedly returned frontend auth challenge"
  fi
  pass_step "Traveler login + UI session API checks passed"

  start_step "E2E-004" "REST endpoint rejects missing bearer token"
  local rest_no_token_status
  rest_no_token_status="$(curl -s -o "${TMP_NO_TOKEN_BODY}" -w '%{http_code}' "${BOOKING_FLIGHTS_URL}")"
  assert_status "401" "${rest_no_token_status}" "Booking API without bearer token"
  assert_contains "${TMP_NO_TOKEN_BODY}" "Missing bearer token" "Booking API unauthenticated response"
  pass_step "REST unauthenticated check passed"

  start_step "E2E-005" "REST endpoint accepts valid Keycloak token"
  local rest_with_token_status
  rest_with_token_status="$(
    curl -s -o "${TMP_WITH_TOKEN_BODY}" -w '%{http_code}' \
      -H "Authorization: Bearer ${USER_ACCESS_TOKEN}" \
      "${BOOKING_FLIGHTS_URL}"
  )"
  assert_status "200" "${rest_with_token_status}" "Booking API with Keycloak traveler token"
  assert_contains "${TMP_WITH_TOKEN_BODY}" '"flight_id"' "Booking API authenticated response"
  pass_step "REST authenticated check passed"
}

run_mcp_protocol_tests() {
  start_step "E2E-006" "MCP JSON-RPC initialize rejects missing bearer token"
  local mcp_no_token_status
  mcp_no_token_status="$(
    curl -s -o "${TMP_MCP_NO_TOKEN_BODY}" -w '%{http_code}' \
      -X POST "${MCP_ENDPOINT_URL}" \
      -H "Content-Type: application/json" \
      -H "Accept: ${MCP_ACCEPT_HEADER}" \
      -H "MCP-Protocol-Version: 2025-11-25" \
      -d "${MCP_INITIALIZE_PAYLOAD}"
  )"
  assert_status "401" "${mcp_no_token_status}" "MCP initialize without bearer token"
  assert_contains "${TMP_MCP_NO_TOKEN_BODY}" "Missing bearer token" "MCP unauthenticated response"
  pass_step "MCP unauthenticated rejection verified"

  start_step "E2E-007" "MCP initialize + tools/list succeed with bearer token"
  local mcp_init_status mcp_tools_status
  mcp_init_status="$(
    curl -s -o "${TMP_MCP_INIT_BODY}" -w '%{http_code}' \
      -X POST "${MCP_ENDPOINT_URL}" \
      -H "Content-Type: application/json" \
      -H "Accept: ${MCP_ACCEPT_HEADER}" \
      -H "MCP-Protocol-Version: 2025-11-25" \
      -H "Authorization: Bearer ${USER_ACCESS_TOKEN}" \
      -d "${MCP_INITIALIZE_PAYLOAD}"
  )"
  assert_status "200" "${mcp_init_status}" "MCP initialize with bearer token"
  if ! jq -e '.result.serverInfo.name == "Booking System MCP"' "${TMP_MCP_INIT_BODY}" >/dev/null; then
    fail_step "MCP initialize response does not contain expected serverInfo"
  fi

  mcp_tools_status="$(
    curl -s -o "${TMP_MCP_TOOLS_BODY}" -w '%{http_code}' \
      -X POST "${MCP_ENDPOINT_URL}" \
      -H "Content-Type: application/json" \
      -H "Accept: ${MCP_ACCEPT_HEADER}" \
      -H "MCP-Protocol-Version: 2025-11-25" \
      -H "Authorization: Bearer ${USER_ACCESS_TOKEN}" \
      -d "${MCP_TOOLS_LIST_PAYLOAD}"
  )"
  assert_status "200" "${mcp_tools_status}" "MCP tools/list with bearer token"
  for tool_name in list_flights book_flight get_bookings cancel_booking register_user get_user_id; do
    assert_mcp_tool_present "${TMP_MCP_TOOLS_BODY}" "${tool_name}"
  done
  pass_step "MCP authenticated JSON-RPC checks passed"
}

run_mcp_metadata_discovery_checks() {
  start_step "E2E-009" "MCP OAuth metadata discovery endpoints are reachable"

  local protected_resource_status auth_server_status
  protected_resource_status="$(
    curl -s -o "${TMP_MCP_OAUTH_PROTECTED_RESOURCE_BODY}" -w '%{http_code}' \
      "${MCP_OAUTH_PROTECTED_RESOURCE_URL}"
  )"
  assert_status "200" "${protected_resource_status}" "MCP oauth-protected-resource endpoint"
  if ! jq -e '.resource and .authorization_servers and (.authorization_servers | length > 0)' "${TMP_MCP_OAUTH_PROTECTED_RESOURCE_BODY}" >/dev/null; then
    fail_step "MCP oauth-protected-resource payload missing expected metadata fields"
  fi

  auth_server_status="$(
    curl -s -o "${TMP_MCP_OAUTH_AUTH_SERVER_BODY}" -w '%{http_code}' \
      "${MCP_OAUTH_AUTH_SERVER_URL}"
  )"
  assert_status "200" "${auth_server_status}" "MCP oauth-authorization-server endpoint"
  if ! jq -e '.issuer and .authorization_endpoint and .token_endpoint and .jwks_uri' "${TMP_MCP_OAUTH_AUTH_SERVER_BODY}" >/dev/null; then
    fail_step "MCP oauth-authorization-server payload missing expected metadata fields"
  fi

  pass_step "MCP OAuth metadata endpoints returned valid payloads"
}

run_mcp_inspector_cli_checks() {
  start_step "E2E-010" "MCP Inspector CLI connectivity checks"
  if run_mcp_inspector_cli "${MCP_ENDPOINT_URL}" "${TMP_MCP_NO_TOKEN_OUT}"; then
    fail_step "MCP Inspector CLI unexpectedly succeeded without bearer token"
  fi
  if ! grep -Eiq "401|Missing bearer token|UNAUTHORIZED" "${TMP_MCP_NO_TOKEN_OUT}"; then
    fail_step "MCP Inspector CLI output without token did not show auth rejection"
  fi
  if ! run_mcp_inspector_cli \
    "${MCP_ENDPOINT_URL}" \
    "${TMP_MCP_WITH_TOKEN_OUT}" \
    --header "Authorization: Bearer ${USER_ACCESS_TOKEN}"; then
    fail_step "MCP Inspector CLI call with bearer token failed"
  fi
  if ! grep -Eq "list_flights|book_flight|get_bookings|cancel_booking|register_user|get_user_id" "${TMP_MCP_WITH_TOKEN_OUT}"; then
    fail_step "MCP Inspector CLI authenticated output does not contain expected tool names"
  fi
  pass_step "MCP Inspector CLI checks passed"
}

write_reports() {
  local completed_at_utc pass_count fail_count total_count
  completed_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  pass_count="$(grep -c $'\tPASS\t' "${STEPS_FILE}" || true)"
  fail_count="$(grep -c $'\tFAIL\t' "${STEPS_FILE}" || true)"
  total_count="$(wc -l < "${STEPS_FILE}" | tr -d ' ')"

  {
    echo "# OAuth Local Test Report"
    echo
    echo "- Run ID: \`${RUN_ID}\`"
    echo "- Scope: \`${SCOPE}\`"
    echo "- Started (UTC): \`${STARTED_AT_UTC}\`"
    echo "- Completed (UTC): \`${completed_at_utc}\`"
    echo "- Final status: \`${STATUS}\`"
    echo "- Passed: \`${pass_count}\`"
    echo "- Failed: \`${fail_count}\`"
    echo "- Total: \`${total_count}\`"
    if [[ -n "${FAIL_REASON}" ]]; then
      echo "- Failure reason: \`${FAIL_REASON}\`"
    fi
    echo
    echo "## Test Cases"
    echo
    echo "| Test ID | Description | Status | Details |"
    echo "| --- | --- | --- | --- |"
    while IFS=$'\t' read -r step_id description step_status details; do
      echo "| ${step_id} | ${description} | ${step_status} | ${details} |"
    done < "${STEPS_FILE}"
    echo
    echo "## Artifacts"
    echo
    echo "- Log: \`${LOG_FILE}\`"
    echo "- JSON: \`${REPORT_JSON}\`"
  } > "${REPORT_MD}"

  local steps_json
  steps_json="$(
    jq -R -s '
      split("\n")
      | map(select(length > 0) | split("\t"))
      | map({
          test_id: .[0],
          description: .[1],
          status: .[2],
          details: .[3]
        })
    ' "${STEPS_FILE}"
  )"

  jq -n \
    --arg run_id "${RUN_ID}" \
    --arg scope "${SCOPE}" \
    --arg started_at_utc "${STARTED_AT_UTC}" \
    --arg completed_at_utc "${completed_at_utc}" \
    --arg status "${STATUS}" \
    --arg fail_reason "${FAIL_REASON}" \
    --arg log_file "${LOG_FILE}" \
    --arg markdown_report "${REPORT_MD}" \
    --argjson pass_count "${pass_count}" \
    --argjson fail_count "${fail_count}" \
    --argjson total_count "${total_count}" \
    --argjson steps "${steps_json}" \
    '{
      run_id: $run_id,
      scope: $scope,
      started_at_utc: $started_at_utc,
      completed_at_utc: $completed_at_utc,
      status: $status,
      fail_reason: $fail_reason,
      summary: {
        passed: $pass_count,
        failed: $fail_count,
        total: $total_count
      },
      artifacts: {
        log_file: $log_file,
        markdown_report: $markdown_report
      },
      steps: $steps
    }' > "${REPORT_JSON}"
}

on_exit() {
  local exit_code=$?
  if [[ "${exit_code}" -ne 0 && "${STATUS}" == "PASS" ]]; then
    STATUS="FAIL"
    if [[ -z "${FAIL_REASON}" ]]; then
      FAIL_REASON="Unexpected command failure (exit code ${exit_code})"
    fi
    if [[ "${FAIL_RECORDED}" != "true" ]]; then
      record_step "${CURRENT_STEP_ID:-UNCLASSIFIED}" "${CURRENT_STEP_DESC:-Unclassified failure}" "FAIL" "${FAIL_REASON}"
      FAIL_RECORDED="true"
    fi
  fi

  write_reports
  echo
  echo "Saved test reports:"
  echo "  - ${REPORT_MD}"
  echo "  - ${REPORT_JSON}"
  echo "  - ${LOG_FILE}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --scope requires a value"
        exit 1
      fi
      SCOPE="$2"
      shift 2
      ;;
    --with-inspector-cli)
      WITH_INSPECTOR_CLI="true"
      shift
      ;;
    --reports-dir)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --reports-dir requires a value"
        exit 1
      fi
      REPORTS_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

case "${SCOPE}" in
  all|ui-rest|mcp) ;;
  *)
    echo "ERROR: invalid --scope '${SCOPE}'. Use one of: all, ui-rest, mcp"
    exit 1
    ;;
esac

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
STARTED_AT_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "${REPORTS_DIR}"
LOG_FILE="${REPORTS_DIR}/oauth-e2e-${SCOPE}-${RUN_ID}.log"
REPORT_MD="${REPORTS_DIR}/oauth-e2e-${SCOPE}-${RUN_ID}.md"
REPORT_JSON="${REPORTS_DIR}/oauth-e2e-${SCOPE}-${RUN_ID}.json"
STEPS_FILE="${REPORTS_DIR}/oauth-e2e-${SCOPE}-${RUN_ID}.steps.tsv"
: > "${STEPS_FILE}"

exec > >(tee -a "${LOG_FILE}") 2>&1
trap on_exit EXIT

echo "Starting OAuth test suite"
echo "Run ID: ${RUN_ID}"
echo "Scope: ${SCOPE}"
echo "Reports dir: ${REPORTS_DIR}"
echo "Inspector CLI checks: ${WITH_INSPECTOR_CLI}"

start_step "E2E-000" "Environment pre-check and compose startup"
require_command docker
require_command curl
require_command jq
compose_prepare
wait_for_url "Keycloak" "${KEYCLOAK_OPENID_CONFIG_URL}"
wait_for_url "Booking API" "${BOOKING_HEALTH_URL}"
wait_for_url "Web app" "${WEB_APP_HEALTH_URL}"
wait_for_url "MCP root" "${MCP_ROOT_URL}"
pass_step "Compose services are reachable"

start_step "E2E-008" "Keycloak Inspector client sync + verification"
bash "${SCRIPT_DIR}/sync-keycloak-inspector-client.sh"
bash "${SCRIPT_DIR}/verify-keycloak-inspector-client.sh"
pass_step "Inspector client settings are valid"

start_step "E2E-011" "Acquire traveler token once for all checks"
obtain_traveler_token
pass_step "Traveler token acquired"

if [[ "${SCOPE}" == "all" || "${SCOPE}" == "ui-rest" ]]; then
  run_ui_and_rest_tests
fi

if [[ "${SCOPE}" == "all" || "${SCOPE}" == "mcp" ]]; then
  run_mcp_metadata_discovery_checks
  run_mcp_protocol_tests
  if [[ "${WITH_INSPECTOR_CLI}" == "true" ]]; then
    run_mcp_inspector_cli_checks
  fi
fi

echo
echo "PASS: OAuth test suite completed for scope '${SCOPE}'."

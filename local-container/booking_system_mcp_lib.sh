#!/usr/bin/env bash
# Shared helpers for the booking_system_mcp_* start/verify scripts. Source this file, do not execute it.

XMCP_FAILURES=0
XMCP_INIT_BODY='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"booking-system-mcp-verify","version":"1.0.0"}}}'

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; XMCP_FAILURES=$((XMCP_FAILURES + 1)); }

# xmcp_load_env FILE: export every variable in FILE when it exists.
xmcp_load_env() {
  local env_file="$1"
  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
    echo "Loaded ${env_file}"
  fi
}

# xmcp_compose DIR ARGS...: docker compose for the variant in DIR, with DIR/mcp.env when present.
xmcp_compose() {
  local dir="$1"
  shift
  local args=(-f "${dir}/docker_compose.yaml")
  if [[ -f "${dir}/mcp.env" ]]; then
    args=(--env-file "${dir}/mcp.env" "${args[@]}")
  fi
  docker compose "${args[@]}" "$@"
}

# xmcp_wait_for URL LABEL [TIMEOUT_SECONDS]: wait until URL answers with any HTTP status.
xmcp_wait_for() {
  local url="$1" label="$2" timeout="${3:-120}" waited=0
  until [[ "$(curl -s -o /dev/null -w '%{http_code}' "${url}" || true)" != "000" ]]; do
    if (( waited >= timeout )); then
      fail "${label} not reachable at ${url} after ${timeout}s"
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  pass "${label} reachable at ${url}"
}

# xmcp_post URL BODY [AUTHORIZATION] [SESSION_ID]: sets XMCP_STATUS, XMCP_BODY, XMCP_HEADERS.
xmcp_post() {
  local url="$1" body="$2" authorization="${3:-}" session_id="${4:-}"
  local header_file output
  header_file="$(mktemp)"
  local args=(-sS -D "${header_file}" -w '\n%{http_code}' -X POST "${url}"
    -H 'Content-Type: application/json'
    -H 'Accept: application/json, text/event-stream'
    --data "${body}")
  if [[ -n "${authorization}" ]]; then
    args+=(-H "Authorization: ${authorization}")
  fi
  if [[ -n "${session_id}" ]]; then
    args+=(-H "mcp-session-id: ${session_id}")
  fi
  output="$(curl "${args[@]}" 2>&1)" || output=$'\n000'
  XMCP_STATUS="${output##*$'\n'}"
  XMCP_BODY="${output%$'\n'*}"
  XMCP_HEADERS="$(cat "${header_file}")"
  rm -f "${header_file}"
}

# xmcp_expect_rejected URL AUTHORIZATION LABEL CHALLENGE: expect 401 with a WWW-Authenticate CHALLENGE.
xmcp_expect_rejected() {
  local url="$1" authorization="$2" label="$3" challenge="$4"
  xmcp_post "${url}" "${XMCP_INIT_BODY}" "${authorization}"
  if [[ "${XMCP_STATUS}" != "401" ]]; then
    fail "${label}: expected 401, got ${XMCP_STATUS}"
    return
  fi
  if ! grep -qi "^www-authenticate: ${challenge}" <<<"${XMCP_HEADERS}"; then
    fail "${label}: 401 without 'WWW-Authenticate: ${challenge}' challenge"
    return
  fi
  pass "${label} -> 401 (${challenge} challenge)"
}

# xmcp_expect_tools URL [AUTHORIZATION]: initialize a session and expect tools/list to expose list_flights.
xmcp_expect_tools() {
  local url="$1" authorization="${2:-}" session_id
  xmcp_post "${url}" "${XMCP_INIT_BODY}" "${authorization}"
  if [[ "${XMCP_STATUS}" != "200" ]]; then
    fail "initialize: expected 200, got ${XMCP_STATUS}: ${XMCP_BODY}"
    return
  fi
  pass "initialize -> 200"

  session_id="$(awk -F': *' 'tolower($1)=="mcp-session-id" {print $2}' <<<"${XMCP_HEADERS}" | tr -d '\r')"
  xmcp_post "${url}" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "${authorization}" "${session_id}"
  xmcp_post "${url}" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' "${authorization}" "${session_id}"
  if [[ "${XMCP_STATUS}" == "200" && "${XMCP_BODY}" == *'"list_flights"'* ]]; then
    pass "tools/list -> list_flights exposed"
  else
    fail "tools/list: expected list_flights, got ${XMCP_STATUS}: ${XMCP_BODY}"
  fi
}

# xmcp_expect_status URL EXPECTED LABEL: expect a plain GET to return EXPECTED.
xmcp_expect_status() {
  local url="$1" expected="$2" label="$3" actual
  actual="$(curl -s -o /dev/null -w '%{http_code}' "${url}" || true)"
  if [[ "${actual}" == "${expected}" ]]; then
    pass "${label} -> ${expected}"
  else
    fail "${label}: expected ${expected}, got ${actual}"
  fi
}

xmcp_summary() {
  if (( XMCP_FAILURES > 0 )); then
    echo "${XMCP_FAILURES} check(s) failed." >&2
    exit 1
  fi
  echo "All checks passed."
}

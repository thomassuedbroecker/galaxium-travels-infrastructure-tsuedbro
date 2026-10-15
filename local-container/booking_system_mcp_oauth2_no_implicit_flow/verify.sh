#!/usr/bin/env bash
# Verifies the OAuth 2.0 MCP variant:
#   - every Keycloak client in the realm import has the implicit flow disabled
#   - MCP OAuth metadata only advertises the "code" response type (no implicit flow)
#   - 401 without a token, with a Basic header, and with an invalid token
#   - client_credentials token has the expected issuer and opens a working MCP session
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../booking_system_mcp_lib.sh"
xmcp_load_env "${SCRIPT_DIR}/mcp.env"

MCP_BASE="http://localhost:${MCP_HOST_PORT:-8084}"
MCP_URL="${MCP_URL:-${MCP_BASE}/mcp}"
EXPECTED_ISSUER="${KEYCLOAK_PUBLIC_BASE_URL:-http://localhost:8086}/realms/galaxium"
# Same resolution as docker compose: relative paths are relative to this folder.
REALM_DIR="${KEYCLOAK_REALM_DIR:-../keycloak/realm}"
[[ "${REALM_DIR}" = /* ]] || REALM_DIR="${SCRIPT_DIR}/${REALM_DIR}"

if python3 - "${REALM_DIR}" <<'PY'
import json, pathlib, sys
files = sorted(pathlib.Path(sys.argv[1]).glob("*.json"))
if not files:
    sys.exit(f"no realm export (*.json) in {sys.argv[1]}")
enabled = [
    f"{f.name}:{c['clientId']}"
    for f in files
    for c in json.loads(f.read_text()).get("clients", [])
    if c.get("implicitFlowEnabled", False)
]
sys.exit(f"implicitFlowEnabled=true for {', '.join(enabled)}" if enabled else 0)
PY
then
  pass "realm import (${REALM_DIR}): implicitFlowEnabled=false for every client"
else
  fail "realm import (${REALM_DIR}): implicit flow check failed"
fi

xmcp_wait_for "${MCP_BASE}/" "MCP server" || xmcp_summary
xmcp_wait_for "${EXPECTED_ISSUER}/.well-known/openid-configuration" "Keycloak realm" 180 || xmcp_summary

if curl -fsS "${MCP_BASE}/.well-known/oauth-authorization-server" | python3 -c '
import json, sys
meta = json.load(sys.stdin)
assert meta["response_types_supported"] == ["code"], meta["response_types_supported"]
assert "implicit" not in meta["grant_types_supported"], meta["grant_types_supported"]
assert "client_credentials" in meta["grant_types_supported"]
assert "authorization_code" in meta["grant_types_supported"]
'; then
  pass "MCP OAuth metadata: response_types_supported=[code], no implicit grant"
else
  fail "MCP OAuth metadata advertises an implicit flow or misses a required grant"
fi

xmcp_expect_rejected "${MCP_URL}" "" "no Authorization header" "Bearer"
xmcp_expect_rejected "${MCP_URL}" "Basic ZGVtbzpkZW1v" "Basic header instead of bearer" "Bearer"
xmcp_expect_rejected "${MCP_URL}" "Bearer not-a-valid-jwt" "invalid bearer token" "Bearer"

if ! ACCESS_TOKEN="$(bash "${SCRIPT_DIR}/get-token.sh" 2>/dev/null)"; then
  fail "client_credentials token request failed"
  xmcp_summary
fi
pass "client_credentials token issued"

TOKEN_ISSUER="$(python3 -c '
import base64, json, sys
payload = sys.argv[1].split(".")[1]
print(json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))["iss"])
' "${ACCESS_TOKEN}")"
if [[ "${TOKEN_ISSUER}" == "${EXPECTED_ISSUER}" ]]; then
  pass "token issuer matches ${EXPECTED_ISSUER}"
else
  fail "token issuer ${TOKEN_ISSUER} does not match ${EXPECTED_ISSUER}"
fi

xmcp_expect_tools "${MCP_URL}" "Bearer ${ACCESS_TOKEN}"
xmcp_summary

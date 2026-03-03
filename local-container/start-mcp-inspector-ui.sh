#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-${SCRIPT_DIR}/test-results}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
CONFIG_FILE="${RESULTS_DIR}/inspector-ui-config-${RUN_ID}.md"

MCP_URL="${MCP_URL:-http://localhost:8084/mcp}"
TOKEN_SOURCE_CONTAINER="${TOKEN_SOURCE_CONTAINER:-web_app}"
KEYCLOAK_TOKEN_URL_IN_CONTAINER="${KEYCLOAK_TOKEN_URL_IN_CONTAINER:-http://keycloak:8080/realms/galaxium/protocol/openid-connect/token}"
CLIENT_ID="${CLIENT_ID:-web-app-proxy}"
CLIENT_SECRET="${CLIENT_SECRET:-web-app-proxy-secret}"
TRAVELER_USERNAME="${TRAVELER_USERNAME:-demo-user}"
TRAVELER_PASSWORD="${TRAVELER_PASSWORD:-demo-user-password}"
MCP_PROXY_AUTH_TOKEN="${MCP_PROXY_AUTH_TOKEN:-local-dev-token}"
MCP_BASE_URL="$(echo "${MCP_URL}" | sed -E 's#(https?://[^/]+).*#\1#')"
MCP_OAUTH_PROTECTED_RESOURCE_URL="${MCP_BASE_URL}/.well-known/oauth-protected-resource"
MCP_OAUTH_AUTH_SERVER_URL="${MCP_BASE_URL}/.well-known/oauth-authorization-server"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: required command '${command_name}' is not available."
    exit 1
  fi
}

require_command docker
require_command curl
require_command npx
require_command jq

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not running or not accessible."
  exit 1
fi

mkdir -p "${RESULTS_DIR}"

PROTECTED_RESOURCE_STATUS="$(curl -s -o /tmp/galaxium_inspector_oauth_protected_resource.json -w '%{http_code}' "${MCP_OAUTH_PROTECTED_RESOURCE_URL}")"
AUTH_SERVER_STATUS="$(curl -s -o /tmp/galaxium_inspector_oauth_auth_server.json -w '%{http_code}' "${MCP_OAUTH_AUTH_SERVER_URL}")"

if [[ "${PROTECTED_RESOURCE_STATUS}" != "200" ]]; then
  echo "ERROR: MCP OAuth protected resource metadata endpoint not reachable (HTTP ${PROTECTED_RESOURCE_STATUS})"
  echo "URL: ${MCP_OAUTH_PROTECTED_RESOURCE_URL}"
  cat /tmp/galaxium_inspector_oauth_protected_resource.json
  exit 1
fi

if [[ "${AUTH_SERVER_STATUS}" != "200" ]]; then
  echo "ERROR: MCP OAuth authorization server metadata endpoint not reachable (HTTP ${AUTH_SERVER_STATUS})"
  echo "URL: ${MCP_OAUTH_AUTH_SERVER_URL}"
  cat /tmp/galaxium_inspector_oauth_auth_server.json
  exit 1
fi

if ! jq -e '.resource and .authorization_servers and (.authorization_servers | length > 0)' /tmp/galaxium_inspector_oauth_protected_resource.json >/dev/null; then
  echo "ERROR: invalid payload at ${MCP_OAUTH_PROTECTED_RESOURCE_URL}"
  cat /tmp/galaxium_inspector_oauth_protected_resource.json
  exit 1
fi

if ! jq -e '.issuer and .authorization_endpoint and .token_endpoint and .jwks_uri' /tmp/galaxium_inspector_oauth_auth_server.json >/dev/null; then
  echo "ERROR: invalid payload at ${MCP_OAUTH_AUTH_SERVER_URL}"
  cat /tmp/galaxium_inspector_oauth_auth_server.json
  exit 1
fi

TOKEN="$(
  docker exec "${TOKEN_SOURCE_CONTAINER}" python -c "import requests; r=requests.post('${KEYCLOAK_TOKEN_URL_IN_CONTAINER}', data={'grant_type':'password','client_id':'${CLIENT_ID}','client_secret':'${CLIENT_SECRET}','username':'${TRAVELER_USERNAME}','password':'${TRAVELER_PASSWORD}'}, timeout=10); r.raise_for_status(); print(r.json().get('access_token',''))"
)"
TOKEN="$(echo "${TOKEN}" | tr -d '\r\n')"
if [[ -z "${TOKEN}" ]]; then
  echo "ERROR: failed to acquire traveler token from container '${TOKEN_SOURCE_CONTAINER}'."
  exit 1
fi

HEADER_JSON="$(printf '{"Authorization":"Bearer %s"}' "${TOKEN}")"

cat > "${CONFIG_FILE}" <<EOF
# MCP Inspector UI Configuration

- Generated at (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Connection mode: Proxy
- Transport type: Streamable HTTP
- MCP URL: ${MCP_URL}
- Auth mode: Custom Headers

## Custom Header JSON

\`\`\`json
${HEADER_JSON}
\`\`\`

## Important

1. Start inspector with a fixed proxy token:
   \`MCP_PROXY_AUTH_TOKEN=${MCP_PROXY_AUTH_TOKEN} npx @modelcontextprotocol/inspector\`
2. Open the browser URL printed by inspector output.
3. If you open localhost manually, include the same proxy token.
4. Metadata preflight passed:
   - \`${MCP_OAUTH_PROTECTED_RESOURCE_URL}\`
   - \`${MCP_OAUTH_AUTH_SERVER_URL}\`
EOF

echo "Saved Inspector UI config:"
echo "  ${CONFIG_FILE}"
echo
echo "Use these values in Inspector UI:"
echo "  - Connection mode: Proxy"
echo "  - Transport: Streamable HTTP"
echo "  - URL: ${MCP_URL}"
echo "  - Auth mode: Custom Headers"
echo "  - Custom Header JSON:"
echo "${HEADER_JSON}"
echo
echo "Starting inspector with fixed proxy token..."
echo "MCP_PROXY_AUTH_TOKEN=${MCP_PROXY_AUTH_TOKEN} npx @modelcontextprotocol/inspector"
MCP_PROXY_AUTH_TOKEN="${MCP_PROXY_AUTH_TOKEN}" npx @modelcontextprotocol/inspector

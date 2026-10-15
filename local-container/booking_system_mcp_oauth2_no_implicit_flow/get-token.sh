#!/usr/bin/env bash
# Prints an access token obtained with the OAuth 2.0 client_credentials grant.
#
#   export GALAXIUM_MCP_ACCESS_TOKEN="$(bash local-container/booking_system_mcp_oauth2_no_implicit_flow/get-token.sh)"
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../booking_system_mcp_lib.sh"
xmcp_load_env "${SCRIPT_DIR}/mcp.env" >&2

TOKEN_URL="${TOKEN_URL:-${KEYCLOAK_PUBLIC_BASE_URL:-http://localhost:8086}/realms/galaxium/protocol/openid-connect/token}"

curl -fsS -X POST "${TOKEN_URL}" \
  -u "${OIDC_CLIENT_ID:-web-app-proxy}:${OIDC_CLIENT_SECRET:-web-app-proxy-secret}" \
  -d grant_type=client_credentials \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["access_token"])'

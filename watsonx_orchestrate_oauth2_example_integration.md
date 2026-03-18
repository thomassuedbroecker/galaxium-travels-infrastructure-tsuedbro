# Keycloak Redirect URI Configuration for LAN OAuth and MCP Inspector

This note explains the current redirect-URI detail that matters when you use the repository over a LAN IP or DNS name.

## What This Applies To

This is mainly needed for browser-based OAuth clients such as MCP Inspector on port `6274`.

For service-to-service clients such as watsonx Orchestrate using client credentials, a redirect URI is usually not the main issue. In that case, focus on:

- the public token URL
- the client ID and secret
- the required audience for the MCP server
- the public MCP endpoint at `http://<HOST>:8084/mcp`

For the full server-to-server setup background, see [ai_generated_documentation/WATSONX_ORCHESTRATE_BOOKING_MCP_SETUP_GUIDE.md](./ai_generated_documentation/WATSONX_ORCHESTRATE_BOOKING_MCP_SETUP_GUIDE.md).

## Current Repo Defaults

The local realm file already includes these inspector callback URLs:

- `http://localhost:6274/oauth/callback`
- `http://localhost:6274/oauth/callback/debug`
- `http://127.0.0.1:6274/oauth/callback`
- `http://127.0.0.1:6274/oauth/callback/debug`

Source: `local-container/keycloak/realm/galaxium-realm.json`

If you use a LAN IP or DNS name instead of `localhost`, add matching callback URIs for that host.

## Example for a LAN Host

1. Get the host IP address:

```sh
IP_LOCAL_NETWORK_ADDRESS=$(ipconfig getifaddr en0)
echo "${IP_LOCAL_NETWORK_ADDRESS}"
```

2. Add these redirect URIs to the Keycloak client `web-app-proxy`:

```text
http://<LAN_HOST>:6274/oauth/callback
http://<LAN_HOST>:6274/oauth/callback/debug
```

Example:

```text
http://192.168.2.53:6274/oauth/callback
http://192.168.2.53:6274/oauth/callback/debug
```

## Why This Is Required

- Keycloak validates redirect URIs strictly.
- MCP Inspector uses port `6274` for the OAuth browser callback.
- The callback host must match the real host or IP you used to start Inspector.

## Verification

1. Verify Keycloak discovery over the LAN URL:

```sh
curl -fsS http://192.168.2.53:8086/realms/galaxium/.well-known/openid-configuration | jq -r .issuer
```

2. Verify the MCP metadata root over the same LAN host:

```sh
curl -fsS http://192.168.2.53:8084/.well-known/oauth-authorization-server | jq .
```

3. Verify authenticated MCP access through the current public endpoint:

```sh
python3 local-container/mcp_test_app.py \
  --mcp-url http://192.168.2.53:8084/mcp \
  --token-source http \
  --token-url http://192.168.2.53:8086/realms/galaxium/protocol/openid-connect/token
```

4. If you use MCP Inspector, keep:

- connection mode: `Via Proxy`
- transport: `Streamable HTTP`
- MCP URL: `http://192.168.2.53:8084/mcp`

## Common Errors Without This Configuration

- `invalid_redirect_uri`
- OAuth browser callback fails after login
- MCP Inspector cannot complete the OAuth flow

## Related Files

- Realm import: `local-container/keycloak/realm/galaxium-realm.json`
- VM/LAN compose overlay: `local-container/docker_compose.vm-oauth.yaml`
- Remote verifier: `local-container/verify-keycloak-auth-remote.sh`
- Inspector helper: `local-container/start-mcp-inspector-ui.sh`

## Notes

- Keep the MCP public endpoint on `/mcp`.
- Keep the MCP transport on `Streamable HTTP`.
- In the Code Engine deployment package, `deployment/ibm-code-engine/scripts/05-sync-keycloak-client.sh` updates the web UI client URLs after deploy, but extra inspector callback URIs may still need to be added if you use a non-default host.

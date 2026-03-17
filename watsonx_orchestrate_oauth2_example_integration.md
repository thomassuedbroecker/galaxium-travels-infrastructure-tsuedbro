# Keycloak Redirect URI Configuration - "MCP booking server with watsonx Orchestrate via OAuth2"

## Problem
When integrating MCP server with watsonx Orchestrate via OAuth2, the Keycloak client must have the correct redirect URIs configured to match the actual IP address being used.

## Solution
Add the following redirect URIs to the Keycloak `web-app-proxy` client configuration:

1. Get your local network IP address.

```sh
IP_LOCAL_NETWORK_ADDRESS=$(ipconfig getifaddr en0)
echo ${IP_LOCAL_NETWORK_ADDRESS}
192.168.2.53:6274
```

2. Then these are the URI to add:

```
http://192.168.2.53:6274/oauth/callback/debug
http://192.168.2.53:6274/oauth/callback
```

## Why This Is Required
- **MCP Inspector:** Uses port 6274 for OAuth2 callback handling
- **IP Address Matching:** Keycloak validates redirect URIs strictly - must match the actual IP address used in requests
- **OAuth2 Flow:** Authorization Code flow requires a valid redirect URI for the callback after authentication

## Configuration Steps

### Option 1: Via Keycloak Admin UI
1. Navigate to Keycloak Admin Console: `http://192.168.2.53:8086/admin`
2. Select realm: `galaxium`
3. Go to: Clients → `web-app-proxy`
4. Scroll to: "Valid redirect URIs"
5. Add both URIs:
   - `http://192.168.2.53:6274/oauth/callback/debug`
   - `http://192.168.2.53:6274/oauth/callback`
6. Click "Save"

### Option 2: Via Realm Export/Import
Update the realm configuration JSON to include:

```json
{
  "clientId": "web-app-proxy",
  "redirectUris": [
    "http://127.0.0.1:6274/oauth/callback",
    "http://127.0.0.1:6274/oauth/callback/debug",
    "http://localhost:6274/oauth/callback",
    "http://localhost:6274/oauth/callback/debug",
    "http://192.168.2.53:6274/oauth/callback",
    "http://192.168.2.53:6274/oauth/callback/debug"
  ]
}
```

## Verification
After adding the redirect URIs, test the OAuth2 flow:

```bash
# 1. Get token (should work)
curl -X POST "http://192.168.2.53:8086/realms/galaxium/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=web-app-proxy" \
  -d "client_secret=web-app-proxy-secret" \
  -d "username=demo-user" \
  -d "password=demo-user-password" \
  -d "scope=openid profile email"

# 2. Test MCP server access (should return 200 OK)
TOKEN="<access_token_from_above>"
curl -H "Authorization: Bearer $TOKEN" "http://192.168.2.53:8084/"
```

## Common Errors Without This Configuration
- `invalid_redirect_uri` - Redirect URI not registered in Keycloak
- `403 Forbidden` - OAuth2 callback fails due to URI mismatch
- MCP Inspector unable to complete OAuth2 flow

## Related Files
- Infrastructure realm config: `infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container/keycloak/realm/galaxium-realm-orchestrate-config.json`
- Connection definition: `bob-agent-tools-generation/connection-orchestrate-booking-mcp.json`
- Environment variables: `bob-agent-tools-generation/.env.sample`

## Notes
- Port 6274 is the standard port used by MCP Inspector for OAuth2 callbacks
- Always use the actual IP address that will be used in production/testing
- For local development, include localhost, 127.0.0.1, and LAN IP addresses
- For watsonx Orchestrate integration, the redirect URI may need to point to the Orchestrate callback endpoint

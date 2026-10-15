# Keycloak Configuration

Keycloak is the OAuth 2.0 / OpenID Connect token issuer for this repository. This page covers what is configured, who uses it, and how to change it safely. It is written for the consuming [watsonx Orchestrate guide repository](https://github.com/thomassuedbroecker/galaxium-travels-watsonx-orchestrate-mcp-bob-guide), which may need to adjust Keycloak for its watsonx Orchestrate connection.

For the MCP integration, Keycloak is only needed in [`../booking_system_mcp_oauth2_no_implicit_flow/`](../booking_system_mcp_oauth2_no_implicit_flow/README.md). The no-auth and Basic Auth options do not use it.

## At a Glance

| Item | Value |
| --- | --- |
| Image | `quay.io/keycloak/keycloak:26.0`, `start-dev` mode |
| Realm | `galaxium` |
| Realm definition | [`realm/galaxium-realm.json`](./realm/galaxium-realm.json) (the only source of truth) |
| Host URL | `http://localhost:8086` (container port `8080`) |
| Admin console | `http://localhost:8086/admin`, user `admin` / `admin` (demo only) |
| Issuer | `<KEYCLOAK_PUBLIC_BASE_URL>/realms/galaxium` |
| Token URL | `<KEYCLOAK_PUBLIC_BASE_URL>/realms/galaxium/protocol/openid-connect/token` |
| JWKS URL (used by the MCP server) | `http://keycloak:8080/realms/galaxium/protocol/openid-connect/certs` (Docker-internal) |
| Access token lifetime | 5 minutes (Keycloak default; not set in the realm) |
| Allowed grants | `client_credentials`, `authorization_code` (+ PKCE). **Implicit flow is disabled for every client.** |

## Lifecycle: How Configuration Reaches Keycloak

```text
realm/galaxium-realm.json ──(mounted read-only)──▶ /opt/keycloak/data/import
                                                     │
                       container start: --import-realm
                                                     ▼
                                   realm "galaxium" in Keycloak's in-container database
```

- The realm is imported **when the container is created**. No volume persists the Keycloak database.
- `docker compose ... down` followed by `up` re-imports the JSON file from scratch.
- `restart` or `stop`/`start` keeps the current container. Any runtime changes are kept, and the JSON file is not re-read.
- **Changes made in the Admin Console or through the Admin REST API are lost when the container is recreated.** Use them only for quick experiments. Put every permanent change into a realm JSON file.

To apply a realm change: edit the JSON, then run `docker compose -f <compose file> down` and start again.

## What the Realm Contains

### Realm settings

| Setting | Value | Why it matters |
| --- | --- | --- |
| `sslRequired` | `none` | Allows plain-HTTP token requests from non-local addresses, such as the LAN IP that watsonx Orchestrate Developer Edition uses. Keycloak's default (`external`) would reject them. Use HTTPS and `external` beyond a local demo. |
| `registrationAllowed` | `false` | Users cannot self-register. |
| `loginWithEmailAllowed` | `true` | Interactive login accepts email or username. |

### Clients

| Client ID | Type | Grants enabled | Used by | Secret (demo) |
| --- | --- | --- | --- | --- |
| `booking-api` | confidential | `client_credentials` only | Represents the protected resource. Its client ID is the **audience** (`aud`) the booking backends require (`OIDC_AUDIENCE=booking-api`). No component requests tokens as this client. | `booking-api-secret` |
| `web-app-proxy` | confidential | `client_credentials`, `authorization_code`, password (legacy) | Machine-to-machine callers (web app proxies, verify scripts, demo watsonx Orchestrate connection) and MCP Inspector's browser login | `web-app-proxy-secret` |

`web-app-proxy` details:

| Setting | Value | Purpose |
| --- | --- | --- |
| `serviceAccountsEnabled` | `true` | Enables `client_credentials` |
| `standardFlowEnabled` | `true` | Enables `authorization_code` (MCP Inspector) |
| `implicitFlowEnabled` | `false` | Implicit flow is not allowed |
| `directAccessGrantsEnabled` | `true` | Password grant, kept only for legacy verify scripts; do not use it for new integrations |
| `redirectUris` | `http://localhost:6274/oauth/callback`, `.../callback/debug`, the same on `127.0.0.1` | MCP Inspector callbacks for `authorization_code` |
| `webOrigins` | `http://localhost:6274`, `http://127.0.0.1:6274` | CORS for the Inspector |
| Protocol mapper `aud-booking-api` | `oidc-audience-mapper`, `included.client.audience=booking-api`, access token only | Adds `booking-api` to `aud`. **Without it, the MCP server rejects the token.** |

### Users

| Username | Password | Used by |
| --- | --- | --- |
| `demo-user` | `demo-user-password` | Interactive login (MCP Inspector, web UIs) and legacy password-grant scripts |

`client_credentials` tokens do not involve a user.

## What the MCP Server Checks in a Token

`booking_system_mcp` (with `AUTH_MODE=oauth2`) accepts a bearer token only when all of these hold:

| Check | Server setting | Keycloak side |
| --- | --- | --- |
| Signature (RS256) | `OIDC_JWKS_URL` | realm signing keys |
| `iss` | `OIDC_ISSUER` | `--hostname`, the URL Keycloak is started with |
| `aud` contains `booking-api` | `OIDC_AUDIENCE` | the client's audience mapper |
| `exp` not passed | — | access token lifetime |

Scopes and roles are not checked.

### Issuer and hostname

The token's `iss` is built from the URL Keycloak believes it runs on. In `booking_system_mcp_oauth2_no_implicit_flow`, Keycloak starts with `--hostname=${KEYCLOAK_PUBLIC_BASE_URL}`. Tokens therefore always carry `iss = KEYCLOAK_PUBLIC_BASE_URL/realms/galaxium`, no matter which address the token request was sent to. The MCP server's `OIDC_ISSUER` comes from the same variable.

**Rule:** set `KEYCLOAK_PUBLIC_BASE_URL` to the Keycloak URL your client uses. For watsonx Orchestrate Developer Edition, that is `http://<LAN IP>:8086`. See [docs/mcp_access_options.md](../../docs/mcp_access_options.md#reaching-the-server-from-watsonx-orchestrate-developer-edition).

The full stack in `../docker_compose.yaml` does not pin the hostname; it relies on internal URLs and a hostname rewrite instead. Prefer the standalone OAuth folder for the MCP integration.

## How to Adjust the Configuration

There are two ways to make permanent changes:

| Approach | When |
| --- | --- |
| **A. Supply your own realm folder** (recommended for the guide repository) | You need different clients, secrets, or redirect URIs without changing this repository. |
| **B. Edit `realm/galaxium-realm.json`** | The change should become the default for everyone using this repository. This file is shared with the full stacks (`docker_compose.yaml`, `docker_compose.vm-oauth.yaml`). |

### A. Use your own realm folder

`booking_system_mcp_oauth2_no_implicit_flow` mounts `${KEYCLOAK_REALM_DIR}` as the import folder (default `../keycloak/realm`):

```sh
mkdir -p /abs/path/my-realm
cp local-container/keycloak/realm/galaxium-realm.json /abs/path/my-realm/
# edit /abs/path/my-realm/galaxium-realm.json
# in local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env:
export KEYCLOAK_REALM_DIR=/abs/path/my-realm
```

Keep the realm name `galaxium`, the `booking-api` audience, and `implicitFlowEnabled: false`. Otherwise, also change `OIDC_ISSUER`, `OIDC_AUDIENCE`, and the URLs in the compose file. `verify.sh` checks every `*.json` in the folder for the implicit flow. On Docker Desktop, the folder must be in a shared location (your home folder is shared by default).

### Recipe: dedicated client for watsonx Orchestrate

A dedicated client gives watsonx Orchestrate its own secret, which you can rotate independently of the demo client. It allows `client_credentials` only. Add it to the `clients` array:

```json
{
  "clientId": "wxo-booking-mcp",
  "name": "watsonx Orchestrate Booking MCP",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "secret": "change-me-wxo-secret",
  "serviceAccountsEnabled": true,
  "standardFlowEnabled": false,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": false,
  "protocolMappers": [
    {
      "name": "aud-booking-api",
      "protocol": "openid-connect",
      "protocolMapper": "oidc-audience-mapper",
      "consentRequired": false,
      "config": {
        "included.client.audience": "booking-api",
        "id.token.claim": "false",
        "access.token.claim": "true"
      }
    }
  ]
}
```

Then point the verify script at it, recreate the stack, and verify:

```sh
# in mcp.env:
export OIDC_CLIENT_ID=wxo-booking-mcp
export OIDC_CLIENT_SECRET=change-me-wxo-secret
docker compose -f local-container/booking_system_mcp_oauth2_no_implicit_flow/docker_compose.yaml down
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/start.sh
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/verify.sh
```

Hand over `wxo-booking-mcp` and its secret as the client ID and secret of the watsonx Orchestrate `oauth_auth_client_credentials_flow` connection. This recipe was tested: `verify.sh` passes with this client, and the password grant is rejected (`unauthorized_client`).

### Other common changes

| Change | Where | Notes |
| --- | --- | --- |
| Rotate a client secret | `"secret"` of the client | Update the consumer and `OIDC_CLIENT_SECRET` too. A realm export stores secrets in plain text, so keep a real-secret realm file outside Git. |
| Longer token lifetime | Add `"accessTokenLifespan": 900` (seconds) at the realm top level | watsonx Orchestrate requests a new token on its own; a longer lifetime mostly helps manual tests. |
| Another interactive MCP client | Add its callback to the client's `redirectUris`, and its origin to `webOrigins` | Use `authorization_code` with PKCE. Never enable the implicit flow. Also update `OIDC_INSPECTOR_REDIRECT_URIS` on the MCP server if the client uses `/oauth/register`. |
| Different Keycloak URL or IP | `KEYCLOAK_PUBLIC_BASE_URL` in `mcp.env` | Not a realm change; it sets the issuer (see above). |
| HTTPS | Put a TLS-terminating proxy in front, set `KEYCLOAK_PUBLIC_BASE_URL=https://...`, and set `sslRequired` to `external` | — |
| Disable the password grant on `web-app-proxy` | `"directAccessGrantsEnabled": false` | Breaks the legacy verify scripts and `mcp_test_app.py`, which still use the demo user's password grant. |

### Rules for any change

- `implicitFlowEnabled` stays `false` for every client.
- Machine-to-machine clients enable only `serviceAccountsEnabled`; set `standardFlowEnabled` and `directAccessGrantsEnabled` to `false`.
- Every client that calls the MCP server needs the `booking-api` audience mapper.
- After a change, run `verify.sh` in `booking_system_mcp_oauth2_no_implicit_flow`.

## Inspecting a Running Keycloak

```sh
# Discovery document (issuer, endpoints)
curl -s http://localhost:8086/realms/galaxium/.well-known/openid-configuration | python3 -m json.tool

# Token for the configured client, and its claims
TOKEN="$(bash local-container/booking_system_mcp_oauth2_no_implicit_flow/get-token.sh)"
python3 -c 'import base64,json,sys; p=sys.argv[1].split(".")[1]; print(json.dumps(json.loads(base64.urlsafe_b64decode(p+"="*(-len(p)%4))),indent=2))' "$TOKEN"
```

Check `iss`, `aud` (must contain `booking-api`), `azp` (the client ID), and `exp`.

Related helper scripts for the full stack: `../verify-keycloak-inspector-client.sh` asserts the Inspector client settings, including `implicitFlowEnabled: false`. `../sync-keycloak-inspector-client.sh` pushes them into a running Keycloak.

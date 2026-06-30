# Quickstart

This guide helps you get the example running fast.

## Before you begin

- Docker Engine with Compose v2 installed
- `docker` and `docker compose` available on your PATH
- optional: `jq` for verifying JSON metadata

> **Local dev for `hr_database_frontend/` only** (outside Docker): Java 21 (OpenJDK / Eclipse Temurin), Maven 3.9, and Node.js 20 are required. Run `bash hr_database_frontend/run-hr-app.sh` from the repository root — it starts both the Python HR backend and the Quarkus frontend.

Options 2 and 3 LAN access require a host IP that another machine can reach.
The OAuth smoke check in option 1 also uses `LOCAL_NET_IP`. Set it once for
your platform before running those commands:

macOS:

```sh
export LOCAL_NET_IP=$(ipconfig getifaddr en0)
```

Linux:

```sh
export LOCAL_NET_IP=$(ip route get 1.1.1.1 | awk '{print $NF; exit}')
```

Start in the repository root:

```sh
cd galaxium-travels-infrastructure-tsuedbro
```

## Which option should you choose?

| Option | Use case | Auth |
| --- | --- | --- |
| **1 — Local machine** | Everything on one laptop | Keycloak OAuth |
| **2 — Host + VM/LAN OAuth** | Expose Keycloak/MCP to a second machine or VM | Keycloak OAuth over LAN |
| **3 — Local Basic Auth** | REST, MCP, and both UIs without Keycloak | Shared Basic Auth |
| **4 — Keycloak UI + MCP Basic Auth** | Browser login via Keycloak, MCP backend uses Basic Auth | Mixed |

For the full auth and compose-file breakdown see [ARCHITECTURE.md — Authentication Variants](./ARCHITECTURE.md#authentication-variants).
For architecture boundaries and the reason the two paths keep independent booking state see [ARCHITECTURE.md](./ARCHITECTURE.md).

## Option 1: Local Machine

Use this option when everything runs on one machine.

### 1. Start the stack

Start the full stack:

```sh
docker compose -f local-container/docker_compose.yaml up --build
```

Start only the REST path:

```sh
docker compose -f local-container/docker_compose.yaml up --build \
  keycloak booking_system web_app
```

Start only the MCP path:

```sh
docker compose -f local-container/docker_compose.yaml up --build \
  keycloak booking_system_mcp web_app_mcp
```

### 2. Open the URLs

- Keycloak: `http://localhost:8086`
- HR API docs: `http://localhost:8081/docs`
- HR portal (React UI): `http://localhost:8088`
- Booking REST API docs: `http://localhost:8082/docs`
- REST web UI: `http://localhost:8083`
- MCP endpoint: `http://localhost:8084/mcp`
- MCP web UI: `http://localhost:8085`

If you start only one path, only the matching backend and frontend URLs will be available.

### 3. Log in

- Keycloak admin: `admin` / `admin`
- Traveler user: `demo-user` / `demo-user-password`

### 4. Pick the example you want

- Use the REST example at `http://localhost:8083`
- Use the MCP example at `http://localhost:8085`

Both UIs have the same traveler flow.
The difference is the backend path:

- REST UI calls the REST API
- MCP UI calls MCP tools through the MCP server

### 5. Run the local smoke test

```sh
bash local-container/verify-keycloak-auth-e2e.sh
```

### 6. Stop the stack

```sh
docker compose -f local-container/docker_compose.yaml down
```

## Option 2: Host Machine With VM / LAN OAuth

Use this option when the Galaxium stack runs on the host machine, but another app, agent, or compose stack runs in a VM or on another machine in the LAN.

### 1. Prepare the host env file

```sh
cp local-container/vm-oauth.env.template local-container/vm-oauth.env
```

Edit `local-container/vm-oauth.env` and set the host IP or DNS name that the VM can reach:

```sh
KEYCLOAK_PUBLIC_HOSTNAME=${LOCAL_NET_IP}
KEYCLOAK_PUBLIC_BASE_URL=http://${LOCAL_NET_IP}:8086
MCP_PUBLIC_BASE_URL=http://${LOCAL_NET_IP}:8084
```

Do not use `localhost` in this option.

### 2. Start the host stack

Start the full host stack:

```sh
docker compose --env-file local-container/vm-oauth.env \
  -f local-container/docker_compose.yaml \
  -f local-container/docker_compose.vm-oauth.yaml \
  up --build -d
```

Start only the REST path:

```sh
docker compose --env-file local-container/vm-oauth.env \
  -f local-container/docker_compose.yaml \
  -f local-container/docker_compose.vm-oauth.yaml \
  up --build -d keycloak booking_system web_app
```

Start only the MCP path:

```sh
docker compose --env-file local-container/vm-oauth.env \
  -f local-container/docker_compose.yaml \
  -f local-container/docker_compose.vm-oauth.yaml \
  up --build -d keycloak booking_system_mcp web_app_mcp
```

### 3. Prepare the VM-side client settings

```sh
cp local-container/vm-client.env.template local-container/vm-client.env
```

Edit `local-container/vm-client.env`:

```sh
KEYCLOAK_BASE_URL=http://${LOCAL_NET_IP}:8086
KEYCLOAK_TOKEN_URL=http://${LOCAL_NET_IP}:8086/realms/galaxium/protocol/openid-connect/token
MCP_SERVER_URL=http://${LOCAL_NET_IP}:8084/mcp
```

### 4. Verify the LAN-facing setup

```sh
cp local-container/verify-keycloak-auth-remote.env.template local-container/verify-keycloak-auth-remote.env
bash local-container/verify-keycloak-auth-remote.sh --env-file local-container/verify-keycloak-auth-remote.env
```

### 5. Stop the host stack

```sh
docker compose --env-file local-container/vm-oauth.env \
  -f local-container/docker_compose.yaml \
  -f local-container/docker_compose.vm-oauth.yaml \
  down
```

For the detailed diagram and the explanation of why this OAuth setup works, see [local-container/README.md](./local-container/README.md).

## Option 3: Local Basic Auth

Use this option when you want the REST API, MCP server, and both web UIs without Keycloak browser login.

### 1. Prepare the Basic Auth env file

```sh
cp local-container/basic-auth.env.template local-container/basic-auth.env
```

Edit `local-container/basic-auth.env` if you want credentials other than the demo defaults.

### 2. Start the stack

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth.yaml \
  up --build
```

If you want the dedicated VM/LAN-flavored Basic Auth compose variant from `local-container/`, use:

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth-vm.yaml \
  up --build
```

### 3. Open the URLs

- HR portal (React UI): `http://localhost:8088`
- Booking REST API docs: `http://localhost:8082/docs`
- REST web UI: `http://localhost:8083`
- MCP endpoint: `http://localhost:8084/mcp`
- MCP web UI: `http://localhost:8085`

### 4. Use the shared demo credentials

- Basic Auth user: `demo-basic-user`
- Basic Auth password: `demo-basic-password`

The two web UIs keep a guest traveler profile in the browser session and send the shared Basic Auth header to the backend.

If another VM or LAN client reaches this Basic Auth stack through the host IP or DNS name, prepare the matching client env file:

```sh
cp local-container/vm-client-basic-auth.env.template local-container/vm-client-basic-auth.env
```

Edit `local-container/vm-client-basic-auth.env`:

```sh
MCP_SERVER_URL=http://${LOCAL_NET_IP}:8084/mcp
BASIC_AUTH_USERNAME=demo-basic-user
BASIC_AUTH_PASSWORD=demo-basic-password
```

The same `vm-client-basic-auth.env.template` client settings apply whether you start the backend with `docker_compose.basic-auth.yaml` or `docker_compose.basic-auth-vm.yaml`.

### 5. Run the Basic Auth smoke checks

```sh
bash local-container/verify-basic-auth-backends.sh
bash local-container/verify-basic-auth-frontends-and-inspector.sh
```

### 6. Stop the stack

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth.yaml \
  down
```

If you started the VM/LAN-flavored Basic Auth compose variant, stop it with:

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth-vm.yaml \
  down
```

## Option 4: Keycloak UI + MCP Basic Auth

Use this option when you want the MCP web UI to keep the traveler browser login in Keycloak, but the MCP backend itself should accept the shared Basic Auth header.

### 1. Prepare the Basic Auth env file

```sh
cp local-container/basic-auth.env.template local-container/basic-auth.env
```

Edit `local-container/basic-auth.env` if you want credentials other than the demo defaults.

### 2. Start the mixed stack

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.yaml \
  -f local-container/docker_compose.mcp-ui-keycloak-basic.yaml \
  up --build keycloak booking_system_mcp web_app_mcp
```

### 3. Open the URLs

- Keycloak: `http://localhost:8086`
- MCP endpoint: `http://localhost:8084/mcp`
- MCP web UI: `http://localhost:8085`

### 4. Use the two credential sets

- Traveler user for the browser login: `demo-user` / `demo-user-password`
- Shared Basic Auth for the MCP backend: `demo-basic-user` / `demo-basic-password`

In this mode the traveler still signs in through Keycloak at the browser, but the MCP UI sends the shared Basic Auth header to the MCP backend on tool calls.

### 5. Run the mixed-mode smoke check

```sh
bash local-container/verify-keycloak-ui-basic-auth-mcp.sh
```

### 6. Stop the mixed stack

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.yaml \
  -f local-container/docker_compose.mcp-ui-keycloak-basic.yaml \
  down
```

## Run The Tests

Run the local Basic Auth smoke checks:

```sh
bash local-container/verify-basic-auth-backends.sh
bash local-container/verify-basic-auth-frontends-and-inspector.sh
```

Run the Keycloak UI + MCP Basic Auth smoke check:

```sh
bash local-container/verify-keycloak-ui-basic-auth-mcp.sh
```

Run the WebUI auth matrix with the local template:

```sh
cp testing/webui_matrix/local-machine-network.env.template testing/webui_matrix/local-machine-network.env
bash testing/automation/run-webui-auth-matrix.sh --env-file testing/webui_matrix/local-machine-network.env
```

Run the full cross-environment matrix:

```sh
cp testing/webui_matrix/full-matrix.env.template testing/webui_matrix/full-matrix.env
bash testing/automation/run-webui-auth-matrix.sh --env-file testing/webui_matrix/full-matrix.env
```

## Optional: MCP Inspector

If you want to inspect the MCP server manually, use:

```sh
bash local-container/start-mcp-inspector-ui.sh
```

For the full Inspector flow, including the Basic Auth config path, use [local-container/README.md](./local-container/README.md).

For a step-by-step manual commandline walkthrough of both the OAuth and Basic Auth MCP variants, use [docs/manual_auth_check_using_the_commandline.md](./docs/manual_auth_check_using_the_commandline.md).

# IBM Code Engine Deployment Draft

This folder is a draft deployment package for running the current Galaxium Travels stack on IBM Code Engine.

Scope:

- Keycloak
- HR API
- Booking REST API
- Booking MCP server
- Flask web UI

Status:

- Draft only
- Not executed in this workspace
- Not verified against a live IBM Cloud account

The current environment does not have the `ibmcloud` CLI installed, and no IBM Cloud credentials were provided. Treat these files as a starting point, not as a validated rollout.

## Why This Folder Exists

The repository already contains older Code Engine notes in [`../../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md`](../../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md), but that document does not cover the full current stack and does not include the MCP service deployment flow.

This folder adds:

- a single place for draft Code Engine deployment assets
- a current `application create` based workflow
- a direct deployment path from the local repository checkout
- separate secrets, configmap, and per-step scripts

## Deployment Model

This draft uses two patterns:

1. Local source builds for the repository services with `ibmcloud ce application create --build-source ...`.
2. A direct image deployment for Keycloak with the public image `quay.io/keycloak/keycloak:26.0`.

Keycloak imports the existing realm file from [`../../local-container/keycloak/realm/galaxium-realm.json`](../../local-container/keycloak/realm/galaxium-realm.json) through a Code Engine configmap mount.

## Important Constraints

1. The Keycloak deployment in this draft is demo-oriented because it uses `start-dev`.
2. The HR API writes to a local file. Without a mounted data store, writes are ephemeral.
3. Keycloak state is also ephemeral unless you mount a persistent data store or move Keycloak to an external database-backed setup.
4. The MCP server needs `MCP_PUBLIC_BASE_URL` and `OIDC_AUTHORIZATION_SERVER_URL` set to public URLs so discovery metadata is correct outside Docker Compose.
5. The web UI needs a valid confidential Keycloak client secret for `web-app-proxy`.

## Files

- [`deploy.env.template`](./deploy.env.template): variables to copy into `deploy.env`
- [`scripts/01-project.sh`](./scripts/01-project.sh): target IBM Cloud and create/select the Code Engine project
- [`scripts/02-config-and-secrets.sh`](./scripts/02-config-and-secrets.sh): create the realm configmap and app secrets
- [`scripts/03-deploy-keycloak.sh`](./scripts/03-deploy-keycloak.sh): deploy Keycloak
- [`scripts/04-deploy-services.sh`](./scripts/04-deploy-services.sh): deploy HR, REST, MCP, and web services
- [`scripts/05-summary.sh`](./scripts/05-summary.sh): print URLs and draft verification commands

## Prerequisites

1. Install the IBM Cloud CLI and the Code Engine plugin.
2. Log in to IBM Cloud.
3. Copy `deploy.env.template` to `deploy.env`.
4. Fill in real secret values before running any script.

Example:

```sh
cd deployment/ibm-code-engine
cp deploy.env.template deploy.env
```

## Recommended Order

Run the scripts in this order:

```sh
bash scripts/01-project.sh
bash scripts/02-config-and-secrets.sh
bash scripts/03-deploy-keycloak.sh
bash scripts/04-deploy-services.sh
bash scripts/05-summary.sh
```

## What Gets Deployed

| Component | Source | Port | Notes |
| --- | --- | --- | --- |
| Keycloak | `quay.io/keycloak/keycloak:26.0` | `8080` | Demo-mode draft with realm import |
| HR API | local source `HR_database/` | `8081` | Consider mounting a persistent data store |
| Booking API | local source `booking_system_rest/` | `8082` | OIDC validation enabled |
| Booking MCP | local source `booking_system_mcp/` | `8084` | OIDC validation and public metadata enabled |
| Web UI | local source `galaxium-booking-web-app/` | `8083` | Uses `web-app-proxy` client secret |

## Draft Follow-Up Work

Before calling this production-ready, I would change at least these points:

1. Replace Keycloak `start-dev` with a production configuration and external database.
2. Add persistent storage for Keycloak and HR data if writes must survive restarts.
3. Add custom domains and TLS handling if stable public URLs are required.
4. Add a verified remote smoke test for the MCP server in addition to the current REST and UI checks.
5. Add CI-driven Code Engine promotion instead of workstation-driven deployment.

## Reference Docs

- IBM Code Engine CLI reference: <https://cloud.ibm.com/docs/codeengine?topic=codeengine-cli>
- Deploy app from local source code: <https://cloud.ibm.com/docs/codeengine?topic=codeengine-app-local-source-code>
- Deploy app from repository source code: <https://cloud.ibm.com/docs/codeengine?topic=codeengine-app-source-code>
- Code Engine configmaps: <https://cloud.ibm.com/docs/codeengine?topic=codeengine-configmap>
- Code Engine secrets: <https://cloud.ibm.com/docs/codeengine?topic=codeengine-secret>
- Existing repo note: [`../../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md`](../../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)

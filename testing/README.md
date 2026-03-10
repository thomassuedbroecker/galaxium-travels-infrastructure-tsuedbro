# Testing

This folder is the entry point for repository test automation and test result documentation.

## Scope

- REST API unit and integration tests from `booking_system_rest/tests/`
- UI behavior checks against the compose stack
- MCP integration checks against the compose stack

This README covers the local compose-based automation path.
For the host-stack VM/LAN OAuth verification path, use `local-container/verify-keycloak-auth-remote.sh` as documented in [../QUICKSTART.md](../QUICKSTART.md) and [../local-container/README.md](../local-container/README.md).

## Structure

```text
testing/
├── README.md
├── automation/
│   ├── common.sh
│   ├── run-all-tests.sh
│   ├── run-mcp-integration-tests.sh
│   ├── run-rest-api-tests.sh
│   └── run-ui-behavior-tests.sh
└── results/
    ├── README.md
    └── LATEST-VALIDATION.md
```

## Prerequisites

- Docker with Compose support
- Network access for image and package downloads during container builds

## Commands

Run everything:

```sh
bash testing/automation/run-all-tests.sh
```

Run only the REST API suite:

```sh
bash testing/automation/run-rest-api-tests.sh
```

Run only the UI behavior checks:

```sh
bash testing/automation/run-ui-behavior-tests.sh
```

Run only the MCP integration checks:

```sh
bash testing/automation/run-mcp-integration-tests.sh
```

## What The Integration Suites Cover

UI behavior checks:

- the REST-backed UI and the direct-MCP UI both redirect `/` to `/login` when traveler auth is required
- unauthenticated UI APIs return `401`
- traveler login creates a usable session in both apps
- authenticated UI calls can list flights, view bookings, and book a flight in both apps

MCP integration checks:

- OAuth metadata endpoints are reachable
- unauthenticated MCP `initialize` is rejected
- authenticated `initialize` succeeds
- authenticated `tools/list` exposes the expected booking tools

Raw output and generated reports are written under `testing/results/generated/`.

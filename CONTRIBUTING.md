# Contributing

Thank you for improving Galaxium Travels Infrastructure.

This repository is a demonstration of REST and MCP integration patterns for an AI-ready booking app. Contributions should keep the project easy to understand, runnable, and well documented.

## Developer Certificate of Origin (DCO)

Every commit must carry a `Signed-off-by` trailer certifying agreement with the
[Developer Certificate of Origin](https://developercertificate.org/).
**The hook does this for you automatically** — run the one-time setup below
right after cloning and you never have to think about it again.

```sh
bash setup-hooks.sh
```

That script points Git at the `.githooks/` directory in this repo.
From that point on, every `git commit` appends the trailer automatically.

> **Prerequisite** — your Git identity must be configured:
> ```sh
> git config --global user.name  "Your Name"
> git config --global user.email "you@example.com"
> ```

A GitHub Actions workflow (`.github/workflows/dco.yml`) verifies the trailer on
every PR. Once GitHub's native DCO enforcement is enabled for this repository
the workflow will be removed.

## How to contribute

1. Clone the repo and run `bash setup-hooks.sh` once.
2. Open an issue for new feature ideas, bug fixes, or documentation changes.
3. Work in a feature branch with a descriptive name.
4. Keep docs in sync with code and architecture changes.
5. Submit a pull request against `main` or the current default branch.

## Local development

Use the repository quickstart first:

```sh
cd galaxium-travels-infrastructure-tsuedbro
less QUICKSTART.md
```

To run the local demo stack:

```sh
docker compose -f local-container/docker_compose.yaml up --build
```

To run only the REST path:

```sh
docker compose -f local-container/docker_compose.yaml up --build keycloak booking_system web_app
```

To run only the MCP path:

```sh
docker compose -f local-container/docker_compose.yaml up --build keycloak booking_system_mcp web_app_mcp
```

## Testing

Use the repo test guide for the authoritative scope and prerequisites:

```sh
less testing/README.md
```

Fast validation commands:

```sh
bash testing/automation/run-all-tests.sh
bash testing/automation/run-rest-api-tests.sh
bash testing/automation/run-mcp-integration-tests.sh
```

If you change docs, update both `README.md` and `QUICKSTART.md` as needed.

## Documentation updates

| Document | Responsibility |
| --- | --- |
| `README.md` | Purpose, navigation, services, and verification summary |
| `QUICKSTART.md` | Shortest runnable path and selectable runtime options |
| `ARCHITECTURE.md` | Runtime boundaries, state model, auth modes, and design consequences |
| `local-container/README.md` | Compose details, LAN configuration, and verification helpers |
| `testing/README.md` | Test scope, commands, and recorded evidence |

Keep claims precise: the REST and MCP paths expose equivalent booking flows
but use independent state stores. Do not describe them as a shared booking
database or synchronized system unless the implementation changes.

## Pull Request Checklist

- Run the smallest relevant automated check from `testing/README.md`.
- Update documentation when service topology, authentication, ports, env
  variables, or commands change.
- Update `ARCHITECTURE.md` when a change affects component boundaries or a
  documented architecture decision.
- Do not commit local `.env` files, generated test output, or demo database
  files.

## Notes

This repo is a learning and demonstration project. Keep new code and documentation focused on clarity, architecture, and reproducibility.

# HANDOFF.md — Galaxium Travels Infrastructure

This file is the shared **state** document for AI-assisted development across
agentic IDEs (IBM Bob, Claude Code, Codex, and similar tools). It records
where work stands and what changed in each session.

Rules, patterns, and commands are **not** repeated here — read
[`AGENTS.md`](./AGENTS.md) first. It is the single source of truth for the
service map, non-obvious patterns, test commands, OAuth rules, and code style.

---

## Project in one sentence

Python monorepo that demonstrates REST vs MCP integration for a travel-booking
domain — same business flow, two separate runtimes, swappable auth modes.

---

## Start of session

1. Read [`AGENTS.md`](./AGENTS.md).
2. Read **Current branch and state** below and the latest **Session log** row.
3. Run the smallest relevant test from `AGENTS.md` before changing code.

---

## Current branch and state

| Field | Value |
|---|---|
| Branch | `main` |
| Base branch | `main` |
| Last commit | `af29c97` — docs: align open-source dependency and license overview |
| Uncommitted changes | IBM Code Engine OAuth2 deployment (`deploy-stack-oauth2.sh`, `deploy.env.oauth2`), `.ceignore` source packaging, session caching in CE scripts, idempotent mounts, full live cloud validation, and documentation updates across path guides and READMEs |

Update this section at the end of every session.

---

## Where to look

| Need | File |
|---|---|
| Rules, patterns, test commands (canonical) | [`AGENTS.md`](./AGENTS.md) |
| Decision-tree navigation hub | [`NAVIGATOR.md`](./NAVIGATOR.md) |
| Run options, auth-mode matrix, demo credentials | [`QUICKSTART.md`](./QUICKSTART.md) |
| Architecture decisions and component map | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| MCP endpoint, tools, session handshake, auth | [`docs/AI_ENGINEER_GUIDE.md`](./docs/AI_ENGINEER_GUIDE.md) |
| Compose variants and verification scripts | [`local-container/README.md`](./local-container/README.md) |
| MCP-only access options (no auth / Basic / OAuth 2.0) | [`docs/mcp_access_options.md`](./docs/mcp_access_options.md) |
| Keycloak realm, clients, adjustment recipes | [`local-container/keycloak/README.md`](./local-container/keycloak/README.md) |
| Test scope and evidence | [`testing/README.md`](./testing/README.md) |
| Machine-readable repo summary for LLM tools | [`LLMS.txt`](./LLMS.txt) |

---

## Agentic IDE — per-tool notes

### IBM Bob
- Project rules are loaded from `AGENTS.md` and `.bob/rules-*/AGENTS.md`.
- Use `apply_diff` / `search_and_replace` for surgical edits; avoid full
  rewrites of large files.

### Claude Code
- `AGENTS.md` is loaded at session start.
- Run `python3 -m pytest tests -q` from `booking_system_rest/` before and
  after any change to the REST service.

### Codex (or any OpenAI-based agent)
- Provide `AGENTS.md` plus this file as context when starting a new session.

---

## How to update this file

At the end of a work session:

1. Update **Current branch and state**.
2. Append one row to **Session log** (newest last): date, agent/IDE, branch,
   what changed, next open task.
3. If you changed a rule, pattern, or command, update `AGENTS.md` (and mirror
   it in `LLMS.txt`) — not this file.

---

## Session log

| Date | Agent / IDE | Branch | What changed | Next open task |
|---|---|---|---|---|
| 2026-06-20 | IBM Bob | main | Initial HANDOFF.md created | — |
| 2026-06-25 | IBM Bob | main | Added DCO git hook (`.githooks/commit-msg`), `setup-hooks.sh`, `.github/workflows/dco.yml` (pinned to `dcoapp/app@113757536` v1.0.0). Fixed: mutable tag → SHA pin, `chmod +x` now persisted via `git update-index`, dead `msg` variable removed, double blank-line before sign-off trailer fixed. Added `README.md` badges (Tests, DCO, License). Added `.github/workflows/tests.yml` with three parallel no-Docker jobs: `rest-unit` (5 pytest files), `contracts` (local-container + Code Engine), `webui-unit` (matrix config). | Commit and push open changes (`README.md`, `tests.yml`) |
| 2026-06-27 | IBM Bob | frontend_for_the_hr_database | Documentation sync for `hr_database_frontend` integration: added service to all navigation docs (`README.md`, `NAVIGATOR.md`, `QUICKSTART.md`, `ARCHITECTURE.md`, `LLMS.txt`, `HANDOFF.md`, `AGENTS.md`); updated Mermaid diagrams; added Java/Maven/Node prerequisite note; updated base-image table; added `hr_database_frontend/*.log` to `.gitignore`. 31/31 contract tests passed. | Review and remove stale `docs/reference/` files |
| 2026-07-10 | IBM Bob | main | Renamed `hr_database_frontend/` → `hr_database_frontend_java/` (git mv). Container host port changed 8088→8090 to avoid overlap when running locally and in Docker simultaneously. Updated all references across `AGENTS.md`, `ARCHITECTURE.md`, `HANDOFF.md`, `NAVIGATOR.md`, `QUICKSTART.md`, `README.md`, `LLMS.txt`, `local-container/docker_compose.yaml`, `.gitignore`, `run-hr-app.sh`, and both `docker-compose.yaml` files. | — |
| 2026-09-07 | Manual commit | main | Added PowerPoint overview (`galaxium-travels-repository-overview-with-diagrams.pptx`). Updated `.gitignore`. | — |
| 2026-09-07/08 | Manual commits | main | Added `hr_database_backend_java/` (alternative Quarkus HR API). Added Jobs domain to `hr_database_frontend_java/` (JAX-RS `JobResource`, `JobApiClient`, React pages `JobListPage`, `JobDetailPage`, `JobFormPage`, `jobsApiService`). Configured HR frontend backend URL at runtime (env var) instead of build time. Updated `hr_database_backend/` with `Dockerfile`, `README.md`, `app.py`, and data files (`employees.md`, `jobs.md`). `.gitignore` updated to exclude compiled Java/Maven artifacts. Contract tests realigned to current HR frontend. | — |
| 2026-10-15 | IBM Bob | main | Fixed Bash "unbound variable" errors on macOS (`set -u`) in three verify scripts by replacing empty-array expansion with robust `${arr[@]+"${arr[@]}"}` syntax. Updated `testing/test_local_container_contracts.py` to match. Corrected `/msp` endpoint alias description from "Watson Discovery" → "watsonx Orchestrate" in `docs/AI_ENGINEER_GUIDE.md`, `AGENTS.md`, `LLMS.txt`. Removed stale `docs/reference/suggestions-for-better-developer-navigation.md`. Minor doc/Bob config cleanup (`.bob/mcp.json`, `.bob/rules-ask/AGENTS.md`, `.bob/settings.json`). | — |
| 2026-10-15 | Claude Code | main | Added `/jobs` CRUD to `hr_database_backend_java/` (`Job`, `JobRepository`, `JobResource`, `JobResourceTest`, `data/jobs.md`; 12/12 Maven tests pass) so the HR portal's Jobs pages work with either backend. Docs sync: Jobs + Java backend across README/ARCHITECTURE/NAVIGATOR/LLMS/AGENTS, documented 9 missing MCP/REST env vars, fixed 11 broken links in `docs/`, refreshed `testing/README.md` status. Rewrote `docs/AI_ENGINEER_GUIDE.md`: correct MCP session handshake (verified against a local server), `client_credentials` token instead of password grant, tool argument/return table, booking flow, error shape. Made `AGENTS.md` canonical for rules (added OAuth rule: implicit flow not allowed); slimmed this file to state + log. | Commit the session's changes; add a Maven job for `hr_database_backend_java` to CI |
| 2026-10-15 | Claude Code | main | Added MCP-only access option folders `local-container/booking_system_mcp_no_auth/`, `booking_system_mcp_basic_auth/`, `booking_system_mcp_oauth2_no_implicit_flow/` (compose, `start.sh`, `verify.sh`, `mcp.env.template`, integration handover for the external watsonx Orchestrate guide repo), shared `local-container/booking_system_mcp_lib.sh`, `docs/mcp_access_options.md`, `local-container/keycloak/README.md` (realm, clients, issuer, `KEYCLOAK_REALM_DIR` override, tested dedicated-client recipe). Validated every supported local combination (Options 1–4, basic-auth-vm, WebUI matrix 55/55, MCP-only incl. LAN IP, both HR standalone stacks, Java HR backend 12/12); see `testing/results/LATEST-VALIDATION.md`. Fixed `local-container/README.md` compose commands missing `-f docker_compose.yaml`; documented the HR container-name conflict; docs sync across README/NAVIGATOR/QUICKSTART/ARCHITECTURE/AI guide/LLMS/AGENTS. 39/39 contract tests. | Commit; optional: give standalone HR stacks distinct container names; drop `password` from MCP OAuth metadata once legacy scripts move to `client_credentials` |
| 2026-10-19 | IBM Bob | main | Automated & verified IBM Code Engine OAuth2 stack (`deploy-stack-oauth2.sh`, `deploy.env.oauth2`, `DEPLOY-PATH-B-OAUTH2.md`, `teardown-stack-oauth2.sh`). Added `.ceignore` to resolve package upload limits. Added active-session caching across all 7 deployment scripts to eliminate redundant `ibmcloud login` calls. Made Keycloak volume mounts and env var removals idempotent. Live verified all 5 services, Keycloak OIDC, Bearer auth, and Streamable HTTP MCP tools end-to-end. Updated repo documentation. | — |
| 2026-10-20 | IBM Bob | main | Added `deployment/ibm-code-engine/export-deployment.sh` (exports live Code Engine links as `deployment-links.env`/`.md` with `EXPORTED_AT`, plus configmaps, application definitions and rendered env files to `generated/exports/<project>-<auth mode>-<timestamp>/`; works with `deploy.env` and `deploy.env.oauth2`, read-only, no secret values). Documented in `deployment/ibm-code-engine/README.md` (new section), both path guides, `AGENTS.md`, `LLMS.txt`. |

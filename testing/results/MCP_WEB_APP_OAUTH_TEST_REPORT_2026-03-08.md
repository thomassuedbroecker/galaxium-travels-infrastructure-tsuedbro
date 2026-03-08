# MCP Web App OAuth Test Report

Date: 2026-03-08
Scope: `galaxium-booking-web-app-mcp/` with OAuth always enabled
Primary suite: `bash local-container/verify-keycloak-auth-e2e.sh`

## Overview

- Final status: `PASS`
- Final validated run: `20260308T144828Z`
- Final run duration: `15s`
- March 8 MCP web app validation cycle:
  - Total E2E runs: `4`
  - Passing runs: `2`
  - Failing runs: `2`
  - Total recorded E2E execution time: `63s`
- Final full-suite result count:
  - Passed: `12`
  - Failed: `0`
  - Total: `12`

## Test Environment

- Host OS: `Darwin Mac 25.3.0`, `arm64`
- Docker Server Version: `29.1.3`
- Test execution model: local Docker Compose stack from `local-container/docker_compose.yaml`
- Auth mode for `web-app-mcp`: OAuth required, traveler login required
- Compose services involved:
  - `keycloak` on `8080`
  - `booking_system_rest` on `8082`
  - `web_app` on `8083`
  - `booking_system_mcp` on `8084`
  - `web_app_mcp` on `8085`
- Container/runtime base images:
  - `web_app` and `web_app_mcp`: `python:3.12-slim`
  - `booking_system_rest` and `booking_system_mcp`: `python:3.11-slim`
  - `keycloak`: `quay.io/keycloak/keycloak:26.0`
- MCP client package used by `web_app_mcp`: `mcp 1.26.0`
- MCP server runtime observed in logs: `FastMCP 3.1.0`

## Test Data

- Keycloak admin credentials:
  - `admin / admin`
- Traveler credentials used in test flow:
  - `demo-user / demo-user-password`
- OAuth client used by both web apps:
  - `client_id=web-app-proxy`
  - `client_secret=web-app-proxy-secret`
- Traveler profile derived from Keycloak token during MCP web app login:
  - Username: `demo-user`
  - Name: `Demo User`
  - Email: `demo-user@galaxium.com`
- Booking action test data:
  - `flight_id=1`
- Booking backend seed data from `booking_system_mcp/seed.py`:
  - `10` seeded users
  - `10` seeded flights
  - `20` seeded bookings
- MCP tools explicitly validated:
  - `list_flights`
  - `book_flight`
  - `get_bookings`
  - `cancel_booking`
  - `register_user`
  - `get_user_id`

## Executed Tests

The full suite executed these checks in the final run:

| Test ID | What Was Tested | Expected Result | Final Result |
| --- | --- | --- | --- |
| `E2E-000` | Compose build/startup and health reachability for Keycloak, REST API, REST web app, MCP web app, and MCP root | All services reachable | `PASS` |
| `E2E-008` | Keycloak client sync plus validation of `web-app-proxy` settings for OAuth and Inspector compatibility | Valid client settings | `PASS` |
| `E2E-011` | Traveler token acquisition through Keycloak password grant | Token returned | `PASS` |
| `E2E-001` | Unauthenticated browser access to REST-backed web app root | `302` redirect to `/login` | `PASS` |
| `E2E-002` | Unauthenticated API access to REST-backed web app | `401` with `frontend_auth_required` | `PASS` |
| `E2E-003` | REST-backed web app login and authenticated session APIs | Login succeeds and authenticated endpoints return data | `PASS` |
| `E2E-003B` | MCP-backed web app login and authenticated session APIs | Login succeeds and authenticated endpoints return data | `PASS` |
| `E2E-004` | REST API without bearer token | `401` rejection | `PASS` |
| `E2E-005` | REST API with valid Keycloak token | `200` and flight payload | `PASS` |
| `E2E-009` | MCP OAuth discovery endpoints and dynamic registration endpoint | Valid metadata and `201` registration | `PASS` |
| `E2E-006` | MCP `initialize` without bearer token | `401` rejection | `PASS` |
| `E2E-007` | MCP `initialize` and `tools/list` with bearer token | `200` and expected tool list | `PASS` |

## Run History

### Run 1

- Run ID: `20260308T143825Z`
- Start: `2026-03-08T14:38:25Z`
- End: `2026-03-08T14:38:46Z`
- Duration: `21s`
- Result: `FAIL`
- Summary: `6 passed`, `1 failed`, `7 total`
- Failed test:
  - `E2E-003B`: Traveler login via MCP web app expected HTTP `302` but got `200`
- Finding:
  - Keycloak login itself succeeded, but traveler registration inside `web_app_mcp` failed after the MCP `get_user_id` call returned `USER_NOT_FOUND`.
  - The root cause was that the MCP client exception was wrapped in nested `ExceptionGroup` objects during `anyio` task-group shutdown, so the Flask app received a generic error instead of the mapped `BookingServiceError`.
- Changes caused by this run:
  - Added nested exception unwrapping in [booking_mcp_service.py](/Users/thomassuedbroecker/Documents/dev/gpt_codex/optimize_existing_github_projects/galaxium-travels-infrastructure-tsuedbro/galaxium-booking-web-app-mcp/app/booking_mcp_service.py#L107)
  - Added synchronous wrapper rethrow of mapped domain errors in [booking_mcp_service.py](/Users/thomassuedbroecker/Documents/dev/gpt_codex/optimize_existing_github_projects/galaxium-travels-infrastructure-tsuedbro/galaxium-booking-web-app-mcp/app/booking_mcp_service.py#L199)
- Artifacts:
  - `local-container/test-results/oauth-e2e-all-20260308T143825Z.md`
  - `local-container/test-results/oauth-e2e-all-20260308T143825Z.json`
  - `local-container/test-results/oauth-e2e-all-20260308T143825Z.log`

### Run 2

- Run ID: `20260308T144055Z`
- Start: `2026-03-08T14:40:55Z`
- End: `2026-03-08T14:41:08Z`
- Duration: `13s`
- Result: `FAIL`
- Summary: `6 passed`, `1 failed`, `7 total`
- Failed test:
  - `E2E-003B`: MCP web app flights payload did not match expected pattern `"flight_id"`
- Finding:
  - The login and traveler registration path was fixed.
  - The remaining problem was MCP tool result normalization: `list_flights` returned data shaped as `{"result": [...]}` and the web app wrapper expected a bare list, so the UI endpoint returned `[]`.
- Changes caused by this run:
  - Added result-wrapper unwrapping in [booking_mcp_service.py](/Users/thomassuedbroecker/Documents/dev/gpt_codex/optimize_existing_github_projects/galaxium-travels-infrastructure-tsuedbro/galaxium-booking-web-app-mcp/app/booking_mcp_service.py#L121)
  - Applied the same normalization path to dict and structured MCP outputs in [booking_mcp_service.py](/Users/thomassuedbroecker/Documents/dev/gpt_codex/optimize_existing_github_projects/galaxium-travels-infrastructure-tsuedbro/galaxium-booking-web-app-mcp/app/booking_mcp_service.py#L262)
- Artifacts:
  - `local-container/test-results/oauth-e2e-all-20260308T144055Z.md`
  - `local-container/test-results/oauth-e2e-all-20260308T144055Z.json`
  - `local-container/test-results/oauth-e2e-all-20260308T144055Z.log`

### Run 3

- Run ID: `20260308T144222Z`
- Start: `2026-03-08T14:42:22Z`
- End: `2026-03-08T14:42:36Z`
- Duration: `14s`
- Result: `PASS`
- Summary: `12 passed`, `0 failed`, `12 total`
- Outcome:
  - First fully green run for the MCP-backed web app with OAuth enabled
  - Validated login, authenticated UI calls, REST auth behavior, and MCP OAuth/protocol behavior
- Changes caused by this run:
  - No additional fix required after execution; this run confirmed the two MCP service-layer fixes above
- Artifacts:
  - `local-container/test-results/oauth-e2e-all-20260308T144222Z.md`
  - `local-container/test-results/oauth-e2e-all-20260308T144222Z.json`
  - `local-container/test-results/oauth-e2e-all-20260308T144222Z.log`

### Run 4

- Run ID: `20260308T144828Z`
- Start: `2026-03-08T14:48:28Z`
- End: `2026-03-08T14:48:43Z`
- Duration: `15s`
- Result: `PASS`
- Summary: `12 passed`, `0 failed`, `12 total`
- Purpose:
  - Regression run after hardening `web-app-mcp` to be OAuth-only with no insecure mode
- Changes caused before this run:
  - Enforced OAuth-only startup validation in [app.py](/Users/thomassuedbroecker/Documents/dev/gpt_codex/optimize_existing_github_projects/galaxium-travels-infrastructure-tsuedbro/galaxium-booking-web-app-mcp/app/app.py#L49)
  - Removed non-OAuth branches from MCP web app request handling in [app.py](/Users/thomassuedbroecker/Documents/dev/gpt_codex/optimize_existing_github_projects/galaxium-travels-infrastructure-tsuedbro/galaxium-booking-web-app-mcp/app/app.py#L182)
  - Updated secure defaults in [.env-template](/Users/thomassuedbroecker/Documents/dev/gpt_codex/optimize_existing_github_projects/galaxium-travels-infrastructure-tsuedbro/galaxium-booking-web-app-mcp/.env-template#L1)
  - Updated runtime/security docs in [README.md](/Users/thomassuedbroecker/Documents/dev/gpt_codex/optimize_existing_github_projects/galaxium-travels-infrastructure-tsuedbro/galaxium-booking-web-app-mcp/README.md#L1)
  - Updated verifier to wait for the MCP web app health endpoint in [verify-keycloak-auth-e2e.sh](/Users/thomassuedbroecker/Documents/dev/gpt_codex/optimize_existing_github_projects/galaxium-travels-infrastructure-tsuedbro/local-container/verify-keycloak-auth-e2e.sh#L669)
- Outcome:
  - The hardened OAuth-only app still passed the full suite without regressions
- Artifacts:
  - `local-container/test-results/oauth-e2e-all-20260308T144828Z.md`
  - `local-container/test-results/oauth-e2e-all-20260308T144828Z.json`
  - `local-container/test-results/oauth-e2e-all-20260308T144828Z.log`

## Static Validation Executed

These checks were also executed during the cycle:

- `python3 -m compileall galaxium-travels-infrastructure-tsuedbro/galaxium-booking-web-app-mcp/app`
  - Result: `PASS`
  - Purpose: Python syntax/import validation for the new app code
- `bash -n galaxium-travels-infrastructure-tsuedbro/local-container/verify-keycloak-auth-e2e.sh`
  - Result: `PASS`
  - Purpose: shell syntax validation for the updated verifier

Note: per-run durations were recorded by the JSON artifacts only for the E2E suite. The static checks did not persist separate timing metadata.

## Final Conclusion

- `web-app-mcp` is validated as an OAuth-only application.
- The final regression run passed all `12/12` checks.
- Two defects were found during the March 8 validation cycle:
  - nested MCP client exception wrapping
  - MCP result-wrapper normalization
- Both defects were fixed and revalidated in subsequent runs.

## Primary Artifacts

- Final markdown report: `local-container/test-results/oauth-e2e-all-20260308T144828Z.md`
- Final JSON report: `local-container/test-results/oauth-e2e-all-20260308T144828Z.json`
- Final raw log: `local-container/test-results/oauth-e2e-all-20260308T144828Z.log`
- This consolidated report: `testing/results/MCP_WEB_APP_OAUTH_TEST_REPORT_2026-03-08.md`

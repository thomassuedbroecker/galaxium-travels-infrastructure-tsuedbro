# Latest Validation

- Summary date: `2026-03-18`
- Validation type: composite committed validation summary
- Overall status: `PASS`

## Verified Checks

- Local compose OAuth smoke: `PASS`
  - Command: `bash local-container/verify-keycloak-auth-e2e.sh`
  - Coverage: REST auth, MCP auth, traveler web login, inspector client sync, and OAuth metadata discovery
  - Report: `local-container/test-results/oauth-e2e-all-20260318T204838Z.md`

- Local Basic Auth backend smoke: `PASS`
  - Command: `bash local-container/verify-basic-auth-backends.sh`
  - Coverage: REST `401/200` checks plus authenticated MCP `initialize`, `tools/list`, and `tools/call(list_flights)`

- Local Basic Auth frontend plus inspector smoke: `PASS`
  - Command: `bash local-container/verify-basic-auth-frontends-and-inspector.sh`
  - Coverage: REST UI guest flow, MCP UI guest flow, and Basic Auth inspector config generation over `Streamable HTTP`

- WebUI matrix unit config checks: `PASS`
  - Command: `python3 -m unittest testing.webui_matrix.tests.unit.test_config -v`
  - Result: `11/11` tests green

- Full WebUI auth matrix: `PASS`
  - Command:

    ```sh
    WEBUI_TEST_PUBLIC_HOST=192.168.2.88 \
    WEBUI_TEST_RUN_DOCKER=1 \
    WEBUI_TEST_SKIP_BUILD=1 \
    WEBUI_TEST_RUN_FULL_MATRIX=1 \
    python3 -m unittest discover -s testing/webui_matrix/tests -p 'test_*.py' -v
    ```
  - Result: `55 tests passed`, `0 skipped`

- VM / LAN remote auth verification: `PASS`
  - Command: `bash local-container/verify-keycloak-auth-remote.sh --env-file local-container/verify-keycloak-auth-remote.env`
  - Additional checks:
    - MCP metadata checks for `/.well-known/oauth-authorization-server` and `/.well-known/oauth-protected-resource`
    - `python3 local-container/mcp_test_app.py --mcp-url http://192.168.2.88:8084/mcp --token-source http --token-url http://192.168.2.88:8086/realms/galaxium/protocol/openid-connect/token`

## Notes

- This file tracks the latest committed validation state across the active validation slices.
- `bash testing/automation/run-all-tests.sh` is still useful, but it does not include the Basic Auth smoke checks, the full WebUI matrix, or the VM / LAN remote verification.

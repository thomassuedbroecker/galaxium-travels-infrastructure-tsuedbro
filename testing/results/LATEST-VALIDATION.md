# Latest Validation

- Summary date: `2026-09-07`
- Reviewed code commit: `67746dc`
- Latest executed scope: local-container and Code Engine contract tests
- Result: **PASS — 31 tests run, 31 passed, 0 failed**

```sh
python3 -B -m unittest testing.test_local_container_contracts testing.test_code_engine_deployment_contracts -q
```

The four failures previously recorded here were stale test expectations, not
runtime defects, and the local-container suite has been realigned with the
current checkout:

- HR frontend assertions expected `8088:8088`, `HR_API_URL`, and
  `hr_database_frontend:1.0.0`. They now assert the shipped contract —
  `8090:8088`, `HR_BACKEND_URL=http://hr-database:8081`, and
  `hr_database_frontend_java:1.0.0`.
- The env-template parser only recognized bare assignments. It now also accepts
  the `export` prefix used by `basic-auth.env.template`, which the Basic Auth
  verification scripts `source`.

Only the contract suites were rerun. No Docker smoke tests, full auth matrix, or
cloud deployment were rerun.

## Historical Runtime Evidence

[testing/README.md](../README.md#current-verified-state) records later March
runs, including the March 23 aggregate regression, March 24 local contracts,
and March 25 Code Engine contracts. Those historical passes do not establish
that the current checkout passes. Generated artifacts are not tracked in Git.
The March 18 details below are retained as historical evidence only.

## Historical March 18 Checks

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

# Testing for Galaxium Booking REST API

This document describes the current REST API test scope in `booking_system_rest/tests/`.

## Current Test Files

```text
tests/
├── conftest.py
├── test_auth_modes.py
├── test_booking_system.py
├── test_database.py
├── test_flight_management.py
└── test_user_management.py
```

What these cover:

- `test_user_management.py`
  - registration, duplicate-email handling, `/user_id`, and user lookup behavior
- `test_booking_system.py`
  - booking, cancellation, validation, and booking ownership rules
- `test_flight_management.py`
  - flight listing and seat availability behavior
- `test_database.py`
  - database initialization and seeding expectations
- `test_auth_modes.py`
  - `AUTH_MODE=basic` validation and request enforcement

## Fast Commands

From `booking_system_rest/`:

```sh
python3 -m pytest tests -q
```

Verbose run:

```sh
python3 -m pytest tests -v
```

Coverage run:

```sh
python3 -m pytest tests --cov=app --cov=models --cov=db --cov-report=term-missing
```

Convenience runner:

```sh
python run_tests.py fast
python run_tests.py all
python run_tests.py coverage
```

Containerized repo-level run:

```sh
bash ../testing/automation/run-rest-api-tests.sh
```

## Auth Test Notes

- Default local pytest runs exercise the API directly without Keycloak.
- `test_auth_modes.py` verifies the Basic Auth mode:
  - missing credentials fail configuration validation
  - missing request credentials return `401`
  - wrong credentials return `401`
  - correct credentials return `200`
- OAuth behavior for the REST API is primarily validated through the repo-level compose smoke and WebUI matrix flows in [../testing/README.md](../testing/README.md).

## Test Environment

- Tests use `FastAPI TestClient`.
- Database access is isolated through fixture overrides from `conftest.py`.
- The test database is recreated per test session/fixture flow, so persistent local `booking.db` state is not required.

## When To Use Which Path

- Use `python3 -m pytest tests -q` while editing REST API code in this folder.
- Use `bash ../testing/automation/run-rest-api-tests.sh` when you want the same containerized path used by the repo automation.
- Use the repo-level smoke and matrix checks when a REST change can affect OAuth, browser flows, or the shared comparison between REST and MCP.

## Related Docs

- Main REST usage doc: [README.md](README.md)
- Repository-wide testing guide: [../testing/README.md](../testing/README.md)
- Local compose verification flows: [../local-container/README.md](../local-container/README.md)

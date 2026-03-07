# Galaxium Booking REST API

FastAPI and SQLite backend for the booking demo.

## Run Locally

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --reload --port 8082
```

Docs: `http://localhost:8082/docs`

The database is created and seeded on startup.

## Test

```sh
python3 -m pytest tests -q
```

Convenience commands:

```sh
python run_tests.py fast
python run_tests.py all
```

Detailed testing notes live in [TESTING.md](TESTING.md).

## Main Endpoints

- `GET /health`
- `GET /flights`
- `POST /book`
- `GET /bookings/{user_id}`
- `POST /cancel/{booking_id}`
- `POST /register`
- `GET /user_id`

## Auth

Auth is off by default.

Set these variables to require bearer tokens:

- `AUTH_ENABLED=true`
- `OIDC_ISSUER=http://localhost:8080/realms/galaxium`
- `OIDC_AUDIENCE=booking-api`
- `OIDC_JWKS_URL=http://localhost:8080/realms/galaxium/protocol/openid-connect/certs`

Compose injects the container-internal variants automatically.

## Related Docs

- Shared error-handling notes: [docs/error-handling-guide.md](docs/error-handling-guide.md)
- Examples: [docs/error-handling-examples.md](docs/error-handling-examples.md)
- Repository quickstart: [../QUICKSTART.md](../QUICKSTART.md)

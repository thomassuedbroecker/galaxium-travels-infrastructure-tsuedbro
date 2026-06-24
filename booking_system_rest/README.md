# Galaxium Booking REST API

| | |
| --- | --- |
| **Port** | `8082` |
| **Entry point** | `app.py` |
| **Auth config** | `AUTH_MODE=none` (default) · `oauth2` · `basic` |
| **Local run** | `uvicorn app:app --reload --port 8082` |
| **Test command** | `python3 -m pytest tests -q` |
| **Compose service** | `booking_system` |

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

Use one of these modes:

- `AUTH_MODE=none`
- `AUTH_MODE=oauth2`
- `AUTH_MODE=basic`

For backward compatibility, `AUTH_ENABLED=true` still enables the OAuth mode when `AUTH_MODE` is not set.

Set these variables to require bearer tokens:

- `AUTH_MODE=oauth2`
- `OIDC_ISSUER=http://localhost:8086/realms/galaxium`
- `OIDC_AUDIENCE=booking-api`
- `OIDC_JWKS_URL=http://localhost:8086/realms/galaxium/protocol/openid-connect/certs`

Set these variables to require Basic Auth:

- `AUTH_MODE=basic`
- `BASIC_AUTH_USERNAME=demo-basic-user`
- `BASIC_AUTH_PASSWORD=demo-basic-password`

Compose injects the container-internal variants automatically.

## Compose Usage

Compose service name: `booking_system`

- Local compose stack: see [../QUICKSTART.md](../QUICKSTART.md), option 1.
- VM/LAN OAuth host stack: see [../QUICKSTART.md](../QUICKSTART.md), option 2.
- Local Basic Auth stack: see [../local-container/README.md](../local-container/README.md), option 3.
- REST-backed frontend path only:

  ```sh
  docker compose -f ../local-container/docker_compose.yaml up --build \
    keycloak booking_system web_app
  ```

- REST Basic Auth path only:

  ```sh
  docker compose -f ../local-container/docker_compose.basic-auth.yaml up --build \
    booking_system
  ```

## Related Docs

- Shared error-handling notes: [docs/error-handling-guide.md](docs/error-handling-guide.md)
- Examples: [docs/error-handling-examples.md](docs/error-handling-examples.md)
- Repository quickstart: [../QUICKSTART.md](../QUICKSTART.md)
- Compose flow: [../local-container/README.md](../local-container/README.md)

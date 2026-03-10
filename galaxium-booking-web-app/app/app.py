from __future__ import annotations

import base64
import json
import logging
import os
import time
from typing import Any

import requests
from flask import (
    Flask,
    Response,
    jsonify,
    redirect,
    render_template,
    request,
    session,
    url_for,
)
from flask_cors import CORS


LOGIN_SCOPE_DEFAULT = "openid profile email"


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _as_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


BACKEND_URL = (os.getenv("BACKEND_URL") or "").strip()
# Service-to-service OAuth2 toggle.
OAUTH2_ENABLED = _as_bool(os.getenv("OAUTH2_ENABLED"), default=False)
# Browser login requirement toggle.
FRONTEND_AUTH_REQUIRED = _as_bool(
    os.getenv("FRONTEND_AUTH_REQUIRED"),
    default=OAUTH2_ENABLED,
)

OIDC_TOKEN_URL = (os.getenv("OIDC_TOKEN_URL") or "").strip()
OIDC_CLIENT_ID = (os.getenv("OIDC_CLIENT_ID") or "").strip()
OIDC_CLIENT_SECRET = (os.getenv("OIDC_CLIENT_SECRET") or "").strip()
OIDC_SCOPE = (os.getenv("OIDC_SCOPE") or LOGIN_SCOPE_DEFAULT).strip()

FLASK_SECRET_KEY = (os.getenv("FLASK_SECRET_KEY") or "").strip()

FRONTEND_MODE_ID = "rest"
FRONTEND_MODE_LABEL = "REST API"
FRONTEND_MODE_SUMMARY = "This frontend proxies booking requests to the REST backend."
BACKEND_LABEL = "REST API backend"
INTEGRATION_MODE = "rest_api_proxy"

TOKEN_CACHE = {
    "access_token": None,
    "expires_at_epoch": 0,
}

app = Flask(__name__, static_folder="static", template_folder="templates")
app.secret_key = FLASK_SECRET_KEY or "dev-secret-change-me"
logger = logging.getLogger(__name__)

# Enable CORS for all routes and origins
CORS(app, resources={r"/*": {"origins": "*"}}, send_wildcard=True)


def validate_runtime_settings() -> None:
    if not BACKEND_URL:
        raise RuntimeError("BACKEND_URL must be set")

    if FRONTEND_AUTH_REQUIRED and not OAUTH2_ENABLED:
        raise RuntimeError(
            "FRONTEND_AUTH_REQUIRED=true requires OAUTH2_ENABLED=true so user tokens can be validated by backend"
        )

    if not OAUTH2_ENABLED:
        return

    missing = []
    if not OIDC_TOKEN_URL:
        missing.append("OIDC_TOKEN_URL")
    if not OIDC_CLIENT_ID:
        missing.append("OIDC_CLIENT_ID")
    if not OIDC_CLIENT_SECRET:
        missing.append("OIDC_CLIENT_SECRET")
    if FRONTEND_AUTH_REQUIRED and not FLASK_SECRET_KEY:
        missing.append("FLASK_SECRET_KEY")

    if missing:
        raise RuntimeError(
            "OAuth2 is enabled but missing settings: "
            + ", ".join(missing)
        )


validate_runtime_settings()

if FRONTEND_AUTH_REQUIRED:
    logger.warning(
        "FRONTEND_AUTH_REQUIRED=true: browser users must log in with Keycloak. "
        "Backend calls use traveler user token."
    )
elif OAUTH2_ENABLED:
    logger.warning(
        "OAUTH2_ENABLED=true and FRONTEND_AUTH_REQUIRED=false: using service-to-service client credentials."
    )
else:
    logger.warning("OAuth2 disabled: backend calls have no bearer token.")


def _frontend_template_context() -> dict[str, str]:
    return {
        "frontend_mode_id": FRONTEND_MODE_ID,
        "frontend_mode_label": FRONTEND_MODE_LABEL,
        "frontend_mode_summary": FRONTEND_MODE_SUMMARY,
        "backend_label": BACKEND_LABEL,
    }


def _decode_jwt_payload(token: str) -> dict[str, Any]:
    parts = token.split(".")
    if len(parts) < 2:
        return {}
    payload = parts[1]
    payload += "=" * ((4 - len(payload) % 4) % 4)
    try:
        decoded = base64.urlsafe_b64decode(payload.encode("utf-8")).decode("utf-8")
        parsed = json.loads(decoded)
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def _clear_user_session() -> None:
    for key in [
        "user_access_token",
        "user_expires_at_epoch",
        "traveler_username",
        "traveler_name",
        "traveler_email",
        "traveler_id",
    ]:
        session.pop(key, None)


def _get_user_access_token() -> str | None:
    token = session.get("user_access_token")
    if not token:
        return None

    expires_at_epoch = _as_int(session.get("user_expires_at_epoch"), 0)
    now = int(time.time())
    if expires_at_epoch and now >= (expires_at_epoch - 20):
        _clear_user_session()
        return None

    return str(token)


def _profile_from_access_token(token: str) -> dict[str, str]:
    claims = _decode_jwt_payload(token)
    username = (
        claims.get("preferred_username")
        or claims.get("username")
        or claims.get("sub")
        or "traveler"
    )

    name = claims.get("name")
    if not name:
        given = (claims.get("given_name") or "").strip()
        family = (claims.get("family_name") or "").strip()
        if given or family:
            name = f"{given} {family}".strip()
    if not name:
        name = username

    email = claims.get("email") or f"{username}@galaxium.local"

    return {
        "username": str(username),
        "name": str(name),
        "email": str(email),
    }


def _get_service_access_token() -> str | None:
    if not OAUTH2_ENABLED:
        return None

    now = int(time.time())
    cached = TOKEN_CACHE["access_token"]
    if cached and now < (TOKEN_CACHE["expires_at_epoch"] - 20):
        return str(cached)

    data = {
        "grant_type": "client_credentials",
        "client_id": OIDC_CLIENT_ID,
        "client_secret": OIDC_CLIENT_SECRET,
    }
    if OIDC_SCOPE:
        data["scope"] = OIDC_SCOPE

    response = requests.post(OIDC_TOKEN_URL, data=data, timeout=10)
    response.raise_for_status()

    token_payload = response.json()
    token = token_payload.get("access_token")
    if not token:
        raise RuntimeError("Token endpoint did not return an access_token")

    expires_in = _as_int(token_payload.get("expires_in"), 60)
    TOKEN_CACHE["access_token"] = token
    TOKEN_CACHE["expires_at_epoch"] = now + expires_in
    return str(token)


def _backend_bearer_for_request() -> str | None:
    if FRONTEND_AUTH_REQUIRED:
        return _get_user_access_token()
    if OAUTH2_ENABLED:
        return _get_service_access_token()
    return None


def _auth_challenge(api: bool) -> Response:
    if api:
        payload = {
            "error": "frontend_auth_required",
            "detail": "Traveler login is required. Open /login in the browser.",
        }
        return Response(json.dumps(payload), status=401, content_type="application/json")

    next_path = request.path or "/"
    return redirect(url_for("login", next=next_path))


def _backend_request(
    method: str,
    path: str,
    bearer_token: str | None,
    params: dict[str, Any] | None = None,
    json_body: dict[str, Any] | None = None,
) -> requests.Response:
    url = f"{BACKEND_URL}{path}"
    headers = {"Content-Type": "application/json"}
    if bearer_token:
        headers["Authorization"] = f"Bearer {bearer_token}"

    return requests.request(
        method=method,
        url=url,
        params=params,
        json=json_body,
        headers=headers,
        timeout=10,
    )


def _proxy_backend_response(resp: requests.Response) -> Response:
    return Response(resp.content, status=resp.status_code, content_type="application/json")


def _ensure_traveler_registration(bearer_token: str) -> dict[str, Any]:
    if not bearer_token:
        raise RuntimeError("Missing traveler token")

    name = (session.get("traveler_name") or "").strip()
    email = (session.get("traveler_email") or "").strip()
    if not name or not email:
        raise RuntimeError("Missing traveler profile in session")

    lookup_resp = _backend_request(
        "GET",
        "/user_id",
        bearer_token,
        params={"name": name, "email": email},
    )
    lookup_resp.raise_for_status()
    lookup_payload = lookup_resp.json()

    if isinstance(lookup_payload, dict) and lookup_payload.get("user_id"):
        traveler_id = _as_int(lookup_payload.get("user_id"))
        session["traveler_id"] = traveler_id
        return {"traveler_id": traveler_id, "name": name, "email": email}

    if isinstance(lookup_payload, dict) and lookup_payload.get("error_code") == "USER_NOT_FOUND":
        register_resp = _backend_request(
            "POST",
            "/register",
            bearer_token,
            json_body={"name": name, "email": email},
        )
        register_resp.raise_for_status()
        register_payload = register_resp.json()
        if isinstance(register_payload, dict) and register_payload.get("user_id"):
            traveler_id = _as_int(register_payload.get("user_id"))
            session["traveler_id"] = traveler_id
            return {"traveler_id": traveler_id, "name": name, "email": email}
        raise RuntimeError(f"Traveler registration failed: {register_payload}")

    raise RuntimeError(f"Traveler lookup failed: {lookup_payload}")


def _api_proxy(
    method: str,
    path: str,
    params: dict[str, Any] | None = None,
    json_body: dict[str, Any] | None = None,
) -> Response:
    try:
        bearer = _backend_bearer_for_request()
        if FRONTEND_AUTH_REQUIRED and not bearer:
            return _auth_challenge(api=True)

        resp = _backend_request(
            method=method,
            path=path,
            bearer_token=bearer,
            params=params,
            json_body=json_body,
        )
        return _proxy_backend_response(resp)
    except requests.RequestException as exc:
        payload = {"error": "backend_unreachable", "detail": str(exc)}
        return Response(json.dumps(payload), status=502, content_type="application/json")
    except Exception as exc:
        payload = {"error": "auth_error", "detail": str(exc)}
        return Response(json.dumps(payload), status=502, content_type="application/json")


@app.route("/login", methods=["GET", "POST"])
def login():
    if not FRONTEND_AUTH_REQUIRED:
        return redirect(url_for("index"))

    error_message = ""
    next_path = request.values.get("next") or "/"

    if request.method == "POST":
        username = (request.form.get("username") or "").strip()
        password = request.form.get("password") or ""
        if not username or not password:
            error_message = "Username and password are required"
        else:
            data = {
                "grant_type": "password",
                "client_id": OIDC_CLIENT_ID,
                "client_secret": OIDC_CLIENT_SECRET,
                "username": username,
                "password": password,
            }
            if OIDC_SCOPE:
                data["scope"] = OIDC_SCOPE

            try:
                token_resp = requests.post(OIDC_TOKEN_URL, data=data, timeout=10)
                if token_resp.status_code >= 400:
                    error_message = "Keycloak login failed. Verify traveler credentials."
                else:
                    token_payload = token_resp.json()
                    access_token = token_payload.get("access_token")
                    if not access_token:
                        error_message = "Keycloak did not return an access token"
                    else:
                        _clear_user_session()
                        profile = _profile_from_access_token(access_token)
                        expires_in = _as_int(token_payload.get("expires_in"), 60)
                        session["user_access_token"] = access_token
                        session["user_expires_at_epoch"] = int(time.time()) + expires_in
                        session["traveler_username"] = profile["username"]
                        session["traveler_name"] = profile["name"]
                        session["traveler_email"] = profile["email"]
                        _ensure_traveler_registration(access_token)

                        if not next_path.startswith("/"):
                            next_path = "/"
                        return redirect(next_path)
            except Exception as exc:
                error_message = f"Login request failed: {str(exc)}"

    return render_template(
        "login.html",
        error=error_message,
        next_path=next_path,
        **_frontend_template_context(),
    )


@app.route("/logout", methods=["GET"])
def logout():
    _clear_user_session()
    if FRONTEND_AUTH_REQUIRED:
        return redirect(url_for("login"))
    return redirect(url_for("index"))


@app.route("/")
def index():
    traveler = None
    if FRONTEND_AUTH_REQUIRED:
        token = _get_user_access_token()
        if not token:
            return _auth_challenge(api=False)

        try:
            traveler = {
                "traveler_id": session.get("traveler_id"),
                "username": session.get("traveler_username"),
                "name": session.get("traveler_name"),
                "email": session.get("traveler_email"),
            }
            if not traveler.get("traveler_id"):
                traveler = _ensure_traveler_registration(token)
                traveler["username"] = session.get("traveler_username")
            else:
                traveler["traveler_id"] = _as_int(traveler.get("traveler_id"))
        except Exception as exc:
            _clear_user_session()
            return redirect(url_for("login", next="/", error=str(exc)))

    return render_template(
        "index.html",
        backend_url=BACKEND_URL,
        frontend_auth_required=FRONTEND_AUTH_REQUIRED,
        traveler=traveler,
        **_frontend_template_context(),
    )


@app.route("/api/traveler", methods=["GET"])
def api_get_traveler():
    if not FRONTEND_AUTH_REQUIRED:
        payload = {
            "frontend_auth_required": False,
            "detail": "Traveler login is disabled for this deployment",
        }
        return jsonify(payload)

    token = _get_user_access_token()
    if not token:
        return _auth_challenge(api=True)

    try:
        traveler = _ensure_traveler_registration(token)
        traveler["username"] = session.get("traveler_username")
        return jsonify(traveler)
    except Exception as exc:
        return Response(
            json.dumps({"error": "traveler_sync_failed", "detail": str(exc)}),
            status=502,
            content_type="application/json",
        )


@app.route("/api/flights", methods=["GET"])
def api_get_flights():
    return _api_proxy("GET", "/flights")


@app.route("/api/register", methods=["POST"])
def api_register():
    if FRONTEND_AUTH_REQUIRED:
        token = _get_user_access_token()
        if not token:
            return _auth_challenge(api=True)
        try:
            traveler = _ensure_traveler_registration(token)
            traveler["username"] = session.get("traveler_username")
            return jsonify(traveler)
        except Exception as exc:
            return Response(
                json.dumps({"error": "traveler_register_failed", "detail": str(exc)}),
                status=502,
                content_type="application/json",
            )

    body = request.get_json(force=True)
    return _api_proxy("POST", "/register", json_body=body)


@app.route("/api/get_user", methods=["GET"])
def api_get_user():
    if FRONTEND_AUTH_REQUIRED:
        token = _get_user_access_token()
        if not token:
            return _auth_challenge(api=True)
        try:
            traveler = _ensure_traveler_registration(token)
            traveler["username"] = session.get("traveler_username")
            return jsonify(traveler)
        except Exception as exc:
            return Response(
                json.dumps({"error": "traveler_lookup_failed", "detail": str(exc)}),
                status=502,
                content_type="application/json",
            )

    name = request.args.get("name")
    email = request.args.get("email")
    params = {"name": name, "email": email}
    return _api_proxy("GET", "/user_id", params=params)


@app.route("/api/book", methods=["POST"])
def api_book():
    body = request.get_json(force=True) or {}

    if FRONTEND_AUTH_REQUIRED:
        token = _get_user_access_token()
        if not token:
            return _auth_challenge(api=True)

        try:
            traveler = _ensure_traveler_registration(token)
            flight_id = _as_int(body.get("flight_id"), 0)
            if flight_id <= 0:
                payload = {"error": "invalid_request", "detail": "flight_id must be a positive integer"}
                return Response(json.dumps(payload), status=400, content_type="application/json")

            booking_payload = {
                "user_id": traveler["traveler_id"],
                "name": traveler["name"],
                "flight_id": flight_id,
            }
            return _api_proxy("POST", "/book", json_body=booking_payload)
        except Exception as exc:
            return Response(
                json.dumps({"error": "traveler_sync_failed", "detail": str(exc)}),
                status=502,
                content_type="application/json",
            )

    return _api_proxy("POST", "/book", json_body=body)


@app.route("/api/bookings", methods=["GET"])
def api_get_my_bookings():
    if FRONTEND_AUTH_REQUIRED:
        token = _get_user_access_token()
        if not token:
            return _auth_challenge(api=True)
        try:
            traveler = _ensure_traveler_registration(token)
            return _api_proxy("GET", f"/bookings/{traveler['traveler_id']}")
        except Exception as exc:
            return Response(
                json.dumps({"error": "traveler_sync_failed", "detail": str(exc)}),
                status=502,
                content_type="application/json",
            )

    user_id = _as_int(request.args.get("user_id"), 0)
    if user_id <= 0:
        payload = {"error": "invalid_request", "detail": "user_id query parameter is required"}
        return Response(json.dumps(payload), status=400, content_type="application/json")
    return _api_proxy("GET", f"/bookings/{user_id}")


@app.route("/api/bookings/<int:user_id>", methods=["GET"])
def api_get_bookings(user_id: int):
    if FRONTEND_AUTH_REQUIRED:
        token = _get_user_access_token()
        if not token:
            return _auth_challenge(api=True)

        traveler_id = _as_int(session.get("traveler_id"), 0)
        if traveler_id and user_id != traveler_id:
            payload = {
                "error": "forbidden",
                "detail": "Traveler can only access own bookings",
            }
            return Response(json.dumps(payload), status=403, content_type="application/json")

    return _api_proxy("GET", f"/bookings/{user_id}")


@app.route("/api/cancel/<int:booking_id>", methods=["POST"])
def api_cancel(booking_id: int):
    return _api_proxy("POST", f"/cancel/{booking_id}")


@app.route("/api/health")
def health():
    return jsonify(
        {
            "status": "ok",
            "integration_mode": INTEGRATION_MODE,
            "frontend_mode": FRONTEND_MODE_ID,
            "proxy_to": BACKEND_URL,
            "oauth2_enabled": OAUTH2_ENABLED,
            "frontend_auth_required": FRONTEND_AUTH_REQUIRED,
            "frontend_user_login_enforced": FRONTEND_AUTH_REQUIRED,
            "auth_mode": (
                "traveler-login-and-backend"
                if FRONTEND_AUTH_REQUIRED
                else "service-to-service"
                if OAUTH2_ENABLED
                else "none"
            ),
            "traveler_session_active": bool(_get_user_access_token()),
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8083, debug=True)

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

from booking_mcp_service import BookingMcpService, BookingServiceError


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


def _as_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _resolve_backend_auth_mode(
    explicit_mode: str | None,
    *,
    legacy_oauth_enabled: bool,
) -> str:
    if explicit_mode is None:
        return "oauth2" if legacy_oauth_enabled else "none"

    normalized = explicit_mode.strip().lower()
    if normalized in {"none", "oauth2", "basic"}:
        return normalized

    raise RuntimeError(
        "BACKEND_AUTH_MODE must be one of: none, oauth2, basic"
    )


MCP_SERVER_URL = (os.getenv("MCP_SERVER_URL") or "").strip()
BACKEND_AUTH_MODE = _resolve_backend_auth_mode(
    os.getenv("BACKEND_AUTH_MODE"),
    legacy_oauth_enabled=_as_bool(os.getenv("OAUTH2_ENABLED"), default=True),
)
OAUTH2_ENABLED = BACKEND_AUTH_MODE == "oauth2"
FRONTEND_AUTH_REQUIRED = _as_bool(
    os.getenv("FRONTEND_AUTH_REQUIRED"),
    default=OAUTH2_ENABLED,
)

OIDC_TOKEN_URL = (os.getenv("OIDC_TOKEN_URL") or "").strip()
OIDC_CLIENT_ID = (os.getenv("OIDC_CLIENT_ID") or "").strip()
OIDC_CLIENT_SECRET = (os.getenv("OIDC_CLIENT_SECRET") or "").strip()
OIDC_SCOPE = (os.getenv("OIDC_SCOPE") or LOGIN_SCOPE_DEFAULT).strip()
BASIC_AUTH_USERNAME = (os.getenv("BASIC_AUTH_USERNAME") or "").strip()
BASIC_AUTH_PASSWORD = os.getenv("BASIC_AUTH_PASSWORD") or ""
FLASK_SECRET_KEY = (os.getenv("FLASK_SECRET_KEY") or "").strip()
MCP_TIMEOUT_SECONDS = _as_float(os.getenv("MCP_TIMEOUT_SECONDS"), default=10.0)
APP_PORT = _as_int(os.getenv("PORT"), 8085)

FRONTEND_MODE_ID = "mcp"
FRONTEND_MODE_LABEL = "MCP"
FRONTEND_MODE_SUMMARY = "This frontend executes booking actions through MCP tool calls."
BACKEND_LABEL = "MCP server"
INTEGRATION_MODE = "direct_python_mcp_client"

TOKEN_CACHE = {
    "access_token": None,
    "expires_at_epoch": 0,
}

app = Flask(__name__, static_folder="static", template_folder="templates")
app.secret_key = FLASK_SECRET_KEY or "dev-secret-change-me"
logger = logging.getLogger(__name__)

# Keep browser requests simple in local demo deployments.
CORS(app, resources={r"/*": {"origins": "*"}}, send_wildcard=True)

booking_service = BookingMcpService(
    server_url=MCP_SERVER_URL,
    timeout_seconds=MCP_TIMEOUT_SECONDS,
)


def _frontend_template_context() -> dict[str, str]:
    return {
        "frontend_mode_id": FRONTEND_MODE_ID,
        "frontend_mode_label": FRONTEND_MODE_LABEL,
        "frontend_mode_summary": FRONTEND_MODE_SUMMARY,
        "backend_label": BACKEND_LABEL,
    }


def validate_runtime_settings() -> None:
    if not MCP_SERVER_URL:
        raise RuntimeError("MCP_SERVER_URL must be set")

    if FRONTEND_AUTH_REQUIRED and BACKEND_AUTH_MODE != "oauth2":
        raise RuntimeError(
            "FRONTEND_AUTH_REQUIRED=true requires BACKEND_AUTH_MODE=oauth2 so traveler bearer tokens can be sent to the MCP server."
        )

    if BACKEND_AUTH_MODE == "none":
        return

    if BACKEND_AUTH_MODE == "basic":
        missing = []
        if not BASIC_AUTH_USERNAME:
            missing.append("BASIC_AUTH_USERNAME")
        if not BASIC_AUTH_PASSWORD:
            missing.append("BASIC_AUTH_PASSWORD")
        if missing:
            raise RuntimeError(
                "Basic Auth is enabled but missing settings: " + ", ".join(missing)
            )
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
            "OAuth2 is enabled but missing settings: " + ", ".join(missing)
        )


validate_runtime_settings()

if FRONTEND_AUTH_REQUIRED:
    logger.warning(
        "FRONTEND_AUTH_REQUIRED=true: browser users must log in with Keycloak. MCP tool calls reuse the traveler bearer token."
    )
elif BACKEND_AUTH_MODE == "oauth2":
    logger.warning(
        "BACKEND_AUTH_MODE=oauth2 and FRONTEND_AUTH_REQUIRED=false: using service-to-service client credentials for MCP tool calls."
    )
elif BACKEND_AUTH_MODE == "basic":
    logger.warning(
        "BACKEND_AUTH_MODE=basic and FRONTEND_AUTH_REQUIRED=false: using shared Basic Auth credentials for MCP tool calls."
    )
else:
    logger.warning(
        "BACKEND_AUTH_MODE=none and FRONTEND_AUTH_REQUIRED=false: MCP tool calls use no Authorization header."
    )


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


def _clear_guest_traveler_session() -> None:
    for key in [
        "guest_traveler_id",
        "guest_traveler_name",
        "guest_traveler_email",
    ]:
        session.pop(key, None)


def _guest_traveler_from_session() -> dict[str, Any] | None:
    traveler_id = _as_int(session.get("guest_traveler_id"), 0)
    if traveler_id <= 0:
        return None

    return {
        "traveler_id": traveler_id,
        "name": str(session.get("guest_traveler_name") or ""),
        "email": str(session.get("guest_traveler_email") or ""),
        "frontend_auth_required": False,
        "username": None,
    }


def _store_guest_traveler(
    *,
    traveler_id: int,
    name: str,
    email: str,
) -> dict[str, Any]:
    session["guest_traveler_id"] = traveler_id
    session["guest_traveler_name"] = name
    session["guest_traveler_email"] = email
    return {
        "traveler_id": traveler_id,
        "name": name,
        "email": email,
        "frontend_auth_required": False,
        "username": None,
    }


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
    if BACKEND_AUTH_MODE != "oauth2":
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


def _basic_auth_header() -> str | None:
    if BACKEND_AUTH_MODE != "basic":
        return None

    encoded = base64.b64encode(
        f"{BASIC_AUTH_USERNAME}:{BASIC_AUTH_PASSWORD}".encode("utf-8")
    ).decode("ascii")
    return f"Basic {encoded}"


def _backend_authorization_header_for_request() -> str | None:
    if FRONTEND_AUTH_REQUIRED:
        bearer_token = _get_user_access_token()
        return f"Bearer {bearer_token}" if bearer_token else None
    if BACKEND_AUTH_MODE == "oauth2":
        bearer_token = _get_service_access_token()
        return f"Bearer {bearer_token}" if bearer_token else None
    if BACKEND_AUTH_MODE == "basic":
        return _basic_auth_header()
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


def _gateway_error_response(error: str, exc: Exception) -> Response:
    payload = {"error": error, "detail": str(exc)}
    return Response(json.dumps(payload), status=502, content_type="application/json")


def _business_error_response(exc: BookingServiceError) -> Response:
    payload = {
        "success": False,
        "error": exc.error,
        "error_code": exc.error_code,
        "details": exc.details,
    }
    return Response(json.dumps(payload), status=200, content_type="application/json")


def _ensure_traveler_registration(authorization_header: str) -> dict[str, Any]:
    if not authorization_header:
        raise RuntimeError("Missing traveler authorization header")

    name = (session.get("traveler_name") or "").strip()
    email = (session.get("traveler_email") or "").strip()
    if not name or not email:
        raise RuntimeError("Missing traveler profile in session")

    try:
        user = booking_service.get_user_id(
            authorization_header, name=name, email=email
        )
    except BookingServiceError as exc:
        if exc.error_code != "USER_NOT_FOUND":
            raise
        user = booking_service.register_user(
            authorization_header, name=name, email=email
        )

    traveler_id = _as_int(user.get("user_id"), 0)
    if traveler_id <= 0:
        raise RuntimeError(f"Traveler registration returned invalid payload: {user}")

    session["traveler_id"] = traveler_id
    return {"traveler_id": traveler_id, "name": name, "email": email}


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
                        _clear_guest_traveler_session()
                        profile = _profile_from_access_token(access_token)
                        expires_in = _as_int(token_payload.get("expires_in"), 60)
                        session["user_access_token"] = access_token
                        session["user_expires_at_epoch"] = int(time.time()) + expires_in
                        session["traveler_username"] = profile["username"]
                        session["traveler_name"] = profile["name"]
                        session["traveler_email"] = profile["email"]
                        _ensure_traveler_registration(f"Bearer {access_token}")

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
    _clear_guest_traveler_session()
    if FRONTEND_AUTH_REQUIRED:
        return redirect(url_for("login"))
    return redirect(url_for("index"))


@app.route("/")
def index():
    traveler = _guest_traveler_from_session()
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
                traveler = _ensure_traveler_registration(f"Bearer {token}")
                traveler["username"] = session.get("traveler_username")
            else:
                traveler["traveler_id"] = _as_int(traveler.get("traveler_id"))
        except Exception as exc:
            _clear_user_session()
            return redirect(url_for("login", next="/", error=str(exc)))

    return render_template(
        "index.html",
        backend_url=MCP_SERVER_URL,
        frontend_auth_required=FRONTEND_AUTH_REQUIRED,
        traveler=traveler,
        **_frontend_template_context(),
    )


@app.route("/api/traveler", methods=["GET"])
def api_get_traveler():
    if not FRONTEND_AUTH_REQUIRED:
        traveler = _guest_traveler_from_session()
        if traveler:
            return jsonify(traveler)
        return jsonify(
            {
                "frontend_auth_required": False,
                "detail": "Traveler login is disabled for this deployment. Register or look up a traveler profile first.",
            }
        )

    authorization_header = _backend_authorization_header_for_request()
    if not authorization_header:
        return _auth_challenge(api=True)

    try:
        traveler = _ensure_traveler_registration(authorization_header)
        traveler["username"] = session.get("traveler_username")
        return jsonify(traveler)
    except BookingServiceError as exc:
        return _business_error_response(exc)
    except Exception as exc:
        return _gateway_error_response("traveler_sync_failed", exc)


@app.route("/api/flights", methods=["GET"])
def api_get_flights():
    authorization_header = _backend_authorization_header_for_request()
    if FRONTEND_AUTH_REQUIRED and not authorization_header:
        return _auth_challenge(api=True)

    try:
        return jsonify(booking_service.list_flights(authorization_header))
    except BookingServiceError as exc:
        return _business_error_response(exc)
    except Exception as exc:
        return _gateway_error_response("backend_unreachable", exc)


@app.route("/api/register", methods=["POST"])
def api_register():
    authorization_header = _backend_authorization_header_for_request()
    if FRONTEND_AUTH_REQUIRED and not authorization_header:
        return _auth_challenge(api=True)

    if FRONTEND_AUTH_REQUIRED:
        try:
            traveler = _ensure_traveler_registration(authorization_header)
            traveler["username"] = session.get("traveler_username")
            return jsonify(traveler)
        except BookingServiceError as exc:
            return _business_error_response(exc)
        except Exception as exc:
            return _gateway_error_response("traveler_register_failed", exc)

    body = request.get_json(force=True) or {}
    name = str(body.get("name") or "").strip()
    email = str(body.get("email") or "").strip()
    if not name or not email:
        payload = {
            "error": "invalid_request",
            "detail": "name and email are required",
        }
        return Response(json.dumps(payload), status=400, content_type="application/json")

    try:
        user = booking_service.register_user(authorization_header, name=name, email=email)
        traveler_id = _as_int(user.get("user_id"), 0)
        if traveler_id <= 0:
            raise RuntimeError(f"Traveler registration returned invalid payload: {user}")
        traveler = _store_guest_traveler(
            traveler_id=traveler_id,
            name=str(user.get("name") or name),
            email=str(user.get("email") or email),
        )
        return jsonify(traveler)
    except BookingServiceError as exc:
        return _business_error_response(exc)
    except Exception as exc:
        return _gateway_error_response("traveler_register_failed", exc)


@app.route("/api/get_user", methods=["GET"])
def api_get_user():
    authorization_header = _backend_authorization_header_for_request()
    if FRONTEND_AUTH_REQUIRED and not authorization_header:
        return _auth_challenge(api=True)

    if FRONTEND_AUTH_REQUIRED:
        try:
            traveler = _ensure_traveler_registration(authorization_header)
            traveler["username"] = session.get("traveler_username")
            return jsonify(traveler)
        except BookingServiceError as exc:
            return _business_error_response(exc)
        except Exception as exc:
            return _gateway_error_response("traveler_lookup_failed", exc)

    name = (request.args.get("name") or "").strip()
    email = (request.args.get("email") or "").strip()
    if not name or not email:
        payload = {
            "error": "invalid_request",
            "detail": "name and email query parameters are required",
        }
        return Response(json.dumps(payload), status=400, content_type="application/json")

    try:
        user = booking_service.get_user_id(authorization_header, name=name, email=email)
        traveler_id = _as_int(user.get("user_id"), 0)
        if traveler_id <= 0:
            raise RuntimeError(f"Traveler lookup returned invalid payload: {user}")
        traveler = _store_guest_traveler(
            traveler_id=traveler_id,
            name=str(user.get("name") or name),
            email=str(user.get("email") or email),
        )
        return jsonify(traveler)
    except BookingServiceError as exc:
        return _business_error_response(exc)
    except Exception as exc:
        return _gateway_error_response("traveler_lookup_failed", exc)


@app.route("/api/book", methods=["POST"])
def api_book():
    body = request.get_json(force=True) or {}
    authorization_header = _backend_authorization_header_for_request()
    if FRONTEND_AUTH_REQUIRED and not authorization_header:
        return _auth_challenge(api=True)

    try:
        if FRONTEND_AUTH_REQUIRED:
            traveler = _ensure_traveler_registration(authorization_header)
            user_id = traveler["traveler_id"]
            name = traveler["name"]
        else:
            guest_traveler = _guest_traveler_from_session()
            user_id = _as_int(
                body.get("user_id"),
                guest_traveler["traveler_id"] if guest_traveler else 0,
            )
            name = str(
                body.get("name") or (guest_traveler["name"] if guest_traveler else "")
            ).strip()

        flight_id = _as_int(body.get("flight_id"), 0)
        if user_id <= 0 or not name or flight_id <= 0:
            payload = {
                "error": "invalid_request",
                "detail": "Register a traveler first or provide user_id, name, and flight_id.",
            }
            return Response(
                json.dumps(payload), status=400, content_type="application/json"
            )

        booking = booking_service.book_flight(
            authorization_header,
            user_id=user_id,
            name=name,
            flight_id=flight_id,
        )
        return jsonify(booking)
    except BookingServiceError as exc:
        return _business_error_response(exc)
    except Exception as exc:
        return _gateway_error_response("traveler_sync_failed", exc)


@app.route("/api/bookings", methods=["GET"])
def api_get_my_bookings():
    authorization_header = _backend_authorization_header_for_request()
    if FRONTEND_AUTH_REQUIRED and not authorization_header:
        return _auth_challenge(api=True)

    try:
        if FRONTEND_AUTH_REQUIRED:
            traveler = _ensure_traveler_registration(authorization_header)
            user_id = traveler["traveler_id"]
        else:
            guest_traveler = _guest_traveler_from_session()
            user_id = _as_int(
                request.args.get("user_id"),
                guest_traveler["traveler_id"] if guest_traveler else 0,
            )
            if user_id <= 0:
                payload = {
                    "error": "invalid_request",
                    "detail": "Register a traveler first or provide user_id.",
                }
                return Response(
                    json.dumps(payload), status=400, content_type="application/json"
                )

        return jsonify(booking_service.get_bookings(authorization_header, user_id))
    except BookingServiceError as exc:
        return _business_error_response(exc)
    except Exception as exc:
        return _gateway_error_response("traveler_sync_failed", exc)


@app.route("/api/bookings/<int:user_id>", methods=["GET"])
def api_get_bookings(user_id: int):
    authorization_header = _backend_authorization_header_for_request()
    if FRONTEND_AUTH_REQUIRED and not authorization_header:
        return _auth_challenge(api=True)

    if FRONTEND_AUTH_REQUIRED:
        traveler_id = _as_int(session.get("traveler_id"), 0)
        if traveler_id and user_id != traveler_id:
            payload = {
                "error": "forbidden",
                "detail": "Traveler can only access own bookings",
            }
            return Response(
                json.dumps(payload), status=403, content_type="application/json"
            )
    else:
        guest_traveler = _guest_traveler_from_session()
        if guest_traveler and user_id != guest_traveler["traveler_id"]:
            payload = {
                "error": "forbidden",
                "detail": "Guest traveler session can only access own bookings",
            }
            return Response(
                json.dumps(payload), status=403, content_type="application/json"
            )

    try:
        return jsonify(booking_service.get_bookings(authorization_header, user_id))
    except BookingServiceError as exc:
        return _business_error_response(exc)
    except Exception as exc:
        return _gateway_error_response("backend_unreachable", exc)


@app.route("/api/cancel/<int:booking_id>", methods=["POST"])
def api_cancel(booking_id: int):
    authorization_header = _backend_authorization_header_for_request()
    if FRONTEND_AUTH_REQUIRED and not authorization_header:
        return _auth_challenge(api=True)

    try:
        return jsonify(booking_service.cancel_booking(authorization_header, booking_id))
    except BookingServiceError as exc:
        return _business_error_response(exc)
    except Exception as exc:
        return _gateway_error_response("backend_unreachable", exc)


@app.route("/api/health")
def health():
    return jsonify(
        {
            "status": "ok",
            "integration_mode": INTEGRATION_MODE,
            "frontend_mode": FRONTEND_MODE_ID,
            "proxy_to": MCP_SERVER_URL,
            "backend_auth_mode": BACKEND_AUTH_MODE,
            "oauth2_enabled": OAUTH2_ENABLED,
            "frontend_auth_required": FRONTEND_AUTH_REQUIRED,
            "frontend_user_login_enforced": FRONTEND_AUTH_REQUIRED,
            "auth_mode": (
                "traveler-login-and-mcp"
                if FRONTEND_AUTH_REQUIRED
                else "service-to-service-oauth"
                if BACKEND_AUTH_MODE == "oauth2"
                else "basic-backend"
                if BACKEND_AUTH_MODE == "basic"
                else "none"
            ),
            "traveler_session_active": bool(_get_user_access_token()),
            "guest_traveler_session_active": bool(_guest_traveler_from_session()),
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=APP_PORT, debug=True)

import os
import json
import logging
from datetime import datetime
from fastmcp import FastMCP
from fastmcp.server.auth import AccessToken, TokenVerifier
from pydantic import BaseModel
from starlette.middleware import Middleware
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, PlainTextResponse, RedirectResponse, Response

from auth import auth_enabled, validate_access_token, validate_auth_configuration
from db import SessionLocal, init_db
from models import Booking, Flight, User
from seed import seed

CORS_ALLOW_ORIGIN = (os.getenv("MCP_CORS_ALLOW_ORIGIN") or "*").strip() or "*"
CORS_ALLOW_HEADERS = (
    os.getenv("MCP_CORS_ALLOW_HEADERS")
    or "Authorization, Content-Type, MCP-Protocol-Version, mcp-protocol-version"
).strip()
CORS_ALLOW_METHODS = (os.getenv("MCP_CORS_ALLOW_METHODS") or "GET, POST, OPTIONS").strip()
CORS_EXPOSE_HEADERS = (os.getenv("MCP_CORS_EXPOSE_HEADERS") or "WWW-Authenticate").strip()


def _with_cors(response: Response) -> Response:
    response.headers["Access-Control-Allow-Origin"] = CORS_ALLOW_ORIGIN
    response.headers["Access-Control-Allow-Headers"] = CORS_ALLOW_HEADERS
    response.headers["Access-Control-Allow-Methods"] = CORS_ALLOW_METHODS
    response.headers["Access-Control-Expose-Headers"] = CORS_EXPOSE_HEADERS
    return response


def _mcp_base_url() -> str:
    explicit = (os.getenv("MCP_PUBLIC_BASE_URL") or "").strip()
    if explicit:
        return explicit.rstrip("/")
    return "http://localhost:8084"


class KeycloakTokenVerifier(TokenVerifier):
    def __init__(self) -> None:
        super().__init__(base_url=_mcp_base_url())

    async def verify_token(self, token: str) -> AccessToken | None:
        try:
            claims = validate_access_token(token)
        except Exception as exc:
            logging.warning("MCP token validation failed: %s", exc)
            return None

        raw_scope = claims.get("scope")
        scopes = []
        if isinstance(raw_scope, str):
            scopes = [scope for scope in raw_scope.split() if scope]

        client_id = claims.get("azp") or claims.get("client_id") or claims.get("sub")
        if not isinstance(client_id, str) or not client_id.strip():
            client_id = "keycloak-user"

        expires_at = claims.get("exp")
        if not isinstance(expires_at, int):
            expires_at = None

        return AccessToken(
            token=token,
            client_id=client_id,
            scopes=scopes,
            expires_at=expires_at,
            claims=claims,
        )


def _build_auth_provider() -> TokenVerifier | None:
    if not auth_enabled():
        return None
    return KeycloakTokenVerifier()


mcp = FastMCP("Booking System MCP", auth=_build_auth_provider())


def _csv_values(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


HTTP_MIDDLEWARE = [
    Middleware(
        CORSMiddleware,
        allow_origins=[CORS_ALLOW_ORIGIN],
        allow_methods=_csv_values(CORS_ALLOW_METHODS),
        allow_headers=_csv_values(CORS_ALLOW_HEADERS),
        expose_headers=_csv_values(CORS_EXPOSE_HEADERS),
    )
]


# Pydantic models for structured output
class FlightOut(BaseModel):
    flight_id: int
    origin: str
    destination: str
    departure_time: str
    arrival_time: str
    price: int
    seats_available: int
    class Config:
        from_attributes = True

class BookingIn(BaseModel):
    user_id: int
    name: str
    flight_id: int

class BookingOut(BaseModel):
    booking_id: int
    user_id: int
    flight_id: int
    status: str
    booking_time: str
    class Config:
        from_attributes = True

class UserIn(BaseModel):
    name: str
    email: str

class UserOut(BaseModel):
    user_id: int
    name: str
    email: str
    class Config:
        from_attributes = True

@mcp.tool()
def list_flights() -> list[FlightOut]:
    """List all available flights. 
    Returns a list of flights with origin, destination, times, price, and seats available."""
    db = SessionLocal()
    flights = db.query(Flight).all()
    db.close()
    return [FlightOut.from_orm(f) for f in flights]

@mcp.tool()
def book_flight(user_id: int, name: str, flight_id: int) -> BookingOut:
    """Book a seat on a specific flight for a user. 
    Requires user_id, name, and flight_id. 
    Decrements available seats if successful. 
    Returns booking details or raises an error if booking is not possible."""
    db = SessionLocal()
    flight = db.query(Flight).filter(Flight.flight_id == flight_id).first()
    if not flight:
        db.close()
        raise Exception(f"Flight not found. The specified flight_id {flight_id} does not exist in our system. Please check the flight_id or use the list_flights tool to see available flights.")
    if flight.seats_available < 1:
        db.close()
        raise Exception(f"No seats available on flight {flight_id}. The flight is fully booked. Please check other flights or try again later if seats become available.")
    user = db.query(User).filter(User.user_id == user_id, User.name == name).first()
    if not user:
        # Check if user exists but name doesn't match
        existing_user = db.query(User).filter(User.user_id == user_id).first()
        if existing_user:
            db.close()
            raise Exception(f"User ID {user_id} exists but the name '{name}' does not match the registered name '{existing_user.name}'. Please verify the user's name or use the correct name for this user ID.")
        else:
            db.close()
            raise Exception(f"User with ID {user_id} is not registered in our system. The user might need to register first using the register_user tool, or you may need to check if the user_id is correct.")
    flight.seats_available -= 1
    new_booking = Booking(
        user_id=user_id,
        flight_id=flight_id,
        status="booked",
        booking_time=datetime.utcnow().isoformat()
    )
    db.add(new_booking)
    db.commit()
    db.refresh(new_booking)
    db.commit()
    out = BookingOut.from_orm(new_booking)
    db.close()
    return out

@mcp.tool()
def get_bookings(user_id: int) -> list[BookingOut]:
    """Retrieve all bookings for a specific user by user_id. 
    Returns a list of booking details for the user."""
    db = SessionLocal()
    bookings = db.query(Booking).filter(Booking.user_id == user_id).all()
    db.close()
    return [BookingOut.from_orm(b) for b in bookings]

@mcp.tool()
def cancel_booking(booking_id: int) -> BookingOut:
    """Cancel an existing booking by its booking_id. 
    Increments available seats for the flight if successful. 
    Returns updated booking details or raises an error if already cancelled or not found."""
    db = SessionLocal()
    booking = db.query(Booking).filter(Booking.booking_id == booking_id).first()
    if not booking:
        db.close()
        raise Exception(f"Booking with ID {booking_id} not found. The booking may have been deleted or the booking_id may be incorrect. Please verify the booking_id or check if the booking exists.")
    if booking.status == "cancelled":
        db.close()
        raise Exception(f"Booking {booking_id} is already cancelled and cannot be cancelled again. The booking status is currently '{booking.status}'. If you need to make changes, please contact support.")
    flight = db.query(Flight).filter(Flight.flight_id == booking.flight_id).first()
    if flight:
        flight.seats_available += 1
    booking.status = "cancelled"
    db.commit()
    db.refresh(booking)
    out = BookingOut.from_orm(booking)
    db.close()
    return out

@mcp.tool()
def register_user(name: str, email: str) -> UserOut:
    """Register a new user with a name and unique email. 
    Returns the created user's details or raises an error if the email is already registered."""
    db = SessionLocal()
    existing = db.query(User).filter(User.email == email).first()
    if existing:
        db.close()
        raise Exception(f"Email '{email}' is already registered. A user with this email already exists in our system. If you're trying to access an existing account, use the get_user_id tool with the correct name and email to get the user_id.")
    new_user = User(name=name, email=email)
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    out = UserOut.from_orm(new_user)
    db.close()
    return out

@mcp.tool()
def get_user_id(name: str, email: str) -> UserOut:
    """Retrieve a user's information, including user_id, by providing both name and email. 
    Returns user details or raises an error if not found."""
    db = SessionLocal()
    user = db.query(User).filter(User.name == name, User.email == email).first()
    if not user:
        db.close()
        raise Exception(f"User not found with name '{name}' and email '{email}'. The user may not be registered in our system. Please check the spelling of both name and email, or register the user first using the register_user tool.")
    out = UserOut.from_orm(user)
    db.close()
    return out

@mcp.custom_route("/", methods=["GET"])
async def root_health_check(request: Request) -> PlainTextResponse:
    return _with_cors(PlainTextResponse("OK"))


@mcp.custom_route("/msp", methods=["GET", "POST", "OPTIONS"])
@mcp.custom_route("/msp/", methods=["GET", "POST", "OPTIONS"])
async def msp_compat_redirect(request: Request) -> RedirectResponse:
    query = request.url.query
    target = "/mcp"
    if query:
        target = f"{target}?{query}"
    return _with_cors(RedirectResponse(url=target, status_code=307))


def _issuer() -> str:
    return (os.getenv("OIDC_ISSUER") or "").strip()


def _auth_server_url() -> str:
    explicit = (
        os.getenv("OIDC_AUTHORIZATION_SERVER_URL")
        or os.getenv("OIDC_PUBLIC_ISSUER")
        or ""
    ).strip()
    if explicit:
        return explicit

    issuer = _issuer()
    if not issuer:
        return ""

    # Local compose fallback: metadata should point to host-reachable Keycloak URL.
    # Internal in-network issuer (keycloak:8080) breaks Inspector discovery on host.
    if "://keycloak:8080/" in issuer:
        return issuer.replace("://keycloak:8080/", "://localhost:8080/")
    return issuer


def _token_endpoint() -> str:
    auth_server = _auth_server_url()
    if not auth_server:
        return ""
    return f"{auth_server}/protocol/openid-connect/token"


def _authorization_endpoint() -> str:
    auth_server = _auth_server_url()
    if not auth_server:
        return ""
    return f"{auth_server}/protocol/openid-connect/auth"


def _jwks_uri() -> str:
    explicit = (os.getenv("OIDC_JWKS_URL") or "").strip()
    if explicit:
        return explicit
    auth_server = _auth_server_url()
    if not auth_server:
        return ""
    return f"{auth_server}/protocol/openid-connect/certs"


def _registration_endpoint() -> str:
    return f"{_mcp_base_url()}/oauth/register"


def _inspector_redirect_uris() -> list[str]:
    explicit_csv = (os.getenv("OIDC_INSPECTOR_REDIRECT_URIS") or "").strip()
    if explicit_csv:
        values = [item.strip() for item in explicit_csv.split(",") if item.strip()]
        # Preserve order while deduplicating.
        return list(dict.fromkeys(values))
    return [
        "http://localhost:6274/oauth/callback",
        "http://localhost:6274/oauth/callback/debug",
        "http://127.0.0.1:6274/oauth/callback",
        "http://127.0.0.1:6274/oauth/callback/debug",
    ]


def _inspector_client_id() -> str:
    return (
        os.getenv("OIDC_INSPECTOR_CLIENT_ID")
        or os.getenv("OIDC_CLIENT_ID")
        or "web-app-proxy"
    ).strip()


def _inspector_client_secret() -> str:
    return (
        os.getenv("OIDC_INSPECTOR_CLIENT_SECRET")
        or os.getenv("OIDC_CLIENT_SECRET")
        or "web-app-proxy-secret"
    ).strip()


@mcp.custom_route("/.well-known/openid-configuration", methods=["GET", "OPTIONS"])
@mcp.custom_route("/.well-known/openid-configuration/mcp", methods=["GET", "OPTIONS"])
@mcp.custom_route("/.well-known/openid-configuration/msp", methods=["GET", "OPTIONS"])
async def local_openid_configuration(request: Request) -> JSONResponse:
    if request.method.upper() == "OPTIONS":
        return _with_cors(PlainTextResponse("", status_code=204))
    issuer = _auth_server_url()
    return _with_cors(JSONResponse(
        {
            "issuer": issuer,
            "authorization_endpoint": _authorization_endpoint(),
            "token_endpoint": _token_endpoint(),
            "jwks_uri": _jwks_uri(),
        }
    ))


@mcp.custom_route("/.well-known/oauth-authorization-server", methods=["GET", "OPTIONS"])
@mcp.custom_route("/.well-known/oauth-authorization-server/mcp", methods=["GET", "OPTIONS"])
@mcp.custom_route("/.well-known/oauth-authorization-server/msp", methods=["GET", "OPTIONS"])
async def local_oauth_authorization_server(request: Request) -> JSONResponse:
    if request.method.upper() == "OPTIONS":
        return _with_cors(PlainTextResponse("", status_code=204))
    issuer = _auth_server_url()
    return _with_cors(JSONResponse(
        {
            "issuer": issuer,
            "authorization_endpoint": _authorization_endpoint(),
            "token_endpoint": _token_endpoint(),
            "jwks_uri": _jwks_uri(),
            "registration_endpoint": _registration_endpoint(),
            "response_types_supported": ["code"],
            "grant_types_supported": [
                "authorization_code",
                "refresh_token",
                "client_credentials",
                "password",
            ],
            "code_challenge_methods_supported": ["S256"],
            "token_endpoint_auth_methods_supported": [
                "client_secret_basic",
                "client_secret_post",
            ],
            "scopes_supported": ["openid", "profile", "email"],
        }
    ))


def _oauth_protected_resource_payload() -> dict[str, object]:
    issuer = _auth_server_url()
    mcp_base_url = _mcp_base_url()
    mcp_resource = f"{mcp_base_url}/mcp"
    payload: dict[str, object] = {
        "resource": mcp_resource,
        "scopes_supported": ["openid", "profile", "email"],
    }
    # Local Inspector compatibility:
    # advertise MCP base first so clients discover the MCP-hosted
    # oauth-authorization-server metadata (which includes registration_endpoint).
    authorization_servers: list[str] = [mcp_base_url]
    if issuer and issuer not in authorization_servers:
        authorization_servers.append(issuer)
    payload["authorization_servers"] = authorization_servers
    return payload


@mcp.custom_route("/.well-known/oauth-protected-resource", methods=["GET", "OPTIONS"])
@mcp.custom_route("/.well-known/oauth-protected-resource/mcp", methods=["GET", "OPTIONS"])
@mcp.custom_route("/.well-known/oauth-protected-resource/msp", methods=["GET", "OPTIONS"])
async def local_oauth_protected_resource(request: Request) -> JSONResponse:
    if request.method.upper() == "OPTIONS":
        return _with_cors(PlainTextResponse("", status_code=204))
    return _with_cors(JSONResponse(_oauth_protected_resource_payload()))


@mcp.custom_route("/oauth/register", methods=["POST", "OPTIONS"])
@mcp.custom_route("/oauth/register/mcp", methods=["POST", "OPTIONS"])
async def local_oauth_client_registration(request: Request) -> JSONResponse:
    if request.method.upper() == "OPTIONS":
        return _with_cors(PlainTextResponse("", status_code=204))

    request_payload: dict[str, object] = {}
    try:
        decoded = json.loads((await request.body()).decode("utf-8"))
        if isinstance(decoded, dict):
            request_payload = decoded
    except Exception:
        request_payload = {}

    requested_redirects = request_payload.get("redirect_uris")
    allowed_redirects = set(_inspector_redirect_uris())
    effective_redirects: list[str] = []
    if isinstance(requested_redirects, list):
        for item in requested_redirects:
            if isinstance(item, str) and item in allowed_redirects:
                effective_redirects.append(item)

    if not effective_redirects:
        effective_redirects = _inspector_redirect_uris()

    token_endpoint_auth_method = "client_secret_post"
    requested_auth_method = request_payload.get("token_endpoint_auth_method")
    if isinstance(requested_auth_method, str) and requested_auth_method.strip():
        token_endpoint_auth_method = requested_auth_method.strip()

    issued_at = int(datetime.utcnow().timestamp())
    registration_payload = {
        "client_id": _inspector_client_id(),
        "client_secret": _inspector_client_secret(),
        "client_id_issued_at": issued_at,
        "client_secret_expires_at": 0,
        "redirect_uris": effective_redirects,
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "token_endpoint_auth_method": token_endpoint_auth_method,
        "scope": "openid profile email",
        "application_type": "web",
    }
    return _with_cors(JSONResponse(registration_payload, status_code=201))

# Initialize DB and seed data on startup
validate_auth_configuration()
init_db()
seed()

if __name__ == "__main__":
    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",
        port=8084,
        path="/mcp",
        middleware=HTTP_MIDDLEWARE,
    )

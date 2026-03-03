import os
import json
import logging
from datetime import datetime
from fastapi import HTTPException
from fastmcp import FastMCP
from fastmcp.server.dependencies import get_http_headers, get_http_request
from pydantic import BaseModel
from starlette.requests import Request
from starlette.responses import JSONResponse, PlainTextResponse, RedirectResponse

from auth import require_oauth2_header, validate_auth_configuration
from db import SessionLocal, init_db
from models import Booking, Flight, User
from seed import seed

mcp = FastMCP("Booking System MCP")


def _resolve_middleware_call(args, kwargs):
    # FastMCP versions differ in middleware invocation style.
    call_next = kwargs.get("call_next") or kwargs.get("next")
    context = kwargs.get("context") or kwargs.get("ctx")

    if call_next is not None:
        return call_next, context

    if len(args) == 2:
        first, second = args
        if callable(first):
            return first, second
        if callable(second):
            return second, first

    raise RuntimeError("Unexpected middleware invocation signature")


async def _invoke_call_next(call_next, context):
    try:
        return await call_next(context)
    except TypeError:
        return await call_next()


async def _extract_rpc_request(request: Request) -> dict | None:
    if request.method.upper() != "POST":
        return None
    content_type = (request.headers.get("content-type") or "").lower()
    if "json" not in content_type:
        return None
    try:
        payload = json.loads((await request.body()).decode("utf-8"))
    except Exception:
        return None
    return payload if isinstance(payload, dict) else None


def _rpc_result_response(request_id, result: dict) -> JSONResponse:
    return JSONResponse(
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": result,
        }
    )


def _rpc_notification_ack() -> PlainTextResponse:
    # JSON-RPC notifications do not require a response body.
    return PlainTextResponse("", status_code=202)


def _negotiated_protocol_version(request: Request) -> str:
    header_value = (request.headers.get("mcp-protocol-version") or "").strip()
    return header_value or "2025-11-25"


def _tool_specs() -> list[dict]:
    return [
        {
            "name": "list_flights",
            "description": "List all available flights.",
            "inputSchema": {
                "type": "object",
                "properties": {},
                "additionalProperties": False,
            },
        },
        {
            "name": "book_flight",
            "description": "Book a seat on a specific flight for a user.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "user_id": {"type": "integer"},
                    "name": {"type": "string"},
                    "flight_id": {"type": "integer"},
                },
                "required": ["user_id", "name", "flight_id"],
                "additionalProperties": False,
            },
        },
        {
            "name": "get_bookings",
            "description": "Retrieve all bookings for a specific user.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "user_id": {"type": "integer"},
                },
                "required": ["user_id"],
                "additionalProperties": False,
            },
        },
        {
            "name": "cancel_booking",
            "description": "Cancel an existing booking by booking ID.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "booking_id": {"type": "integer"},
                },
                "required": ["booking_id"],
                "additionalProperties": False,
            },
        },
        {
            "name": "register_user",
            "description": "Register a new user with name and email.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "email": {"type": "string"},
                },
                "required": ["name", "email"],
                "additionalProperties": False,
            },
        },
        {
            "name": "get_user_id",
            "description": "Retrieve user details by name and email.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "email": {"type": "string"},
                },
                "required": ["name", "email"],
                "additionalProperties": False,
            },
        },
    ]


def _serialize_result(value):
    if isinstance(value, BaseModel):
        return value.model_dump()
    if isinstance(value, list):
        return [_serialize_result(item) for item in value]
    if isinstance(value, dict):
        return {k: _serialize_result(v) for k, v in value.items()}
    return value


def _call_tool_by_name(tool_name: str, arguments: dict):
    if tool_name == "list_flights":
        return list_flights()
    if tool_name == "book_flight":
        return book_flight(
            user_id=arguments["user_id"],
            name=arguments["name"],
            flight_id=arguments["flight_id"],
        )
    if tool_name == "get_bookings":
        return get_bookings(user_id=arguments["user_id"])
    if tool_name == "cancel_booking":
        return cancel_booking(booking_id=arguments["booking_id"])
    if tool_name == "register_user":
        return register_user(name=arguments["name"], email=arguments["email"])
    if tool_name == "get_user_id":
        return get_user_id(name=arguments["name"], email=arguments["email"])
    raise ValueError(f"Unknown tool: {tool_name}")


async def oauth2_middleware(*args, **kwargs):
    call_next, context = _resolve_middleware_call(args, kwargs)

    request = get_http_request()
    if request is None:
        return await _invoke_call_next(call_next, context)

    request_method = request.method.upper()
    request_path = request.url.path

    if request_method == "OPTIONS":
        return await _invoke_call_next(call_next, context)

    if request_method == "GET" and (
        request_path == "/"
        or request_path.startswith("/.well-known/")
    ):
        return await _invoke_call_next(call_next, context)

    # Backward-compatible alias route: /msp -> /mcp.
    if request_path in {"/msp", "/msp/"}:
        return await _invoke_call_next(call_next, context)

    headers = get_http_headers(include_all=False)
    authorization_header = headers.get("authorization")
    try:
        require_oauth2_header(authorization_header)
    except HTTPException as exc:
        return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})

    rpc_payload = await _extract_rpc_request(request)
    if rpc_payload:
        method = rpc_payload.get("method")
        request_id = rpc_payload.get("id")
        logging.warning("MCP request method=%s id=%s path=%s", method, request_id, request_path)

        if method == "initialize":
            return _rpc_result_response(
                request_id,
                {
                    "protocolVersion": _negotiated_protocol_version(request),
                    "capabilities": {
                        "tools": {"listChanged": False},
                        "resources": {"listChanged": False, "subscribe": False},
                        "prompts": {"listChanged": False},
                        "logging": {},
                    },
                    "serverInfo": {
                        "name": "Booking System MCP",
                        "version": "1.0.0",
                    },
                    "instructions": "Use tools/list to discover available booking tools.",
                },
            )

        # Compatibility shims for clients that probe optional methods
        # and fail hard on -32601.
        if method == "ping":
            return _rpc_result_response(request_id, {})
        if method == "notifications/initialized":
            return _rpc_notification_ack()
        if method == "notifications/cancelled":
            return _rpc_notification_ack()
        if method == "notifications/roots/list_changed":
            return _rpc_notification_ack()
        if method == "tools/list":
            return _rpc_result_response(request_id, {"tools": _tool_specs()})
        if method == "tools/call":
            params = rpc_payload.get("params") or {}
            tool_name = params.get("name")
            arguments = params.get("arguments") or {}
            try:
                tool_result = _call_tool_by_name(tool_name, arguments)
                serialized_result = _serialize_result(tool_result)
                return _rpc_result_response(
                    request_id,
                    {
                        "content": [
                            {
                                "type": "text",
                                "text": json.dumps(serialized_result),
                            }
                        ],
                        "structuredContent": serialized_result,
                        "isError": False,
                    },
                )
            except Exception as exc:
                return _rpc_result_response(
                    request_id,
                    {
                        "content": [
                            {
                                "type": "text",
                                "text": f"Tool call failed: {str(exc)}",
                            }
                        ],
                        "isError": True,
                    },
                )
        if method == "resources/list":
            return _rpc_result_response(request_id, {"resources": []})
        if method == "resources/templates/list":
            return _rpc_result_response(request_id, {"resourceTemplates": []})
        if method == "resources/subscribe":
            return _rpc_result_response(request_id, {})
        if method == "resources/unsubscribe":
            return _rpc_result_response(request_id, {})
        if method == "resources/read":
            return _rpc_result_response(request_id, {"contents": []})
        if method == "prompts/list":
            return _rpc_result_response(request_id, {"prompts": []})
        if method == "prompts/get":
            return _rpc_result_response(
                request_id,
                {"description": "", "messages": []},
            )
        if method == "completion/complete":
            return _rpc_result_response(
                request_id,
                {"completion": {"values": [], "total": 0, "hasMore": False}},
            )
        if method == "completions/complete":
            return _rpc_result_response(
                request_id,
                {"completion": {"values": [], "total": 0, "hasMore": False}},
            )
        if method == "logging/setLevel":
            return _rpc_result_response(request_id, {})
        if method == "roots/list":
            return _rpc_result_response(request_id, {"roots": []})

    return await _invoke_call_next(call_next, context)


def register_middleware(server: FastMCP, middleware_handler):
    middleware_attr = getattr(server, "middleware", None)
    if callable(middleware_attr):
        logging.warning("Registering MCP middleware using callable 'middleware'")
        middleware_attr(middleware_handler)
        return
    if isinstance(middleware_attr, list):
        logging.warning("Registering MCP middleware by appending to list 'middleware'")
        middleware_attr.append(middleware_handler)
        logging.warning("MCP middleware list size is now: %s", len(middleware_attr))
        return

    add_middleware = getattr(server, "add_middleware", None)
    if callable(add_middleware):
        logging.warning("Registering MCP middleware using callable 'add_middleware'")
        add_middleware(middleware_handler)
        return

    raise RuntimeError("FastMCP middleware registration is not supported by this version")


register_middleware(mcp, oauth2_middleware)


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
    return PlainTextResponse("OK")


@mcp.custom_route("/msp", methods=["GET", "POST", "OPTIONS"])
@mcp.custom_route("/msp/", methods=["GET", "POST", "OPTIONS"])
async def msp_compat_redirect(request: Request) -> RedirectResponse:
    query = request.url.query
    target = "/mcp"
    if query:
        target = f"{target}?{query}"
    return RedirectResponse(url=target, status_code=307)


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


@mcp.custom_route("/.well-known/openid-configuration", methods=["GET"])
async def local_openid_configuration(request: Request) -> JSONResponse:
    issuer = _auth_server_url()
    return JSONResponse(
        {
            "issuer": issuer,
            "authorization_endpoint": _authorization_endpoint(),
            "token_endpoint": _token_endpoint(),
            "jwks_uri": _jwks_uri(),
        }
    )


@mcp.custom_route("/.well-known/oauth-authorization-server", methods=["GET"])
async def local_oauth_authorization_server(request: Request) -> JSONResponse:
    issuer = _auth_server_url()
    return JSONResponse(
        {
            "issuer": issuer,
            "authorization_endpoint": _authorization_endpoint(),
            "token_endpoint": _token_endpoint(),
            "jwks_uri": _jwks_uri(),
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
    )


def _oauth_protected_resource_payload() -> dict[str, object]:
    issuer = _auth_server_url()
    mcp_base = "http://localhost:8084/mcp"
    payload: dict[str, object] = {
        "resource": mcp_base,
        "scopes_supported": ["openid", "profile", "email"],
    }
    if issuer:
        payload["authorization_servers"] = [issuer]
    return payload


@mcp.custom_route("/.well-known/oauth-protected-resource", methods=["GET"])
@mcp.custom_route("/.well-known/oauth-protected-resource/mcp", methods=["GET"])
@mcp.custom_route("/.well-known/oauth-protected-resource/msp", methods=["GET"])
async def local_oauth_protected_resource(request: Request) -> JSONResponse:
    return JSONResponse(_oauth_protected_resource_payload())

# Initialize DB and seed data on startup
validate_auth_configuration()
init_db()
seed()

if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8084, path="/mcp")

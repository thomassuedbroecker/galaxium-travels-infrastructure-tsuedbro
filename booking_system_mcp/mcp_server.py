import os
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

    return await _invoke_call_next(call_next, context)


def register_middleware(server: FastMCP, middleware_handler):
    middleware_attr = getattr(server, "middleware", None)
    if callable(middleware_attr):
        middleware_attr(middleware_handler)
        return
    if isinstance(middleware_attr, list):
        middleware_attr.append(middleware_handler)
        return

    add_middleware = getattr(server, "add_middleware", None)
    if callable(add_middleware):
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


def _token_endpoint() -> str:
    issuer = _issuer()
    if not issuer:
        return ""
    return f"{issuer}/protocol/openid-connect/token"


def _jwks_uri() -> str:
    explicit = (os.getenv("OIDC_JWKS_URL") or "").strip()
    if explicit:
        return explicit
    issuer = _issuer()
    if not issuer:
        return ""
    return f"{issuer}/protocol/openid-connect/certs"


@mcp.custom_route("/.well-known/openid-configuration", methods=["GET"])
async def local_openid_configuration(request: Request) -> JSONResponse:
    issuer = _issuer()
    return JSONResponse(
        {
            "issuer": issuer,
            "token_endpoint": _token_endpoint(),
            "jwks_uri": _jwks_uri(),
        }
    )


@mcp.custom_route("/.well-known/oauth-authorization-server", methods=["GET"])
async def local_oauth_authorization_server(request: Request) -> JSONResponse:
    issuer = _issuer()
    return JSONResponse(
        {
            "issuer": issuer,
            "token_endpoint": _token_endpoint(),
            "jwks_uri": _jwks_uri(),
        }
    )


def _oauth_protected_resource_payload() -> dict[str, object]:
    issuer = _issuer()
    mcp_base = "http://localhost:8084/mcp"
    payload: dict[str, object] = {
        "resource": mcp_base,
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

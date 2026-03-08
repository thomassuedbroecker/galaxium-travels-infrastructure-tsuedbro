from __future__ import annotations

import asyncio
import inspect
import json
from contextlib import AsyncExitStack
from dataclasses import asdict, dataclass, is_dataclass
from typing import Any

import httpx
from mcp import ClientSession

try:
    from mcp.client.streamable_http import (
        streamable_http_client as streamablehttp_client,
    )
except ImportError:
    try:
        from mcp.client.streamable_http import streamablehttp_client
    except ImportError:
        try:
            from mcp.client.streamablehttp_client import (
                streamable_http_client as streamablehttp_client,
            )
        except ImportError:
            from mcp.client.streamablehttp_client import streamablehttp_client


@dataclass
class BookingServiceError(Exception):
    error: str
    error_code: str
    details: str

    def __str__(self) -> str:
        return f"{self.error_code}: {self.details}"


ERROR_PATTERNS = (
    ("Flight not found", "Flight not found", "FLIGHT_NOT_FOUND"),
    ("No seats available", "No seats available", "NO_SEATS_AVAILABLE"),
    ("does not match the registered name", "Name mismatch", "NAME_MISMATCH"),
    ("User with ID", "User not found", "USER_NOT_FOUND"),
    ("User not found with name", "User not found", "USER_NOT_FOUND"),
    ("already registered", "Email already registered", "EMAIL_EXISTS"),
    ("Booking with ID", "Booking not found", "BOOKING_NOT_FOUND"),
    ("already cancelled", "Booking already cancelled", "ALREADY_CANCELLED"),
)


def _to_plain_data(value: Any) -> Any:
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, dict):
        return {key: _to_plain_data(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_to_plain_data(item) for item in value]
    if is_dataclass(value):
        return _to_plain_data(asdict(value))

    model_dump = getattr(value, "model_dump", None)
    if callable(model_dump):
        return _to_plain_data(model_dump())

    dict_method = getattr(value, "dict", None)
    if callable(dict_method):
        return _to_plain_data(dict_method())

    if hasattr(value, "__dict__"):
        return {
            key: _to_plain_data(item)
            for key, item in vars(value).items()
            if not key.startswith("_")
        }

    return str(value)


def _text_fragments(content: Any) -> list[str]:
    if not isinstance(content, list):
        return []

    fragments: list[str] = []
    for item in content:
        text = getattr(item, "text", None)
        if isinstance(text, str) and text.strip():
            fragments.append(text.strip())
    return fragments


def _map_error(detail: str) -> BookingServiceError | None:
    normalized = detail.strip()
    if not normalized:
        return None

    for pattern, error, error_code in ERROR_PATTERNS:
        if pattern in normalized:
            return BookingServiceError(
                error=error,
                error_code=error_code,
                details=normalized,
            )

    return None


def _find_booking_service_error(exc: BaseException) -> BookingServiceError | None:
    if isinstance(exc, BookingServiceError):
        return exc

    nested = getattr(exc, "exceptions", None)
    if nested:
        for item in nested:
            found = _find_booking_service_error(item)
            if found:
                return found

    return None


def _unwrap_result_container(value: Any) -> Any:
    if isinstance(value, dict) and set(value.keys()) == {"result"}:
        return value["result"]
    return value


class BookingMcpService:
    def __init__(self, server_url: str, timeout_seconds: float = 10.0) -> None:
        self.server_url = server_url
        self.timeout_seconds = timeout_seconds

    def list_flights(self, bearer_token: str | None) -> list[dict[str, Any]]:
        result = self._run_sync("list_flights", {}, bearer_token)
        return result if isinstance(result, list) else []

    def register_user(
        self,
        bearer_token: str | None,
        *,
        name: str,
        email: str,
    ) -> dict[str, Any]:
        result = self._run_sync(
            "register_user",
            {"name": name, "email": email},
            bearer_token,
        )
        return result if isinstance(result, dict) else {}

    def get_user_id(
        self,
        bearer_token: str | None,
        *,
        name: str,
        email: str,
    ) -> dict[str, Any]:
        result = self._run_sync(
            "get_user_id",
            {"name": name, "email": email},
            bearer_token,
        )
        return result if isinstance(result, dict) else {}

    def book_flight(
        self,
        bearer_token: str | None,
        *,
        user_id: int,
        name: str,
        flight_id: int,
    ) -> dict[str, Any]:
        result = self._run_sync(
            "book_flight",
            {
                "user_id": user_id,
                "name": name,
                "flight_id": flight_id,
            },
            bearer_token,
        )
        return result if isinstance(result, dict) else {}

    def get_bookings(
        self,
        bearer_token: str | None,
        user_id: int,
    ) -> list[dict[str, Any]]:
        result = self._run_sync("get_bookings", {"user_id": user_id}, bearer_token)
        return result if isinstance(result, list) else []

    def cancel_booking(
        self,
        bearer_token: str | None,
        booking_id: int,
    ) -> dict[str, Any]:
        result = self._run_sync("cancel_booking", {"booking_id": booking_id}, bearer_token)
        return result if isinstance(result, dict) else {}

    def _run_sync(
        self,
        tool_name: str,
        arguments: dict[str, Any],
        bearer_token: str | None,
    ) -> Any:
        try:
            return asyncio.run(self._call_tool(tool_name, arguments, bearer_token))
        except BaseException as exc:
            mapped_error = _find_booking_service_error(exc)
            if mapped_error:
                raise mapped_error from None
            raise

    async def _call_tool(
        self,
        tool_name: str,
        arguments: dict[str, Any],
        bearer_token: str | None,
    ) -> Any:
        headers = {"Accept": "application/json, text/event-stream"}
        if bearer_token:
            headers["Authorization"] = f"Bearer {bearer_token}"

        async with AsyncExitStack() as stack:
            stream_kwargs = {}
            signature = inspect.signature(streamablehttp_client)

            if "headers" in signature.parameters:
                stream_kwargs["headers"] = headers
            elif "http_client" in signature.parameters:
                http_client = await stack.enter_async_context(
                    httpx.AsyncClient(
                        headers=headers,
                        timeout=self.timeout_seconds,
                        follow_redirects=True,
                    )
                )
                stream_kwargs["http_client"] = http_client
            elif bearer_token:
                raise RuntimeError(
                    "Installed mcp package does not support authenticated streamable HTTP client headers."
                )

            transport = await stack.enter_async_context(
                streamablehttp_client(self.server_url, **stream_kwargs)
            )
            read_stream, write_stream, *_ = transport
            session = await stack.enter_async_context(
                ClientSession(read_stream, write_stream)
            )
            await session.initialize()

            try:
                result = await session.call_tool(tool_name, arguments=arguments)
            except Exception as exc:
                mapped_error = _map_error(str(exc))
                if mapped_error:
                    raise mapped_error from exc
                raise

            return self._normalize_tool_result(result)

    def _normalize_tool_result(self, result: Any) -> Any:
        if result is None:
            return None

        if isinstance(result, (list, str, int, float, bool)):
            return result
        if isinstance(result, dict):
            return _unwrap_result_container(result)

        if getattr(result, "isError", False):
            detail = self._extract_result_detail(result)
            mapped_error = _map_error(detail)
            if mapped_error:
                raise mapped_error
            raise BookingServiceError(
                error="MCP tool failed",
                error_code="MCP_TOOL_ERROR",
                details=detail or "The MCP tool returned an unknown error.",
            )

        structured = getattr(result, "structuredContent", None)
        if structured is not None:
            return _unwrap_result_container(_to_plain_data(structured))

        content = getattr(result, "content", None)
        text_fragments = _text_fragments(content)
        if len(text_fragments) == 1:
            try:
                return json.loads(text_fragments[0])
            except json.JSONDecodeError:
                return text_fragments[0]
        if text_fragments:
            return text_fragments

        return _unwrap_result_container(_to_plain_data(result))

    def _extract_result_detail(self, result: Any) -> str:
        structured = getattr(result, "structuredContent", None)
        if structured:
            return json.dumps(_to_plain_data(structured))

        text_fragments = _text_fragments(getattr(result, "content", None))
        if text_fragments:
            return " ".join(text_fragments)

        return str(_to_plain_data(result))

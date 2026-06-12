"""Darwin LDBWS REST client and response decoding — API_NOTES.md §§2-5.

Mirrors DarwinKit's models and error taxonomy. Every response field is
treated as optional (quirk 4); an empty board is a normal result, not an
error (quirk 1).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime

import requests

from .config import Config


class DarwinError(Exception):
    """Base for all API failures."""


class NetworkError(DarwinError):
    pass


class Unauthorized(DarwinError):
    def __str__(self) -> str:
        return (
            "API key rejected. Check the consumer key and that the "
            "Rail Data Marketplace subscription is active."
        )


class RateLimited(DarwinError):
    pass


class ServerError(DarwinError):
    pass


class UnexpectedResponse(DarwinError):
    pass


@dataclass(frozen=True)
class Departure:
    id: str
    destination: str
    destination_crs: str | None
    via: str | None
    scheduled: str  # "HH:MM"
    expected: str  # "On time" | "HH:MM" | "Delayed" | "Cancelled"
    platform: str | None
    operator_name: str
    is_cancelled: bool
    reason: str | None
    calling_point_crs_codes: tuple[str, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class DepartureBoard:
    station_name: str
    crs: str
    generated_at: datetime | None
    departures: tuple[Departure, ...]


def parse_generated_at(value: str | None) -> datetime | None:
    """Quirk 2: .NET 7-digit fractional seconds break strict ISO-8601
    parsers — strip the fraction before parsing."""
    if not value:
        return None
    cleaned = re.sub(r"\.\d+", "", value)
    try:
        return datetime.fromisoformat(cleaned)
    except ValueError:
        return None


def decode_board(payload: dict) -> DepartureBoard:
    if not isinstance(payload, dict):
        raise UnexpectedResponse(f"Expected JSON object, got {type(payload).__name__}")

    departures = []
    for service in payload.get("trainServices") or []:
        std = service.get("std")
        if not std:
            continue  # a service without a scheduled time can't be displayed
        destinations = service.get("destination") or [{}]
        destination = destinations[0]
        calling_points = tuple(
            point["crs"]
            for group in service.get("subsequentCallingPoints") or []
            for point in group.get("callingPoint") or []
            if point.get("crs")
        )
        cancelled = bool(service.get("isCancelled"))
        departures.append(
            Departure(
                id=service.get("serviceID") or f"{std}-{destination.get('crs', '???')}",
                destination=destination.get("locationName") or "Unknown",
                destination_crs=destination.get("crs"),
                via=destination.get("via"),
                scheduled=std,
                expected=service.get("etd") or ("Cancelled" if cancelled else "On time"),
                platform=service.get("platform"),
                operator_name=service.get("operator") or "",
                is_cancelled=cancelled,
                reason=service.get("cancelReason") or service.get("delayReason"),
                calling_point_crs_codes=calling_points,
            )
        )

    return DepartureBoard(
        station_name=payload.get("locationName") or payload.get("crs") or "Unknown",
        crs=payload.get("crs") or "",
        generated_at=parse_generated_at(payload.get("generatedAt")),
        departures=tuple(departures),
    )


class DarwinClient:
    def __init__(self, config: Config, session: requests.Session | None = None):
        self.config = config
        self.session = session or requests.Session()

    def fetch_departures(self, num_rows: int = 12, time_window_minutes: int = 120) -> DepartureBoard:
        url = f"{self.config.base_url}/GetDepBoardWithDetails/{self.config.crs}"
        try:
            response = self.session.get(
                url,
                params={"numRows": num_rows, "timeWindow": time_window_minutes},
                headers={"x-apikey": self.config.api_key, "Accept": "application/json"},
                timeout=15,
            )
        except requests.RequestException as exc:
            raise NetworkError(str(exc)) from exc

        if response.status_code in (401, 403):
            raise Unauthorized()
        if response.status_code == 429:
            raise RateLimited("Rate limited by the API")
        if response.status_code != 200:
            raise ServerError(f"Darwin API returned HTTP {response.status_code}")

        try:
            payload = response.json()
        except ValueError as exc:
            raise UnexpectedResponse(f"Response body is not JSON: {exc}") from exc
        return decode_board(payload)

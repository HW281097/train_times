"""TfL Unified API bus-arrivals client and decoding — TFL_API_NOTES.md.

Mirrors TfLKit's models and error taxonomy. The arrivals response is a
top-level JSON array (quirk 1); every field is optional; an empty array is a
normal result, not an error (quirk 2); predictions arrive unsorted and must be
sorted by timeToStation (quirk 3).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime

import requests

from .config import TflConfig, TflStop

BASE_URL = "https://api.tfl.gov.uk"

# Send a real User-Agent: edge/CDNs in front of these APIs commonly 403 the
# default "python-requests" UA. See TFL_API_NOTES.md §2.2.
USER_AGENT = "LeaBoard/1.0"


class TflError(Exception):
    """Base for all TfL API failures."""


class NetworkError(TflError):
    pass


class Unauthorized(TflError):
    def __str__(self) -> str:
        return "TfL API key rejected. Check the app_key in your config's tfl block."


class RateLimited(TflError):
    pass


class ServerError(TflError):
    pass


class UnexpectedResponse(TflError):
    pass


@dataclass(frozen=True)
class BusArrival:
    id: str
    line_name: str  # route number: "55", "N38"
    destination: str
    time_to_station: int  # seconds
    expected_arrival: datetime | None

    @property
    def minutes_until_arrival(self) -> int:
        """Whole minutes derived from time_to_station (floored)."""
        return max(0, self.time_to_station) // 60

    @property
    def is_due(self) -> bool:
        return self.minutes_until_arrival < 1


@dataclass(frozen=True)
class BusBoard:
    stop_id: str
    stop_name: str
    generated_at: datetime | None
    arrivals: tuple[BusArrival, ...]


def parse_expected_arrival(value: str | None) -> datetime | None:
    """Parse an ISO-8601 UTC instant like "2026-06-13T12:16:40Z". Strips any
    fractional seconds first (defensive — quirk 6) and normalises the trailing
    Z so datetime.fromisoformat copes on all supported versions."""
    if not value:
        return None
    cleaned = re.sub(r"\.\d+", "", value).replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(cleaned)
    except ValueError:
        return None


def decode_arrivals(
    payload: list,
    stop_id: str,
    fallback_stop_name: str,
    fetched_at: datetime,
) -> BusBoard:
    if not isinstance(payload, list):
        raise UnexpectedResponse(
            f"Expected a JSON array of predictions, got {type(payload).__name__}"
        )

    arrivals = []
    for prediction in payload:
        time_to_station = prediction.get("timeToStation") or 0
        line = (prediction.get("lineName") or prediction.get("lineId") or "").strip()
        if not line:
            continue  # a prediction with no route number can't be displayed
        destination = (prediction.get("destinationName") or "").strip() or (
            prediction.get("towards") or ""
        ).strip()
        arrivals.append(
            BusArrival(
                id=prediction.get("id") or f"{line}-{time_to_station}",
                line_name=line,
                destination=destination,
                time_to_station=time_to_station,
                expected_arrival=parse_expected_arrival(prediction.get("expectedArrival")),
            )
        )

    arrivals.sort(key=lambda arrival: arrival.time_to_station)

    if payload:
        resolved_id = payload[0].get("naptanId") or stop_id
        name = payload[0].get("stationName") or fallback_stop_name
    else:
        resolved_id, name = stop_id, fallback_stop_name

    return BusBoard(
        stop_id=resolved_id,
        stop_name=name,
        generated_at=fetched_at,
        arrivals=tuple(arrivals),
    )


class TflClient:
    def __init__(self, config: TflConfig, session: requests.Session | None = None):
        self.config = config
        self.session = session or requests.Session()

    def fetch_arrivals(self, stop: TflStop, fetched_at: datetime | None = None) -> BusBoard:
        fetched_at = fetched_at or datetime.now()
        url = f"{BASE_URL}/StopPoint/{stop.id}/Arrivals"
        params = {"app_key": self.config.app_key} if self.config.app_key else {}
        try:
            response = self.session.get(
                url,
                params=params,
                headers={"Accept": "application/json", "User-Agent": USER_AGENT},
                timeout=15,
            )
        except requests.RequestException as exc:
            raise NetworkError(str(exc)) from exc

        if response.status_code in (401, 403):
            raise Unauthorized()
        if response.status_code == 429:
            raise RateLimited("Rate limited by the TfL API")
        if response.status_code != 200:
            raise ServerError(f"TfL API returned HTTP {response.status_code}")

        try:
            payload = response.json()
        except ValueError as exc:
            raise UnexpectedResponse(f"Response body is not JSON: {exc}") from exc
        return decode_arrivals(payload, stop.id, stop.label, fetched_at)

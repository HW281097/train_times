"""Direction grouping (API_NOTES.md §6) and past-train filtering /
minutes-until (§8). Must stay rule-for-rule identical to DarwinKit's
LeaBridgeDirections.swift and DepartureFilter.swift.
"""

from __future__ import annotations

from datetime import datetime

from .darwin import Departure

STRATFORD_CRS = "SRA"

STRATFORD_TITLE = "Towards Stratford"
NORTHBOUND_TITLE = "Towards Tottenham Hale & beyond"


def direction(departure: Departure) -> str:
    """§6: destination or any calling point SRA -> 'stratford';
    everything else heads north -> 'tottenham_hale'."""
    if departure.destination_crs == STRATFORD_CRS:
        return "stratford"
    if STRATFORD_CRS in departure.calling_point_crs_codes:
        return "stratford"
    return "tottenham_hale"


def grouped(departures: list[Departure] | tuple[Departure, ...]) -> dict[str, list[Departure]]:
    groups: dict[str, list[Departure]] = {"stratford": [], "tottenham_hale": []}
    for departure in departures:
        groups[direction(departure)].append(departure)
    return groups


def minutes_of_day(value: str) -> int | None:
    parts = value.split(":")
    if len(parts) != 2:
        return None
    try:
        hours, minutes = int(parts[0]), int(parts[1])
    except ValueError:
        return None
    if not (0 <= hours < 24 and 0 <= minutes < 60):
        return None
    return hours * 60 + minutes


def effective_time(departure: Departure) -> str:
    """Revised etd when it parses as HH:MM, otherwise the scheduled time."""
    if minutes_of_day(departure.expected) is not None:
        return departure.expected
    return departure.scheduled


def has_no_estimate(departure: Departure) -> bool:
    """etd 'Delayed': running but Darwin has no estimate."""
    return not departure.is_cancelled and departure.expected.lower() == "delayed"


def minutes_until(departure: Departure, now: datetime) -> int | None:
    """Minutes from `now` to the effective departure, wrapped to -120...1319
    because board times carry no date (§5 quirk 7)."""
    target = minutes_of_day(effective_time(departure))
    if target is None:
        return None
    now_minutes = now.hour * 60 + now.minute
    diff = (target - now_minutes + 1440) % 1440
    if diff >= 1320:
        diff -= 1440
    return diff


def upcoming(departures, now: datetime) -> list[Departure]:
    """§8: drop departed services; keep 'Delayed' (no estimate) and anything
    unparseable; cancelled services drop once their scheduled time passes."""
    kept = []
    for departure in departures:
        if has_no_estimate(departure):
            kept.append(departure)
            continue
        minutes = minutes_until(departure, now)
        if minutes is None or minutes >= 0:
            kept.append(departure)
    return kept

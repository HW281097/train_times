"""Decoding tests against the SAME captured fixtures the Swift tests use,
proving both bus implementations parse identically. TFL_API_NOTES.md."""

import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from leaboard.tfl import (
    BusArrival,
    UnexpectedResponse,
    decode_arrivals,
    parse_expected_arrival,
)

FIXTURES = Path(__file__).resolve().parents[2] / "TfLKit/Tests/TfLKitTests/Fixtures"
FETCHED_AT = datetime(2026, 6, 13, 11, 53, 43)


def board(name, stop_id, label):
    payload = json.loads((FIXTURES / name).read_text())
    return decode_arrivals(payload, stop_id, label, FETCHED_AT)


def test_hackney_metadata():
    hackney = board("arrivals_towards_hackney.json", "490009131W", "Towards Hackney")
    assert hackney.stop_id == "490009131W"
    assert hackney.stop_name == "Emmanuel Parish Church"
    assert len(hackney.arrivals) == 6


def test_arrivals_sorted_soonest_first():
    # Raw capture order is 1377, 874, 201, 442, 636, 234 — unsorted (quirk 3).
    hackney = board("arrivals_towards_hackney.json", "490009131W", "Towards Hackney")
    assert [a.time_to_station for a in hackney.arrivals] == [201, 234, 442, 636, 874, 1377]


def test_soonest_arrival():
    arrival = board("arrivals_towards_hackney.json", "490009131W", "Towards Hackney").arrivals[0]
    assert arrival.id == "-1879565940"
    assert arrival.line_name == "55"
    assert arrival.destination == "Oxford Circus"
    assert arrival.time_to_station == 201
    assert arrival.minutes_until_arrival == 3  # 201 // 60
    assert not arrival.is_due
    # expectedArrival "2026-06-13T11:57:04Z"
    utc = arrival.expected_arrival.astimezone(timezone.utc)
    assert (utc.hour, utc.minute, utc.second) == (11, 57, 4)


def test_route_56_destination():
    hackney = board("arrivals_towards_hackney.json", "490009131W", "Towards Hackney")
    route56 = next(a for a in hackney.arrivals if a.line_name == "56")
    assert route56.destination == "Smithfield, St Bartholomew's Hospital"


def test_walthamstow_board():
    walthamstow = board("arrivals_towards_walthamstow.json", "490009131E", "Towards Walthamstow")
    assert walthamstow.stop_id == "490009131E"
    assert [a.time_to_station for a in walthamstow.arrivals] == [346, 1167, 1590, 1697]
    first = walthamstow.arrivals[0]
    assert first.line_name == "55"
    assert first.destination == "Walthamstow Central"
    assert first.minutes_until_arrival == 5  # 346 // 60


def test_empty_array_is_not_an_error():
    result = decode_arrivals([], "490009131W", "Towards Hackney", FETCHED_AT)
    assert result.stop_id == "490009131W"
    assert result.stop_name == "Towards Hackney"  # fell back to the label
    assert result.arrivals == ()


def test_destination_falls_back_to_towards():
    payload = [{
        "id": "p1", "lineName": "N55", "destinationName": "", "towards": "Walthamstow",
        "timeToStation": 40, "expectedArrival": "2026-06-13T12:00:40Z",
        "naptanId": "490009131E", "stationName": "Emmanuel Parish Church",
    }]
    arrival = decode_arrivals(payload, "490009131E", "Towards Walthamstow", FETCHED_AT).arrivals[0]
    assert arrival.line_name == "N55"
    assert arrival.destination == "Walthamstow"
    assert arrival.is_due  # 40 s -> 0 min


def test_non_array_payload_raises():
    with pytest.raises(UnexpectedResponse):
        decode_arrivals({"not": "an array"}, "x", "y", FETCHED_AT)


def test_expected_arrival_parsing():
    assert parse_expected_arrival("2026-06-13T12:16:40Z") is not None
    assert parse_expected_arrival("2026-06-13T12:16:40.4542597Z") is not None  # quirk 6
    assert parse_expected_arrival("not a date") is None
    assert parse_expected_arrival(None) is None


def test_minutes_floored_from_seconds():
    assert BusArrival("p", "55", "X", 59, None).minutes_until_arrival == 0
    assert BusArrival("p", "55", "X", 60, None).minutes_until_arrival == 1
    assert BusArrival("p", "55", "X", 201, None).minutes_until_arrival == 3

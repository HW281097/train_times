"""Decoding tests against the SAME captured fixture the Swift tests use,
proving both implementations parse identically."""

import json
from datetime import timezone
from pathlib import Path

import pytest

from leaboard.darwin import decode_board, parse_generated_at

FIXTURE = (
    Path(__file__).resolve().parents[2]
    / "DarwinKit/Tests/DarwinKitTests/Fixtures/sample_board.json"
)


@pytest.fixture(scope="module")
def board():
    return decode_board(json.loads(FIXTURE.read_text()))


def test_board_metadata(board):
    assert board.station_name == "Lea Bridge"
    assert board.crs == "LEB"
    assert len(board.departures) == 10
    # 2026-06-12T11:29:12.6568398+01:00 -> 10:29:12 UTC; the .NET 7-digit
    # fraction must not break parsing.
    utc = board.generated_at.astimezone(timezone.utc)
    assert (utc.hour, utc.minute, utc.second) == (10, 29, 12)


def test_first_service(board):
    departure = board.departures[0]
    assert departure.id == "4048751LEABDGE_"
    assert departure.destination == "Stratford (London)"
    assert departure.destination_crs == "SRA"
    assert departure.scheduled == "11:29"
    assert departure.expected == "On time"
    assert departure.platform == "1"
    assert departure.operator_name == "Greater Anglia"
    assert not departure.is_cancelled
    assert departure.calling_point_crs_codes == ("SRA",)


def test_northbound_calling_points(board):
    departure = board.departures[1]
    assert departure.destination_crs == "BIS"
    assert departure.calling_point_crs_codes[0] == "TOM"
    assert departure.calling_point_crs_codes[-1] == "BIS"
    assert len(departure.calling_point_crs_codes) == 7


def test_degraded_states_decode():
    payload = {
        "trainServices": [
            {"std": "11:23", "etd": "11:29", "isCancelled": False,
             "delayReason": "delayed by a train fault",
             "destination": [{"locationName": "Meridian Water", "crs": "MRW"}]},
            {"std": "11:38", "etd": "Cancelled", "isCancelled": True,
             "cancelReason": "shortage of train crew", "platform": None,
             "destination": [{"locationName": "Stratford (London)", "crs": "SRA"}]},
        ],
        "locationName": "Lea Bridge", "crs": "LEB",
    }
    board = decode_board(payload)
    delayed, cancelled = board.departures
    assert delayed.expected == "11:29" and delayed.reason == "delayed by a train fault"
    assert cancelled.is_cancelled and cancelled.platform is None
    assert cancelled.expected == "Cancelled"


def test_empty_board_is_not_an_error():
    board = decode_board({"locationName": "Lea Bridge", "crs": "LEB"})
    assert board.departures == ()


def test_generated_at_parsing():
    assert parse_generated_at("2026-06-12T11:29:12.6568398+01:00") is not None
    assert parse_generated_at("not a date") is None
    assert parse_generated_at(None) is None

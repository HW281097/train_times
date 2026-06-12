"""Direction grouping (§6) and past-train filtering (§8) — mirrors
DirectionTests.swift and DepartureFilterTests.swift."""

import json
from datetime import datetime
from pathlib import Path

from leaboard import logic
from leaboard.darwin import Departure, decode_board

FIXTURE = (
    Path(__file__).resolve().parents[2]
    / "DarwinKit/Tests/DarwinKitTests/Fixtures/sample_board.json"
)


def make(std="12:00", etd="On time", cancelled=False, dest_crs="MRW", calls=()):
    return Departure(
        id="t", destination="Test", destination_crs=dest_crs, via=None,
        scheduled=std, expected=etd, platform=None, operator_name="GA",
        is_cancelled=cancelled, reason=None, calling_point_crs_codes=tuple(calls),
    )


def at(hour, minute):
    return datetime(2026, 6, 12, hour, minute)


def test_grouping_matches_swift_expectations():
    board = decode_board(json.loads(FIXTURE.read_text()))
    groups = logic.grouped(board.departures)
    assert [d.scheduled for d in groups["stratford"]] == ["11:29", "11:44", "11:59", "12:14", "12:29"]
    assert [d.scheduled for d in groups["tottenham_hale"]] == ["11:32", "11:49", "12:02", "12:19", "12:32"]


def test_direction_rules():
    assert logic.direction(make(dest_crs="SRA", calls=["SRA"])) == "stratford"
    assert logic.direction(make(dest_crs="LST", calls=["SRA", "LST"])) == "stratford"
    assert logic.direction(make(dest_crs="BIS", calls=["TOM", "BIS"])) == "tottenham_hale"
    assert logic.direction(make(dest_crs=None)) == "tottenham_hale"


def test_departed_on_time_train_is_dropped():
    # The original bug: an "11:29, On time" train still showing at 11:31.
    assert logic.upcoming([make(std="11:29")], at(11, 31)) == []


def test_future_and_revised_trains_are_kept():
    assert len(logic.upcoming([make(std="11:34")], at(11, 31))) == 1
    running = make(std="11:29", etd="11:35")
    assert logic.effective_time(running) == "11:35"
    assert logic.minutes_until(running, at(11, 31)) == 4
    assert len(logic.upcoming([running], at(11, 31))) == 1
    assert logic.upcoming([make(std="11:20", etd="11:25")], at(11, 31)) == []


def test_delayed_without_estimate_always_kept():
    delayed = make(std="11:00", etd="Delayed")
    assert logic.has_no_estimate(delayed)
    assert len(logic.upcoming([delayed], at(11, 31))) == 1


def test_cancelled_kept_until_scheduled_time_passes():
    cancelled = make(std="11:38", etd="Cancelled", cancelled=True)
    assert len(logic.upcoming([cancelled], at(11, 31))) == 1
    assert logic.upcoming([cancelled], at(11, 40)) == []


def test_midnight_wraparound():
    after = make(std="00:05")
    assert logic.minutes_until(after, at(23, 58)) == 7
    assert len(logic.upcoming([after], at(23, 58))) == 1
    before = make(std="23:58")
    assert logic.minutes_until(before, at(0, 2)) == -4
    assert logic.upcoming([before], at(0, 2)) == []


def test_unparseable_times_are_kept():
    weird = make(std="??:??")
    assert logic.minutes_until(weird, at(11, 31)) is None
    assert len(logic.upcoming([weird], at(11, 31))) == 1

"""Canned departures for development without an API key (mirrors the Mac
app's demo mode). Times are generated relative to now."""

from __future__ import annotations

from datetime import datetime, timedelta

from .darwin import Departure, DepartureBoard
from .tfl import BusArrival, BusBoard


def _time(now: datetime, minutes: int) -> str:
    return (now + timedelta(minutes=minutes)).strftime("%H:%M")


def demo_board(now: datetime | None = None) -> DepartureBoard:
    now = now or datetime.now()
    departures = (
        Departure(
            id="demo-1", destination="Stratford (London)", destination_crs="SRA",
            via=None, scheduled=_time(now, 4), expected="On time", platform="1",
            operator_name="Greater Anglia", is_cancelled=False, reason=None,
            calling_point_crs_codes=("SRA",),
        ),
        Departure(
            id="demo-2", destination="Bishops Stortford", destination_crs="BIS",
            via=None, scheduled=_time(now, 7), expected="On time", platform="2",
            operator_name="Greater Anglia", is_cancelled=False, reason=None,
            calling_point_crs_codes=("TOM", "CHN", "BXB", "HWN", "BIS"),
        ),
        Departure(
            id="demo-3", destination="Meridian Water", destination_crs="MRW",
            via=None, scheduled=_time(now, 15), expected=_time(now, 21), platform="2",
            operator_name="Greater Anglia", is_cancelled=False,
            reason="This train has been delayed by a train fault",
            calling_point_crs_codes=("TOM", "NUM", "MRW"),
        ),
        Departure(
            id="demo-4", destination="Stratford (London)", destination_crs="SRA",
            via=None, scheduled=_time(now, 19), expected="Cancelled", platform=None,
            operator_name="Greater Anglia", is_cancelled=True,
            reason="This train has been cancelled because of a shortage of train crew",
            calling_point_crs_codes=(),
        ),
        Departure(
            id="demo-5", destination="Hertford East", destination_crs="HFE",
            via=None, scheduled=_time(now, 28), expected="Delayed", platform="2",
            operator_name="Greater Anglia", is_cancelled=False, reason=None,
            calling_point_crs_codes=("TOM", "WAR", "HFE"),
        ),
        Departure(
            id="demo-6", destination="Stratford (London)", destination_crs="SRA",
            via=None, scheduled=_time(now, 34), expected="On time", platform="1",
            operator_name="Greater Anglia", is_cancelled=False, reason=None,
            calling_point_crs_codes=("SRA",),
        ),
    )
    return DepartureBoard(
        station_name="Lea Bridge", crs="LEB", generated_at=now, departures=departures
    )


def demo_bus_boards(now: datetime | None = None) -> tuple[BusBoard, BusBoard]:
    """Canned bus arrivals for both directions (mirrors the Mac app's demo).
    Routes mix 2- and 3-character numbers to exercise column spacing."""
    now = now or datetime.now()

    def arrival(id: str, line: str, dest: str, minutes: int) -> BusArrival:
        return BusArrival(
            id=id,
            line_name=line,
            destination=dest,
            time_to_station=minutes * 60,
            expected_arrival=now + timedelta(minutes=minutes),
        )

    towards_hackney = BusBoard(
        stop_id="490009131W",
        stop_name="Emmanuel Parish Church",
        generated_at=now,
        arrivals=(
            arrival("demo-a1", "55", "Oxford Circus", 0),
            arrival("demo-a2", "56", "Smithfield, St Bartholomew's Hospital", 3),
            arrival("demo-a3", "N38", "Hackney Central", 8),
            arrival("demo-a4", "55", "Oxford Circus", 12),
        ),
    )
    towards_walthamstow = BusBoard(
        stop_id="490009131E",
        stop_name="Emmanuel Parish Church",
        generated_at=now,
        arrivals=(
            arrival("demo-b1", "55", "Walthamstow Central", 2),
            arrival("demo-b2", "N55", "Walthamstow Central", 6),
            arrival("demo-b3", "56", "Whipps Cross", 11),
            arrival("demo-b4", "55", "Walthamstow Central", 19),
        ),
    )
    return towards_hackney, towards_walthamstow

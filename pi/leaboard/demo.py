"""Canned departures for development without an API key (mirrors the Mac
app's demo mode). Times are generated relative to now."""

from __future__ import annotations

from datetime import datetime, timedelta

from .darwin import Departure, DepartureBoard


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

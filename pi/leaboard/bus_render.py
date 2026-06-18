"""Renders the bus board onto a 256x64 greyscale image for the SSD1322 OLED.

Same amber pixel style as the train board (render.py) — the panel is
monochrome, so there is no red theme here; the boards are told apart by the
header naming the board ("LEA BRIDGE BUSES"). TFL_API_NOTES.md §8.

Layout (y, font):
     0  header (5x7 bright): "LEA BRIDGE BUSES" + live clock
     9  section title (4x6 dim): TOWARDS HACKNEY
    17  arrival row (5x7)        } 3 rows — Hackney is the priority direction
    25  arrival row
    33  arrival row
    41  section title (4x6 dim): TOWARDS WALTHAMSTOW
    49  arrival row              } 1 row
    58  footer (4x6 dim): last-updated + error state

Rows per section are ROWS_PER_SECTION; each section reserves its full height
so the second always starts at the same y. Row columns (5px/char): route x=2
(2-3 chars), destination x=24 (the only column that truncates), minutes
right-aligned to x=254.
"""

from __future__ import annotations

from datetime import datetime

from PIL import Image, ImageDraw

from .render import BRIGHT, DIM, HEIGHT, WIDTH, _font, _wrapped_text, to_amber
from .tfl import BusArrival

BOARD_NAME = "LEA BRIDGE BUSES"
# Rows shown per section, by position: (Towards Hackney, Towards Walthamstow).
# Hackney gets more room as it's the priority direction.
ROWS_PER_SECTION = (3, 1)
DEST_MAX_CHARS = 32

__all__ = ["render_bus_board", "minutes_text", "to_amber", "WIDTH", "HEIGHT"]


def minutes_text(arrival: BusArrival, now: datetime, fetched_at: datetime | None = None) -> str:
    """Countdown for a row, ticking down between polls: the API's
    time_to_station snapshot minus the wall time elapsed since the fetch.
    Under a minute (or past) reads "Due"."""
    elapsed = (now - fetched_at).total_seconds() if fetched_at else 0
    minutes = int((arrival.time_to_station - elapsed) // 60)
    if minutes < 1:
        return "Due"
    if minutes > 99:
        return "99+"
    return f"{minutes} min"


def render_bus_board(
    sections,
    now: datetime,
    fetched_at: datetime | None = None,
    error: Exception | None = None,
) -> Image.Image:
    """`sections`: an iterable of (title, arrivals) pairs, where arrivals is a
    sequence of BusArrival or None when no data has been fetched yet."""
    sections = list(sections)
    image = Image.new("L", (WIDTH, HEIGHT), 0)
    draw = ImageDraw.Draw(image)
    body, small = _font("5x7"), _font("4x6")

    draw.text((2, 0), BOARD_NAME, font=body, fill=BRIGHT)
    clock = now.strftime("%H:%M:%S")
    draw.text((WIDTH - 2 - 5 * len(clock), 0), clock, font=body, fill=BRIGHT)

    if all(arrivals is None for _, arrivals in sections):
        message = str(error) if error else "Waiting for first update..."
        _wrapped_text(draw, message, body)
    else:
        y = 9
        for (title, arrivals), max_rows in zip(sections, ROWS_PER_SECTION):
            y = _section(draw, body, small, y, title, arrivals, now, fetched_at, max_rows)

    # Footer: freshness + error state (mirrors the train board).
    if error is not None and any(a is not None for _, a in sections):
        stamp = fetched_at.strftime("%H:%M") if fetched_at else "--:--"
        footer = f"! Update failed - showing data from {stamp}"
    elif fetched_at is not None:
        footer = f"Updated {fetched_at:%H:%M:%S}"
    else:
        footer = "Starting..."
    draw.text((2, 58), footer, font=small, fill=DIM)

    return image


def _section(draw, body, small, y: int, title: str, arrivals, now, fetched_at, max_rows: int) -> int:
    """Draw a titled section and return the y where the next one should start.
    Always reserves space for max_rows so later sections sit at a stable y."""
    draw.text((2, y), title.upper(), font=small, fill=DIM)
    rows = (arrivals or ())[:max_rows]
    if not rows:
        draw.text((24, y + 8), "No buses", font=body, fill=DIM)
    else:
        for index, arrival in enumerate(rows):
            _row(draw, body, y + 8 + index * 8, arrival, now, fetched_at)
    return y + 8 + max_rows * 8


def short_destination(name: str) -> str:
    """Trim a long TfL destination to its leading place name so it fits the
    narrow OLED, e.g. "Smithfield, St Bartholomew's Hospital" -> "Smithfield".
    Names without a comma are returned unchanged."""
    return name.split(",")[0].strip()


def _row(draw, body, y: int, arrival: BusArrival, now, fetched_at) -> None:
    # Route number, prominent. Fixed destination start (x=24) so 2- and
    # 3-character route numbers (55, N38) both align.
    draw.text((2, y), arrival.line_name, font=body, fill=BRIGHT)
    draw.text((24, y), short_destination(arrival.destination)[:DEST_MAX_CHARS], font=body, fill=BRIGHT)
    minutes = minutes_text(arrival, now, fetched_at)
    draw.text((254 - 5 * len(minutes), y), minutes, font=body, fill=BRIGHT)

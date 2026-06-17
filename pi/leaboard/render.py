"""Renders a DepartureBoard onto a 256x64 8-bit greyscale PIL image for the
SSD1322 OLED (the panel itself is 4-bit; luma quantises on output).

Layout (y, font):
     0  header (5x7 bright): station name + live clock
    10  section title (4x6 dim): TOWARDS STRATFORD
    18  departure row (5x7)
    26  departure row
    35  section title (4x6 dim): TOWARDS TOTTENHAM HALE & BEYOND
    43  departure row
    51  departure row
    58  footer (4x6 dim): last-updated + error state

Row columns (5px/char): time x=2, destination x=32 (24 chars max, the only
column that truncates), platform x=159, status x=174 ("Cancelled" is the
widest at 9 chars), minutes right-aligned to x=254.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from PIL import BdfFontFile, Image, ImageDraw, ImageFont

from . import logic
from .darwin import Departure, DepartureBoard

WIDTH, HEIGHT = 256, 64
BRIGHT = 255
DIM = 130

ROWS_PER_DIRECTION = 2

_FONT_DIR = Path(__file__).parent / "fonts"
_FONT_CACHE = Path.home() / ".cache" / "leaboard" / "fonts"
_fonts: dict[str, ImageFont.ImageFont] = {}


def _font(name: str) -> ImageFont.ImageFont:
    """Loads a vendored BDF font, compiling it to PIL's format on first use."""
    if name not in _fonts:
        _FONT_CACHE.mkdir(parents=True, exist_ok=True)
        pil_path = _FONT_CACHE / f"{name}.pil"
        if not pil_path.exists():
            with open(_FONT_DIR / f"{name}.bdf", "rb") as fp:
                BdfFontFile.BdfFontFile(fp).save(str(_FONT_CACHE / name))
        _fonts[name] = ImageFont.load(str(pil_path))
    return _fonts[name]


def status_text(departure: Departure) -> str:
    if departure.is_cancelled:
        return "Cancelled"
    if departure.expected.lower() == "on time":
        return "On time"
    if departure.expected.lower() == "delayed":
        return "Delayed"
    return f"Exp {departure.expected}"


def minutes_text(departure: Departure, now: datetime) -> str:
    if departure.is_cancelled or logic.has_no_estimate(departure):
        return "-"
    minutes = logic.minutes_until(departure, now)
    if minutes is None:
        return "-"
    if minutes <= 0:
        return "Due"
    if minutes > 99:
        return "99+"
    return f"{minutes}m"


def render_board(
    board: DepartureBoard | None,
    now: datetime,
    fetched_at: datetime | None = None,
    error: Exception | None = None,
) -> Image.Image:
    image = Image.new("L", (WIDTH, HEIGHT), 0)
    draw = ImageDraw.Draw(image)
    body, small = _font("5x7"), _font("4x6")

    # Header: station + board name (so the alternating screens are obviously
    # different) + live clock.
    station = (board.station_name if board else "Lea Bridge").upper()
    draw.text((2, 0), f"{station} TRAINS", font=body, fill=BRIGHT)
    clock = now.strftime("%H:%M:%S")
    draw.text((WIDTH - 2 - 5 * len(clock), 0), clock, font=body, fill=BRIGHT)

    if board is None:
        message = str(error) if error else "Waiting for first update..."
        _wrapped_text(draw, message, body)
    else:
        groups = logic.grouped(logic.upcoming(board.departures, now))
        _section(draw, body, small, 10, logic.STRATFORD_TITLE, groups["stratford"], now)
        _section(draw, body, small, 35, logic.NORTHBOUND_TITLE, groups["tottenham_hale"], now)

    # Footer: freshness + error state.
    if error is not None and board is not None:
        stamp = fetched_at.strftime("%H:%M") if fetched_at else "--:--"
        footer = f"! Update failed - showing data from {stamp}"
    elif fetched_at is not None:
        footer = f"Updated {fetched_at:%H:%M:%S}"
    else:
        footer = "Starting..."
    draw.text((2, 58), footer, font=small, fill=DIM)

    return image


def _section(draw, body, small, y: int, title: str, departures: list[Departure], now: datetime) -> None:
    draw.text((2, y), title.upper(), font=small, fill=DIM)
    rows = departures[:ROWS_PER_DIRECTION]
    if not rows:
        draw.text((32, y + 8), "No departures", font=body, fill=DIM)
        return
    for index, departure in enumerate(rows):
        _row(draw, body, y + 8 + index * 8, departure, now)


def _row(draw, body, y: int, departure: Departure, now: datetime) -> None:
    draw.text((2, y), departure.scheduled, font=body, fill=BRIGHT)

    destination = departure.destination[:24]
    draw.text((32, y), destination, font=body, fill=BRIGHT)
    if departure.is_cancelled:
        draw.line((32, y + 3, 32 + 5 * len(destination) - 2, y + 3), fill=BRIGHT)

    platform = f"P{departure.platform}" if departure.platform else "-"
    draw.text((159, y), platform, font=body, fill=DIM)

    draw.text((174, y), status_text(departure), font=body, fill=BRIGHT)

    minutes = minutes_text(departure, now)
    draw.text((254 - 5 * len(minutes), y), minutes, font=body, fill=BRIGHT)


def _wrapped_text(draw, message: str, font, x: int = 2, y: int = 18, chars: int = 50) -> None:
    words, lines, current = message.split(), [], ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if len(candidate) > chars and current:
            lines.append(current)
            current = word
        else:
            current = candidate
    lines.append(current)
    for index, line in enumerate(lines[:4]):
        draw.text((x, y + index * 9), line, font=font, fill=DIM)


def to_amber(image: Image.Image, scale: int = 4) -> Image.Image:
    """Upscaled amber-on-black RGB rendering — used for mockups and for
    previewing frames on a dev machine without the OLED attached."""
    scaled = image.resize((image.width * scale, image.height * scale), Image.NEAREST)
    red = scaled
    green = scaled.point(lambda v: v * 176 // 255)
    blue = scaled.point(lambda _: 0)
    return Image.merge("RGB", (red, green, blue))

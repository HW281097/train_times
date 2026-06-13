"""Bus renderer smoke tests: frames are the right size and contain lit pixels
in the expected regions, and the countdown text behaves."""

from datetime import datetime, timedelta

from leaboard.demo import demo_bus_boards
from leaboard.render import HEIGHT, WIDTH
from leaboard.tfl import BusArrival
from leaboard.bus_render import minutes_text, render_bus_board, to_amber

NOW = datetime(2026, 6, 13, 12, 30)
LABELS = ("Towards Hackney", "Towards Walthamstow")


def _sections(now=NOW):
    a, b = demo_bus_boards(now)
    return [(LABELS[0], a.arrivals), (LABELS[1], b.arrivals)]


def test_frame_dimensions_and_content():
    frame = render_bus_board(_sections(), NOW, fetched_at=NOW)
    assert frame.size == (WIDTH, HEIGHT)
    assert frame.mode == "L"
    assert frame.getbbox() is not None
    # Header row has bright pixels ("LEA BRIDGE BUSES" + clock).
    header = frame.crop((0, 0, WIDTH, 8))
    assert header.getextrema()[1] == 255


def test_no_data_frame_renders():
    frame = render_bus_board([(LABELS[0], None), (LABELS[1], None)], NOW,
                             error=RuntimeError("No bus stops configured"))
    assert frame.getbbox() is not None


def test_empty_sections_say_no_buses():
    frame = render_bus_board([(LABELS[0], ()), (LABELS[1], ())], NOW, fetched_at=NOW)
    assert frame.getbbox() is not None  # "No buses" text drawn


def test_minutes_text():
    # demo arrival "demo-a1" is 0 minutes out -> Due; "demo-a4" is 12 minutes.
    due = BusArrival("x", "55", "Oxford Circus", 30, None)
    soon = BusArrival("y", "55", "Oxford Circus", 12 * 60, None)
    assert minutes_text(due, NOW, fetched_at=NOW) == "Due"
    assert minutes_text(soon, NOW, fetched_at=NOW) == "12 min"
    # Ticks down as wall time elapses past the fetch.
    assert minutes_text(soon, NOW + timedelta(minutes=10), fetched_at=NOW) == "2 min"
    assert minutes_text(soon, NOW + timedelta(minutes=13), fetched_at=NOW) == "Due"


def test_amber_upscale():
    amber = to_amber(render_bus_board(_sections(), NOW, fetched_at=NOW), scale=4)
    assert amber.size == (WIDTH * 4, HEIGHT * 4)
    assert amber.mode == "RGB"

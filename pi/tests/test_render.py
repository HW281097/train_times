"""Renderer smoke tests: frames are the right size and actually contain
lit pixels in the expected regions."""

from datetime import datetime

from leaboard.demo import demo_board
from leaboard.render import WIDTH, HEIGHT, minutes_text, render_board, status_text, to_amber


NOW = datetime(2026, 6, 12, 11, 30)


def test_frame_dimensions_and_content():
    frame = render_board(demo_board(NOW), NOW, fetched_at=NOW)
    assert frame.size == (WIDTH, HEIGHT)
    assert frame.mode == "L"
    assert frame.getbbox() is not None  # something was drawn
    # Header row contains bright pixels (station name + clock).
    header = frame.crop((0, 0, WIDTH, 8))
    assert header.getextrema()[1] == 255


def test_error_frame_renders_without_board():
    frame = render_board(None, NOW, error=RuntimeError("No API key configured"))
    assert frame.getbbox() is not None


def test_status_and_minutes_text():
    board = demo_board(NOW)
    on_time, _, delayed_est, cancelled, no_estimate, _ = board.departures
    assert status_text(on_time) == "On time"
    assert status_text(delayed_est) == f"Exp {delayed_est.expected}"
    assert status_text(cancelled) == "Cancelled"
    assert status_text(no_estimate) == "Delayed"
    assert minutes_text(on_time, NOW) == "4m"
    assert minutes_text(cancelled, NOW) == "-"
    assert minutes_text(no_estimate, NOW) == "-"


def test_amber_upscale():
    frame = render_board(demo_board(NOW), NOW, fetched_at=NOW)
    amber = to_amber(frame, scale=4)
    assert amber.size == (WIDTH * 4, HEIGHT * 4)
    assert amber.mode == "RGB"

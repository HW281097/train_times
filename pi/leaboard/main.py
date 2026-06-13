"""LeaBoard run loop.

    python3 -m leaboard.main                 drive the SSD1322 OLED
    python3 -m leaboard.main --demo          canned data (no API key needed)
    python3 -m leaboard.main --png out.png   render both boards to PNGs and exit
    python3 -m leaboard.main --once          fetch once, print both boards, exit

The display AUTO-ALTERNATES between the train board (~15 s) and the bus board
(~10 s); durations come from the config `display` block (TFL_API_NOTES §9).
Each board keeps its own polling cadence — trains no faster than 60 s, buses
no faster than 30 s — backing off to 5 min when a board is empty (overnight)
and keeping the last good data on errors.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from datetime import datetime

from . import config, logic
from .bus_render import render_bus_board
from .config import ConfigError
from .darwin import DarwinClient, DarwinError
from .demo import demo_board, demo_bus_boards
from .render import render_board, to_amber
from .tfl import TflClient, TflError


def make_device():
    """SSD1322 over SPI via luma.oled. Imported lazily so dev machines
    without the hardware libraries can run --demo/--png/tests."""
    from luma.core.interface.serial import spi
    from luma.oled.device import ssd1322

    return ssd1322(spi(device=0, port=0))


class Poller:
    """Fetches one board on its own cadence, keeping the last good data on
    error and backing off when the board is empty."""

    def __init__(self, name, fetch, is_empty, errors, base_interval, empty_interval=300):
        self.name = name
        self.fetch = fetch
        self.is_empty = is_empty
        self.errors = errors
        self.base_interval = base_interval
        self.empty_interval = empty_interval
        self.data = None
        self.fetched_at = None
        self.error = None
        self.last_attempt = 0.0

    def poll_if_due(self, now_mono: float) -> None:
        if self.data is not None and self.is_empty(self.data):
            interval = self.empty_interval
        else:
            interval = self.base_interval
        if self.last_attempt and now_mono - self.last_attempt < interval:
            return
        self.last_attempt = now_mono or 1e-9
        try:
            self.data = self.fetch()
            self.fetched_at = datetime.now()
            self.error = None
        except self.errors as exc:
            self.error = exc  # keep last good self.data
            print(f"{self.name} fetch failed: {exc}", file=sys.stderr)


def _raise(exc):
    def fetch():
        raise exc

    return fetch


def _make_fetchers(args):
    """Returns (train_fetch, bus_fetch, labels, display)."""
    display = config.load_display()
    if args.demo:
        labels = ("Towards Hackney", "Towards Walthamstow")
        return demo_board, demo_bus_boards, labels, display

    darwin = DarwinClient(config.load())
    train_fetch = darwin.fetch_departures

    try:
        tfl_config = config.load_tfl()
        tfl = TflClient(tfl_config)
        labels = (tfl_config.direction_a.label, tfl_config.direction_b.label)

        def bus_fetch():
            return (
                tfl.fetch_arrivals(tfl_config.direction_a),
                tfl.fetch_arrivals(tfl_config.direction_b),
            )

    except ConfigError as exc:
        # No bus config: the bus screen shows the setup error but the cycle
        # (and the train board) keeps working.
        labels = ("Towards Hackney", "Towards Walthamstow")
        bus_fetch = _raise(exc)

    return train_fetch, bus_fetch, labels, display


def _bus_sections(boards, labels):
    if boards is None:
        return [(labels[0], None), (labels[1], None)]
    board_a, board_b = boards
    return [(labels[0], board_a.arrivals), (labels[1], board_b.arrivals)]


def _print_train_board(board, now) -> None:
    groups = logic.grouped(logic.upcoming(board.departures, now))
    print(f"\n{board.station_name} TRAINS  generated {board.generated_at}")
    for key, title in (("stratford", logic.STRATFORD_TITLE), ("tottenham_hale", logic.NORTHBOUND_TITLE)):
        print(f"\n  {title}")
        for dep in groups[key] or []:
            mins = logic.minutes_until(dep, now)
            print(f"    {dep.scheduled}  {dep.destination:<24} P{dep.platform or '-'}  {dep.expected:<10} {mins}m")


def _print_bus_boards(boards, labels, now) -> None:
    print("\nLEA BRIDGE BUSES")
    for (title, arrivals) in _bus_sections(boards, labels):
        print(f"\n  {title}")
        for arrival in (arrivals or ())[:3]:
            print(f"    {arrival.line_name:<3} {arrival.destination:<32} {arrival.minutes_until_arrival} min")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Lea Bridge OLED departure board")
    parser.add_argument("--demo", action="store_true", help="use canned data, no API key needed")
    parser.add_argument("--png", metavar="PATH", help="render both boards to PNGs and exit")
    parser.add_argument("--scale", type=int, default=4, help="PNG upscale factor (default 4)")
    parser.add_argument("--once", action="store_true", help="fetch once, print both boards, exit")
    args = parser.parse_args(argv)

    train_fetch, bus_fetch, labels, display = _make_fetchers(args)

    if args.png:
        now = datetime.now()
        stem, ext = os.path.splitext(args.png)
        ext = ext or ".png"
        train_path, bus_path = f"{stem}-trains{ext}", f"{stem}-buses{ext}"

        to_amber(render_board(train_fetch(), now, fetched_at=now), scale=args.scale).save(train_path)
        sections = _bus_sections(bus_fetch(), labels)
        to_amber(render_bus_board(sections, now, fetched_at=now), scale=args.scale).save(bus_path)
        print(f"Wrote {train_path} and {bus_path}")
        return 0

    if args.once:
        now = datetime.now()
        _print_train_board(train_fetch(), now)
        _print_bus_boards(bus_fetch(), labels, now)
        return 0

    trains = Poller(
        "trains", train_fetch,
        is_empty=lambda board: not board.departures,
        errors=DarwinError, base_interval=60,
    )
    buses = Poller(
        "buses", bus_fetch,
        is_empty=lambda boards: all(not b.arrivals for b in boards),
        errors=(TflError, ConfigError), base_interval=30,
    )

    def render_trains(now):
        return render_board(trains.data, now, trains.fetched_at, trains.error)

    def render_buses(now):
        return render_bus_board(_bus_sections(buses.data, labels), now, buses.fetched_at, buses.error)

    schedule = [
        (display.train_seconds, render_trains),
        (display.bus_seconds, render_buses),
    ]

    device = make_device()
    while True:
        for seconds, render in schedule:
            end = time.monotonic() + seconds
            while True:
                mono = time.monotonic()
                trains.poll_if_due(mono)
                buses.poll_if_due(mono)
                device.display(render(datetime.now()).convert(device.mode))
                if mono >= end:
                    break
                time.sleep(1)


if __name__ == "__main__":
    sys.exit(main())

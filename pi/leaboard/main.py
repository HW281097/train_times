"""LeaBoard run loop.

    python3 -m leaboard.main                 drive the SSD1322 OLED
    python3 -m leaboard.main --demo          canned data (no API key needed)
    python3 -m leaboard.main --png out.png   render one frame to a PNG and exit
    python3 -m leaboard.main --once          fetch once, print the board, exit

Polling: 60s normally, backing off to 5 min when the board is empty
(overnight), per API_NOTES.md §8. On errors the last good board stays up
with a warning in the footer.
"""

from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime

from . import config, logic
from .darwin import DarwinClient, DarwinError
from .demo import demo_board
from .render import render_board, to_amber


def make_device():
    """SSD1322 over SPI via luma.oled. Imported lazily so dev machines
    without the hardware libraries can run --demo/--png/tests."""
    from luma.core.interface.serial import spi
    from luma.oled.device import ssd1322

    return ssd1322(spi(device=0, port=0))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Lea Bridge OLED departure board")
    parser.add_argument("--demo", action="store_true", help="use canned data, no API key needed")
    parser.add_argument("--png", metavar="PATH", help="render one frame to PNG and exit")
    parser.add_argument("--scale", type=int, default=4, help="PNG upscale factor (default 4)")
    parser.add_argument("--once", action="store_true", help="fetch once, print text board, exit")
    args = parser.parse_args(argv)

    if args.demo:
        fetch = demo_board
    else:
        client = DarwinClient(config.load())
        fetch = client.fetch_departures

    if args.png:
        board = fetch()
        now = datetime.now()
        to_amber(render_board(board, now, fetched_at=now), scale=args.scale).save(args.png)
        print(f"Wrote {args.png}")
        return 0

    if args.once:
        board = fetch()
        now = datetime.now()
        groups = logic.grouped(logic.upcoming(board.departures, now))
        print(f"{board.station_name} ({board.crs})  generated {board.generated_at}")
        for key, title in (("stratford", logic.STRATFORD_TITLE), ("tottenham_hale", logic.NORTHBOUND_TITLE)):
            print(f"\n  {title}")
            for dep in groups[key] or []:
                mins = logic.minutes_until(dep, now)
                print(f"    {dep.scheduled}  {dep.destination:<24} P{dep.platform or '-'}  {dep.expected:<10} {mins}m")
        return 0

    device = make_device()
    board, fetched_at, error = None, None, None
    last_fetch = 0.0
    while True:
        interval = 300 if (board is not None and not board.departures) else 60
        if board is None or time.monotonic() - last_fetch >= interval:
            last_fetch = time.monotonic()
            try:
                board = fetch()
                fetched_at, error = datetime.now(), None
            except DarwinError as exc:
                error = exc
                print(f"fetch failed: {exc}", file=sys.stderr)
        frame = render_board(board, datetime.now(), fetched_at, error)
        device.display(frame.convert(device.mode))
        time.sleep(1)


if __name__ == "__main__":
    sys.exit(main())

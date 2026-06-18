# LeaBoard Pi — OLED departure board

The same live Lea Bridge departures as the Mac menu bar app, on a
**256×64 SSD1322 OLED** driven by a Raspberry Pi. By default the display
**auto-alternates** between a **train** screen (~15 s) and a **bus** screen
(~10 s); it can also show just one (see [Display modes](#display-modes)).
Implemented entirely from [`docs/API_NOTES.md`](../docs/API_NOTES.md)
(trains) and [`docs/TFL_API_NOTES.md`](../docs/TFL_API_NOTES.md) (buses), and
tested against the same captured API responses as the Swift code.

The panel is monochrome amber, so **both** boards use the amber pixel style
(no red theme here — that's the Mac bus panel); they're told apart by the
header naming the board ("LEA BRIDGE TRAINS" vs "LEA BRIDGE BUSES").

## Hardware

- Raspberry Pi (any 40-pin model; a Zero 2 W is plenty — no Pi 5 caveats,
  this is plain SPI)
- 3.12" / 2.8" **SSD1322 256×64 OLED module, SPI variant, yellow on black**.
  Before buying/wiring, check the listing says SSD1322 and "4SPI"/"4-wire
  SPI" — some modules ship jumpered for parallel mode and need a solder
  jumper moved (often labelled R5/R6 or BS0/BS1) to select SPI.
- 7 female-female jumper wires.

### Wiring (module → Pi header)

Module pin names vary by vendor; all the common aliases are listed.

| OLED pin (aliases)   | Pi pin | BCM |
|----------------------|--------|-----|
| VCC                  | 1 (3.3V) | — |
| GND                  | 6      | —   |
| D0 / SCLK / CLK / SCK| 23     | GPIO11 (SCLK) |
| D1 / MOSI / DIN / SDA| 19     | GPIO10 (MOSI) |
| CS                   | 24     | GPIO8 (CE0) |
| DC / D/C             | 18     | GPIO24 |
| RES / RST            | 22     | GPIO25 |

On 16-pin modules (e.g. the 3.12" boards with the full header), only these
7 pins are used — typically numbered GND=1, VCC=2, CLK=4, DIN=5, D/C=14,
RES=15, CS=16. Check your board's silkscreen.

These are luma.oled's defaults, so no pin configuration is needed in code.

## Setup

```sh
sudo raspi-config nonint do_spi 0        # enable SPI
sudo apt install -y python3-pip git
git clone https://github.com/HW281097/train_times.git
cd train_times/pi
pip3 install -r requirements.txt

mkdir -p ~/.config/leaboard
cp ../config.example.json ~/.config/leaboard/config.json
nano ~/.config/leaboard/config.json      # paste your RDM key + TfL app_key
```

Same config file, format and location as the Mac app (API_NOTES §7,
TFL_API_NOTES §7). The `tfl` block (app_key + the two `{id,label}` stops)
drives the bus screen. The optional `display` block sets the mode and the
cycle durations — see [Display modes](#display-modes) below. A missing `tfl`
block leaves the bus screen showing a setup message while trains keep working
(and in a trains-only mode you don't need a `tfl` block at all).

## Run

```sh
python3 -m leaboard.main --demo            # canned data, no API key needed
python3 -m leaboard.main --once            # fetch once, print the active board(s) as text
python3 -m leaboard.main --png board.png   # render the active board(s) to PNGs and exit
python3 -m leaboard.main                   # the real thing, on the OLED
python3 -m leaboard.main --mode buses      # force a mode for this run (see below)
```

`--png board.png` writes `board-trains.png` and/or `board-buses.png` depending
on the mode, so you can preview the layouts. `--png` and `--once` also work on
a Mac/PC (and combine with `--demo` / `--mode`) — handy for previewing without
the hardware.

## Display modes

The board runs in one of three modes, set by `display.mode` in `config.json`
(or overridden per run with `--mode`):

| Mode                   | Shows                                                |
|------------------------|------------------------------------------------------|
| `alternate` (default)  | both boards, cycling trains then buses               |
| `trains`               | the train board only                                 |
| `buses`                | the bus board only                                   |

```json
"display": { "mode": "alternate", "trainSeconds": 15, "busSeconds": 10 }
```

- `trainSeconds` / `busSeconds` — how long each board shows in `alternate`
  mode (seconds; default 15 / 10). Ignored in single-board modes.
- In a single-board mode the other API is **never contacted**, so a
  trains-only board needs no `tfl` block and a buses-only board needs no
  Darwin key.
- `--mode {alternate,trains,buses}` overrides the config for one run, e.g.
  `python3 -m leaboard.main --mode trains` to bring a new board up on trains
  first, or `--demo --mode buses --png out.png` to preview just the bus layout.

### Start on boot

```sh
sudo cp leaboard.service /etc/systemd/system/
sudo systemctl enable --now leaboard
journalctl -u leaboard -f                  # logs
```

(Adjust `WorkingDirectory`/`User` in the unit if your paths differ.)

## Tests

```sh
cd pi && python3 -m pytest
```

The decoding tests run against the *same* captured responses the Swift tests
use — `DarwinKit/Tests/DarwinKitTests/Fixtures/sample_board.json` (trains)
and `TfLKit/Tests/TfLKitTests/Fixtures/arrivals_towards_*.json` (buses) — and
the logic tests mirror the Swift direction/filtering suites case-for-case. If
a rule changes on either side, change it in both and in the matching notes
file (API_NOTES.md / TFL_API_NOTES.md).

## Display layout (256×64)

The display alternates between two boards. Train screen
(`leaboard/render.py`):

```
LEA BRIDGE TRAINS                            11:30:42
TOWARDS STRATFORD
11:34 Stratford (London)        P1  On time       4m
11:49 Stratford (London)        -   Cancelled      -
TOWARDS TOTTENHAM HALE & BEYOND
11:37 Bishops Stortford         P2  On time       7m
11:45 Meridian Water            P2  Exp 11:51    21m
Updated 11:30:42
```

Bus screen (`leaboard/bus_render.py`):

```
LEA BRIDGE BUSES                             11:30:42
TOWARDS HACKNEY
55  Oxford Circus                            Due
56  Smithfield                               3 min
55  Oxford Circus                            9 min
TOWARDS WALTHAMSTOW
55  Walthamstow Central                      2 min
Updated 11:30:42
```

The train board shows two rows per direction (`ROWS_PER_DIRECTION` in
`leaboard/render.py`); the bus board shows 3 rows for the priority Hackney
direction and 1 for Walthamstow (`ROWS_PER_SECTION` in
`leaboard/bus_render.py`), and trims long destinations to the leading place
name ("Smithfield"). Section titles come from the config `label`s. The OLED
is monochrome amber,
so the train board strikes cancellations through rather than colouring them
red, and section titles/footer use a dimmer grey level. The bus route column
is fixed-width so 2- and 3-character numbers (55, N38) align. Fonts are the
public-domain X11 `misc-fixed` 5×7 and 4×6 bitmaps, vendored in
`leaboard/fonts/`.

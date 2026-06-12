# LeaBoard Pi — OLED departure board

Phase 2 of LeaBoard: the same live Lea Bridge departures as the Mac menu
bar app, on a **256×64 SSD1322 OLED** driven by a Raspberry Pi. Implemented
entirely from [`docs/API_NOTES.md`](../docs/API_NOTES.md) and tested against
the same captured API response as the Swift code.

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
nano ~/.config/leaboard/config.json      # paste your RDM consumer key
```

Same config file format and location as the Mac app (API_NOTES §7).

## Run

```sh
python3 -m leaboard.main --demo            # canned data, no API key needed
python3 -m leaboard.main --once            # fetch once, print as text (no OLED needed)
python3 -m leaboard.main --png board.png   # render one frame to a PNG (no OLED needed)
python3 -m leaboard.main                   # the real thing, on the OLED
```

`--png` and `--once` also work on a Mac/PC — handy for previewing layout
changes without the hardware.

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

The decoding tests run against `DarwinKit/Tests/DarwinKitTests/Fixtures/sample_board.json`
— the *same* captured response the Swift tests use — and the logic tests
mirror DarwinKit's direction and filtering suites case-for-case. If a rule
changes on either side, change it in both and in API_NOTES.md.

## Display layout (256×64)

```
LEA BRIDGE                                   11:30:42
TOWARDS STRATFORD
11:34 Stratford (London)        P1  On time       4m
11:49 Stratford (London)        -   Cancelled      -
TOWARDS TOTTENHAM HALE & BEYOND
11:37 Bishops Stortford         P2  On time       7m
11:45 Meridian Water            P2  Exp 11:51    21m
Updated 11:30:42
```

Two departures per direction (`ROWS_PER_DIRECTION` in `leaboard/render.py`).
The OLED is monochrome amber, so cancellations are struck through rather
than coloured red, and section titles/footer use a dimmer grey level.
Fonts are the public-domain X11 `misc-fixed` 5×7 and 4×6 bitmaps, vendored
in `leaboard/fonts/`.

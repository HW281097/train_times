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

> **How it gets its data:** the Pi joins your home Wi-Fi and makes *outbound*
> HTTPS requests to the two transport APIs on a timer (trains ≤ every 60 s,
> buses ≤ every 30 s). It's client-only — no port forwarding, no static IP. If
> the network or an API hiccups it keeps the last good board with a footer
> warning and retries. It needs the correct clock (NTP, set automatically when
> online) because the "X min" countdowns use local time — so set the timezone
> to Europe/London (below).

## Hardware

- Raspberry Pi with a 40-pin header. A **Zero WH / Zero 2 W** is plenty — this
  is plain SPI, no Pi 5 caveats. Note the **OS bit-ness** differs by model
  (see [Flash the SD card](#1-flash-the-sd-card)): the original **Zero / Zero W
  / Zero WH are ARMv6 and need the 32-bit OS**; Zero 2 W / Pi 3/4/5 can run
  64-bit.
- 3.12" / 2.8" **SSD1322 256×64 OLED module, SPI variant, yellow on black**.
  Before buying/wiring, check the listing says SSD1322 and "4SPI"/"4-wire
  SPI" — some modules ship jumpered for parallel mode and need a solder
  jumper moved (often labelled R5/R6 or BS0/BS1) to select SPI.
- 7 female-female jumper wires.
- A 5 V micro-USB power supply (a phone charger is fine).

### Wiring (module → Pi header)

⚠️ **Wire with the Pi powered off.** Module pin names vary by vendor; the
common aliases are listed. Match the OLED pads to the Pi's **physical** pin
numbers:

| OLED pin (aliases)    | Pi physical pin | BCM |
|-----------------------|-----------------|-----|
| VCC                   | **1 (3.3 V)**   | —   |
| GND                   | 6               | —   |
| D0 / SCLK / CLK / SCK | 23              | GPIO11 (SCLK) |
| D1 / MOSI / DIN / SDA | 19              | GPIO10 (MOSI) |
| CS                    | 24              | GPIO8 (CE0) |
| DC / D/C              | 18              | GPIO24 |
| RES / RST             | 22              | GPIO25 |

On 16-pin modules (the 3.12" boards with the full header), only these 7 pins
are used — typically numbered GND=1, VCC=2, CLK=4, DIN=5, D/C=14, RES=15,
CS=16, but **trust your board's silkscreen labels over the numbers**.

Getting **VCC → pin 1 (3.3 V, never 5 V)** and **GND → pin 6** right is the
safety-critical part; mixing up the signal wires only gives a blank screen, no
damage. To locate Pi pins reliably: physical **pin 1 has a square solder pad**
(the rest are round), and running `pinout` on the Pi prints a labelled diagram
of the header. These are luma.oled's defaults, so no pin config is needed in
code.

---

## 1. Flash the SD card

Use **Raspberry Pi Imager** (raspberrypi.com/software):

1. **Choose OS** → "Raspberry Pi OS (other)" → **Raspberry Pi OS Lite**
   (headless, no desktop). **Pick 32-bit for a Zero / Zero W / Zero WH**
   (ARMv6 can't run 64-bit); 64-bit is fine on a Zero 2 W / Pi 3/4/5.
2. **Choose Storage** → your SD card.
3. **Next → Edit Settings** (the OS-customisation gear), and set:
   - **Hostname:** `leaboard`
   - **Enable SSH** (password is fine)
   - **Username / password:** e.g. `henry` / a memorable password
   - **Wireless LAN:** your Wi-Fi SSID + password, **country `GB`** (the radio
     stays off until the country is set)
   - **Locale → timezone:** `Europe/London`
4. **Save → Write**, then put the card in the Pi (gold contacts toward the
   board).

## 2. First boot & connect

The Zero has no power button — it boots when you apply power to the **outer
"PWR IN" micro-USB port** (the inner one is data). Wait ~1–2 min for the first
boot, then from your Mac:

```sh
ssh henry@leaboard.local           # your username/hostname; type "yes" on first connect
```

- A **"Connection reset by … port 22"** right after accepting the key means
  the Pi is **still finishing first boot** — wait a minute and retry.
- If `.local` won't resolve, find the Pi's IP in your router and
  `ssh henry@192.168.x.x`.
- **Know which machine you're on** from the prompt: `henry@Henrys-MacBook` is
  your **Mac**; `henry@leaboard` is the **Pi**. Run the steps below only once
  you see `@leaboard`.

## 3. Enable SPI (the OLED bus)

```sh
sudo raspi-config nonint do_spi 0
sudo reboot                        # drops your SSH session — reconnect after ~30 s
```
After reconnecting, confirm it appeared:
```sh
ls /dev/spidev*                    # expect: /dev/spidev0.0
```

## 4. Get the code

```sh
sudo apt update && sudo apt install -y git
git clone https://github.com/HW281097/train_times.git
cd train_times/pi
```

## 5. Install dependencies

Current Raspberry Pi OS (Bookworm) blocks system-wide `pip`, so use a
virtual environment. On a slow Zero W, let apt provide Pillow/requests so pip
doesn't spend 10–20 min compiling Pillow:

```sh
sudo apt install -y python3-venv python3-pil python3-requests libjpeg-dev zlib1g-dev
python3 -m venv --system-site-packages .venv
.venv/bin/pip install luma.oled
```
(On a faster Pi you can instead just do `.venv/bin/pip install -r requirements.txt`.)

## 6. Configure your keys

Same config file, format and location as the Mac app (`~/.config/leaboard/config.json`).
Easiest is to copy the one already working on your Mac — **run this on your Mac**:

```sh
ssh henry@leaboard.local 'mkdir -p ~/.config/leaboard'
scp ~/.config/leaboard/config.json henry@leaboard.local:~/.config/leaboard/config.json
```
Or create it on the Pi from the template and edit it:
```sh
mkdir -p ~/.config/leaboard
cp ../config.example.json ~/.config/leaboard/config.json
nano ~/.config/leaboard/config.json        # RDM key + TfL app_key + stops
```
The `tfl` block (app_key + the two `{id,label}` stops) drives the bus screen;
the `display` block sets the mode and cycle durations (see
[Display modes](#display-modes)). A missing `tfl` block leaves the bus screen
showing a setup message while trains keep working (and a trains-only mode
needs no `tfl` block at all).

## 7. Run & test

Use the venv's Python (`.venv/bin/python`), or `source .venv/bin/activate`
first and just use `python`.

```sh
.venv/bin/python -m leaboard.main --once   # fetch once, print both boards as text
.venv/bin/python -m leaboard.main          # drive the OLED for real (Ctrl-C to stop)
.venv/bin/python -m leaboard.main --demo   # canned data, no API key needed
.venv/bin/python -m leaboard.main --png board.png   # render active board(s) to PNGs
.venv/bin/python -m leaboard.main --mode buses      # force a mode for this run
```

`--once` is the quickest health check: if it prints live departures, your keys
and network are good (it does **not** touch the OLED — a blank panel there is
expected). `--png` writes `board-trains.png` / `board-buses.png` (scp them to
your Mac to view); both `--png` and `--once` also run on a Mac/PC with
`--demo`.

## Display modes

The board runs in one of three modes, set by `display.mode` in `config.json`
(or overridden per run / in the service with `--mode`):

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
- `--mode {alternate,trains,buses}` overrides the config for one run or in the
  service's `ExecStart` line.

## Run on boot (systemd service)

Make it start automatically and survive reboots/power cuts. The committed
`leaboard.service` defaults to user `pi`, the system Python, and
`/home/pi/...`; **edit those to match your username, venv, and path** or the
service fails with `status=200/CHDIR` (wrong WorkingDirectory) or a
`ModuleNotFoundError` (not using the venv). The reliable way is to write the
unit directly (substitute your username for `henry` throughout):

```sh
sudo tee /etc/systemd/system/leaboard.service > /dev/null <<'EOF'
[Unit]
Description=LeaBoard OLED departure board
After=network-online.target
Wants=network-online.target

[Service]
User=henry
WorkingDirectory=/home/henry/train_times/pi
ExecStart=/home/henry/train_times/pi/.venv/bin/python -m leaboard.main
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now leaboard
systemctl status leaboard          # expect: active (running)
```

For a single-mode board, append the flag to `ExecStart`, e.g.
`… -m leaboard.main --mode buses`. This unit lives in `/etc/systemd/system/`,
**separate from the repo**, so `git pull` never disturbs it — you only rewrite
it to change the mode or paths.

## Day-to-day operations

All on the Pi over SSH:

```sh
# status & logs
systemctl status leaboard
journalctl -u leaboard -f               # live logs (Ctrl-C to stop watching)
journalctl -u leaboard -n 50 --no-pager # recent logs (for troubleshooting)

# control
sudo systemctl stop leaboard            # turn the board off (last frame stays on the panel)
sudo systemctl start leaboard
sudo systemctl restart leaboard         # restart without code changes

# update to the latest code, then apply it
cd ~/train_times && git pull && sudo systemctl restart leaboard

# change the mode or durations
#   - mode:      rewrite the ExecStart (the tee block above) → daemon-reload → restart
#   - durations: edit ~/.config/leaboard/config.json (display block) → restart
sudo systemctl restart leaboard

# stop auto-start on boot entirely
sudo systemctl disable --now leaboard
```

Once the service is running, **don't also launch the board manually** — both
would fight over the screen. To test by hand: `sudo systemctl stop leaboard`,
run your command, then `sudo systemctl start leaboard`.

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| `ssh` says **"Connection reset … port 22"** | Pi still finishing first boot — wait a minute and retry. |
| **`--once` works but the OLED is blank** | Wiring/SPI. Check `ls /dev/spidev0.0` exists; re-seat **CLK→23, DIN→19, CS→24, DC→18, RES→22**; confirm **VCC→1, GND→6**. (A blank panel during `--once` itself is normal — it's text only.) |
| **Garbled / half image** | Usually **DC (pin 18)** or **RES (pin 22)** loose or swapped. |
| Service won't start, **`status=200/CHDIR`** | `WorkingDirectory`/`User` in the unit don't match your user/home — rewrite the unit (see [Run on boot](#run-on-boot-systemd-service)). |
| Service **`ModuleNotFoundError`** | `ExecStart` isn't the venv Python — point it at `…/.venv/bin/python`. |
| **Permission denied** on `/dev/spidev0.0` | `sudo usermod -aG spi,gpio <user>` then `sudo reboot`. |
| **`Unauthorized` / 403** from an API | The User-Agent fix is already in, so it's a bad key/`baseUrl` — re-copy `config.json` from the Mac. |
| **Wrong "min" countdowns / clock off** | `timedatectl` should show `Europe/London` and "System clock synchronized: yes" (needs internet at boot; the Pi has no battery clock). |
| **`pip` "externally managed" error** | Use the venv from step 5 (or `pip install --break-system-packages`). |

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
is monochrome amber, so the train board strikes cancellations through rather
than colouring them red, and section titles/footer use a dimmer grey level.
The bus route column is fixed-width so 2- and 3-character numbers (55, N38)
align. Fonts are the public-domain X11 `misc-fixed` 5×7 and 4×6 bitmaps,
vendored in `leaboard/fonts/`.

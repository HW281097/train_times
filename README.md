# LeaBoard

A macOS menu bar app showing live **train and bus departures** around
**Lea Bridge** in London. Two menu bar icons, two panels, one app:

- 🚆 **Trains** (amber, UK rail departure-board style) from National Rail's
  **Darwin** Live Departure Board REST API via the
  [Rail Data Marketplace](https://raildata.org.uk). Grouped by direction —
  **Toward Stratford** and **Toward Tottenham Hale & beyond** (Meridian Water,
  Hertford East, Bishops Stortford, ...). Auto-refreshes every 60 s while open,
  flags delays (orange) and cancellations (red, struck through).
- 🚌 **Buses** (TfL red, London-bus style) from the **TfL Unified API**
  StopPoint Arrivals endpoint, for the two Lea Bridge Road stops at Emmanuel
  Parish Church — **Towards Hackney** and **Towards Walthamstow** (routes 55,
  56, N38, N55). Auto-refreshes every 30 s while open. Each row shows the route
  number, destination and minutes until due ("4 min" / "Due").

## Project layout

```
LeaBoard.xcodeproj/      Xcode project for the menu bar app
LeaBoard/                App sources (SwiftUI, two MenuBarExtra scenes) — UI only
DarwinKit/               Swift package: ALL Darwin (train) API logic, zero UI
  Sources/DarwinKit/     Models, client, config, direction rules
  Tests/DarwinKitTests/  Decoding + direction tests with a captured API response
TfLKit/                  Swift package: ALL TfL (bus) API logic, zero UI
  Sources/TfLKit/        Models, client, config, decoding, errors
  Tests/TfLKitTests/     Decoding + config tests with captured API responses
pi/                      Raspberry Pi + SSD1322 OLED port (Python, both boards)
docs/API_NOTES.md        Language-neutral train (Darwin) API spec
docs/TFL_API_NOTES.md    Language-neutral bus (TfL) API spec
config.example.json      Template for your API config (shared by both apps)
```

The split matters: **everything the app knows about each API lives in its
Swift package and is documented in the matching `docs/*_NOTES.md`**, so the
Raspberry Pi port (below) is built without reading any Swift.

## Setup

### 1. Get API keys

**Trains (Darwin / Rail Data Marketplace):**

1. Register (free) at [raildata.org.uk](https://raildata.org.uk).
2. Subscribe to the **"Live Departure Board"** product (the public LDBWS
   feed from Rail Delivery Group / National Rail Enquiries — *not* the
   "Staff Version").
3. From the subscription's **Specification** page, copy your **Consumer
   key** (the consumer *secret* is not needed) and the exact endpoint URL
   shown there.

Details, sample response and API quirks: [`docs/API_NOTES.md`](docs/API_NOTES.md).

**Buses (TfL Unified API):**

1. Register (free) at the **TfL API portal**,
   [api-portal.tfl.gov.uk](https://api-portal.tfl.gov.uk/).
2. Open **Products** and subscribe to the free **"500 Requests per min"**
   plan (instant approval).
3. Open your **Profile** and copy the **Primary key** — that single value
   is your `app_key` (there is no `app_id` and no secret). The API also
   works keyless at a lower rate limit, so the bus panel runs without a key,
   just rate-limited.

The two bus stops are already resolved (Emmanuel Parish Church, NaPTAN
`490009131W` towards Hackney and `490009131E` towards Walthamstow); to use
different stops, resolve their flag codes per
[`docs/TFL_API_NOTES.md`](docs/TFL_API_NOTES.md) §2.1 and edit the config.

Details, sample response and API quirks: [`docs/TFL_API_NOTES.md`](docs/TFL_API_NOTES.md).

### 2. Configure the keys (never committed)

```sh
mkdir -p ~/.config/leaboard
cp config.example.json ~/.config/leaboard/config.json
# then edit ~/.config/leaboard/config.json
```

One shared config file holds both APIs:

```json
{
  "apiKey": "YOUR_DARWIN_CONSUMER_KEY",
  "baseUrl": "https://api1.raildata.org.uk/.../api/20220120",
  "crs": "LEB",
  "tfl": {
    "appKey": "YOUR_TFL_APP_KEY",
    "directionA": { "id": "490009131W", "label": "Towards Hackney" },
    "directionB": { "id": "490009131E", "label": "Towards Walthamstow" }
  }
}
```

- `apiKey` (trains) is required for the train panel; if the endpoint URL on
  your Specification page differs from the example `baseUrl` (the version
  segment can vary), use yours.
- The `tfl` block drives the bus panel: `appKey` (optional), and the two
  stops as `{ id, label }`. A missing `tfl` block just disables the bus
  panel — trains are unaffected.
- The `display` block (board mode + cycle durations) is only used by the
  Raspberry Pi board; the Mac app ignores it.

Alternatively set environment variables — useful in the Xcode scheme:
`DARWIN_API_KEY` (+ optional `DARWIN_BASE_URL` / `DARWIN_CRS`) for trains,
and `TFL_APP_KEY`, `TFL_STOP_A_ID` / `TFL_STOP_A_LABEL`, `TFL_STOP_B_ID` /
`TFL_STOP_B_LABEL` for buses.

`config.json` is in `.gitignore`; only `config.example.json` is committed.

### 3. Build & run

Open `LeaBoard.xcodeproj` in Xcode 15+ (macOS 14+), select the **LeaBoard**
scheme and run. The app appears only in the menu bar (no Dock icon).

**No API key yet?** Run in demo mode: set the environment variable
`LEABOARD_DEMO=1` in the scheme (Product → Scheme → Edit Scheme → Run →
Arguments → Environment Variables). **Both** panels render realistic canned
data — the train board including a delay and a cancellation, the bus board a
mix of 55/56/N38/N55 with a "Due" — each with a DEMO badge in the header.
Remove the variable once your keys arrive.

### 4. Tests

Each Swift package decodes its captured sample responses (and DarwinKit
also exercises the direction-grouping rules):

```sh
cd DarwinKit && swift test
cd TfLKit && swift test
```

(or run them in Xcode via the packages).

## The physical board (Raspberry Pi)

Lives in [`pi/`](pi/): the same train **and** bus departures on a 256×64
SSD1322 amber OLED driven by a Raspberry Pi, in Python. The display
auto-alternates between a train screen and a bus screen. It was implemented
entirely from [`docs/API_NOTES.md`](docs/API_NOTES.md) and
[`docs/TFL_API_NOTES.md`](docs/TFL_API_NOTES.md) — the language-neutral
records of each endpoint, auth, response schema, rules and quirks — and its
tests run against the same captured API responses as the Swift tests, so the
implementations are provably in sync. All three apps share the same
`config.json` format. When either side learns something new about an API,
update the matching notes file in the same change.

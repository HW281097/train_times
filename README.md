# LeaBoard

A macOS menu bar app showing live train departures from **Lea Bridge (LEB)**
in London, styled like a UK rail departure board (amber on black). Data comes
from National Rail's **Darwin** Live Departure Board REST API via the
[Rail Data Marketplace](https://raildata.org.uk).

Click the train icon in the menu bar to see the next departures, grouped by
direction:

- **Toward Stratford**
- **Toward Tottenham Hale & beyond** (Meridian Water, Hertford East,
  Bishops Stortford, ...)

The panel auto-refreshes every 60 seconds while open, has a manual refresh
button, and flags delays (orange) and cancellations (red, struck through).

## Project layout

```
LeaBoard.xcodeproj/      Xcode project for the menu bar app
LeaBoard/                App sources (SwiftUI, MenuBarExtra) — UI only
DarwinKit/               Swift package: ALL Darwin API logic, zero UI
  Sources/DarwinKit/     Models, client, config, direction rules
  Tests/DarwinKitTests/  Decoding + direction tests with a saved sample response
docs/API_NOTES.md        Language-neutral API spec (endpoint, auth, quirks)
config.example.json      Template for your API config
```

The split matters: **everything the app knows about Darwin lives in
DarwinKit and is documented in `docs/API_NOTES.md`**, so phase 2 (below) can
be built without reading any Swift.

## Setup

### 1. Get an API key

1. Register (free) at [raildata.org.uk](https://raildata.org.uk).
2. Subscribe to the **"Live Departure Board"** product (the public LDBWS
   feed from Rail Delivery Group / National Rail Enquiries — *not* the
   "Staff Version").
3. From the subscription's **Specification** page, copy your **Consumer
   key** (the consumer *secret* is not needed) and the exact endpoint URL
   shown there.

Details, sample response and API quirks: [`docs/API_NOTES.md`](docs/API_NOTES.md).

### 2. Configure the key (never committed)

```sh
mkdir -p ~/.config/leaboard
cp config.example.json ~/.config/leaboard/config.json
# then edit ~/.config/leaboard/config.json and paste your consumer key
```

If the endpoint URL on your Specification page differs from the `baseUrl`
in the example (the version segment can vary), use yours.

Alternatively set environment variables — useful in the Xcode scheme:
`DARWIN_API_KEY`, and optionally `DARWIN_BASE_URL` / `DARWIN_CRS`.

`config.json` is in `.gitignore`; only `config.example.json` is committed.

### 3. Build & run

Open `LeaBoard.xcodeproj` in Xcode 15+ (macOS 14+), select the **LeaBoard**
scheme and run. The app appears only in the menu bar (no Dock icon).

**No API key yet?** Run in demo mode: set the environment variable
`LEABOARD_DEMO=1` in the scheme (Product → Scheme → Edit Scheme → Run →
Arguments → Environment Variables). The board renders realistic canned
departures — including a delay and a cancellation — with a DEMO badge in
the header. Remove the variable once your key arrives.

### 4. Tests

DarwinKit's tests decode a saved sample API response and exercise the
direction-grouping rules:

```sh
cd DarwinKit && swift test
```

(or run them in Xcode via the package).

## Phase 2: the physical board 🚧

The plan is a Raspberry Pi driving an RGB LED dot-matrix display with the
same Lea Bridge departures, most likely in Python. That port should be
implemented **from [`docs/API_NOTES.md`](docs/API_NOTES.md) alone** — it
records the endpoint, auth, response schema, sample JSON, direction rules
and every quirk discovered so far, and both implementations share the same
`config.json` format. When the Swift side learns something new about the
API, update API_NOTES.md in the same change.

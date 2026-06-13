# TfL Unified API Notes (London bus arrivals)

This file is the **language-neutral spec** for talking to Transport for
London's Unified API for live **bus** arrivals at LeaBoard's two stops. The
Swift implementation lives in `TfLKit/`; the Raspberry Pi / Python
implementation (`pi/leaboard/tfl.py`) is written **from this document alone**,
without reading the Swift code. If either side learns a new quirk, record it
here. This is the bus counterpart to `API_NOTES.md` (trains / Darwin).

---

## 1. Registration & credentials

1. Go to the **TfL API Management portal**: <https://api-portal.tfl.gov.uk/>
   and create a free account.
2. Sign in, open **Products**, and subscribe to the free plan (the
   **"500 Requests per min"** product). Approval is instant.
3. Open your **Profile**. You get a **Primary key** and a **Secondary key** —
   either one is your **`app_key`**. That single value is the only credential
   the app needs.
   - There is **no** `app_id` any more. Older docs and libraries pass an
     `app_id` alongside the key; it is deprecated — send only `app_key`.
   - There is no secret and no OAuth, unlike the Darwin/RDM side.

> The API also works **without a key** at a lower rate limit, which is enough
> for resolving stop IDs and capturing a sample by hand. For the running app,
> use a key.

## 2. Endpoint

```
GET https://api.tfl.gov.uk/StopPoint/{naptanId}/Arrivals?app_key={app_key}
```

- `{naptanId}`: the stop's NaPTAN id, e.g. `490009131W`. **One physical bus
  stop = one NaPTAN id = one direction of travel.** LeaBoard polls two stops,
  one per direction (see §6).
- `app_key`: query parameter. Optional but recommended (rate limits, §2.2).
- The base host is `https://api.tfl.gov.uk` and never needs versioning in the
  path (contrast the Darwin base URL, which does).

The response is a **top-level JSON array** of prediction objects — there is no
envelope object. An **empty array `[]`** is a normal result (no buses due),
not an error.

### 2.1 Resolving a stop's NaPTAN id from the 5-digit flag code

The 5-digit number on the bus-stop flag is the **SMS / Countdown code**, not
the NaPTAN id the Arrivals endpoint needs. Resolve it once with search:

```
GET https://api.tfl.gov.uk/StopPoint/Search/{smsCode}?modes=bus
```

Each `matches[]` entry has `id` (the NaPTAN), `name`, `towards`,
`stopLetter`, and the `lines` serving it. Put the `id` and a human label in
config (§7) rather than hardcoding. LeaBoard's two stops were resolved this
way:

| Flag code | NaPTAN id     | name                     | towards     | stopLetter | lines              |
|-----------|---------------|--------------------------|-------------|------------|--------------------|
| 76079     | `490009131W`  | Emmanuel Parish Church   | Clapton     | LL         | 55, 56, N38, N55   |
| 77974     | `490009131E`  | Emmanuel Parish Church   | Bakers Arms | LF         | 55, 56, N38, N55   |

(Both are the same stop pair on Lea Bridge Road. The user-facing labels are
"Towards Hackney" and "Towards Walthamstow" respectively — chosen for clarity
over the API's own `towards` text.)

### 2.2 Auth, rate limits, status codes

```sh
curl "https://api.tfl.gov.uk/StopPoint/490009131W/Arrivals?app_key=$TFL_APP_KEY"
```

| Concern      | Detail                                                              |
|--------------|--------------------------------------------------------------------|
| Auth         | `app_key` query parameter; no header auth                          |
| User-Agent   | Send an explicit one (`User-Agent: LeaBoard/1.0`). Edge/CDNs in front of these transport APIs commonly return a generic HTML **403** to default client UAs like `python-requests/2.x` — which looks just like an auth failure. `curl`/`URLSession` UAs pass; the Python `requests` client must set one. |
| Rate limit   | ~500 requests/min with a key; ~50/min keyless. Two stops every 30 s is ~4/min — far below the limit. |

| Status   | Meaning / handling                                                   |
|----------|----------------------------------------------------------------------|
| 200      | Array of predictions (possibly empty — see §5)                       |
| 401, 403 | Key missing/wrong/invalid (only relevant once a key is in use)       |
| 429      | Rate limited — back off, keep last good board                        |
| 5xx      | TfL-side problem; retry next poll cycle                              |

## 3. Sample response

Two **real captured responses** (2026-06-13 11:53 UTC) are the test fixtures
for both ports:

- `TfLKit/Tests/TfLKitTests/Fixtures/arrivals_towards_hackney.json`
  — stop `490009131W` (towards Hackney), 6 predictions, routes 55 & 56.
- `TfLKit/Tests/TfLKitTests/Fixtures/arrivals_towards_walthamstow.json`
  — stop `490009131E` (towards Walthamstow), 4 predictions, route 55.

One prediction, abridged (fields LeaBoard ignores omitted):

```json
{
  "id": "-1879565940",
  "naptanId": "490009131W",
  "stationName": "Emmanuel Parish Church",
  "lineName": "55",
  "destinationName": "Oxford Circus",
  "towards": "Clapton",
  "timeToStation": 201,
  "expectedArrival": "2026-06-13T11:57:04Z",
  "timeToLive": "2026-06-13T11:57:34Z",
  "modeName": "bus",
  "timestamp": "2026-06-13T11:53:43.4542597Z"
}
```

## 4. Field semantics

Per prediction object:

| Field             | Type      | Notes                                                       |
|-------------------|-----------|-------------------------------------------------------------|
| `id`              | string    | Prediction id — use as row identity. Can be negative-looking (`"-1879565940"`); it's an opaque string, not a number. |
| `lineName`        | string    | The **route number** shown on the bus: `"55"`, `"56"`, `"N38"`, `"N55"`. This is the prominent field. (`lineId` is the lower-case form, e.g. `"n38"`.) |
| `destinationName` | string    | Where the bus terminates, e.g. `"Oxford Circus"`. **May be empty** — fall back to `towards`. |
| `towards`         | string    | Coarser direction text, e.g. `"Clapton"`. Fallback for an empty `destinationName`. |
| `timeToStation`   | int       | **Seconds** until arrival, as of `timestamp`. The basis for "minutes until". |
| `expectedArrival` | string    | ISO-8601 **UTC** instant, e.g. `"2026-06-13T11:57:04Z"`. Absolute arrival time; use it to recompute minutes live between polls. |
| `timeToLive`      | string    | ISO-8601 UTC; after this the prediction is stale (§5).      |
| `naptanId`        | string    | The stop this prediction is for.                            |
| `stationName`     | string    | Human stop name, e.g. `"Emmanuel Parish Church"`.           |
| `modeName`        | string    | `"bus"` here.                                               |

Fields both ports deliberately **ignore**: `$type`, `operationType`,
`vehicleId`, `lineId`, `platformName`, `direction`, `bearing`, `tripId`,
`baseVersion`, `destinationNaptanId`, `currentLocation`, `timing`.

Derived values used by both ports:

- **minutesUntilArrival** := `timeToStation` (seconds) integer-divided by 60
  (floor). 201 s → 3, 59 s → 0. For a live display that ticks between polls,
  recompute from `expectedArrival - now` instead (same flooring).
- **due** := minutesUntilArrival < 1 (i.e. under a minute, or already past).

## 5. Quirks (treat all fields as optional)

1. **Top-level array, not an object.** Decode the body as `[Prediction]`.
2. **Empty `[]` ≠ error.** No buses due (common overnight for the daytime
   routes) returns `200` with `[]`. Render "No buses", don't fail.
3. **Predictions are NOT sorted.** The array arrives in arbitrary order
   (the Hackney capture is `1377, 874, 201, 442, 636, 234` seconds). **Always
   sort by `timeToStation` ascending** before display.
4. **`destinationName` can be empty.** Fall back to `towards`. If both are
   empty, show the route alone.
5. **Ghost / stale predictions.** A prediction can momentarily carry a
   `timeToStation` of 0 or an `expectedArrival` already in the past (a bus
   that just arrived). Show it as "Due"; don't treat it as an error. TfL
   prunes predictions after their `timeToLive`, so they self-expire — no
   manual past-filtering is required (contrast the Darwin board, §8 there).
6. **`.NET timestamps.** `timestamp` carries 7-digit fractional seconds
   (`...11:53:43.4542597Z`), which strict ISO-8601 parsers reject. The fields
   we actually parse (`expectedArrival`, `timeToLive`) have **no** fraction,
   but strip any fraction defensively before parsing, exactly as the Darwin
   port does for `generatedAt`.
7. **Night buses.** `N38` / `N55` only appear in the predictions overnight;
   `55` / `56` only in the daytime. Nothing special to handle — they're just
   more `lineName` values. The display must cope with 2- and 3-character route
   numbers (pad the route column to 3 chars).
8. **All four routes serve both stops**, so each direction's board is a mix of
   route numbers; never assume one route per stop.

## 6. The two stops / directions

LeaBoard shows two sections, one per stop/direction, titled from the config
labels (§7):

- **Towards Hackney** — stop `490009131W` (flag 76079). Routes head west /
  towards central London (55 → Oxford Circus, 56 → St Bartholomew's Hospital).
- **Towards Walthamstow** — stop `490009131E` (flag 77974). Routes head east
  (55 → Walthamstow Central).

There is **no direction-detection logic** like the train board's calling-point
rules: each stop *is* a direction, so a section is simply "all arrivals at
that stop, soonest first". Each stop is one Arrivals request; a refresh makes
two requests.

## 7. Shared config format

Both apps read the same JSON config as the train side (`config.example.json`),
extended with a `tfl` block:

```json
{
  "apiKey": "YOUR_DARWIN_CONSUMER_KEY",
  "baseUrl": "https://api1.raildata.org.uk/.../api/20220120",
  "crs": "LEB",
  "tfl": {
    "appKey": "YOUR_TFL_APP_KEY",
    "directionA": { "id": "490009131W", "label": "Towards Hackney" },
    "directionB": { "id": "490009131E", "label": "Towards Walthamstow" }
  },
  "display": { "trainSeconds": 15, "busSeconds": 10 }
}
```

- `tfl.appKey` — optional; the API works keyless (rate-limited). Demo mode
  needs nothing.
- `tfl.directionA` / `directionB` — each `{ id, label }`. `id` is the NaPTAN;
  `label` is the section title shown on the board. IDs are never hardcoded.
- `display.trainSeconds` / `busSeconds` — Pi only: how long each board shows
  in the auto-alternation cycle (§9). Default 15 / 10. The Mac app ignores
  this block.

Lookup order (both platforms), mirroring the Darwin side:
1. Environment variables `TFL_APP_KEY`, `TFL_STOP_A_ID`, `TFL_STOP_A_LABEL`,
   `TFL_STOP_B_ID`, `TFL_STOP_B_LABEL` (handy for Xcode schemes / CI).
2. `~/.config/leaboard/config.json`
3. `./config.json` (current working directory).

A missing/invalid `tfl` block disables the bus feature gracefully (the Mac
bus panel shows a setup hint; trains are unaffected). The real `config.json`
is gitignored; never commit a key.

## 8. Display rules

- **Sections:** two, titled with the config labels (Towards Hackney / Towards
  Walthamstow). Mac shows 3–4 rows per section; the Pi OLED shows 2.
- **Row:** route number (prominent) · destination (secondary, truncates) ·
  minutes until due.
- **Minutes:** `"4 min"`; `"Due"` when under a minute (or already past).
- **Sort:** soonest first, by `timeToStation` (§5.3).
- **Empty:** "No buses" — a normal state.
- **Errors / rate limiting:** keep showing the last good board with its
  last-updated time, like the train side.
- **Theme:** the Mac bus panel is **TfL red (~#DC241F) on white/dark**,
  deliberately distinct from the amber train board. The Pi OLED is monochrome
  amber for **both** boards (no red); the boards are distinguished by the
  header naming the board ("LEA BRIDGE BUSES" vs "LEA BRIDGE TRAINS").

## 9. Polling etiquette & board alternation (Pi)

- The Mac bus panel polls every **30 s while the panel is open** only.
- The Pi auto-alternates: train board ~15 s, bus board ~10 s (configurable,
  §7). Each board keeps its own poll cadence: **buses no faster than 30 s,
  trains no faster than 60 s.** Back off when a board is empty overnight
  (5 min), and keep the last good board on errors rather than blanking.

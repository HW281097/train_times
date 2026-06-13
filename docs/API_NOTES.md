# Darwin Live Departure Board API Notes

This file is the **language-neutral spec** for talking to National Rail's
Darwin Live Departure Board (LDBWS) REST API. The Swift implementation lives
in `DarwinKit/`; the phase-2 Raspberry Pi / Python implementation should be
written **from this document alone**, without reading the Swift code.
If the Swift code learns a new quirk, record it here.

---

## 1. Registration & credentials

1. Create a free account at <https://raildata.org.uk> (Rail Data Marketplace).
2. In the product catalogue, search for **"Live Departure Board"** — the
   public LDBWS product published by **Rail Delivery Group / National Rail
   Enquiries**. Subscribe (free, approval is usually instant).
   - Do **not** confuse it with *"Live Arrival and Departure Boards — Staff
     Version"*, a richer feed with a different schema. This project uses the
     public one.
3. After subscribing, open the product's **Specification** tab in your RDM
   dashboard. You get two values:
   - **Consumer key** — this is the API key. The only credential this API
     needs.
   - **Consumer secret** — *not used* by this API (it exists for RDM's
     OAuth-style products). Keep it safe but ignore it.

> The old `lite.realtime.nationalrail.co.uk` SOAP service (OpenLDBWS) and its
> tokens are legacy; new registrations go through RDM and use this REST API.

## 2. Endpoint

```
GET {baseUrl}/GetDepBoardWithDetails/{crs}?numRows=12&timeWindow=120
```

- `baseUrl` (as of June 2026):
  `https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api/20220120`
  - **Quirk:** the `1010-live-departure-board-dep1_2` segment encodes the
    product *version* you subscribed to and may differ (e.g. an older
    subscription used `...-dep`). Always copy the exact URL from your
    subscription's Specification page. That's why `baseUrl` lives in the
    config file rather than in code.
- `{crs}`: 3-letter station code, upper case. **Lea Bridge = `LEB`**.
- Other operations exist on the same base (`GetDepartureBoard`,
  `GetArrivalBoard`, `GetArrBoardWithDetails`, `GetServiceDetails`, ...).
  We use `GetDepBoardWithDetails` because the *WithDetails* variant includes
  each train's calling points, which direction detection needs (§6).

### Query parameters

| Param        | Range          | Meaning                                   |
|--------------|----------------|-------------------------------------------|
| `numRows`    | 1–150          | Max services returned                      |
| `timeWindow` | up to 120 (min)| How far ahead to look                      |
| `timeOffset` | −120…119 (min) | Shift the window's start (we don't use it) |
| `filterCrs` / `filterType` | — | Only trains calling at another station (we don't use it; direction logic in §6 replaces it) |

### Headers

```
x-apikey: <consumer key>
Accept: application/json   (cosmetic; the API returns JSON regardless)
User-Agent: LeaBoard/1.0   (REQUIRED — see quirk below)
```

**Quirk — User-Agent:** the API sits behind an edge/CDN that returns a
generic HTML **403 Forbidden** (not the gateway's usual JSON auth error) to
requests with a default client User-Agent such as `python-requests/2.x`.
Always send an explicit User-Agent. `curl` and Swift's `URLSession` use UAs
that happen to pass, which is why the Mac app worked before the Pi port did;
the Python `requests` client must set one. A valid key with a blocked UA looks
exactly like an auth failure — check the response body (HTML 403 = edge block;
JSON = gateway).

No other auth. Example:

```sh
curl -H "x-apikey: $DARWIN_API_KEY" \
  "https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api/20220120/GetDepBoardWithDetails/LEB?numRows=12&timeWindow=120"
```

### HTTP status codes

| Status   | Meaning / handling                                            |
|----------|---------------------------------------------------------------|
| 200      | Board returned (possibly with **no** `trainServices` — see §5)|
| 401, 403 | Key missing/wrong/expired, or subscription not active         |
| 429      | Rate limited — back off (free tier allows ~5 million requests/month; a 60 s poll is nowhere near it) |
| 5xx      | Darwin-side problem; retry next poll cycle                    |

## 3. Sample response

A **real captured response** (GetDepBoardWithDetails/LEB, 2026-06-12
11:29 BST, 10 services, pretty-printed but otherwise verbatim) is kept at
[`DarwinKit/Tests/DarwinKitTests/Fixtures/sample_board.json`](../DarwinKit/Tests/DarwinKitTests/Fixtures/sample_board.json)
and is the fixture for the Swift decoding tests. The Python port should use
the same file for its tests. Abridged shape:

```json
{
  "trainServices": [
    {
      "subsequentCallingPoints": [
        { "callingPoint": [
            { "locationName": "Tottenham Hale", "crs": "TOM", "st": "11:39", "et": "On time",
              "isCancelled": false, "length": 0, "detachFront": false,
              "affectedByDiversion": false, "rerouteDelay": 0 }
          ],
          "serviceType": "train", "serviceChangeRequired": false, "assocIsCancelled": false }
      ],
      "futureCancellation": false,
      "futureDelay": false,
      "origin":      [ { "locationName": "Stratford (London)", "crs": "SRA", "assocIsCancelled": false } ],
      "destination": [ { "locationName": "Bishops Stortford", "crs": "BIS", "assocIsCancelled": false } ],
      "std": "11:32",
      "etd": "On time",
      "platform": "2",
      "operator": "Greater Anglia",
      "operatorCode": "LE",
      "isCircularRoute": false,
      "isCancelled": false,
      "filterLocationCancelled": false,
      "serviceType": "train",
      "length": 0,
      "detachFront": false,
      "isReverseFormation": false,
      "serviceID": "4031123LEABDGE_"
    }
  ],
  "Xmlns": { "Count": 8 },
  "generatedAt": "2026-06-12T11:29:12.6568398+01:00",
  "locationName": "Lea Bridge",
  "crs": "LEB",
  "filterType": "to",
  "platformAvailable": true,
  "areServicesAvailable": true
}
```

The capture contained only on-time services; the degraded shapes (revised
`etd` time, `"Delayed"`, `"Cancelled"` + `cancelReason`/`delayReason`) are
documented in §4 and exercised by inline JSON in the decoding tests. If a
live response is ever seen disagreeing with those shapes, update this file
and the tests together.

## 4. Field semantics

Per service in `trainServices`:

| Field      | Type      | Notes                                                       |
|------------|-----------|-------------------------------------------------------------|
| `serviceID`| string    | Unique per service per day — use as row identity            |
| `std`      | `"HH:mm"` | Scheduled departure                                          |
| `etd`      | string    | One of: `"On time"`, a revised time `"HH:mm"`, `"Delayed"` (running, no estimate), `"Cancelled"` |
| `platform` | string?   | Often missing/null (always render a placeholder)            |
| `operator` | string    | e.g. `"Greater Anglia"` (`operatorCode` is the 2-letter TOC) |
| `isCancelled` | bool?  | Authoritative cancellation flag; may be absent when false   |
| `cancelReason`, `delayReason` | string? | Human-readable, only when relevant        |
| `destination` | array  | Array of locations (`locationName`, `crs`, optional `via`). Almost always one entry; >1 only for trains that divide. Use the first. |
| `subsequentCallingPoints` | array | Array of *groups*, each `{ "callingPoint": [...] }`. One group normally; extra groups only for dividing trains. Each calling point: `locationName`, `crs`, `st`, `et` plus ignorable flags. |

Fields both ports deliberately **ignore**: `serviceType`, `length` (0 =
unknown, not a 0-car train), `detachFront`, `isReverseFormation`,
`isCircularRoute`, `futureCancellation`, `futureDelay`,
`filterLocationCancelled`, `assocIsCancelled`, `affectedByDiversion`,
`rerouteDelay`, `serviceChangeRequired`.

Derived values used by both ports:

- **delayed** := not cancelled **and** `etd != "On time"` (case-insensitive).
- **display status** := `etd` verbatim, except revised times render as
  `"Exp HH:mm"`.

## 5. Quirks (treat all fields as optional)

1. **Empty board ≠ error.** Late at night the 200 response simply *omits*
   `trainServices` (or sets it null). Render "No departures", don't fail.
2. **.NET timestamps.** `generatedAt` has 7-digit fractional seconds
   (`2026-06-12T11:02:13.4406884+01:00`). Many ISO-8601 parsers (including
   Swift's `ISO8601DateFormatter` and some strict Python parsers) reject >6
   fraction digits — strip the fraction before parsing. (Python's
   `datetime.fromisoformat` on 3.11+ copes, but don't rely on it.)
3. **`destination` is an array**, not an object — a SOAP-to-JSON artifact.
   Same for `origin` and the `subsequentCallingPoints` group wrapper.
4. **Missing means false/absent.** Fields like `isCancelled`, `platform`,
   `delayReason` are omitted rather than sent as `false`/`null` in many
   cases. Decode everything as optional with defaults.
5. **`nrccMessages`** (station-wide notices) are *absent entirely* when
   there are none (confirmed in the live capture). When present they
   contain embedded HTML-ish markup and their JSON shape has varied across
   product versions (strings vs `{"Value": ...}` objects). We don't parse
   them; if the Pi version wants them, sanity-check the live shape first.
6. **Base URL versioning** — see §2; never hardcode the product-version path
   segment.
7. **Times have no dates.** `std`/`etd` are clock times only. Around
   midnight a delayed 23:58 train may show an `etd` of `00:10`; don't try
   to sort by parsing these into datetimes, preserve API order (it's already
   sorted by expected departure).
8. **`"Xmlns": {"Count": N}`** appears at the top level — a SOAP-to-JSON
   conversion artifact. In the live capture `Count` was 8 while there were
   10 services, so it is not a service count. Ignore it entirely.
9. **`filterType` is present even when unfiltered** (`"to"` in the capture
   despite no `filterCrs` being sent). Ignore unless filtering is in use.

## 6. Direction detection at Lea Bridge

Lea Bridge (LEB) is on the two-track Lea Valley line: **Stratford (SRA)** is
the next/terminus station southbound; **Tottenham Hale (TOM)** then
**Meridian Water (MRW)** and beyond (Hertford East, Bishops Stortford,
Stansted Airport, Cambridge) are northbound. Every train fits exactly one of
two groups. Rules, applied in order:

1. `destination[0].crs == "SRA"` → **Toward Stratford**.
2. Any subsequent calling point `crs == "SRA"` → **Toward Stratford**
   (future-proofing for through services continuing past Stratford).
3. Otherwise → **Toward Tottenham Hale & beyond**. (Sanity marker: such
   trains call at `TOM` or `MRW` next; if a train matches neither rule 1–2
   nor has those calling points, it still goes in this group.)

Reference CRS codes: `LEB` Lea Bridge, `SRA` Stratford, `TOM` Tottenham
Hale, `MRW` Meridian Water, `NUM` Northumberland Park, `BIS` Bishops
Stortford, `HFE` Hertford East.

Swift implementation: `DarwinKit/Sources/DarwinKit/LeaBridgeDirections.swift`.

## 7. Shared config format

Both the Mac app and the Pi read the same JSON config
(see `config.example.json`):

```json
{
  "apiKey": "YOUR_CONSUMER_KEY",
  "baseUrl": "https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api/20220120",
  "crs": "LEB"
}
```

- `apiKey` — required; the RDM consumer key.
- `baseUrl` — optional; defaults to the URL above.
- `crs` — optional; defaults to `LEB`.

Lookup order (both platforms should follow it):
1. Environment variables `DARWIN_API_KEY`, `DARWIN_BASE_URL`, `DARWIN_CRS`.
2. `~/.config/leaboard/config.json`
3. `./config.json` (current working directory).

The real `config.json` is gitignored; never commit a key.

## 8. Past-train filtering & minutes-until display

Darwin can keep a service on the board for a minute or two after it has
actually departed, and a polling client adds its own lag, so an "11:29"
train can still be in the response at 11:31. Both ports apply the same
post-processing (Swift: `DarwinKit/Sources/DarwinKit/DepartureFilter.swift`):

- **Effective time** := `etd` when it parses as `HH:mm`, else `std`.
- **Minutes until departure** := effective time − now, in whole minutes,
  wrapped to the range **−120…1319** (times carry no date — quirk 7 — so
  anything up to 2 h behind the clock counts as past, everything else as
  upcoming; this makes a 00:05 train "+7 min" at 23:58 and a 23:58 train
  "−4 min" at 00:02).
- **Filter:** drop services with minutes < 0, EXCEPT keep:
  - `etd == "Delayed"` (no estimate — it hasn't departed, however late);
  - services whose times don't parse (can't judge, don't hide);
  - note cancelled services use `std` as effective time, so they stay
    visible until their scheduled time passes, then drop.
- **Display:** minutes ≤ 0 renders as "Due"; cancelled and "Delayed"
  services show a dash instead of minutes.

## 9. Polling etiquette

- The Mac app polls every **60 s while the panel is open** only. The Pi
  board will poll continuously — 60 s is still fine for the free tier, but
  consider backing off to 5 min overnight when the board is empty.
- On 429 or network failure, keep showing the last good board with its
  timestamp rather than blanking the display.

import Foundation

/// A single predicted bus arrival, flattened from the TfL Unified API
/// `StopPoint/{id}/Arrivals` response into exactly what a board needs.
public struct BusArrival: Identifiable, Equatable, Sendable {
    /// TfL's prediction `id`, unique per prediction — used as row identity.
    /// It is an opaque string and can look negative (e.g. "-1879565940").
    public let id: String

    /// Route number as shown on the bus, e.g. "55", "56", "N38".
    public let lineName: String

    /// Where the bus terminates, e.g. "Oxford Circus". Falls back to the
    /// coarser `towards` text when the API leaves `destinationName` empty.
    public let destination: String

    /// Seconds until arrival as of the fetch (`timeToStation` from the API).
    public let timeToStation: Int

    /// Absolute expected arrival instant (parsed from `expectedArrival`, UTC).
    /// Use this to recompute the countdown live between polls.
    public let expectedArrival: Date

    /// Whole minutes until arrival, derived from `timeToStation` (floored).
    /// 201 s → 3, 59 s → 0. This is the value at fetch time; for a ticking
    /// display use `minutesUntilArrival(at:)`.
    public var minutesUntilArrival: Int {
        max(0, timeToStation) / 60
    }

    /// True when the bus is under a minute away (or already past) — renders
    /// as "Due".
    public var isDue: Bool {
        minutesUntilArrival < 1
    }

    public init(
        id: String,
        lineName: String,
        destination: String,
        timeToStation: Int,
        expectedArrival: Date
    ) {
        self.id = id
        self.lineName = lineName
        self.destination = destination
        self.timeToStation = timeToStation
        self.expectedArrival = expectedArrival
    }

    /// Whole minutes until arrival relative to `now`, computed from the
    /// absolute `expectedArrival` so the countdown ticks down between polls.
    /// Negative/sub-minute values clamp to 0 (rendered as "Due").
    public func minutesUntilArrival(at now: Date) -> Int {
        max(0, Int(expectedArrival.timeIntervalSince(now) / 60))
    }
}

/// The arrivals board for one stop (one direction) at one moment in time.
public struct BusBoard: Equatable, Sendable {
    /// The stop's NaPTAN id, e.g. "490009131W".
    public let stopId: String

    /// Human stop name from the API (`stationName`), e.g. "Emmanuel Parish
    /// Church". Falls back to the configured label when the API omits it.
    public let stopName: String

    /// When this board was fetched.
    public let generatedAt: Date

    /// Arrivals sorted soonest-first (by `timeToStation`). Empty is a normal
    /// state — no buses due — not an error.
    public let arrivals: [BusArrival]

    public init(stopId: String, stopName: String, generatedAt: Date, arrivals: [BusArrival]) {
        self.stopId = stopId
        self.stopName = stopName
        self.generatedAt = generatedAt
        self.arrivals = arrivals
    }
}

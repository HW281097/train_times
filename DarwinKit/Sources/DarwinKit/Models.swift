import Foundation

/// A single departing service, flattened from the Darwin LDBWS response into
/// exactly what a departure board needs to render.
public struct Departure: Identifiable, Equatable, Sendable {
    /// Darwin's `serviceID`, unique per service per day.
    public let id: String

    /// Destination station name, e.g. "Stratford", "Bishops Stortford".
    public let destination: String

    /// Destination CRS code, e.g. "SRA". Used for direction grouping.
    public let destinationCRS: String?

    /// Optional "via ..." routing text supplied by Darwin.
    public let via: String?

    /// Scheduled departure time as shown on the board, "HH:mm".
    public let scheduled: String

    /// Expected departure: "On time", a revised time like "14:32",
    /// "Delayed" (no estimate), or "Cancelled".
    public let expected: String

    /// Platform number, when Darwin knows it (often absent at small stations).
    public let platform: String?

    /// Operating company, e.g. "Greater Anglia".
    public let operatorName: String

    /// True when the service is cancelled at this station.
    public let isCancelled: Bool

    /// Darwin's human-readable reason for a cancellation or delay, if any.
    public let reason: String?

    /// CRS codes of every calling point after this station, in order.
    /// Used for direction detection (see `LeaBridgeDirections`).
    public let callingPointCRSCodes: [String]

    /// True when the service is running but not on time
    /// (`expected` is "Delayed" or a revised time differing from `scheduled`).
    public var isDelayed: Bool {
        guard !isCancelled else { return false }
        return expected.caseInsensitiveCompare("On time") != .orderedSame
    }

    public init(
        id: String,
        destination: String,
        destinationCRS: String?,
        via: String?,
        scheduled: String,
        expected: String,
        platform: String?,
        operatorName: String,
        isCancelled: Bool,
        reason: String?,
        callingPointCRSCodes: [String]
    ) {
        self.id = id
        self.destination = destination
        self.destinationCRS = destinationCRS
        self.via = via
        self.scheduled = scheduled
        self.expected = expected
        self.platform = platform
        self.operatorName = operatorName
        self.isCancelled = isCancelled
        self.reason = reason
        self.callingPointCRSCodes = callingPointCRSCodes
    }
}

/// A departure board for one station at one moment in time.
public struct DepartureBoard: Equatable, Sendable {
    /// Full station name as returned by Darwin, e.g. "Lea Bridge".
    public let stationName: String

    /// CRS code of the station the board is for.
    public let crs: String

    /// When Darwin generated this board. Falls back to the fetch time if the
    /// timestamp can't be parsed (see API_NOTES.md on fractional seconds).
    public let generatedAt: Date

    /// Departures in the order Darwin returns them (soonest first).
    /// Empty when no services are running — that is a normal state late at
    /// night, not an error.
    public let departures: [Departure]

    public init(stationName: String, crs: String, generatedAt: Date, departures: [Departure]) {
        self.stationName = stationName
        self.crs = crs
        self.generatedAt = generatedAt
        self.departures = departures
    }
}

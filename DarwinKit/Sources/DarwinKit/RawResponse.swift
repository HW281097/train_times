import Foundation

// Raw Codable mirror of the LDBWS REST JSON. Field names match the API
// exactly; everything is optional because Darwin omits fields rather than
// sending null in many cases (notably `trainServices` on an empty board).
// The shape is documented for the Raspberry Pi port in docs/API_NOTES.md —
// keep that file in sync with any changes here.

struct RawStationBoard: Decodable {
    let generatedAt: String?
    let locationName: String?
    let crs: String?
    let trainServices: [RawService]?
}

struct RawService: Decodable {
    let serviceID: String?
    let std: String?
    let etd: String?
    let platform: String?
    let `operator`: String?
    let operatorCode: String?
    let isCancelled: Bool?
    let cancelReason: String?
    let delayReason: String?
    let destination: [RawLocation]?
    let subsequentCallingPoints: [RawCallingPointGroup]?
}

struct RawLocation: Decodable {
    let locationName: String?
    let crs: String?
    let via: String?
}

struct RawCallingPointGroup: Decodable {
    let callingPoint: [RawCallingPoint]?
}

struct RawCallingPoint: Decodable {
    let locationName: String?
    let crs: String?
    let st: String?
    let et: String?
}

extension DepartureBoard {
    /// Decodes the raw LDBWS JSON into the public model.
    static func decode(_ data: Data, fetchedAt: Date = Date()) throws -> DepartureBoard {
        let raw: RawStationBoard
        do {
            raw = try JSONDecoder().decode(RawStationBoard.self, from: data)
        } catch {
            throw DarwinError.unexpectedResponse("Could not decode board JSON: \(error)")
        }

        let departures = (raw.trainServices ?? []).compactMap { service -> Departure? in
            // A service without a scheduled time can't be displayed.
            guard let std = service.std else { return nil }
            let destination = service.destination?.first
            // Calling point groups: the first group is the train's own route;
            // extra groups only appear for trains that divide en route.
            let callingPoints = service.subsequentCallingPoints?
                .flatMap { $0.callingPoint ?? [] }
                .compactMap(\.crs) ?? []
            let cancelled = service.isCancelled ?? false
            return Departure(
                id: service.serviceID ?? "\(std)-\(destination?.crs ?? "???")",
                destination: destination?.locationName ?? "Unknown",
                destinationCRS: destination?.crs,
                via: destination?.via,
                scheduled: std,
                expected: service.etd ?? (cancelled ? "Cancelled" : "On time"),
                platform: service.platform,
                operatorName: service.operator ?? "",
                isCancelled: cancelled,
                reason: service.cancelReason ?? service.delayReason,
                callingPointCRSCodes: callingPoints
            )
        }

        return DepartureBoard(
            stationName: raw.locationName ?? raw.crs ?? "Unknown",
            crs: raw.crs ?? "",
            generatedAt: Self.parseGeneratedAt(raw.generatedAt) ?? fetchedAt,
            departures: departures
        )
    }

    /// Darwin timestamps carry .NET-style 7-digit fractional seconds
    /// (e.g. "2026-06-12T11:02:13.4406884+01:00"), which ISO8601DateFormatter
    /// rejects, so the fraction is stripped before parsing.
    static func parseGeneratedAt(_ string: String?) -> Date? {
        guard var s = string else { return nil }
        if let dotIndex = s.firstIndex(of: ".") {
            let tail = s[dotIndex...]
            if let zoneIndex = tail.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                s.removeSubrange(dotIndex..<zoneIndex)
            } else {
                s.removeSubrange(dotIndex...)
            }
        }
        return ISO8601DateFormatter().date(from: s)
    }
}

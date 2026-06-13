import Foundation

// Raw Codable mirror of the TfL Unified API arrivals JSON. The response is a
// top-level ARRAY of these (no envelope). Every field is optional — treat the
// API defensively, per docs/TFL_API_NOTES.md §5. Keep that file in sync with
// any change here.

struct RawPrediction: Decodable {
    let id: String?
    let lineName: String?
    let lineId: String?
    let destinationName: String?
    let towards: String?
    let timeToStation: Int?
    let expectedArrival: String?
    let naptanId: String?
    let stationName: String?
}

extension BusBoard {
    /// Decodes the raw arrivals JSON (a top-level array) into the public model,
    /// sorted soonest-first. An empty array yields a board with no arrivals,
    /// which is a normal state, not an error.
    ///
    /// - Parameters:
    ///   - data: the raw response body.
    ///   - stopId: the NaPTAN id requested (used when the API omits it).
    ///   - fallbackStopName: the configured label, used when the API omits
    ///     `stationName` (e.g. an empty array carries no stop name).
    ///   - fetchedAt: the moment of fetch, used as `generatedAt`.
    static func decode(
        _ data: Data,
        stopId: String,
        fallbackStopName: String,
        fetchedAt: Date = Date()
    ) throws -> BusBoard {
        let raw: [RawPrediction]
        do {
            raw = try JSONDecoder().decode([RawPrediction].self, from: data)
        } catch {
            throw TfLError.unexpectedResponse("Could not decode arrivals JSON: \(error)")
        }

        let arrivals = raw.compactMap { prediction -> BusArrival? in
            let timeToStation = prediction.timeToStation ?? 0
            let expected = Self.parseExpectedArrival(prediction.expectedArrival)
                ?? fetchedAt.addingTimeInterval(TimeInterval(timeToStation))
            let line = nonEmpty(prediction.lineName) ?? nonEmpty(prediction.lineId)
            // A prediction with no route number can't be displayed meaningfully.
            guard let lineName = line else { return nil }
            let destination = nonEmpty(prediction.destinationName)
                ?? nonEmpty(prediction.towards)
                ?? ""
            return BusArrival(
                id: prediction.id ?? "\(lineName)-\(timeToStation)",
                lineName: lineName,
                destination: destination,
                timeToStation: timeToStation,
                expectedArrival: expected
            )
        }
        .sorted { $0.timeToStation < $1.timeToStation }

        return BusBoard(
            stopId: arrivals.isEmpty ? stopId : (raw.first?.naptanId ?? stopId),
            stopName: nonEmpty(raw.first?.stationName) ?? fallbackStopName,
            generatedAt: fetchedAt,
            arrivals: arrivals
        )
    }

    /// Parses an ISO-8601 UTC instant like "2026-06-13T12:16:40Z". Strips any
    /// fractional seconds first (defensive — `expectedArrival` carries none in
    /// practice, but `.NET` timestamps elsewhere have 7 digits, TFL_API_NOTES §6).
    static func parseExpectedArrival(_ string: String?) -> Date? {
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

/// Returns the string if it is non-nil and non-empty, else nil.
private func nonEmpty(_ string: String?) -> String? {
    guard let string, !string.isEmpty else { return nil }
    return string
}

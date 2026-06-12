import XCTest
@testable import DarwinKit

final class DepartureDecodingTests: XCTestCase {
    // Fixtures/sample_board.json is a real GetDepBoardWithDetails/LEB
    // response captured 2026-06-12 11:29 BST (see docs/API_NOTES.md §3).
    private func sampleBoard() throws -> DepartureBoard {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "sample_board", withExtension: "json", subdirectory: "Fixtures")
        )
        return try DepartureBoard.decode(Data(contentsOf: url))
    }

    func testDecodesBoardMetadata() throws {
        let board = try sampleBoard()
        XCTAssertEqual(board.stationName, "Lea Bridge")
        XCTAssertEqual(board.crs, "LEB")
        XCTAssertEqual(board.departures.count, 10)

        // 2026-06-12T11:29:12+01:00 == 10:29:12 UTC; the .NET 7-digit
        // fractional seconds must not break parsing.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.hour, .minute, .second], from: board.generatedAt)
        XCTAssertEqual(parts.hour, 10)
        XCTAssertEqual(parts.minute, 29)
        XCTAssertEqual(parts.second, 12)
    }

    func testDecodesOnTimeService() throws {
        let departure = try XCTUnwrap(sampleBoard().departures.first)
        XCTAssertEqual(departure.id, "4048751LEABDGE_")
        XCTAssertEqual(departure.destination, "Stratford (London)")
        XCTAssertEqual(departure.destinationCRS, "SRA")
        XCTAssertEqual(departure.scheduled, "11:29")
        XCTAssertEqual(departure.expected, "On time")
        XCTAssertEqual(departure.platform, "1")
        XCTAssertEqual(departure.operatorName, "Greater Anglia")
        XCTAssertFalse(departure.isCancelled)
        XCTAssertFalse(departure.isDelayed)
        XCTAssertEqual(departure.callingPointCRSCodes, ["SRA"])
    }

    func testDecodesNorthboundCallingPoints() throws {
        // 11:32 to Bishops Stortford: first call Tottenham Hale, last BIS.
        let departure = try sampleBoard().departures[1]
        XCTAssertEqual(departure.destinationCRS, "BIS")
        XCTAssertEqual(departure.callingPointCRSCodes.first, "TOM")
        XCTAssertEqual(departure.callingPointCRSCodes.last, "BIS")
        XCTAssertEqual(departure.callingPointCRSCodes.count, 7)
    }

    // The live capture contained only on-time services; the degraded states
    // below use inline JSON matching the captured schema exactly.

    func testDecodesDelayedServiceWithEstimate() throws {
        let board = try DepartureBoard.decode(Data(service(
            std: "11:23", etd: "11:29",
            extra: #""delayReason": "This train has been delayed by a train fault","#
        ).utf8))
        let departure = try XCTUnwrap(board.departures.first)
        XCTAssertEqual(departure.expected, "11:29")
        XCTAssertTrue(departure.isDelayed)
        XCTAssertFalse(departure.isCancelled)
        XCTAssertEqual(departure.reason, "This train has been delayed by a train fault")
    }

    func testDecodesDelayedServiceWithoutEstimate() throws {
        let board = try DepartureBoard.decode(Data(service(std: "11:53", etd: "Delayed").utf8))
        let departure = try XCTUnwrap(board.departures.first)
        XCTAssertEqual(departure.expected, "Delayed")
        XCTAssertTrue(departure.isDelayed)
        XCTAssertTrue(departure.hasNoEstimate)
    }

    func testDecodesCancelledService() throws {
        let board = try DepartureBoard.decode(Data(service(
            std: "11:38", etd: "Cancelled", cancelled: true, platform: nil,
            extra: #""cancelReason": "This train has been cancelled because of a shortage of train crew","#
        ).utf8))
        let departure = try XCTUnwrap(board.departures.first)
        XCTAssertTrue(departure.isCancelled)
        XCTAssertFalse(departure.isDelayed)
        XCTAssertEqual(departure.expected, "Cancelled")
        XCTAssertNil(departure.platform)
        XCTAssertEqual(departure.reason, "This train has been cancelled because of a shortage of train crew")
    }

    func testEmptyBoardDecodesToNoDepartures() throws {
        // Late at night Darwin omits trainServices entirely.
        let json = """
        {
          "Xmlns": { "Count": 8 },
          "generatedAt": "2026-06-12T01:30:00.0000000+01:00",
          "locationName": "Lea Bridge",
          "crs": "LEB",
          "filterType": "to",
          "platformAvailable": true,
          "areServicesAvailable": true
        }
        """
        let board = try DepartureBoard.decode(Data(json.utf8))
        XCTAssertEqual(board.crs, "LEB")
        XCTAssertTrue(board.departures.isEmpty)
    }

    func testGarbageBodyThrowsUnexpectedResponse() {
        XCTAssertThrowsError(try DepartureBoard.decode(Data("<html>".utf8))) { error in
            guard case DarwinError.unexpectedResponse = error else {
                return XCTFail("Expected .unexpectedResponse, got \(error)")
            }
        }
    }

    /// A one-service board in the captured schema, with overridable status.
    private func service(
        std: String,
        etd: String,
        cancelled: Bool = false,
        platform: String? = "2",
        extra: String = ""
    ) -> String {
        let platformJSON = platform.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "trainServices": [
            {
              "subsequentCallingPoints": [
                {
                  "callingPoint": [
                    { "locationName": "Tottenham Hale", "crs": "TOM", "st": "11:27", "et": "\(etd)",
                      "isCancelled": \(cancelled), "length": 0, "detachFront": false,
                      "affectedByDiversion": false, "rerouteDelay": 0 }
                  ],
                  "serviceType": "train", "serviceChangeRequired": false, "assocIsCancelled": false
                }
              ],
              "futureCancellation": false,
              "futureDelay": false,
              "origin": [ { "locationName": "Stratford (London)", "crs": "SRA", "assocIsCancelled": false } ],
              "destination": [ { "locationName": "Meridian Water", "crs": "MRW", "assocIsCancelled": false } ],
              "std": "\(std)",
              "etd": "\(etd)",
              "platform": \(platformJSON),
              "operator": "Greater Anglia",
              "operatorCode": "LE",
              "isCircularRoute": false,
              "isCancelled": \(cancelled),
              \(extra)
              "filterLocationCancelled": false,
              "serviceType": "train",
              "length": 0,
              "detachFront": false,
              "isReverseFormation": false,
              "serviceID": "4099999LEABDGE_"
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
        """
    }
}

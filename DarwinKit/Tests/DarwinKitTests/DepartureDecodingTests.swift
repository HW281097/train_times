import XCTest
@testable import DarwinKit

final class DepartureDecodingTests: XCTestCase {
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
        XCTAssertEqual(board.departures.count, 5)

        // 2026-06-12T11:02:13+01:00 == 10:02:13 UTC; the 7-digit fractional
        // seconds in the fixture must not break parsing.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.hour, .minute, .second], from: board.generatedAt)
        XCTAssertEqual(parts.hour, 10)
        XCTAssertEqual(parts.minute, 2)
        XCTAssertEqual(parts.second, 13)
    }

    func testDecodesOnTimeService() throws {
        let departure = try XCTUnwrap(sampleBoard().departures.first)
        XCTAssertEqual(departure.destination, "Bishops Stortford")
        XCTAssertEqual(departure.destinationCRS, "BIS")
        XCTAssertEqual(departure.scheduled, "11:08")
        XCTAssertEqual(departure.expected, "On time")
        XCTAssertEqual(departure.platform, "2")
        XCTAssertEqual(departure.operatorName, "Greater Anglia")
        XCTAssertFalse(departure.isCancelled)
        XCTAssertFalse(departure.isDelayed)
        XCTAssertEqual(departure.callingPointCRSCodes.first, "TOM")
        XCTAssertEqual(departure.callingPointCRSCodes.last, "BIS")
    }

    func testDecodesDelayedServiceWithEstimate() throws {
        let departure = try sampleBoard().departures[2]
        XCTAssertEqual(departure.scheduled, "11:23")
        XCTAssertEqual(departure.expected, "11:29")
        XCTAssertTrue(departure.isDelayed)
        XCTAssertFalse(departure.isCancelled)
        XCTAssertEqual(departure.reason, "This train has been delayed by a train fault")
    }

    func testDecodesDelayedServiceWithoutEstimate() throws {
        let departure = try sampleBoard().departures[4]
        XCTAssertEqual(departure.expected, "Delayed")
        XCTAssertTrue(departure.isDelayed)
    }

    func testDecodesCancelledService() throws {
        let departure = try sampleBoard().departures[3]
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
          "generatedAt": "2026-06-12T01:30:00.0000000+01:00",
          "locationName": "Lea Bridge",
          "crs": "LEB",
          "platformAvailable": true
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
}

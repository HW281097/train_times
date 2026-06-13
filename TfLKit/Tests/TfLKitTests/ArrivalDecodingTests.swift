import XCTest
@testable import TfLKit

final class ArrivalDecodingTests: XCTestCase {
    // Fixtures are real StopPoint/{id}/Arrivals captures from 2026-06-13
    // 11:53 UTC (see docs/TFL_API_NOTES.md §3).
    private func board(
        fixture: String,
        stopId: String,
        label: String,
        fetchedAt: Date = Date()
    ) throws -> BusBoard {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures")
        )
        return try BusBoard.decode(
            Data(contentsOf: url), stopId: stopId, fallbackStopName: label, fetchedAt: fetchedAt
        )
    }

    private var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func testDecodesHackneyBoardMetadata() throws {
        let board = try board(
            fixture: "arrivals_towards_hackney", stopId: "490009131W", label: "Towards Hackney"
        )
        XCTAssertEqual(board.stopId, "490009131W")
        XCTAssertEqual(board.stopName, "Emmanuel Parish Church")
        XCTAssertEqual(board.arrivals.count, 6)
    }

    func testArrivalsAreSortedSoonestFirst() throws {
        // The raw capture order is 1377, 874, 201, 442, 636, 234 — unsorted.
        let board = try board(
            fixture: "arrivals_towards_hackney", stopId: "490009131W", label: "Towards Hackney"
        )
        XCTAssertEqual(board.arrivals.map(\.timeToStation), [201, 234, 442, 636, 874, 1377])
    }

    func testDecodesSoonestArrival() throws {
        let arrival = try XCTUnwrap(
            board(fixture: "arrivals_towards_hackney", stopId: "490009131W", label: "Towards Hackney")
                .arrivals.first
        )
        XCTAssertEqual(arrival.id, "-1879565940")
        XCTAssertEqual(arrival.lineName, "55")
        XCTAssertEqual(arrival.destination, "Oxford Circus")
        XCTAssertEqual(arrival.timeToStation, 201)
        XCTAssertEqual(arrival.minutesUntilArrival, 3)   // 201 / 60, floored
        XCTAssertFalse(arrival.isDue)

        // expectedArrival "2026-06-13T11:57:04Z"
        let parts = utcCalendar.dateComponents([.hour, .minute, .second], from: arrival.expectedArrival)
        XCTAssertEqual(parts.hour, 11)
        XCTAssertEqual(parts.minute, 57)
        XCTAssertEqual(parts.second, 4)
    }

    func testDecodesRoute56Arrival() throws {
        let board = try board(
            fixture: "arrivals_towards_hackney", stopId: "490009131W", label: "Towards Hackney"
        )
        let route56 = try XCTUnwrap(board.arrivals.first { $0.lineName == "56" })
        XCTAssertEqual(route56.destination, "Smithfield, St Bartholomew's Hospital")
    }

    func testDecodesWalthamstowBoard() throws {
        let board = try board(
            fixture: "arrivals_towards_walthamstow", stopId: "490009131E", label: "Towards Walthamstow"
        )
        XCTAssertEqual(board.stopId, "490009131E")
        XCTAssertEqual(board.arrivals.count, 4)
        XCTAssertEqual(board.arrivals.map(\.timeToStation), [346, 1167, 1590, 1697])
        let first = try XCTUnwrap(board.arrivals.first)
        XCTAssertEqual(first.lineName, "55")
        XCTAssertEqual(first.destination, "Walthamstow Central")
        XCTAssertEqual(first.minutesUntilArrival, 5)   // 346 / 60, floored
    }

    func testEmptyArrayIsNormalNotAnError() throws {
        // No buses due returns 200 with [] — a valid board with no arrivals.
        let board = try BusBoard.decode(
            Data("[]".utf8), stopId: "490009131W", fallbackStopName: "Towards Hackney"
        )
        XCTAssertEqual(board.stopId, "490009131W")
        XCTAssertEqual(board.stopName, "Towards Hackney")   // fell back to label
        XCTAssertTrue(board.arrivals.isEmpty)
    }

    func testDestinationFallsBackToTowardsWhenEmpty() throws {
        let json = """
        [{ "id": "p1", "lineName": "N55", "destinationName": "", "towards": "Walthamstow",
           "timeToStation": 40, "expectedArrival": "2026-06-13T12:00:40Z",
           "naptanId": "490009131E", "stationName": "Emmanuel Parish Church" }]
        """
        let board = try BusBoard.decode(
            Data(json.utf8), stopId: "490009131E", fallbackStopName: "Towards Walthamstow"
        )
        let arrival = try XCTUnwrap(board.arrivals.first)
        XCTAssertEqual(arrival.lineName, "N55")
        XCTAssertEqual(arrival.destination, "Walthamstow")
        XCTAssertTrue(arrival.isDue)   // 40 s → 0 min → "Due"
    }

    func testGarbageBodyThrowsUnexpectedResponse() {
        XCTAssertThrowsError(
            try BusBoard.decode(Data("<html>".utf8), stopId: "x", fallbackStopName: "y")
        ) { error in
            guard case TfLError.unexpectedResponse = error else {
                return XCTFail("Expected .unexpectedResponse, got \(error)")
            }
        }
    }

    func testMinutesUntilArrivalTicksFromExpectedArrival() throws {
        let arrival = BusArrival(
            id: "p", lineName: "55", destination: "Oxford Circus",
            timeToStation: 600,
            expectedArrival: Date(timeIntervalSince1970: 1_000_000)
        )
        // 5 minutes 30 s before the expected arrival → 5 min.
        XCTAssertEqual(arrival.minutesUntilArrival(at: Date(timeIntervalSince1970: 1_000_000 - 330)), 5)
        // 30 s before → under a minute → 0 (Due).
        XCTAssertEqual(arrival.minutesUntilArrival(at: Date(timeIntervalSince1970: 1_000_000 - 30)), 0)
        // Already past → clamps to 0 (Due).
        XCTAssertEqual(arrival.minutesUntilArrival(at: Date(timeIntervalSince1970: 1_000_000 + 120)), 0)
    }
}

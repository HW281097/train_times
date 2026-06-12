import XCTest
@testable import DarwinKit

final class DirectionTests: XCTestCase {
    private func departure(destinationCRS: String?, callingPoints: [String] = []) -> Departure {
        Departure(
            id: "test",
            destination: "Test",
            destinationCRS: destinationCRS,
            via: nil,
            scheduled: "12:00",
            expected: "On time",
            platform: nil,
            operatorName: "Greater Anglia",
            isCancelled: false,
            reason: nil,
            callingPointCRSCodes: callingPoints
        )
    }

    func testStratfordDestinationIsStratfordDirection() {
        let dep = departure(destinationCRS: "SRA", callingPoints: ["SRA"])
        XCTAssertEqual(LeaBridgeDirections.direction(of: dep), .stratford)
    }

    func testServiceCallingAtStratfordIsStratfordDirection() {
        let dep = departure(destinationCRS: "LST", callingPoints: ["SRA", "LST"])
        XCTAssertEqual(LeaBridgeDirections.direction(of: dep), .stratford)
    }

    func testNorthboundDestinationsAreTottenhamHaleDirection() {
        for (dest, calls) in [
            ("BIS", ["TOM", "MRW", "CHN", "BIS"]),
            ("MRW", ["TOM", "NUM", "MRW"]),
            ("HFE", ["TOM", "WAR", "HFE"]),
        ] {
            let dep = departure(destinationCRS: dest, callingPoints: calls)
            XCTAssertEqual(LeaBridgeDirections.direction(of: dep), .tottenhamHale, "for \(dest)")
        }
    }

    func testUnknownDestinationFallsBackToNorthbound() {
        let dep = departure(destinationCRS: nil)
        XCTAssertEqual(LeaBridgeDirections.direction(of: dep), .tottenhamHale)
    }

    func testGroupingPreservesOrderWithinDirections() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "sample_board", withExtension: "json", subdirectory: "Fixtures")
        )
        let board = try DepartureBoard.decode(Data(contentsOf: url))
        let groups = LeaBridgeDirections.grouped(board.departures)

        XCTAssertEqual(groups[.stratford]?.map(\.scheduled), ["11:14", "11:38"])
        XCTAssertEqual(groups[.tottenhamHale]?.map(\.scheduled), ["11:08", "11:23", "11:53"])
    }
}

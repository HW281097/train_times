import XCTest
@testable import DarwinKit

final class DepartureFilterTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func clock(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: hour, minute: minute))!
    }

    private func departure(std: String, etd: String, cancelled: Bool = false) -> Departure {
        Departure(
            id: "\(std)-\(etd)",
            destination: "Test",
            destinationCRS: "SRA",
            via: nil,
            scheduled: std,
            expected: etd,
            platform: nil,
            operatorName: "Greater Anglia",
            isCancelled: cancelled,
            reason: nil,
            callingPointCRSCodes: []
        )
    }

    // The reported bug: an "11:29, On time" train still showing at 11:31.
    func testDepartedOnTimeTrainIsDropped() {
        let departed = departure(std: "11:29", etd: "On time")
        let kept = DepartureFilter.upcoming([departed], at: clock(11, 31), calendar: calendar)
        XCTAssertTrue(kept.isEmpty)
    }

    func testFutureTrainIsKept() {
        let future = departure(std: "11:34", etd: "On time")
        let kept = DepartureFilter.upcoming([future], at: clock(11, 31), calendar: calendar)
        XCTAssertEqual(kept.count, 1)
    }

    func testRevisedTimeOverridesPastScheduledTime() {
        // std has passed but the train is now expected at 11:35 — keep it.
        let running = departure(std: "11:29", etd: "11:35")
        XCTAssertEqual(running.effectiveTime, "11:35")
        XCTAssertEqual(running.minutesUntilDeparture(from: clock(11, 31), calendar: calendar), 4)
        XCTAssertEqual(DepartureFilter.upcoming([running], at: clock(11, 31), calendar: calendar).count, 1)
    }

    func testRevisedTimeInPastIsDropped() {
        let departed = departure(std: "11:20", etd: "11:25")
        XCTAssertTrue(DepartureFilter.upcoming([departed], at: clock(11, 31), calendar: calendar).isEmpty)
    }

    func testDelayedWithoutEstimateIsAlwaysKept() {
        // No estimate means it hasn't departed, however late it is.
        let delayed = departure(std: "11:00", etd: "Delayed")
        XCTAssertTrue(delayed.hasNoEstimate)
        XCTAssertEqual(DepartureFilter.upcoming([delayed], at: clock(11, 31), calendar: calendar).count, 1)
    }

    func testCancelledTrainKeptUntilScheduledTimePasses() {
        let cancelled = departure(std: "11:38", etd: "Cancelled", cancelled: true)
        XCTAssertEqual(DepartureFilter.upcoming([cancelled], at: clock(11, 31), calendar: calendar).count, 1)
        XCTAssertTrue(DepartureFilter.upcoming([cancelled], at: clock(11, 40), calendar: calendar).isEmpty)
    }

    func testMidnightWraparound() {
        // 00:05 train seen at 23:58 is 7 minutes away, not 24 hours gone.
        let afterMidnight = departure(std: "00:05", etd: "On time")
        XCTAssertEqual(afterMidnight.minutesUntilDeparture(from: clock(23, 58), calendar: calendar), 7)
        XCTAssertEqual(DepartureFilter.upcoming([afterMidnight], at: clock(23, 58), calendar: calendar).count, 1)

        // 23:58 train seen at 00:02 departed 4 minutes ago.
        let beforeMidnight = departure(std: "23:58", etd: "On time")
        XCTAssertEqual(beforeMidnight.minutesUntilDeparture(from: clock(0, 2), calendar: calendar), -4)
        XCTAssertTrue(DepartureFilter.upcoming([beforeMidnight], at: clock(0, 2), calendar: calendar).isEmpty)
    }

    func testUnparseableTimesAreKept() {
        let weird = departure(std: "??:??", etd: "On time")
        XCTAssertNil(weird.minutesUntilDeparture(from: clock(11, 31), calendar: calendar))
        XCTAssertEqual(DepartureFilter.upcoming([weird], at: clock(11, 31), calendar: calendar).count, 1)
    }
}

import Foundation
import TfLKit

/// Canned bus arrivals for running the app before a TfL key is registered.
/// Enabled by launching with LEABOARD_DEMO=1. Times are generated relative to
/// now so the board always looks live, and the routes mix 2- and 3-character
/// numbers (55/56 and N38/N55) to exercise column spacing.
enum DemoBusBoard {
    static func make(now: Date = Date()) -> (a: BusBoard, b: BusBoard) {
        func arrival(_ id: String, _ line: String, _ dest: String, minutes: Int) -> BusArrival {
            BusArrival(
                id: id,
                lineName: line,
                destination: dest,
                timeToStation: minutes * 60,
                expectedArrival: now.addingTimeInterval(TimeInterval(minutes * 60))
            )
        }

        let towardsHackney = BusBoard(
            stopId: "490009131W",
            stopName: "Emmanuel Parish Church",
            generatedAt: now,
            arrivals: [
                arrival("demo-a1", "55", "Oxford Circus", minutes: 0),
                arrival("demo-a2", "56", "Smithfield, St Bartholomew's Hospital", minutes: 3),
                arrival("demo-a3", "N38", "Hackney Central", minutes: 8),
                arrival("demo-a4", "55", "Oxford Circus", minutes: 12),
            ]
        )

        let towardsWalthamstow = BusBoard(
            stopId: "490009131E",
            stopName: "Emmanuel Parish Church",
            generatedAt: now,
            arrivals: [
                arrival("demo-b1", "55", "Walthamstow Central", minutes: 2),
                arrival("demo-b2", "N55", "Walthamstow Central", minutes: 6),
                arrival("demo-b3", "56", "Whipps Cross", minutes: 11),
                arrival("demo-b4", "55", "Walthamstow Central", minutes: 19),
            ]
        )

        return (towardsHackney, towardsWalthamstow)
    }
}

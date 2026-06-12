import Foundation
import DarwinKit

/// Canned departures for running the app before the Rail Data Marketplace
/// subscription is approved. Enabled by launching with LEABOARD_DEMO=1.
/// Times are generated relative to now so the board always looks live.
enum DemoBoard {
    static func make(now: Date = Date()) -> DepartureBoard {
        func time(_ minutesFromNow: Int) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: now.addingTimeInterval(TimeInterval(minutesFromNow * 60)))
        }

        let departures = [
            Departure(
                id: "demo-1",
                destination: "Stratford",
                destinationCRS: "SRA",
                via: nil,
                scheduled: time(4),
                expected: "On time",
                platform: "1",
                operatorName: "Greater Anglia",
                isCancelled: false,
                reason: nil,
                callingPointCRSCodes: ["SRA"]
            ),
            Departure(
                id: "demo-2",
                destination: "Bishops Stortford",
                destinationCRS: "BIS",
                via: nil,
                scheduled: time(7),
                expected: "On time",
                platform: "2",
                operatorName: "Greater Anglia",
                isCancelled: false,
                reason: nil,
                callingPointCRSCodes: ["TOM", "MRW", "CHN", "BXB", "HWN", "BIS"]
            ),
            Departure(
                id: "demo-3",
                destination: "Meridian Water",
                destinationCRS: "MRW",
                via: nil,
                scheduled: time(15),
                expected: time(21),
                platform: "2",
                operatorName: "Greater Anglia",
                isCancelled: false,
                reason: "This train has been delayed by a train fault",
                callingPointCRSCodes: ["TOM", "NUM", "MRW"]
            ),
            Departure(
                id: "demo-4",
                destination: "Stratford",
                destinationCRS: "SRA",
                via: nil,
                scheduled: time(19),
                expected: "Cancelled",
                platform: nil,
                operatorName: "Greater Anglia",
                isCancelled: true,
                reason: "This train has been cancelled because of a shortage of train crew",
                callingPointCRSCodes: []
            ),
            Departure(
                id: "demo-5",
                destination: "Hertford East",
                destinationCRS: "HFE",
                via: nil,
                scheduled: time(28),
                expected: "Delayed",
                platform: "2",
                operatorName: "Greater Anglia",
                isCancelled: false,
                reason: nil,
                callingPointCRSCodes: ["TOM", "WAR", "HFE"]
            ),
            Departure(
                id: "demo-6",
                destination: "Stratford",
                destinationCRS: "SRA",
                via: nil,
                scheduled: time(34),
                expected: "On time",
                platform: "1",
                operatorName: "Greater Anglia",
                isCancelled: false,
                reason: nil,
                callingPointCRSCodes: ["SRA"]
            ),
        ]

        return DepartureBoard(
            stationName: "Lea Bridge",
            crs: "LEB",
            generatedAt: now,
            departures: departures
        )
    }
}

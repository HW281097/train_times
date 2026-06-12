import Foundation

// Past-train filtering and "minutes until departure", shared logic for any
// front end (mirrored for the Pi port in docs/API_NOTES.md §8 — keep in sync).
//
// Motivation: Darwin can keep a service on the board for a minute or two
// after it has actually departed, and a polling client adds its own lag on
// top, so an "11:29" train can still be showing at 11:31. Filtering on the
// effective departure time fixes that.

extension Departure {
    /// The clock time that best represents the actual departure: the revised
    /// `expected` time when there is one, otherwise the scheduled time.
    public var effectiveTime: String {
        Self.minutesOfDay(expected) != nil ? expected : scheduled
    }

    /// True when `expected` is "Delayed" — running, but Darwin has no
    /// estimate, so minutes-until is unknowable.
    public var hasNoEstimate: Bool {
        !isCancelled && expected.caseInsensitiveCompare("Delayed") == .orderedSame
    }

    /// Whole minutes from `now` until the effective departure time, or nil
    /// when the time can't be parsed.
    ///
    /// Board times carry no date (API_NOTES §5 quirk 7), so the difference
    /// is wrapped to -120...1319: anything up to two hours behind the clock
    /// counts as past, everything else as upcoming. That keeps a 00:05
    /// train "in 7 minutes" at 23:58, and a 23:58 train "4 minutes gone"
    /// at 00:02.
    public func minutesUntilDeparture(from now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let target = Self.minutesOfDay(effectiveTime) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        var diff = (target - nowMinutes + 1440) % 1440
        if diff >= 1320 { diff -= 1440 }
        return diff
    }

    static func minutesOfDay(_ string: String) -> Int? {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]), (0..<24).contains(hours),
              let minutes = Int(parts[1]), (0..<60).contains(minutes)
        else { return nil }
        return hours * 60 + minutes
    }
}

public enum DepartureFilter {
    /// Drops services whose effective departure time has passed, keeping:
    /// - "Delayed" services with no estimate (still expected, however late);
    /// - services whose times don't parse (can't judge, so don't hide);
    /// - cancelled services until their scheduled time passes (worth seeing
    ///   that the 11:38 is cancelled while 11:38 hasn't happened yet).
    public static func upcoming(
        _ departures: [Departure],
        at now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Departure] {
        departures.filter { departure in
            if departure.hasNoEstimate { return true }
            guard let minutes = departure.minutesUntilDeparture(from: now, calendar: calendar) else {
                return true
            }
            return minutes >= 0
        }
    }
}

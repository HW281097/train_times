import Foundation

/// Which way a train through Lea Bridge is heading.
public enum BoardDirection: String, CaseIterable, Sendable {
    /// Southbound toward Stratford (the line's southern terminus from here).
    case stratford
    /// Northbound toward Tottenham Hale / Meridian Water and beyond
    /// (Hertford East, Bishops Stortford, Stansted Airport, Cambridge...).
    case tottenhamHale

    public var displayName: String {
        switch self {
        case .stratford: return "Toward Stratford"
        case .tottenhamHale: return "Toward Tottenham Hale & beyond"
        }
    }
}

/// Direction detection for Lea Bridge (LEB).
///
/// Lea Bridge sits on the two-track Lea Valley line between Stratford (SRA)
/// to the south and Tottenham Hale (TOM) / Meridian Water (MRW) to the north,
/// so every train serves exactly one of two directions. The rules below are
/// mirrored in docs/API_NOTES.md for the Raspberry Pi port — keep both in sync.
public enum LeaBridgeDirections {
    static let stratfordCRS = "SRA"
    static let northboundMarkers: Set<String> = ["TOM", "MRW"]

    /// Rules, in order:
    /// 1. Destination is Stratford → `.stratford`.
    /// 2. Any subsequent calling point is Stratford → `.stratford`
    ///    (covers hypothetical through services).
    /// 3. Destination or any calling point is Tottenham Hale or Meridian
    ///    Water → `.tottenhamHale`.
    /// 4. Fallback: `.tottenhamHale` — every non-Stratford service from
    ///    Lea Bridge heads north.
    public static func direction(of departure: Departure) -> BoardDirection {
        if departure.destinationCRS == stratfordCRS { return .stratford }
        if departure.callingPointCRSCodes.contains(stratfordCRS) { return .stratford }
        return .tottenhamHale
    }

    /// Splits a board into the two direction groups, preserving order.
    public static func grouped(_ departures: [Departure]) -> [BoardDirection: [Departure]] {
        Dictionary(grouping: departures, by: direction(of:))
    }
}

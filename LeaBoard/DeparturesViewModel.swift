import Foundation
import Observation
import DarwinKit

@MainActor
@Observable
final class DeparturesViewModel {
    /// Rows shown per direction section.
    static let rowsPerDirection = 5

    private(set) var stationName = "Lea Bridge"
    private(set) var stratford: [Departure] = []
    private(set) var northbound: [Departure] = []
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    /// True when no config/API key was found — the panel shows setup help.
    private(set) var needsSetup = false

    private var client: DarwinClient?

    /// Demo mode (LEABOARD_DEMO=1) renders canned departures so the UI can
    /// be exercised before an API key exists. The view shows a DEMO badge.
    let isDemo = ProcessInfo.processInfo.environment["LEABOARD_DEMO"] == "1"

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let board = isDemo
                ? DemoBoard.make()
                : try await makeClient().fetchDepartures()
            let upcoming = DepartureFilter.upcoming(board.departures)
            let groups = LeaBridgeDirections.grouped(upcoming)
            stationName = board.stationName
            stratford = Array((groups[.stratford] ?? []).prefix(Self.rowsPerDirection))
            northbound = Array((groups[.tottenhamHale] ?? []).prefix(Self.rowsPerDirection))
            lastUpdated = Date()
            errorMessage = nil
            needsSetup = false
        } catch let error as DarwinError {
            if case .missingConfiguration = error { needsSetup = true }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeClient() throws -> DarwinClient {
        if let client { return client }
        let config = try DarwinConfig.load()
        let client = DarwinClient(config: config)
        self.client = client
        return client
    }
}

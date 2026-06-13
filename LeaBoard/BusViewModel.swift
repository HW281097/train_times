import Foundation
import Observation
import TfLKit

@MainActor
@Observable
final class BusViewModel {
    /// Rows shown per direction section (the panel has room for 3–4).
    static let rowsPerDirection = 4

    private(set) var directionALabel = "Towards Hackney"
    private(set) var directionBLabel = "Towards Walthamstow"
    private(set) var directionA: [BusArrival] = []
    private(set) var directionB: [BusArrival] = []
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    /// True when no `tfl` config was found — the panel shows setup help.
    private(set) var needsSetup = false

    private var client: TfLClient?
    private var config: TfLConfig?

    /// Demo mode (LEABOARD_DEMO=1) renders canned arrivals so the UI can be
    /// exercised before a TfL key exists. The view shows a DEMO badge.
    let isDemo = ProcessInfo.processInfo.environment["LEABOARD_DEMO"] == "1"

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if isDemo {
                let demo = DemoBusBoard.make()
                apply(a: demo.a, b: demo.b, labelA: "Towards Hackney", labelB: "Towards Walthamstow")
            } else {
                let (client, config) = try makeClient()
                async let aBoard = client.fetchArrivals(for: config.directionA)
                async let bBoard = client.fetchArrivals(for: config.directionB)
                let (a, b) = try await (aBoard, bBoard)
                apply(a: a, b: b, labelA: config.directionA.label, labelB: config.directionB.label)
            }
            lastUpdated = Date()
            errorMessage = nil
            needsSetup = false
        } catch let error as TfLError {
            if case .missingConfiguration = error { needsSetup = true }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(a: BusBoard, b: BusBoard, labelA: String, labelB: String) {
        directionALabel = labelA
        directionBLabel = labelB
        directionA = Array(a.arrivals.prefix(Self.rowsPerDirection))
        directionB = Array(b.arrivals.prefix(Self.rowsPerDirection))
    }

    private func makeClient() throws -> (TfLClient, TfLConfig) {
        if let client, let config { return (client, config) }
        let config = try TfLConfig.load()
        let client = TfLClient(config: config)
        self.client = client
        self.config = config
        return (client, config)
    }
}

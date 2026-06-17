import Foundation

/// Configuration for the TfL Unified API bus arrivals.
///
/// Shares the on-disk JSON config with the Darwin/train side
/// (see config.example.json), reading the `tfl` block:
///
///     {
///       "tfl": {
///         "appKey": "<TfL app_key>",
///         "directionA": { "id": "490009131W", "label": "Towards Hackney" },
///         "directionB": { "id": "490009131E", "label": "Towards Walthamstow" }
///       }
///     }
///
/// `appKey` is optional — the API works keyless, just rate-limited.
public struct TfLConfig: Sendable, Equatable {
    /// One configured stop: its NaPTAN id and the section label to show.
    public struct Stop: Sendable, Equatable {
        public let id: String
        public let label: String

        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    /// TfL `app_key`, sent as a query parameter. Optional.
    public let appKey: String?

    /// First direction's stop (e.g. towards Hackney).
    public let directionA: Stop

    /// Second direction's stop (e.g. towards Walthamstow).
    public let directionB: Stop

    /// The Unified API base; never needs versioning in the path.
    public static let baseURL = URL(string: "https://api.tfl.gov.uk")!

    public init(appKey: String?, directionA: Stop, directionB: Stop) {
        self.appKey = appKey
        self.directionA = directionA
        self.directionB = directionB
    }

    /// Both stops, in display order.
    public var stops: [Stop] { [directionA, directionB] }

    /// Loads configuration from, in order of precedence:
    /// 1. Environment variables `TFL_APP_KEY` and the stop pairs
    ///    `TFL_STOP_A_ID`/`TFL_STOP_A_LABEL`, `TFL_STOP_B_ID`/`TFL_STOP_B_LABEL`
    ///    (handy for Xcode schemes and CI). Used when both stop IDs are set.
    /// 2. `~/.config/leaboard/config.json`
    /// 3. `config.json` in the current working directory.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> TfLConfig {
        if let aID = environment["TFL_STOP_A_ID"], !aID.isEmpty,
           let bID = environment["TFL_STOP_B_ID"], !bID.isEmpty {
            return TfLConfig(
                appKey: environment["TFL_APP_KEY"].flatMap { $0.isEmpty ? nil : $0 },
                directionA: Stop(id: aID, label: environment["TFL_STOP_A_LABEL"] ?? "Direction A"),
                directionB: Stop(id: bID, label: environment["TFL_STOP_B_LABEL"] ?? "Direction B")
            )
        }

        let candidates = [
            fileManager.homeDirectoryForCurrentUser
                .appending(path: ".config/leaboard/config.json"),
            URL(filePath: fileManager.currentDirectoryPath)
                .appending(path: "config.json"),
        ]
        for url in candidates where fileManager.fileExists(atPath: url.path) {
            return try load(from: url)
        }

        throw TfLError.missingConfiguration(
            searched: ["$TFL_STOP_A_ID/$TFL_STOP_B_ID"] + candidates.map(\.path)
        )
    }

    /// Loads the `tfl` block from a specific JSON config file.
    public static func load(from url: URL) throws -> TfLConfig {
        struct ConfigFile: Decodable {
            struct TfL: Decodable {
                struct Stop: Decodable { let id: String; let label: String? }
                let appKey: String?
                let directionA: Stop
                let directionB: Stop
            }
            let tfl: TfL?
        }
        let file: ConfigFile
        do {
            file = try JSONDecoder().decode(ConfigFile.self, from: Data(contentsOf: url))
        } catch {
            throw TfLError.invalidConfiguration("\(url.path): \(error.localizedDescription)")
        }
        guard let tfl = file.tfl else {
            throw TfLError.missingConfiguration(searched: [url.path + " (no \"tfl\" block)"])
        }
        guard !tfl.directionA.id.isEmpty, !tfl.directionB.id.isEmpty,
              !tfl.directionA.id.hasPrefix("490…"), !tfl.directionB.id.hasPrefix("490…") else {
            throw TfLError.invalidConfiguration("\(url.path): tfl stop ids are empty or still placeholders")
        }
        let appKey = tfl.appKey.flatMap { key in
            (key.isEmpty || key.hasPrefix("YOUR_")) ? nil : key
        }
        return TfLConfig(
            appKey: appKey,
            directionA: Stop(id: tfl.directionA.id, label: tfl.directionA.label ?? "Direction A"),
            directionB: Stop(id: tfl.directionB.id, label: tfl.directionB.label ?? "Direction B")
        )
    }
}

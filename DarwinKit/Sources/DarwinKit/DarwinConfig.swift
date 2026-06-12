import Foundation

/// Configuration for the Darwin LDBWS REST API.
///
/// The on-disk format is plain JSON shared with the future Raspberry Pi /
/// Python implementation (see config.example.json at the repo root):
///
///     {
///       "apiKey": "<RDM consumer key>",
///       "baseUrl": "https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api/20220120",
///       "crs": "LEB"
///     }
///
/// `baseUrl` and `crs` are optional and default to the values below.
public struct DarwinConfig: Sendable {
    /// Consumer key from the Rail Data Marketplace subscription,
    /// sent as the `x-apikey` header.
    public let apiKey: String

    /// Base URL up to (and excluding) the operation segment, no trailing
    /// slash. NOTE: the `1010-live-departure-board-dep1_2` path segment is
    /// tied to the product version you subscribed to — copy the exact URL
    /// from the product's Specification page on raildata.org.uk.
    public let baseURL: URL

    /// Station the board is for. Lea Bridge = "LEB".
    public let crs: String

    public static let defaultBaseURL = URL(string:
        "https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api/20220120")!

    public static let defaultCRS = "LEB"

    public init(apiKey: String, baseURL: URL = Self.defaultBaseURL, crs: String = Self.defaultCRS) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.crs = crs
    }

    /// Loads configuration from, in order of precedence:
    /// 1. Environment variables `DARWIN_API_KEY` (+ optional `DARWIN_BASE_URL`,
    ///    `DARWIN_CRS`) — handy for Xcode schemes and CI.
    /// 2. `~/.config/leaboard/config.json`
    /// 3. `config.json` in the current working directory.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> DarwinConfig {
        if let key = environment["DARWIN_API_KEY"], !key.isEmpty {
            let base = environment["DARWIN_BASE_URL"].flatMap(URL.init(string:)) ?? defaultBaseURL
            return DarwinConfig(apiKey: key, baseURL: base, crs: environment["DARWIN_CRS"] ?? defaultCRS)
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

        throw DarwinError.missingConfiguration(
            searched: ["$DARWIN_API_KEY"] + candidates.map(\.path)
        )
    }

    /// Loads configuration from a specific JSON file.
    public static func load(from url: URL) throws -> DarwinConfig {
        struct ConfigFile: Decodable {
            let apiKey: String
            let baseUrl: String?
            let crs: String?
        }
        let file: ConfigFile
        do {
            file = try JSONDecoder().decode(ConfigFile.self, from: Data(contentsOf: url))
        } catch {
            throw DarwinError.invalidConfiguration("\(url.path): \(error.localizedDescription)")
        }
        guard !file.apiKey.isEmpty, !file.apiKey.hasPrefix("YOUR_") else {
            throw DarwinError.invalidConfiguration("\(url.path): apiKey is empty or still the placeholder")
        }
        let base: URL
        if let baseString = file.baseUrl {
            guard let parsed = URL(string: baseString) else {
                throw DarwinError.invalidConfiguration("\(url.path): baseUrl is not a valid URL")
            }
            base = parsed
        } else {
            base = defaultBaseURL
        }
        return DarwinConfig(apiKey: file.apiKey, baseURL: base, crs: file.crs ?? defaultCRS)
    }
}

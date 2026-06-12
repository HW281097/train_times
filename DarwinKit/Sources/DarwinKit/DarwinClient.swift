import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the Darwin Live Departure Board REST API
/// (LDBWS via the Rail Data Marketplace).
///
/// Endpoint and auth details are documented in docs/API_NOTES.md, which is
/// the spec for the Raspberry Pi port — keep it in sync with this file.
public actor DarwinClient {
    private let config: DarwinConfig
    private let session: URLSession

    public init(config: DarwinConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Fetches the departure board (with calling points) for the configured
    /// station. An empty `departures` array is a normal result late at night.
    ///
    /// - Parameters:
    ///   - numRows: Maximum services to return (API accepts 1...150).
    ///   - timeWindowMinutes: How far ahead to look (API accepts up to 120).
    public func fetchDepartures(
        numRows: Int = 12,
        timeWindowMinutes: Int = 120
    ) async throws -> DepartureBoard {
        var components = URLComponents(
            url: config.baseURL.appending(path: "GetDepBoardWithDetails/\(config.crs)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "numRows", value: String(numRows)),
            URLQueryItem(name: "timeWindow", value: String(timeWindowMinutes)),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(config.apiKey, forHTTPHeaderField: "x-apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw DarwinError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DarwinError.unexpectedResponse("Non-HTTP response")
        }
        switch http.statusCode {
        case 200:
            return try DepartureBoard.decode(data)
        case 401, 403:
            throw DarwinError.unauthorized
        case 429:
            throw DarwinError.rateLimited
        default:
            throw DarwinError.serverError(statusCode: http.statusCode)
        }
    }
}

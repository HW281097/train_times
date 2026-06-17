import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the TfL Unified API bus arrivals
/// (`GET /StopPoint/{naptanId}/Arrivals`).
///
/// Endpoint and auth details are documented in docs/TFL_API_NOTES.md, which is
/// the spec for the Raspberry Pi port — keep it in sync with this file.
public actor TfLClient {
    private let config: TfLConfig
    private let session: URLSession

    public init(config: TfLConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Fetches the arrivals board for one configured stop (one direction).
    /// An empty `arrivals` array is a normal result, not an error.
    public func fetchArrivals(for stop: TfLConfig.Stop) async throws -> BusBoard {
        var components = URLComponents(
            url: TfLConfig.baseURL.appending(path: "StopPoint/\(stop.id)/Arrivals"),
            resolvingAgainstBaseURL: false
        )!
        if let appKey = config.appKey {
            components.queryItems = [URLQueryItem(name: "app_key", value: appKey)]
        }

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Send an explicit User-Agent: edge/CDNs commonly 403 default client
        // UAs (see TFL_API_NOTES.md §2.2).
        request.setValue("LeaBoard/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw TfLError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TfLError.unexpectedResponse("Non-HTTP response")
        }
        switch http.statusCode {
        case 200:
            return try BusBoard.decode(data, stopId: stop.id, fallbackStopName: stop.label)
        case 401, 403:
            throw TfLError.unauthorized
        case 429:
            throw TfLError.rateLimited
        default:
            throw TfLError.serverError(statusCode: http.statusCode)
        }
    }
}

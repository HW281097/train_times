import Foundation

public enum DarwinError: Error, LocalizedError {
    /// No usable configuration found. Associated value lists the locations
    /// that were searched, for display in setup instructions.
    case missingConfiguration(searched: [String])

    /// The config file existed but couldn't be parsed.
    case invalidConfiguration(String)

    /// Network-level failure (offline, DNS, timeout).
    case network(URLError)

    /// The API rejected the key (HTTP 401/403) — bad, expired, or
    /// not-yet-approved subscription.
    case unauthorized

    /// Too many requests (HTTP 429).
    case rateLimited

    /// Any other non-200 status.
    case serverError(statusCode: Int)

    /// 200 OK but the body wasn't the JSON shape we expect.
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration(let searched):
            return "No API key configured. Searched: \(searched.joined(separator: ", ")). See README for setup."
        case .invalidConfiguration(let detail):
            return "Config file is invalid: \(detail)"
        case .network(let urlError):
            return "Network error: \(urlError.localizedDescription)"
        case .unauthorized:
            return "API key rejected. Check the consumer key and that your Rail Data Marketplace subscription is active."
        case .rateLimited:
            return "Rate limited by the API. Try again shortly."
        case .serverError(let statusCode):
            return "Darwin API returned HTTP \(statusCode)."
        case .unexpectedResponse(let detail):
            return "Unexpected API response: \(detail)"
        }
    }
}

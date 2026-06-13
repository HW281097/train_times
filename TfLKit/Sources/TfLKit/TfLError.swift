import Foundation

public enum TfLError: Error, LocalizedError {
    /// No usable bus configuration found (no `tfl` block / stop IDs).
    /// Associated value lists the locations searched, for setup instructions.
    case missingConfiguration(searched: [String])

    /// The config file existed but the `tfl` block couldn't be parsed.
    case invalidConfiguration(String)

    /// Network-level failure (offline, DNS, timeout).
    case network(URLError)

    /// The API rejected the key (HTTP 401/403) — only relevant when a key is set.
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
            return "No bus stops configured. Searched: \(searched.joined(separator: ", ")). See README for the tfl config block."
        case .invalidConfiguration(let detail):
            return "Bus config is invalid: \(detail)"
        case .network(let urlError):
            return "Network error: \(urlError.localizedDescription)"
        case .unauthorized:
            return "TfL API key rejected. Check the app_key in your config's tfl block."
        case .rateLimited:
            return "Rate limited by the TfL API. Try again shortly."
        case .serverError(let statusCode):
            return "TfL API returned HTTP \(statusCode)."
        case .unexpectedResponse(let detail):
            return "Unexpected API response: \(detail)"
        }
    }
}

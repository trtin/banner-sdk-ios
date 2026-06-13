import Foundation

public enum TrackEvent: String, Sendable {
    case impression
    case click
}

public enum BannerError: Error, Sendable {
    case invalidURL
    case notHTTP
    case httpStatus(Int)
}

/// Thin client over the backend embed API. Mirrors the web SDK (backend/apps/api/src/embed/sdk.ts):
///   - resolve:  GET <baseURL>?site=&placement=
///   - track:    GET <baseURL>/track?b=&t=&v=&_=
///
/// `baseURL` must point at the embed root, e.g. `https://yourhost/api/embed`.
public final class BannerClient: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession

    /// Stable per-install visitor id, mirroring the web SDK's `localStorage['bnr_vid']`.
    public let visitorId: String

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.visitorId = BannerClient.loadVisitorId()
    }

    /// Convenience: build a client from a host base like `https://yourhost` (appends `/api/embed`).
    public convenience init?(host: String, session: URLSession = .shared) {
        guard var comps = URLComponents(string: host) else { return nil }
        comps.path = (comps.path as NSString).appendingPathComponent("/api/embed")
        guard let url = comps.url else { return nil }
        self.init(baseURL: url, session: session)
    }

    public func resolve(site: String, placement: String) async throws -> EmbedPayload {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BannerError.invalidURL
        }
        comps.queryItems = [
            URLQueryItem(name: "site", value: site),
            URLQueryItem(name: "placement", value: placement),
        ]
        guard let url = comps.url else { throw BannerError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BannerError.notHTTP }
        guard http.statusCode == 200 else { throw BannerError.httpStatus(http.statusCode) }
        return try JSONDecoder().decode(EmbedPayload.self, from: data)
    }

    /// Fire-and-forget tracking beacon. Failures are intentionally swallowed —
    /// tracking must never block or surface to the host app, matching the web SDK.
    public func track(bannerId: String, event: TrackEvent) {
        guard var comps = URLComponents(
            url: baseURL.appendingPathComponent("track"),
            resolvingAgainstBaseURL: false
        ) else { return }
        comps.queryItems = [
            URLQueryItem(name: "b", value: bannerId),
            URLQueryItem(name: "t", value: event.rawValue),
            URLQueryItem(name: "v", value: visitorId),
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000))),
        ]
        guard let url = comps.url else { return }
        session.dataTask(with: url).resume()
    }

    // MARK: - Visitor id

    private static let visitorKey = "bnr_vid"

    private static func loadVisitorId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: visitorKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: visitorKey)
        return fresh
    }
}

import Foundation

enum APIClientError: LocalizedError {
    case emptyEnvelope
    case httpStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .emptyEnvelope: return "服务器返回了空响应"
        case .httpStatus(let code): return "HTTP \(code)"
        case .decoding(let inner): return "解析失败：\(inner)"
        }
    }
}

final class APIClient: @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]  // bypass system proxy for LAN/Tailscale
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    func health() async throws -> Health {
        try await getEnvelope("/api/health")
    }

    func systemInfo() async throws -> SystemInfo {
        try await getEnvelope("/api/system/info")
    }

    func detections() async throws -> DetectionsResponse {
        try await getRaw("/api/detections")
    }

    func stats() async throws -> Stats {
        try await getRaw("/api/stats")
    }

    func vlmAnalysis() async throws -> VLMAnalysis {
        let resp: VLMResponse = try await getRaw("/api/vlm_analysis")
        return resp.analysis
    }

    func feedingEvents() async throws -> FeedingSummary {
        try await getEnvelope("/api/feeding_events")
    }

    func activitySummary() async throws -> ActivitySummary {
        try await getEnvelope("/api/activity_summary")
    }

    func videoFeedURL() -> URL {
        baseURL.appendingPathComponent("/video_feed")
    }

    func visualization3DURL(azim: Double, elev: Double) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/3d_visualization"),
                                  resolvingAgainstBaseURL: false) ?? URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "azim", value: String(format: "%.1f", azim)),
            URLQueryItem(name: "elev", value: String(format: "%.1f", elev)),
        ]
        return comps.url ?? baseURL.appendingPathComponent("/api/3d_visualization")
    }

    func visualization3DImageData(azim: Double, elev: Double) async throws -> Data {
        var req = URLRequest(url: visualization3DURL(azim: azim, elev: elev))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return data
    }

    private func getRaw<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await session.data(from: urlFor(path))
        try validate(response)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }

    private func getEnvelope<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await session.data(from: urlFor(path))
        try validate(response)
        let env: APIEnvelope<T>
        do {
            env = try decoder.decode(APIEnvelope<T>.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
        guard env.ok, let value = env.data else {
            throw APIClientError.emptyEnvelope
        }
        return value
    }

    private func urlFor(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return baseURL.appendingPathComponent(String(path.dropFirst()))
        }
        return baseURL.appendingPathComponent(path)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.httpStatus(0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIClientError.httpStatus(http.statusCode)
        }
    }
}

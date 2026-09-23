import Foundation

public enum APIClientError: LocalizedError {
    case emptyEnvelope
    case httpStatus(Int)
    case decoding(Error)

    public var errorDescription: String? {
        switch self {
        case .emptyEnvelope: return "服务器返回了空响应"
        case .httpStatus(let code): return "HTTP \(code)"
        case .decoding(let inner): return "解析失败：\(inner)"
        }
    }
}

public final class APIClient: @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    public func health() async throws -> Health {
        try await getEnvelope("/api/health")
    }

    public func systemInfo() async throws -> SystemInfo {
        try await getEnvelope("/api/system/info")
    }

    public func detections() async throws -> DetectionsResponse {
        try await getRaw("/api/detections")
    }

    public func stats() async throws -> Stats {
        try await getRaw("/api/stats")
    }

    public func vlmAnalysis() async throws -> VLMAnalysis {
        let resp: VLMResponse = try await getRaw("/api/vlm_analysis")
        return resp.analysis
    }

    public func feedingEvents() async throws -> FeedingSummary {
        try await getEnvelope("/api/feeding_events")
    }

    public func activitySummary() async throws -> ActivitySummary {
        try await getEnvelope("/api/activity_summary")
    }

    public func videoFeedURL() -> URL {
        baseURL.appendingPathComponent("/video_feed")
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

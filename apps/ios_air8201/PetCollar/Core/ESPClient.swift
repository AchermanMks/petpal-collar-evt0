import Foundation

enum ESPClientError: LocalizedError {
    case invalidHost
    case httpStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidHost: return "ESP 地址格式不合法"
        case .httpStatus(let code): return "HTTP \(code)"
        case .decoding(let inner): return "解析失败：\(inner)"
        }
    }
}

struct ESPStatus: Codable, Equatable, Sendable {
    struct Chip: Codable, Equatable, Sendable {
        let model: String
        let cores: Int
        let rev: String
        let flashMb: Int
        enum CodingKeys: String, CodingKey {
            case model, cores, rev
            case flashMb = "flash_mb"
        }
    }

    struct Memory: Codable, Equatable, Sendable {
        let heapFree: Int
        let heapMin: Int
        let psramFree: Int
        let psramTotal: Int
        enum CodingKeys: String, CodingKey {
            case heapFree = "heap_free"
            case heapMin = "heap_min"
            case psramFree = "psram_free"
            case psramTotal = "psram_total"
        }
    }

    struct WiFi: Codable, Equatable, Sendable {
        let ssid: String
        let rssi: Int
        let ch: Int
        let ip: String
        let mac: String
        let bssid: String
    }

    struct Battery: Codable, Equatable, Sendable {
        let ok: Bool
        let v: Double
        let soc: Double
    }

    let chip: Chip
    let mem: Memory
    let tempC: Double
    let uptimeS: Int
    let wifi: WiFi
    let batt: Battery
    let sim7670: String

    enum CodingKeys: String, CodingKey {
        case chip, mem, wifi, batt, sim7670
        case tempC = "temp_c"
        case uptimeS = "uptime_s"
    }
}

final class ESPClient: @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.protocolClasses = [AirHardwareProtocol.self]
        config.timeoutIntervalForRequest = 75
        config.timeoutIntervalForResource = 75
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // ESP 是 HTTP/1.1，禁用 HTTP/3 / multipath 之类的性能开关在 LAN 上没用
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    /// 接受 "esp32-led.local"、"192.168.5.x"、"http://...:80" 等输入，统一加 http:// 前缀。
    static func makeBaseURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "http://\(trimmed)"
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }

    /// 给灯光控制用：:81 是 CameraWebServer（只跑 MJPEG），/led/* 全 404。
    /// 把端口为 81 的输入归一化到 :80。
    static func makeLEDBaseURL(from input: String) -> URL? {
        guard let url = makeBaseURL(from: input) else { return nil }
        if url.port == 81, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.port = nil
            return comps.url
        }
        return url
    }

    func setOn() async throws {
        try await getPlain("/led/on")
    }

    /// 呼吸灯（Air8201G 固件软件 PWM，3 s 一个周期，持续 5 分钟或直到关灯）
    func setBreathe() async throws {
        try await getPlain("/led/breathe")
    }
    func setOff() async throws {
        try await getPlain("/led/off")
    }

    func setRGB(r: Int, g: Int, b: Int) async throws {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/led/rgb"),
            resolvingAgainstBaseURL: false
        ) ?? URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "r", value: String(clampByte(r))),
            URLQueryItem(name: "g", value: String(clampByte(g))),
            URLQueryItem(name: "b", value: String(clampByte(b))),
        ]
        guard let url = comps.url else { throw ESPClientError.invalidHost }
        let (_, response) = try await session.data(from: url)
        try validate(response)
    }

    func status() async throws -> ESPStatus {
        let url = baseURL.appendingPathComponent("/api/status")
        let (data, response) = try await session.data(from: url)
        try validate(response)
        do {
            return try JSONDecoder().decode(ESPStatus.self, from: data)
        } catch {
            throw ESPClientError.decoding(error)
        }
    }

    // MARK: - Speaker (MAX98357A via I2S)

    func speakerBeep(freq: Int = 1000, duration: Int = 2000, volume: Int = 80) async throws {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/speaker/beep"),
            resolvingAgainstBaseURL: false
        ) ?? URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "freq", value: String(max(100, min(8000, freq)))),
            URLQueryItem(name: "duration", value: String(max(100, min(10000, duration)))),
            URLQueryItem(name: "volume", value: String(max(0, min(100, volume)))),
        ]
        guard let url = comps.url else { throw ESPClientError.invalidHost }
        let (_, response) = try await session.data(from: url)
        try validate(response)
    }

    func speakerMeow(volume: Int = 80) async throws {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/speaker/meow"),
            resolvingAgainstBaseURL: false
        ) ?? URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "volume", value: String(max(0, min(100, volume)))),
        ]
        guard let url = comps.url else { throw ESPClientError.invalidHost }
        let (_, response) = try await session.data(from: url)
        try validate(response)
    }

    func speakerStop() async throws {
        try await getPlain("/speaker/stop")
    }

    func speakerTest() async throws {
        try await getPlain("/speaker/test")
    }

    // MARK: - Speaker File Management (LittleFS)

    struct SpeakerFile: Decodable, Sendable {
        let name: String
        let bytes: Int
    }

    struct SpeakerFilesResponse: Decodable, Sendable {
        let files: [SpeakerFile]
        let total: Int
        let used: Int
    }

    func speakerFiles() async throws -> SpeakerFilesResponse {
        let url = baseURL.appendingPathComponent("/speaker/files")
        let (data, response) = try await session.data(from: url)
        try validate(response)
        do {
            return try JSONDecoder().decode(SpeakerFilesResponse.self, from: data)
        } catch {
            throw ESPClientError.decoding(error)
        }
    }

    func speakerPlayFile(name: String, volume: Int = 80) async throws {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/speaker/play"),
            resolvingAgainstBaseURL: false
        ) ?? URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "volume", value: String(max(0, min(100, volume)))),
        ]
        guard let url = comps.url else { throw ESPClientError.invalidHost }
        let (_, response) = try await session.data(from: url)
        try validate(response)
    }

    func speakerUpload(name: String, pcmData: Data) async throws {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/speaker/upload"),
            resolvingAgainstBaseURL: false
        ) ?? URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "name", value: name),
        ]
        guard let url = comps.url else { throw ESPClientError.invalidHost }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = pcmData
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func speakerDeleteFile(name: String) async throws {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/speaker/delete"),
            resolvingAgainstBaseURL: false
        ) ?? URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "name", value: name),
        ]
        guard let url = comps.url else { throw ESPClientError.invalidHost }
        let (_, response) = try await session.data(from: url)
        try validate(response)
    }

    // MARK: - GPS

    struct GPSData: Decodable, Sendable {
        let fix: Bool
        let lat: Double
        let lng: Double
        let alt: Double
        let speedKmh: Double
        let sats: Int
        let ageMs: Int
        let datetime: String
        // 诊断字段，旧固件没有，可选
        let charsTotal: Int?
        let sentencesWithFix: Int?
        let lastNmeaAgeMs: Int?  // 0xFFFFFFFF (4294967295) = 从未收到 NMEA

        enum CodingKeys: String, CodingKey {
            case fix, lat, lng, alt, sats, datetime
            case speedKmh = "speed_kmh"
            case ageMs = "age_ms"
            case charsTotal = "chars_total"
            case sentencesWithFix = "sentences_with_fix"
            case lastNmeaAgeMs = "last_nmea_age_ms"
        }
    }

    // MARK: - Motor

    struct MotorStatus: Decodable, Sendable {
        let on: Bool
    }

    func motorVibrate(intensity: Int = 255, duration: Int = 500) async throws {
        guard let url = URL(string: "\(baseURL.absoluteString)/motor/vibrate?intensity=\(intensity)&duration=\(duration)") else { return }
        let (_, response) = try await session.data(from: url)
        try validate(response)
    }

    func motorStop() async throws {
        try await getPlain("/motor/stop")
    }

    func motorStatus() async throws -> MotorStatus {
        let url = baseURL.appendingPathComponent("/motor/status")
        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try JSONDecoder().decode(MotorStatus.self, from: data)
    }

    // MARK: - Arc Igniter (台面 demo · 严禁接触动物)

    struct ArcStatus: Decodable, Sendable {
        let on: Bool
        let count: UInt32
        let cooldownRemainMs: UInt32
        let maxDurationMs: UInt32
        let cooldownMs: UInt32

        enum CodingKeys: String, CodingKey {
            case on, count
            case cooldownRemainMs = "cooldown_remain_ms"
            case maxDurationMs = "max_duration_ms"
            case cooldownMs = "cooldown_ms"
        }
    }

    struct ArcFireResult: Decodable, Sendable {
        let ok: Bool
        let duration: Int?
        let count: UInt32?
        let err: String?
        let remainMs: UInt32?

        enum CodingKeys: String, CodingKey {
            case ok, duration, count, err
            case remainMs = "remain_ms"
        }
    }

    /// 触发一次电弧。成功返回 ok=true，被 busy/cooldown 挡住时 ESP 返回 429，
    /// 这里把 429 也当成"非错误的业务回执"解析出来给 UI 显示原因。
    func arcFire(duration: Int = 200) async throws -> ArcFireResult {
        guard let url = URL(string: "\(baseURL.absoluteString)/arc/fire?duration=\(duration)") else {
            throw ESPClientError.httpStatus(0)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw ESPClientError.httpStatus(0) }
        // 200 与 429 都解 JSON；其它状态作错误抛
        if http.statusCode == 200 || http.statusCode == 429 {
            return try JSONDecoder().decode(ArcFireResult.self, from: data)
        }
        throw ESPClientError.httpStatus(http.statusCode)
    }

    func arcStop() async throws {
        try await getPlain("/arc/stop")
    }

    func arcStatus() async throws -> ArcStatus {
        let url = baseURL.appendingPathComponent("/arc/status")
        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try JSONDecoder().decode(ArcStatus.self, from: data)
    }

    // MARK: - GPS

    func gps() async throws -> GPSData {
        let url = baseURL.appendingPathComponent("/api/gps")
        let (data, response) = try await session.data(from: url)
        try validate(response)
        do {
            return try JSONDecoder().decode(GPSData.self, from: data)
        } catch {
            throw ESPClientError.decoding(error)
        }
    }

    private func getPlain(_ path: String) async throws {
        let url = baseURL.appendingPathComponent(path)
        let (_, response) = try await session.data(from: url)
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ESPClientError.httpStatus(0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ESPClientError.httpStatus(http.statusCode)
        }
    }

    private func clampByte(_ v: Int) -> Int { max(0, min(255, v)) }
}

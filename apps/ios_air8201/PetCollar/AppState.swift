import Foundation
import Observation
import os.log

private let dbg = Logger(subsystem: "PetCollar", category: "AppState")

enum BackendEndpointError: LocalizedError {
    case empty
    case invalidURL
    case unsupportedScheme
    case invalidHost
    case invalidPort
    case unexpectedPath

    var errorDescription: String? {
        switch self {
        case .empty: return "请输入后端服务器地址"
        case .invalidURL: return "服务器地址格式不正确"
        case .unsupportedScheme: return "服务器地址必须使用 http 或 https"
        case .invalidHost: return "服务器 IP 或主机名不正确"
        case .invalidPort: return "服务器端口不正确"
        case .unexpectedPath: return "只需填写服务器地址，不要附加接口路径"
        }
    }
}

/// Linux 真后端的统一入口。
///
/// Tailscale MagicDNS 主机名不依赖家庭网络的 DHCP 地址，作为真机默认入口；
/// 当前 Tailscale IP、Avahi `.local` 主机名和局域网 IP 依次作为兜底。
/// 这里绝不指向 mock_server。
enum BackendEndpoint {
    static let preferredBaseURLString = "http://jialiang-battle-ax-h610m-a-wifi.tail99e2ea.ts.net:5008"
    static let tailscaleFallbackBaseURLString = "http://100.81.166.42:5008"
    static let localBaseURLString = "http://jialiang-BATTLE-AX-H610M-A-WIFI.local:5008"
    static let lanFallbackBaseURLString = "http://192.168.5.122:5008"

    private static let staleHosts: Set<String> = [
        "100.108.197.12", // 已失效的旧 Tailscale 地址
        "192.168.5.40",  // Mac 测试服务器地址
        "192.168.5.48",  // 曾误填的旧地址
        "127.0.0.1",
        "localhost",
    ]

    static func migratedSavedURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return preferredBaseURLString }

        // 曾在真机中出现过的 `IP.端口` 错写无法可靠解析，直接迁移到 Linux 主机名。
        if trimmed.lowercased() == "http://192.168.5.48.5008" {
            return preferredBaseURLString
        }

        guard let url = try? normalizedURL(from: trimmed),
              let host = url.host?.lowercased()
        else {
            return preferredBaseURLString
        }
        return staleHosts.contains(host) ? preferredBaseURLString : url.absoluteString
    }

    static func connectionCandidates(from raw: String) throws -> [URL] {
        let requested = try normalizedURL(from: raw)
        let requestedHost = requested.host?.lowercased()
        let knownURLs = try [
            preferredBaseURLString,
            tailscaleFallbackBaseURLString,
            localBaseURLString,
            lanFallbackBaseURLString,
        ].map { try normalizedURL(from: $0) }
        let linuxHosts = Set(knownURLs.compactMap { $0.host?.lowercased() })

        var candidates = [requested]
        if let requestedHost, linuxHosts.contains(requestedHost) {
            candidates.append(contentsOf: knownURLs)
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.absoluteString).inserted }
    }

    static func normalizedURL(from raw: String) throws -> URL {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw BackendEndpointError.empty }
        if !value.contains("://") { value = "http://\(value)" }

        guard var components = URLComponents(string: value) else {
            throw BackendEndpointError.invalidURL
        }
        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw BackendEndpointError.unsupportedScheme
        }
        guard let host = components.host, !host.isEmpty else {
            throw BackendEndpointError.invalidHost
        }
        guard components.path.isEmpty || components.path == "/",
              components.query == nil,
              components.fragment == nil
        else {
            throw BackendEndpointError.unexpectedPath
        }

        // URLComponents 会把 `192.168.5.48.5008` 当普通域名；对纯数字点分地址再做 IPv4 校验。
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            let octets = host.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4,
                  octets.allSatisfy({ part in
                      guard let value = Int(part) else { return false }
                      return (0...255).contains(value)
                  })
            else {
                throw BackendEndpointError.invalidHost
            }
        }

        if components.port == nil { components.port = 5008 }
        guard let port = components.port, (1...65535).contains(port) else {
            throw BackendEndpointError.invalidPort
        }

        components.scheme = scheme
        components.path = ""
        guard let url = components.url else { throw BackendEndpointError.invalidURL }
        return url
    }
}

@MainActor
@Observable
final class AppState {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(String)  // associated: last error reason
        case failed(String)
    }

    var baseURL: URL?
    var status: Status = .disconnected
    var systemInfo: SystemInfo?
    var health: Health?

    private(set) var api: APIClient?

    /// Last successfully-used URL string, so reconnect can retry the same target.
    private var lastURLString: String?

    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    private let heartbeatInterval: Duration = .seconds(10)
    private let reconnectInitialDelay: Duration = .seconds(1)
    private let reconnectMaxDelay: Duration = .seconds(30)

    @discardableResult
    func connect(urlString: String) async -> Bool {
        status = .connecting
        cancelRecovery()
        let candidates: [URL]
        do {
            candidates = try BackendEndpoint.connectionCandidates(from: urlString)
        } catch {
            status = .failed(error.localizedDescription)
            return false
        }
        lastURLString = candidates.first?.absoluteString

        var lastError: Error?
        for url in candidates {
            let client = APIClient(baseURL: url)
            do {
                let health = try await client.health()
                let info = try await client.systemInfo()
                self.baseURL = url
                self.api = client
                self.health = health
                self.systemInfo = info
                self.lastURLString = url.absoluteString
                self.status = .connected
                dbg.info("connected to \(url.absoluteString, privacy: .public)")
                startHeartbeat()
                return true
            } catch {
                lastError = error
                dbg.error("connect failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        self.status = .failed(lastError.map(humanMessage(for:)) ?? "无法连接到 Linux 后端")
        return false
    }

    func disconnect() {
        cancelRecovery()
        baseURL = nil
        api = nil
        health = nil
        systemInfo = nil
        lastURLString = nil
        status = .disconnected
        MJPEGStream.backendFeed.stop()
        dbg.info("disconnected (manual)")
    }

    /// App 启动 / 回前台时调。若有历史 URL 且当前未连接，自动连上去。
    @discardableResult
    func autoConnectIfPossible(savedURL: String) async -> Bool {
        let trimmed = savedURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        switch status {
        case .disconnected, .failed:
            dbg.info("auto-connect triggered for \(trimmed, privacy: .public)")
            return await connect(urlString: trimmed)
        case .connected:
            return true
        case .connecting, .reconnecting:
            return false
        }
    }

    /// 回前台时调用。若处于 .failed 用上次的 URL 再试一次。
    func refreshOnForeground() async {
        if case .failed = status, let last = lastURLString {
            await connect(urlString: last)
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.heartbeatInterval)
                guard !Task.isCancelled else { return }
                await self.pulse()
            }
        }
    }

    private func pulse() async {
        guard case .connected = status, let api else { return }
        do {
            let h = try await api.health()
            self.health = h
        } catch {
            dbg.error("heartbeat failed: \(error.localizedDescription, privacy: .public)")
            let msg = humanMessage(for: error)
            status = .reconnecting(msg)
            heartbeatTask?.cancel()
            heartbeatTask = nil
            startReconnect(reason: msg)
        }
    }

    // MARK: - Reconnect

    private func startReconnect(reason: String) {
        guard let urlString = lastURLString else {
            status = .failed(reason)
            return
        }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            var delay = self.reconnectInitialDelay
            var attempt = 0
            while !Task.isCancelled {
                attempt += 1
                dbg.info("reconnect attempt #\(attempt, privacy: .public)")
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                if case .reconnecting = self.status {
                    if await self.tryReconnect(urlString: urlString) {
                        dbg.info("reconnected after \(attempt, privacy: .public) attempts")
                        return
                    }
                } else {
                    return
                }
                delay = min(delay * 2, self.reconnectMaxDelay)
            }
        }
    }

    private func tryReconnect(urlString: String) async -> Bool {
        guard let urls = try? BackendEndpoint.connectionCandidates(from: urlString) else {
            status = .failed("URL 解析失败")
            return false
        }

        var lastError: Error?
        for url in urls {
            let client = APIClient(baseURL: url)
            do {
                let h = try await client.health()
                let info = try await client.systemInfo()
                self.baseURL = url
                self.api = client
                self.health = h
                self.systemInfo = info
                self.lastURLString = url.absoluteString
                self.status = .connected
                startHeartbeat()
                return true
            } catch {
                lastError = error
            }
        }
        status = .reconnecting(lastError.map(humanMessage(for:)) ?? "无法连接到 Linux 后端")
        return false
    }

    private func cancelRecovery() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    // MARK: - Error translation

    private func humanMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost: return "无法连接到服务器（拒绝连接）"
            case .timedOut: return "连接超时（检查 IP 和局域网）"
            case .cannotFindHost: return "找不到主机"
            case .notConnectedToInternet: return "网络未连接"
            case .networkConnectionLost: return "网络连接中断"
            default: return urlError.localizedDescription
            }
        }
        if let api = error as? APIClientError {
            return api.localizedDescription
        }
        return error.localizedDescription
    }
}

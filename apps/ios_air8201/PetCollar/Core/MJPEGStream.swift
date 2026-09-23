import UIKit
import Foundation
import Observation
import os.log

/// Streams an MJPEG `multipart/x-mixed-replace` endpoint via
/// `URLSessionDataDelegate` and publishes the latest decoded UIImage.
///
/// We use the delegate API instead of `URLSession.bytes(from:)` because the
/// latter has been observed to buffer or mis-handle `multipart/x-mixed-replace`,
/// leaving the AsyncSequence effectively empty even though the server is
/// streaming fine (confirmed via curl).
///
/// Frame boundaries are detected with JPEG SOI (0xFFD8) and EOI (0xFFD9).
/// 流中断时自动指数退避重连（1s → 2s → ... → 10s），首帧收到后退避重置。
@MainActor
@Observable
final class MJPEGStream {
    /// ESP32-CAM stream (persistent — never disconnect on view transitions).
    static let espCamera = MJPEGStream()
    /// Backend video feed (from realtime_pet_monitor).
    static let backendFeed = MJPEGStream()

    var currentFrame: UIImage?
    var isRunning: Bool = false
    var lastError: String?
    var isReconnecting: Bool = false
    /// 流服务器死了但主机本身还在线（典型 ESP32-CAM 现象：:80 通而 :81 立刻 RST）。
    /// UI 用这个状态弹"请按 RST 重启设备"提示，比模糊的"网络连接中断"更可操作。
    var streamServerDown: Bool = false
    private(set) var framesReceived: Int = 0
    private(set) var bytesReceived: Int = 0

    private var reader: Reader?
    private(set) var currentURL: URL?
    private var backoffSec: Double = 1
    private let maxBackoffSec: Double = 10
    private var restartTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var freshnessTask: Task<Void,Never>?

    /// Start streaming if not already connected to the same URL.
    /// ESP32-CAM only supports 1 client — never tear down a working connection.
    func ensureRunning(url: URL) {
        if isRunning, currentURL == url { return }
        stop()
        currentURL = url
        backoffSec = 1
        isRunning = true
        isReconnecting = false
        lastError = nil
        streamServerDown = false
        spawnReader(url: url)
    }

    func stop() {
        freshnessTask?.cancel(); freshnessTask=nil
        isRunning = false
        isReconnecting = false
        streamServerDown = false
        restartTask?.cancel()
        restartTask = nil
        probeTask?.cancel()
        probeTask = nil
        reader?.cancel()
        reader = nil
        currentURL = nil
        currentFrame = nil
        framesReceived = 0
        bytesReceived = 0
    }

    private func spawnReader(url: URL) {
        let r = Reader(owner: self, airCamera: self === MJPEGStream.espCamera)
        reader = r
        r.start(url: url)
    }

    fileprivate func onFrame(_ data: Data) {
        guard isRunning else { return }
        guard let image = UIImage(data: data) else { return }
        self.currentFrame = image
        self.framesReceived &+= 1
        // Successful frame → reset backoff & 清掉"设备需重启"标记
        if backoffSec != 1 { backoffSec = 1 }
        if isReconnecting { isReconnecting = false }
        if lastError != nil { lastError = nil }
        if streamServerDown { streamServerDown = false }
        if self === MJPEGStream.espCamera {
            freshnessTask?.cancel()
            freshnessTask=Task { [weak self] in
                try? await Task.sleep(for:.seconds(10))
                guard !Task.isCancelled,let self,self.isRunning else { return }
                self.currentFrame=nil
                self.lastError="10s 未收到新画面，等待摄像头响应"
            }
        }
    }

    fileprivate func onBytes(_ count: Int) {
        self.bytesReceived &+= count
    }

    fileprivate func onError(_ message: String) {
        self.lastError = message
    }

    /// Called by Reader when URLSessionTask completes (with or without error).
    /// If still supposed to be running (not stopped by user), schedule a retry
    /// with exponential backoff.
    fileprivate func onStreamEnded(error: Error?) {
        freshnessTask?.cancel(); freshnessTask=nil
        reader = nil
        guard isRunning, let url = currentURL else { return }
        if self === MJPEGStream.espCamera { currentFrame = nil } // A frozen image is not LIVE.
        let delay = backoffSec
        backoffSec = min(backoffSec * 2, maxBackoffSec)
        let reason = error?.localizedDescription ?? "流结束"
        lastError = "\(reason) · \(Int(delay))s 后重连"
        isReconnecting = true
        // 错误信号像 "立刻 RST / connection lost / 还没收过帧" 时，去探一下主机 :80
        // 区分"设备整机离线"（无需提示）vs"主控活流死"（需要提示按 RST 重启）
        if shouldProbeServerHealth(error: error) {
            schedulePeerHealthProbe(streamURL: url)
        }
        restartTask?.cancel()
        restartTask = Task { [weak self, url, delay] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isRunning else { return }
                self.spawnReader(url: url)
            }
        }
    }

    private func shouldProbeServerHealth(error: Error?) -> Bool {
        if self === MJPEGStream.espCamera { return false } // Never probe the previous ESP32 host.
        // 已经收过帧（说明流之前是活的）+ 现在断了 → 也探一下；从未收过帧 + 立刻断 → 必探。
        guard let error else { return false }
        let urlError = error as? URLError
        let suspicious: Set<URLError.Code> = [
            .networkConnectionLost,  // RST
            .cannotConnectToHost,    // 连接被拒
        ]
        if let code = urlError?.code, suspicious.contains(code) { return true }
        // 没收任何字节就结束的也可疑
        return bytesReceived == 0
    }

    /// 同 host 但走 :80（或默认端口）GET /，看主机是否在线。
    /// 主机活 + 流持续断 → streamServerDown = true。
    private func schedulePeerHealthProbe(streamURL: URL) {
        guard let host = streamURL.host else { return }
        var comps = URLComponents()
        comps.scheme = streamURL.scheme ?? "http"
        comps.host = host
        comps.port = nil  // 走默认 80
        comps.path = "/"
        guard let probeURL = comps.url else { return }
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            var req = URLRequest(url: probeURL)
            req.timeoutInterval = 3
            req.httpMethod = "HEAD"
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 3
            config.connectionProxyDictionary = [:]  // bypass system proxy
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let isAlive: Bool
            do {
                let (_, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                    isAlive = true
                } else {
                    isAlive = false
                }
            } catch {
                isAlive = false
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.isRunning else { return }
                self.streamServerDown = isAlive
            }
        }
    }
}

/// Backing reader that owns a URLSession + delegate lifetime.
/// Kept separate so `@Observable` main-actor state and nonisolated delegate
/// callbacks don't mix confusingly.
private final class Reader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private weak var owner: MJPEGStream?
    private let airCamera: Bool
    private var session: URLSession?
    private var task: URLSessionDataTask?

    private var buffer = Data()
    private var capturing = false

    private let log = Logger(subsystem: "PetCollar", category: "MJPEGStream")

    init(owner: MJPEGStream, airCamera: Bool) {
        self.owner = owner
        self.airCamera = airCamera
    }

    func start(url: URL) {
        let config = URLSessionConfiguration.ephemeral
        if airCamera { config.protocolClasses = [AirHardwareProtocol.self] }
        config.timeoutIntervalForRequest = airCamera ? 45 : 30
        config.timeoutIntervalForResource = .infinity
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldUsePipelining = false
        config.connectionProxyDictionary = [:]  // do not use system proxy
        let sess = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
        self.session = sess

        var req = URLRequest(url: url)
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        req.setValue("*/*", forHTTPHeaderField: "Accept")

        let t = sess.dataTask(with: req)
        self.task = t
        log.info("MJPEG start url=\(url.absoluteString, privacy: .public)")
        t.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            log.info("MJPEG response status=\(http.statusCode)")
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        Task { @MainActor [weak self] in
            self?.owner?.onBytes(data.count)
        }
        buffer.append(data)
        var searchedFrom = 0
        processBuffer(&searchedFrom)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let err = error {
            log.error("MJPEG completed with error: \(err.localizedDescription, privacy: .public)")
        } else {
            log.info("MJPEG completed (no error)")
        }
        Task { @MainActor [weak self] in
            self?.owner?.onStreamEnded(error: error)
        }
    }

    // MARK: JPEG frame extraction

    private func processBuffer(_ searchedFrom: inout Int) {
        // Scan `buffer` for JPEG SOI (0xFFD8) and EOI (0xFFD9) pairs.
        // Deliver each complete JPEG and drop consumed bytes.
        while true {
            if !capturing {
                guard let soi = findMarker(0xFFD8, in: buffer, from: 0) else {
                    if buffer.count > 4096 {
                        buffer.removeFirst(buffer.count - 1)
                    }
                    return
                }
                if soi > 0 {
                    buffer.removeFirst(soi)
                }
                capturing = true
            }
            guard let eoiStart = findMarker(0xFFD9, in: buffer, from: 2) else {
                if buffer.count > 8 * 1024 * 1024 {
                    buffer.removeAll(keepingCapacity: true)
                    capturing = false
                }
                return
            }
            let jpegEnd = eoiStart + 2
            let jpeg = buffer.prefix(jpegEnd)
            let jpegData = Data(jpeg)
            buffer.removeFirst(jpegEnd)
            capturing = false

            Task { @MainActor [weak self, jpegData] in
                self?.owner?.onFrame(jpegData)
            }
        }
    }

    /// Find the starting offset of a 2-byte marker (e.g. 0xFFD8) in `data`.
    private func findMarker(_ marker: UInt16, in data: Data, from start: Int) -> Int? {
        let hi = UInt8((marker >> 8) & 0xFF)
        let lo = UInt8(marker & 0xFF)
        guard data.count >= start + 2 else { return nil }
        let bytes = Array(data)
        var i = start
        while i < bytes.count - 1 {
            if bytes[i] == hi && bytes[i + 1] == lo {
                return i
            }
            i += 1
        }
        return nil
    }
}

enum MJPEGError: LocalizedError {
    case badStatus(Int)
    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "视频流 HTTP \(code)"
        }
    }
}

import Foundation
import Network
import Observation

// MARK: - 局域网桌宠发现与召唤（iOS 面板 / Mac 主 App 共用）
//
// 桌宠 App（Mac DesktopPet.app / Windows PetPal桌宠.exe）常驻时用 Bonjour
// `_petpal._tcp` 广播自己（TXT: platform=mac|windows）+ 随机端口极简 HTTP。
// 这里浏览同一网络并列出，summon() 直接对目标发一个裸 HTTP GET /summon
//（走 NWConnection，不经 URLSession/ATS），对方悬浮猫立刻现身。
@MainActor
@Observable
public final class DesktopPetFinder {
    public struct Machine: Identifiable, Sendable {
        public let id: String
        public let name: String        // 广播名，如 "Mac · 小明的MacBook"
        public let platform: String    // "mac" / "windows"
        public let result: NWBrowser.Result
    }

    public var machines: [Machine] = []
    @ObservationIgnored private var browser: NWBrowser?

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_petpal._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.update(results) }
        }
        b.start(queue: .main)
        browser = b
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        machines = []
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        machines = results.compactMap { r in
            guard case let .service(name, _, _, _) = r.endpoint else { return nil }
            var platform = "mac"
            if case let .bonjour(txt) = r.metadata, let p = txt.dictionary["platform"] {
                platform = p
            }
            return Machine(id: "\(platform)|\(name)", name: name, platform: platform, result: r)
        }
        .sorted { $0.name < $1.name }
    }

    /// path: "/summon" 现身，"/dismiss" 收回
    public func send(_ path: String, to machine: Machine,
                     done: @escaping @MainActor (Bool) -> Void) {
        let conn = NWConnection(to: machine.result.endpoint, using: .tcp)
        var finished = false
        let finish: (Bool) -> Void = { ok in
            guard !finished else { return }
            finished = true
            conn.cancel()
            Task { @MainActor in done(ok) }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let req = "GET \(path) HTTP/1.1\r\nHost: petpal\r\nConnection: close\r\n\r\n"
                conn.send(content: req.data(using: .utf8), completion: .contentProcessed { _ in })
                conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                    let ok = data.flatMap { String(data: $0, encoding: .utf8) }?.contains("200") ?? false
                    finish(ok)
                }
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        conn.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish(false) }   // 兜底超时
    }

    public func summon(_ machine: Machine, done: @escaping @MainActor (Bool) -> Void) {
        send("/summon", to: machine, done: done)
    }
}

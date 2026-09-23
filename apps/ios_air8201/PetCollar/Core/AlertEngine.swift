import Foundation
import Observation
import UserNotifications
import os.log

private let dbg = Logger(subsystem: "PetCollar", category: "AlertEngine")

struct AlertRule: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case staleTimeout
        case forbiddenZone
        case vlmKeyword

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .staleTimeout: return "静止超时"
            case .forbiddenZone: return "进入禁区"
            case .vlmKeyword: return "VLM 关键词"
            }
        }
        var iconName: String {
            switch self {
            case .staleTimeout: return "moon.zzz.fill"
            case .forbiddenZone: return "exclamationmark.shield.fill"
            case .vlmKeyword: return "text.magnifyingglass"
            }
        }
    }

    let id: UUID
    var name: String
    var kind: Kind
    var enabled: Bool
    var thresholdSec: Double
    var zoneMinX: Double
    var zoneMinY: Double
    var zoneMaxX: Double
    var zoneMaxY: Double
    var keyword: String

    static func staleTimeout(name: String = "静止超时", thresholdSec: Double = 120) -> AlertRule {
        AlertRule(
            id: UUID(), name: name, kind: .staleTimeout, enabled: true,
            thresholdSec: thresholdSec,
            zoneMinX: 0, zoneMinY: 0, zoneMaxX: 0, zoneMaxY: 0, keyword: ""
        )
    }
    static func forbiddenZone(name: String = "禁区", x: Double = 0, y: Double = 0, w: Double = 1, h: Double = 1) -> AlertRule {
        AlertRule(
            id: UUID(), name: name, kind: .forbiddenZone, enabled: true,
            thresholdSec: 0,
            zoneMinX: x, zoneMinY: y, zoneMaxX: x + w, zoneMaxY: y + h, keyword: ""
        )
    }
    static func vlmKeyword(name: String = "关键词", keyword: String = "") -> AlertRule {
        AlertRule(
            id: UUID(), name: name, kind: .vlmKeyword, enabled: true,
            thresholdSec: 0,
            zoneMinX: 0, zoneMinY: 0, zoneMaxX: 0, zoneMaxY: 0, keyword: keyword
        )
    }

    var summary: String {
        switch kind {
        case .staleTimeout:
            return String(format: "无活动 > %.0fs", thresholdSec)
        case .forbiddenZone:
            return String(format: "禁区 (%.1f, %.1f) → (%.1f, %.1f) m",
                          zoneMinX, zoneMinY, zoneMaxX, zoneMaxY)
        case .vlmKeyword:
            return "命中 \"\(keyword)\""
        }
    }
}

struct AlertEvent: Identifiable, Hashable {
    let id: UUID
    let ruleId: UUID
    let ruleName: String
    let kind: AlertRule.Kind
    let triggeredAt: Date
    let trackId: Int?
    let message: String
}

@MainActor
@Observable
final class AlertEngine: NSObject {
    private var _rules: [AlertRule] = []
    var rules: [AlertRule] {
        get { _rules }
        set { _rules = newValue; persist() }
    }

    private(set) var history: [AlertEvent] = []
    private(set) var authorizationGranted: Bool = false

    private var lastFiredPerKey: [String: Date] = [:]
    private var lastSeenPerTrack: [Int: (ts: Double, x: Double, y: Double, klass: String)] = [:]
    private var lastNotifiedStaleTs: [String: Double] = [:]
    private var lastVLMSignature: String = ""

    private let debounceInterval: TimeInterval = 60
    private let storageKey = "alertRules.v1"

    private var detectionPoll: Task<Void, Never>?
    private var vlmPoll: Task<Void, Never>?

    override init() {
        super.init()
        _rules = loadRules()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: Lifecycle

    func start(api: APIClient, vlmEnabled: Bool) {
        stop()
        detectionPoll = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let resp = try await api.detections()
                    await MainActor.run { self?.ingest(detections: resp.recent) }
                } catch {
                    dbg.error("alert detection poll error: \(error.localizedDescription, privacy: .public)")
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        if vlmEnabled {
            vlmPoll = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        let v = try await api.vlmAnalysis()
                        await MainActor.run { self?.ingest(vlm: v) }
                    } catch {
                        dbg.error("alert vlm poll error: \(error.localizedDescription, privacy: .public)")
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    func stop() {
        detectionPoll?.cancel(); detectionPoll = nil
        vlmPoll?.cancel(); vlmPoll = nil
    }

    // MARK: Rule CRUD

    func add(_ rule: AlertRule) { rules.append(rule) }
    func update(_ rule: AlertRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            var copy = rules
            copy[idx] = rule
            rules = copy
        }
    }
    func delete(at offsets: IndexSet) {
        var copy = rules
        copy.remove(atOffsets: offsets)
        rules = copy
    }
    func toggle(_ rule: AlertRule) {
        var copy = rule
        copy.enabled.toggle()
        update(copy)
    }

    // MARK: Ingest

    func ingest(detections: [Detection]) {
        guard !rules.isEmpty else { return }
        let now = Date().timeIntervalSince1970

        for det in detections {
            guard let trackId = det.trackId else { continue }
            lastSeenPerTrack[trackId] = (det.ts, det.physicalCoords.x, det.physicalCoords.y, det.klass)
        }

        for rule in rules where rule.enabled {
            switch rule.kind {
            case .forbiddenZone:
                for det in detections {
                    guard let trackId = det.trackId else { continue }
                    let x = det.physicalCoords.x
                    let y = det.physicalCoords.y
                    if x >= rule.zoneMinX && x <= rule.zoneMaxX
                        && y >= rule.zoneMinY && y <= rule.zoneMaxY {
                        let msg = String(format: "%@ #%d 进入禁区 (%.2f, %.2f) m",
                                         det.klass, trackId, x, y)
                        fire(rule: rule, trackId: trackId, message: msg)
                    }
                }
            case .staleTimeout:
                for (trackId, seen) in lastSeenPerTrack {
                    let gap = now - seen.ts
                    if gap > rule.thresholdSec {
                        let key = "\(rule.id)-\(trackId)-\(Int(seen.ts))"
                        if lastNotifiedStaleTs[key] != nil { continue }
                        lastNotifiedStaleTs[key] = seen.ts
                        let msg = String(format: "%@ #%d 已 %.0fs 无更新", seen.klass, trackId, gap)
                        fire(rule: rule, trackId: trackId, message: msg)
                    }
                }
            case .vlmKeyword:
                break // handled by ingest(vlm:)
            }
        }

        let cutoff = now - 600
        lastSeenPerTrack = lastSeenPerTrack.filter { $0.value.ts > cutoff }
        if lastNotifiedStaleTs.count > 200 {
            lastNotifiedStaleTs.removeAll()
        }
    }

    func ingest(vlm: VLMAnalysis) {
        guard !rules.isEmpty else { return }
        let signature = "\(vlm.scene)||\(vlm.behavior)"
        if signature == lastVLMSignature { return }
        lastVLMSignature = signature

        let combined = "\(vlm.scene) \(vlm.behavior)".lowercased()
        for rule in rules where rule.enabled && rule.kind == .vlmKeyword {
            let kw = rule.keyword.trimmingCharacters(in: .whitespaces).lowercased()
            guard !kw.isEmpty else { continue }
            if combined.contains(kw) {
                let msg = "VLM 命中 \"\(rule.keyword)\""
                fire(rule: rule, trackId: nil, message: msg)
            }
        }
    }

    // MARK: Fire

    private func fire(rule: AlertRule, trackId: Int?, message: String) {
        let key = "\(rule.id)-\(trackId ?? -1)"
        let now = Date()
        if let last = lastFiredPerKey[key], now.timeIntervalSince(last) < debounceInterval {
            return
        }
        lastFiredPerKey[key] = now

        let event = AlertEvent(
            id: UUID(), ruleId: rule.id, ruleName: rule.name,
            kind: rule.kind, triggeredAt: now, trackId: trackId, message: message
        )
        history.insert(event, at: 0)
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        postLocalNotification(title: rule.name, body: message, eventId: event.id)
        dbg.info("alert fired: \(rule.name, privacy: .public) — \(message, privacy: .public)")
    }

    func clearHistory() { history.removeAll() }

    // MARK: Notifications

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorizationGranted = granted
            dbg.info("notification auth granted=\(granted, privacy: .public)")
        } catch {
            authorizationGranted = false
            dbg.error("notification auth error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func postLocalNotification(title: String, body: String, eventId: UUID) {
        guard authorizationGranted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: eventId.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { err in
            if let err { dbg.error("post notification failed: \(err.localizedDescription, privacy: .public)") }
        }
    }

    // MARK: Persistence

    private func loadRules() -> [AlertRule] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([AlertRule].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(_rules) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

extension AlertEngine: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

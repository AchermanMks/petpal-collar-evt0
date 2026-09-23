import Foundation
import Observation

public enum CatPart: Sendable {
    case head, body, tail
}

// MARK: - 虚拟宠物状态机（四端共享内核）
//
// 数据融合策略（APP 只做展示，不做实时计算）：
// - 连接后端时：饱食度以真实进食事件为准、活力以真实活动量为准、
//   行为由检测到的猫（在镜头里/多久没出现/正在进食）驱动
// - 未连接时：纯虚拟模式（云养猫），按本地互动时间戳 + 昼夜节律推算
//
// 与原 ios_app 的 TamagotchiModel 同源；此处解耦了 AppState / UIKit 触感 / ESP，
// 改为注入 `client` 闭包，使 Mac 桌宠、iOS 小组件、两端主 App 都能复用同一套算法。

@MainActor
@Observable
public final class PetState {
    public enum Behavior: Sendable {
        case idle, walking, eating, sleeping, happy
    }

    public var behavior: Behavior = .idle
    public var connected = false
    public var feeding: FeedingSummary?
    public var activity: ActivitySummary?
    public var lastCatSeen: Date?

    @ObservationIgnored private var transient: Behavior?
    @ObservationIgnored private var transientUntil: Date?
    /// 互动时间戳的持久化存储。默认 .standard；传 App Group suite 即可三端共享。
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: 持久化的虚拟互动时间戳（云养猫跨启动延续）

    private var lastFedAt: Date {
        get { Date(timeIntervalSince1970: defaults.double(forKey: "tama.lastFedAt")) }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: "tama.lastFedAt") }
    }

    private var lastPettedAt: Date {
        get { Date(timeIntervalSince1970: defaults.double(forKey: "tama.lastPettedAt")) }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: "tama.lastPettedAt") }
    }

    public var adoptedDays: Int {
        let key = "tama.adoptedAt"
        var ts = defaults.double(forKey: key)
        if ts == 0 {
            ts = Date().timeIntervalSince1970
            defaults.set(ts, forKey: key)
        }
        let days = Int(Date().timeIntervalSince1970 - ts) / 86400
        return days + 1
    }

    // MARK: 三围（0-100，惰性按时间戳推算，无需后台计时器）

    /// 饱食度：虚拟喂食和真实进食事件取最近一次，8 小时从满掉到空。
    public var satiety: Double {
        var lastFeed = lastFedAt
        if let realEnd = feeding?.recentEvents.map(\.endTs).max() {
            lastFeed = max(lastFeed, Date(timeIntervalSince1970: realEnd))
        }
        if feeding?.inProgress == true { return 100 }
        let hours = Date().timeIntervalSince(lastFeed) / 3600
        return (100 - hours * 12.5).clamped(to: 0...100)
    }

    /// 心情：抚摸加成 4 小时内衰减 + 真实活动加成 + 吃饱加成。
    public var mood: Double {
        let pettedHours = Date().timeIntervalSince(lastPettedAt) / 3600
        let petBonus = (30 * (1 - pettedHours / 4)).clamped(to: 0...30)
        let activityBonus = min(20, activity?.lastHourMeters ?? 0)
        let fullBonus: Double = satiety > 50 ? 10 : 0
        return (40 + petBonus + activityBonus + fullBonus).clamped(to: 0...100)
    }

    /// 活力：连接时映射最近一小时真实活动量；虚拟模式按昼夜节律。
    public var energy: Double {
        if connected, let a = activity {
            return (30 + a.lastHourMeters * 1.4).clamped(to: 0...100)
        }
        let hour = Calendar.current.component(.hour, from: Date())
        return (hour >= 22 || hour < 7) ? 20 : 70
    }

    public var isHungry: Bool { satiety < 25 }

    /// 真实存在感：摄像头最近 60 秒内见过猫。
    public var catOnCamera: Bool {
        guard let seen = lastCatSeen else { return false }
        return Date().timeIntervalSince(seen) < 60
    }

    // MARK: 主循环（由视图 .task 驱动；client() 返回非 nil 即视为已连接）

    public func run(client: @escaping @MainActor () -> APIClient?) async {
        var i = 0
        while !Task.isCancelled {
            if let api = client() {
                connected = true
                if i % 2 == 0 { await fetchDetections(api) }
                if i % 10 == 0 { await fetchFeeding(api) }
                if i % 20 == 0 { await fetchActivity(api) }
            } else {
                connected = false
            }
            updateBehavior(now: Date())
            i += 1
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    private func fetchDetections(_ api: APIClient) async {
        guard let resp = try? await api.detections() else { return }
        if let latestCat = resp.recent.filter({ $0.klass == "cat" }).map(\.ts).max() {
            lastCatSeen = Date(timeIntervalSince1970: latestCat)
        }
    }

    private func fetchFeeding(_ api: APIClient) async {
        feeding = try? await api.feedingEvents()
    }

    private func fetchActivity(_ api: APIClient) async {
        activity = try? await api.activitySummary()
    }

    private func updateBehavior(now: Date) {
        // 真实进食优先级最高
        if feeding?.inProgress == true {
            behavior = .eating
            return
        }
        // 互动触发的临时行为
        if let t = transient, let until = transientUntil, now < until {
            behavior = t
            return
        }
        transient = nil

        if connected {
            if catOnCamera {
                behavior = (activity?.lastHourMeters ?? 0) > 5 ? .walking : .idle
            } else if let seen = lastCatSeen, now.timeIntervalSince(seen) < 600 {
                behavior = .idle
            } else {
                behavior = .sleeping   // 很久没在镜头里，大概在休息
            }
        } else {
            let hour = Calendar.current.component(.hour, from: now)
            if hour >= 22 || hour < 7 {
                behavior = .sleeping
            } else {
                // 虚拟模式：每 4 分钟里有 1 分钟出来溜达
                behavior = Int(now.timeIntervalSince1970 / 60) % 4 == 0 ? .walking : .idle
            }
        }
    }

    // MARK: 互动（纯逻辑；触感反馈交给各端自己做）

    public func feed() {
        lastFedAt = Date()
        setTransient(.eating, seconds: 6)
    }

    public func pet() {
        lastPettedAt = Date()
        setTransient(.happy, seconds: 4)
    }

    private func setTransient(_ b: Behavior, seconds: TimeInterval) {
        transient = b
        transientUntil = Date().addingTimeInterval(seconds)
        behavior = b
    }

    // MARK: 快照（写给 iOS 小组件 / 跨进程共享，避免各端各自硬轮询后端）

    public func snapshot(petName: String) -> PetSnapshot {
        PetSnapshot(
            petName: petName,
            satiety: satiety,
            mood: mood,
            energy: energy,
            behavior: PetSnapshot.Behavior(behavior),
            outfit: nil,
            connected: connected,
            catOnCamera: catOnCamera,
            adoptedDays: adoptedDays,
            updatedAt: Date()
        )
    }
}

import Foundation

// 宠物状态的轻量快照。主 App 把 PetState 算出的结果写进 App Group 容器，
// iOS 小组件只读快照、不联网（小组件有刷新预算限制，不能硬轮询后端）。
// Mac 桌宠常驻进程可自己跑 PetState，也可写快照供其它进程读。

public struct PetSnapshot: Codable, Equatable, Sendable {
    public enum Behavior: String, Codable, Sendable {
        case idle, walking, eating, sleeping, happy

        public init(_ b: PetState.Behavior) {
            switch b {
            case .idle: self = .idle
            case .walking: self = .walking
            case .eating: self = .eating
            case .sleeping: self = .sleeping
            case .happy: self = .happy
            }
        }
    }

    public var petName: String
    public var satiety: Double
    public var mood: Double
    public var energy: Double
    public var behavior: Behavior
    public var outfit: String?
    public var connected: Bool
    public var catOnCamera: Bool
    public var adoptedDays: Int
    public var updatedAt: Date

    public init(petName: String, satiety: Double, mood: Double, energy: Double,
                behavior: Behavior, outfit: String?, connected: Bool,
                catOnCamera: Bool, adoptedDays: Int, updatedAt: Date) {
        self.petName = petName
        self.satiety = satiety
        self.mood = mood
        self.energy = energy
        self.behavior = behavior
        self.outfit = outfit
        self.connected = connected
        self.catOnCamera = catOnCamera
        self.adoptedDays = adoptedDays
        self.updatedAt = updatedAt
    }
}

// MARK: - 共享读写

public enum PetSnapshotStore {
    /// 三端共用的 App Group。需在各 target 的 entitlements 里勾选同名 group。
    public static let appGroupID = "group.com.petpal.air8201g"
    private static let key = "pet.snapshot"

    /// 优先写 App Group 的 UserDefaults；拿不到容器（未配 entitlement）时回退到 .standard。
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static func save(_ snapshot: PetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static func load() -> PetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PetSnapshot.self, from: data)
    }
}

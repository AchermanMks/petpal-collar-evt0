import SwiftUI
import SceneKit
import AVFoundation
import UIKit
import simd
import PetKit      // PetSnapshot / PetSnapshotStore：写进 App Group 供小组件只读
import WidgetKit   // 刷新小组件时间线
import Network     // Bonjour 发现局域网里的电脑桌宠（_petpal._tcp）

// MARK: - 虚拟宠物状态机
//
// 数据融合策略（APP 只做展示，不做实时计算）：
// - 连接后端时：饱食度以真实进食事件为准、活力以真实活动量为准、
//   行为由检测到的猫（在镜头里/多久没出现/正在进食）驱动
// - 未连接时：纯虚拟模式（云养猫），按本地互动时间戳 + 昼夜节律推算

@MainActor
@Observable
final class TamagotchiModel {
    enum Behavior {
        case idle, walking, eating, sleeping, happy
    }

    var behavior: Behavior = .idle
    var connected = false
    var feeding: FeedingSummary?
    var activity: ActivitySummary?
    var lastCatSeen: Date?
    var toast: String?

    @ObservationIgnored private var transient: Behavior?
    @ObservationIgnored private var transientUntil: Date?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    // MARK: 持久化的虚拟互动时间戳（云养猫跨启动延续）

    private static let defaults = UserDefaults.standard

    private var lastFedAt: Date {
        get { Date(timeIntervalSince1970: Self.defaults.double(forKey: "tama.lastFedAt")) }
        set { Self.defaults.set(newValue.timeIntervalSince1970, forKey: "tama.lastFedAt") }
    }

    private var lastPettedAt: Date {
        get { Date(timeIntervalSince1970: Self.defaults.double(forKey: "tama.lastPettedAt")) }
        set { Self.defaults.set(newValue.timeIntervalSince1970, forKey: "tama.lastPettedAt") }
    }

    var adoptedDays: Int {
        let key = "tama.adoptedAt"
        var ts = Self.defaults.double(forKey: key)
        if ts == 0 {
            ts = Date().timeIntervalSince1970
            Self.defaults.set(ts, forKey: key)
        }
        let days = Int(Date().timeIntervalSince1970 - ts) / 86400
        return days + 1
    }

    // MARK: 三围（0-100，惰性按时间戳推算，无需后台计时器）

    /// 饱食度：虚拟喂食和真实进食事件取最近一次，8 小时从满掉到空
    var satiety: Double {
        var lastFeed = lastFedAt
        if let realEnd = feeding?.recentEvents.map(\.endTs).max() {
            lastFeed = max(lastFeed, Date(timeIntervalSince1970: realEnd))
        }
        if feeding?.inProgress == true { return 100 }
        let hours = Date().timeIntervalSince(lastFeed) / 3600
        return (100 - hours * 12.5).clamped(to: 0...100)
    }

    /// 心情：抚摸加成 4 小时内衰减 + 真实活动加成 + 吃饱加成
    var mood: Double {
        let pettedHours = Date().timeIntervalSince(lastPettedAt) / 3600
        let petBonus = (30 * (1 - pettedHours / 4)).clamped(to: 0...30)
        let activityBonus = min(20, activity?.lastHourMeters ?? 0)
        let fullBonus: Double = satiety > 50 ? 10 : 0
        return (40 + petBonus + activityBonus + fullBonus).clamped(to: 0...100)
    }

    /// 活力：连接时映射最近一小时真实活动量；虚拟模式按昼夜节律
    var energy: Double {
        if connected, let a = activity {
            return (30 + a.lastHourMeters * 1.4).clamped(to: 0...100)
        }
        let hour = Calendar.current.component(.hour, from: Date())
        return (hour >= 22 || hour < 7) ? 20 : 70
    }

    var isHungry: Bool { satiety < 25 }

    /// 真实存在感：摄像头最近 60 秒内见过猫
    var catOnCamera: Bool {
        guard let seen = lastCatSeen else { return false }
        return Date().timeIntervalSince(seen) < 60
    }

    // MARK: 主循环（由视图 .task 驱动）

    func run(state: AppState) async {
        var i = 0
        while !Task.isCancelled {
            if case .connected = state.status, let api = state.api {
                connected = true
                if i % 2 == 0 { await fetchDetections(api) }
                if i % 10 == 0 { await fetchFeeding(api) }
                if i % 20 == 0 { await fetchActivity(api) }
            } else {
                connected = false
            }
            updateBehavior(now: Date())
            writeSnapshot()                                    // 每拍把状态落到 App Group
            if i % 7 == 0 { WidgetCenter.shared.reloadAllTimelines() }  // 约每 10s 让小组件刷新
            i += 1
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    // MARK: 快照（写给 iOS 小组件，同源：与主 App 同一份三围/行为）
    //
    // 小组件有刷新预算、不能硬轮询后端，只读这份由主 App 算好的快照。
    // 装扮/宠物名由视图层注入（它们是 @AppStorage，模型本身不持有）。
    var snapshotName = "喵喵"
    var snapshotOutfitRaw = "none"

    private func writeSnapshot() {
        let b: PetSnapshot.Behavior
        switch behavior {
        case .idle: b = .idle
        case .walking: b = .walking
        case .eating: b = .eating
        case .sleeping: b = .sleeping
        case .happy: b = .happy
        }
        let snap = PetSnapshot(
            petName: snapshotName,
            satiety: satiety, mood: mood, energy: energy,
            behavior: b,
            outfit: snapshotOutfitRaw == "none" ? nil : snapshotOutfitRaw,
            connected: connected,
            catOnCamera: catOnCamera,
            adoptedDays: adoptedDays,
            updatedAt: Date()
        )
        PetSnapshotStore.save(snap)
    }

    /// 用户从首页主动「把桌宠放上手机」：立刻落一份最新快照并催小组件刷新，
    /// 这样回桌面长按添加「电子宠物」小组件即可看到与 App 同源的猫。
    func pushToWidget() {
        writeSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
        toast = "已放上小组件 · 回桌面长按添加「电子宠物」"
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
        // 调试钩子：simctl launch ... -tamaDebugBehavior walking|eating|sleeping|happy|idle
        if let dbg = UserDefaults.standard.string(forKey: "tamaDebugBehavior") {
            let map: [String: Behavior] = ["idle": .idle, "walking": .walking, "eating": .eating,
                                           "sleeping": .sleeping, "happy": .happy]
            if let forced = map[dbg] {
                behavior = forced
                return
            }
        }
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

    // MARK: 互动

    func feed() {
        lastFedAt = Date()
        setTransient(.eating, seconds: 6)
        haptic(.medium)
    }

    func pet() {
        lastPettedAt = Date()
        setTransient(.happy, seconds: 4)
        haptic(.light)
    }

    /// 呼唤：真实项圈播放猫叫；失败只提示不报错（纯虚拟用户没有项圈）
    func call(espHost: String) {
        setTransient(.happy, seconds: 4)
        haptic(.medium)
        Task {
            guard let url = ESPClient.makeLEDBaseURL(from: espHost) else {
                showToast("项圈地址无效")
                return
            }
            do {
                try await ESPClient(baseURL: url).speakerMeow(volume: 80)
                showToast("项圈喵了一声～")
            } catch {
                showToast("项圈没有回应（虚拟喵已送达）")
            }
        }
    }

    private func setTransient(_ b: Behavior, seconds: TimeInterval) {
        transient = b
        transientUntil = Date().addingTimeInterval(seconds)
        behavior = b
    }

    private func showToast(_ msg: String) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { toast = nil }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

// MARK: - 像素精灵

struct PixelSprite {
    let rows: [String]
    var width: Int { rows.first?.count ?? 1 }
    var height: Int { rows.count }


    // 坐姿 A：竖尾巴 + 睁眼（'o' 是眼睛镂空）
    static let sitA = PixelSprite(rows: [
        ".##..##.........",
        ".######.........",
        ".#o##o#.........",
        ".######.........",
        "..####..........",
        "..####.......#..",
        ".######.....#...",
        ".#######...#....",
        ".########..#....",
        ".#########.#....",
        ".##########.....",
        "..##..##........",
    ])

    // 坐姿 B：眨眼 + 尾巴垂下
    static let sitB = PixelSprite(rows: [
        ".##..##.........",
        ".######.........",
        ".######.........",
        ".######.........",
        "..####..........",
        "..####..........",
        ".######......#..",
        ".#######...#....",
        ".########..#....",
        ".#########.#....",
        ".##########.....",
        "..##..##........",
    ])

    // 趴睡 A：尾巴翘起
    static let sleepA = PixelSprite(rows: [
        "................",
        "................",
        "................",
        "................",
        "................",
        ".##..##.........",
        ".######.........",
        ".######......##.",
        ".##############.",
        ".##############.",
        ".##############.",
        "..##.....##.....",
    ])

    // 趴睡 B：尾巴放平
    static let sleepB = PixelSprite(rows: [
        "................",
        "................",
        "................",
        "................",
        "................",
        ".##..##.........",
        ".######.........",
        ".######.........",
        ".##############.",
        ".##############.",
        ".##############.",
        "..##.....##.....",
    ])

    static let fish = PixelSprite(rows: [
        "..####...#",
        ".######.##",
        "#o######.#",
        ".######.##",
        "..####...#",
    ])

    static let heart = PixelSprite(rows: [
        ".##.##.",
        "#######",
        "#######",
        ".#####.",
        "..###..",
        "...#...",
    ])
}

struct PixelSpriteView: View {
    let sprite: PixelSprite
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let pw = size.width / CGFloat(sprite.width)
            let ph = size.height / CGFloat(sprite.height)
            for (y, row) in sprite.rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    let rect = CGRect(x: CGFloat(x) * pw, y: CGFloat(y) * ph, width: pw, height: ph)
                        .insetBy(dx: pw * 0.06, dy: ph * 0.06)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: pw * 0.18), with: .color(color))
                }
            }
        }
        .aspectRatio(CGFloat(sprite.width) / CGFloat(sprite.height), contentMode: .fit)
    }
}

// MARK: - 变装（2D 贴图与 3D 体素共用一套点阵，与 sitA 坐标对齐）

enum Outfit: String, CaseIterable, Identifiable {
    case none, beret, crown, bow, glasses, scarf, collar, wizard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "无"
        case .beret: return "贝雷帽"
        case .crown: return "皇冠"
        case .bow: return "蝴蝶结"
        case .glasses: return "墨镜"
        case .scarf: return "围巾"
        case .collar: return "铃铛项圈"
        case .wizard: return "巫师帽"
        }
    }

    var labelEN: String {
        switch self {
        case .none: return "None"
        case .beret: return "Beret"
        case .crown: return "Crown"
        case .bow: return "Bow"
        case .glasses: return "Shades"
        case .scarf: return "Scarf"
        case .collar: return "Bell"
        case .wizard: return "Wizard"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .none: return .clear
        case .beret: return UIColor(red: 0.78, green: 0.22, blue: 0.28, alpha: 1)
        case .crown: return UIColor(red: 0.93, green: 0.76, blue: 0.28, alpha: 1)
        case .bow: return UIColor(red: 0.94, green: 0.42, blue: 0.62, alpha: 1)
        case .glasses: return UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
        case .scarf: return UIColor(red: 0.90, green: 0.45, blue: 0.18, alpha: 1)
        case .collar: return UIColor(red: 0.80, green: 0.16, blue: 0.20, alpha: 1)
        case .wizard: return UIColor(red: 0.28, green: 0.24, blue: 0.55, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    /// 帽类在 3D 里整圈包住头部，其它配饰只贴在脸前
    var isHat: Bool { self == .beret || self == .crown || self == .wizard }

    var sprite: PixelSprite? {
        switch self {
        case .none:
            return nil
        case .beret:
            return PixelSprite(rows: [
                ".######.........",
                ".##.............",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
            ])
        case .crown:
            return PixelSprite(rows: [
                ".#.##.#.........",
                ".######.........",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
            ])
        case .bow:
            return PixelSprite(rows: [
                ".....##.##......",
                "......###.......",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
            ])
        case .glasses:
            return PixelSprite(rows: [
                "................",
                "................",
                ".########.......",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
            ])
        case .scarf:
            return PixelSprite(rows: [
                "................",
                "................",
                "................",
                "................",
                "..#####.........",
                "..##............",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
            ])
        case .collar:
            return PixelSprite(rows: [
                "................",
                "................",
                "................",
                "................",
                "..#####.........",
                "....#...........",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
            ])
        case .wizard:
            return PixelSprite(rows: [
                "....#...........",
                ".#######........",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
            ])
        }
    }
}

// MARK: - LCD 配色（屏幕是"实体硬件"，不随 App 主题变）

private enum LCD {
    static let screen = Color(red: 0.776, green: 0.843, blue: 0.620)
    static let screenDeep = Color(red: 0.714, green: 0.792, blue: 0.553)
    static let pixel = Color(red: 0.169, green: 0.208, blue: 0.141)
    static let pixelFaint = pixel.opacity(0.12)
    static let pixelUIColor = UIColor(red: 0.169, green: 0.208, blue: 0.141, alpha: 1)
    static let screenUIColor = UIColor(red: 0.776, green: 0.843, blue: 0.620, alpha: 1)
}

// MARK: - 全屏电子宠物首页

struct TamagotchiHomeView: View {
    @Environment(AppState.self) private var state
    @Environment(PetRouter.self) private var router
    @State private var model = TamagotchiModel()
    @State private var voice = TomVoice()
    @AppStorage("tama.is3D") private var is3D: Bool = true   // 首页优先展示 3D 宠物形象，并记住用户切换
    @AppStorage("entryMode") private var entryMode: String = ""
    @AppStorage("virtualBreed") private var virtualBreed: String = ""

    @State private var riggedFeedNonce = 0   // 骨骼猫喂食动作触发器（低头+咀嚼）
    @State private var riggedPetNonce = 0    // 骨骼猫抚摸动作触发器（蹭手+抖耳）
    @State private var showWardrobe = false
    @State private var showExtend = false
    @State private var showActions = false   // 操作钮默认收起，点爪印钮一并展开
    @AppStorage("petName") private var petName: String = "喵喵"
    @AppStorage("espHost") private var espHost: String = "esp32-led.local"
    @AppStorage("tama.outfit") private var outfitRaw: String = Outfit.none.rawValue
    @AppStorage("xp") private var xp: Int = 0
    @AppStorage("interactionCount") private var interactionCount: Int = 0
    @AppStorage("appLanguage") private var appLanguage: String = "zh"
    private var en: Bool { appLanguage == "en" }
    private func tr(_ zh: String, _ english: String) -> String { en ? english : zh }
    @Binding var path: NavigationPath
    @State private var pullOffset: CGFloat = 0

    private var outfit: Outfit { Outfit(rawValue: outfitRaw) ?? .none }

    private var isConnected: Bool {
        if case .connected = state.status { return true }
        return false
    }

    var body: some View {
        ZStack {
            // 与「我的」页同款淡蓝星空底（原 LCD 绿渐变 + 点阵格已弃用）
            StarrySkyBackground()

            VStack(spacing: 10) {
                header
                stage
                if showWardrobe {
                    WardrobeStrip(selectedRaw: $outfitRaw)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                actionArea
                syncStrip
                shopPullHint
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .offset(y: min(pullOffset * 0.3, 0))
        }
        .overlay(alignment: .bottom) {
            let progress = min(max(-pullOffset - 50, 0) / 70, 1.0)
            HStack(spacing: 8) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 16, weight: .bold))
                Text(pullOffset < -120 ? tr("松手进入商城", "Release for Shop")
                                       : tr("继续上滑…", "Keep pulling…"))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(LCD.pixel)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(LCD.pixel.opacity(0.1))
                    .overlay(Capsule().strokeBorder(LCD.pixel.opacity(0.3), lineWidth: 1))
            )
            .opacity(progress)
            .offset(y: -20 - (1 - progress) * 20)
            .allowsHitTesting(false)
        }
        .gesture(
            DragGesture(minimumDistance: 80)
                .onChanged { value in
                    let h = value.translation.height
                    if h < 0, abs(h) > abs(value.translation.width) {
                        pullOffset = h
                    }
                }
                .onEnded { _ in
                    if pullOffset < -120 {
                        pullOffset = 0
                        // 直接切到「发现」页的商城栏目，不另起 ShopView 页面
                        router.requestOpenShop()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            pullOffset = 0
                        }
                    }
                }
        )
        .statusBarHidden()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showExtend) {
            ExtendPetSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .animation(.easeInOut(duration: 0.25), value: showWardrobe)
        .task(id: isConnected) {
            model.snapshotName = petName
            model.snapshotOutfitRaw = outfitRaw
            await model.run(state: state)
        }
        .onChange(of: petName) { model.snapshotName = petName }
        .onChange(of: outfitRaw) {
            model.snapshotOutfitRaw = outfitRaw
            gainXP(5)
        }
        // 小组件「打开桌宠」：进入 3D 体素猫（手机上最接近「桌宠」的形态）。
        .onChange(of: router.openPetNonce) {
            withAnimation { is3D = true }
        }
        // 真实进食事件（后端检测到猫在碗边）→ 骨骼猫低头吃饭
        .onChange(of: model.behavior) { _, new in
            if new == .eating { riggedFeedNonce += 1 }
        }
    }

    // MARK: 顶部状态区

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(en ? "\(petName) · Day \(model.adoptedDays)" : "\(petName) · 第\(model.adoptedDays)天")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text(presenceText)
                    .font(.system(size: 12, weight: .bold))
            }
            HStack(spacing: 14) {
                LCDMeter(label: tr("饱", "Full"), value: model.satiety)
                LCDMeter(label: tr("心", "Mood"), value: model.mood)
                LCDMeter(label: tr("力", "Energy"), value: model.energy)
                Spacer()
                if model.isHungry {
                    Text(tr("饿!", "Hungry!"))
                        .font(.system(size: 12, weight: .heavy))
                }
                Image(systemName: model.connected
                      ? "antenna.radiowaves.left.and.right"
                      : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 12, weight: .bold))
                    .opacity(model.connected ? 1 : 0.4)
            }
        }
        .foregroundStyle(LCD.pixel)
    }

    private var presenceText: String {
        if !model.connected { return tr("虚拟模式", "Virtual") }
        if model.feeding?.inProgress == true { return tr("进食中", "Eating") }
        if model.catOnCamera { return tr("在镜头里", "On Camera") }
        if model.behavior == .sleeping { return tr("休息中", "Resting") }
        return tr("在家", "At Home")
    }

    // MARK: 舞台（2D 像素 / 3D 体素切换）

    private var stage: some View {
        GeometryReader { geo in
            ZStack {
                if is3D {
                    // 舞台聚光灯光晕，让猫从点阵底上"立"出来
                    RadialGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                                   center: UnitPoint(x: 0.5, y: 0.55),
                                   startRadius: 20, endRadius: 230)
                        .allowsHitTesting(false)
                    // 骨骼真猫：cat_idle.usdz（35 骨骼 idle 动画），行为映射到播放速度，
                    // 喂食/抚摸/变装通过骨骼叠加约束呈现
                    RiggedCatSceneView(outfit: PetKit.Outfit(rawValue: outfitRaw) ?? .none,
                                       animationSpeed: riggedSpeed,
                                       feedNonce: riggedFeedNonce,
                                       petNonce: riggedPetNonce) { part in
                        // PetKit.CatPart → 本地 CatPart（历史遗留的同名枚举）
                        switch part {
                        case .head: tomReact(.head)
                        case .body: tomReact(.body)
                        case .tail: tomReact(.tail)
                        }
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: 0.55)) { timeline in
                        pixelStage(t: timeline.date.timeIntervalSince1970, size: geo.size)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(alignment: .top) {
                if let toast = model.toast {
                    Text(toast)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LCD.pixel)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(LCD.pixel.opacity(0.12)))
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.toast)
        }
        .frame(maxHeight: .infinity)
    }

    /// 行为 → 骨骼猫 idle 播放速度：idle 剪辑用速度表达精神状态
    /// （睡觉呼吸般缓慢，开心/走动明显活泼）
    private var riggedSpeed: Double {
        switch model.behavior {
        case .sleeping: return 0.35
        case .eating:   return 0.9
        case .walking:  return 1.3
        case .happy:    return 1.5
        case .idle:     return 1.0
        }
    }

    // MARK: 汤姆猫互动（3D 模式）

    private func tomReact(_ part: CatPart) {
        switch part {
        case .head:
            voice.meow("喵～")
            model.pet()
        case .body:
            voice.meow("咕噜咕噜")
            model.pet()
        case .tail:
            voice.meow("喵！")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func pixelStage(t: TimeInterval, size: CGSize) -> some View {
        let catWidth = min(size.width * 0.6, 240)
        let k = catWidth / 132   // 相对原 132pt 设计稿的缩放
        let frameA = Int(t / 0.55) % 2 == 0
        let sprite: PixelSprite
        switch model.behavior {
        case .sleeping: sprite = frameA ? .sleepA : .sleepB
        default: sprite = frameA ? .sitA : .sitB
        }

        let walking = model.behavior == .walking
        let wanderX = walking ? sin(t * 0.5) * Double(size.width * 0.22) : 0
        let facing: CGFloat = walking && cos(t * 0.5) < 0 ? -1 : 1
        let bounceY = walking ? -abs(sin(t * 3.2)) * 3 * k : 0
        let eatSquash = model.behavior == .eating ? 0.94 + 0.06 * sin(t * 6) : 1.0
        let jumpY = model.behavior == .happy ? -abs(sin(t * 4)) * 8 * k : 0

        return ZStack {
            ZStack {
                PixelSpriteView(sprite: sprite, color: LCD.pixel)
                if let overlay = outfit.sprite {
                    PixelSpriteView(sprite: overlay, color: outfit.color)
                        // 趴睡时头部下移 5 行，配饰跟着移
                        .offset(y: model.behavior == .sleeping ? 5 * catWidth / 16 : 0)
                }
            }
            .frame(width: catWidth)
            .scaleEffect(x: facing, y: eatSquash, anchor: .bottom)
            .offset(x: wanderX, y: bounceY + jumpY)
            .contentShape(Rectangle())
            .onTapGesture { model.pet() }

            if model.behavior == .eating {
                PixelSpriteView(sprite: .fish, color: LCD.pixel)
                    .frame(width: 34 * k)
                    .scaleEffect(0.7 + 0.3 * abs(sin(t * 1.5)))
                    .offset(x: wanderX + catWidth * 0.6, y: catWidth * 0.3)
            }

            if model.behavior == .happy {
                heartsOverlay(t: t, k: k)
            }

            if model.behavior == .sleeping {
                zzzOverlay(t: t, k: k)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func heartsOverlay(t: TimeInterval, k: CGFloat) -> some View {
        ForEach(0..<3, id: \.self) { i in
            let phase = (t * 0.8 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
            PixelSpriteView(sprite: .heart, color: LCD.pixel)
                .frame(width: 16 * k)
                .opacity(1 - phase)
                .offset(x: (CGFloat(i - 1) * 34 + sin(t * 2 + Double(i)) * 6) * k,
                        y: (-20 - phase * 44) * k)
        }
    }

    private func zzzOverlay(t: TimeInterval, k: CGFloat) -> some View {
        ForEach(0..<3, id: \.self) { i in
            let phase = (t * 0.5 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
            Text("Z")
                .font(.system(size: (12 + CGFloat(i) * 3) * k, weight: .heavy))
                .foregroundStyle(LCD.pixel.opacity(1 - phase))
                .offset(x: (40 + CGFloat(i) * 14 + phase * 8) * k,
                        y: (-10 - phase * 30 - CGFloat(i) * 8) * k)
        }
    }

    // MARK: 操作区

    /// 互动攒经验：等级制度见 PetLevel（我的页展示）
    private func gainXP(_ amount: Int) {
        xp += amount
        interactionCount += 1
    }

    /// 操作区：默认只留一颗爪印钮，点击弹出整排操作；再点收起（连同衣柜一起收）
    private var actionArea: some View {
        VStack(spacing: 12) {
            if showActions {
                actionBar
                    .transition(
                        .move(edge: .bottom)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.90, anchor: .bottom))
                    )
            }
            actionToggle
        }
    }

    private var actionToggle: some View {
        Button {
            let opening = !showActions
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                showActions = opening
                if !opening { showWardrobe = false }   // 收起时衣柜一并收，避免残留空条
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack {
                Circle()
                    .fill(LCD.pixel.opacity(showActions ? 0.85 : 0.10))
                Circle()
                    .strokeBorder(LCD.pixel, lineWidth: 2)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(showActions ? LCD.screen : LCD.pixel)
                    .rotationEffect(.degrees(showActions ? -15 : 0))
                    .scaleEffect(showActions ? 0.92 : 1.0)
            }
            .frame(width: 50, height: 50)
        }
        .buttonStyle(TamagotchiButtonStyle())
        .accessibilityLabel(showActions ? tr("收起操作", "Hide actions") : tr("展开操作", "Show actions"))
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            lcdButton(icon: "fish.fill", label: tr("喂食", "Feed")) {
                model.feed()
                riggedFeedNonce += 1
                gainXP(20)
            }
            lcdButton(icon: "hand.raised.fill", label: tr("抚摸", "Pet")) {
                model.pet()
                riggedPetNonce += 1
                gainXP(10)
            }
            lcdButton(icon: "music.note", label: tr("呼唤", "Call")) {
                model.call(espHost: espHost)
                gainXP(10)
            }
            lcdButton(icon: "tshirt.fill", label: tr("变装", "Outfit"), active: showWardrobe) {
                showWardrobe.toggle()
            }
            lcdButton(icon: is3D ? "view.2d" : "view.3d", label: is3D ? "2D" : "3D", active: is3D) {
                is3D.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            lcdButton(icon: "apps.iphone", label: tr("桌宠", "Desktop"), active: showExtend) {
                showExtend = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func lcdButton(icon: String, label: String, active: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(LCD.pixel.opacity(active ? 0.85 : 0.10))
                    Circle()
                        .strokeBorder(LCD.pixel, lineWidth: 2)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(active ? LCD.screen : LCD.pixel)
                }
                .frame(width: 52, height: 52)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LCD.pixel)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TamagotchiButtonStyle())
    }

    // MARK: 真实数据同步条

    private var syncStrip: some View {
        HStack(spacing: 8) {
            if isConnected {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .bold))
                Text(en
                     ? "\(model.feeding?.todayCount ?? 0) meals · \(Int(model.activity?.todayMeters ?? 0))m · \(model.catOnCamera ? "On Camera" : "Off Camera")"
                     : "今日\(model.feeding?.todayCount ?? 0)餐 · 活动\(Int(model.activity?.todayMeters ?? 0))m · \(model.catOnCamera ? "镜头里" : "镜头外")")
                Spacer()
                NavigationLink(value: HomeRoute.live) {
                    HStack(spacing: 2) {
                        Text(tr("实况", "Live"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LCD.pixel)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().strokeBorder(LCD.pixel, lineWidth: 1.5))
                }
            } else {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(tr("云养猫 · 虚拟模式", "Cloud Cat · Virtual"))
                Spacer()
                Text(tr("连接后端同步真猫数据", "Connect backend to sync real data"))
                    .opacity(0.55)
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(LCD.pixel)
        .padding(.top, 2)
    }

    private var shopPullHint: some View {
        VStack(spacing: 3) {
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 20, weight: .bold))
        }
        .foregroundStyle(LCD.pixel.opacity(pullOffset < -40 ? 0.7 : 0.3))
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

private struct TamagotchiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: LCD 五段电量条

private struct LCDMeter: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LCD.pixel)
            HStack(spacing: 1.5) {
                ForEach(0..<5, id: \.self) { i in
                    Rectangle()
                        .fill(Double(i) < value / 20 ? LCD.pixel : LCD.pixel.opacity(0.15))
                        .frame(width: 5, height: 8)
                }
            }
        }
    }
}

// MARK: - 衣柜

/// 单位坐标多边形：0~1 归一化坐标，随容器缩放。
private struct UnitPoly: Shape {
    let pts: [(Double, Double)]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let f = pts.first else { return p }
        p.move(to: CGPoint(x: f.0 * rect.width, y: f.1 * rect.height))
        for q in pts.dropFirst() {
            p.addLine(to: CGPoint(x: q.0 * rect.width, y: q.1 * rect.height))
        }
        p.closeSubpath()
        return p
    }
}

/// 变装图标：彩色贴纸风——每个配饰用自身主题色 + 上亮下暗渐变 + 白高光。
/// 用纯 SwiftUI 形状（Ellipse/RoundedRectangle/Shape + LinearGradient）而非 Canvas：
/// Canvas 的 GraphicsContext.Shading 在部分真机系统版本上渲染异常（整块出黑），
/// SwiftUI 原生渐变管线与通行证金卡同源，全设备验证过。
private struct OutfitIcon: View {
    let outfit: Outfit

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width, geo.size.height)
            content
                .frame(width: u, height: u)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    /// 竖向渐变（上亮下暗），贴纸体积感
    private func vGrad(_ top: Color, _ bottom: Color) -> LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// 在单位方框里摆一个椭圆
    private func dot(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                     _ fill: some ShapeStyle) -> some View {
        GeometryReader { g in
            Ellipse().fill(fill)
                .frame(width: w * g.size.width, height: h * g.size.height)
                .offset(x: x * g.size.width, y: y * g.size.height)
        }
    }

    /// 在单位方框里摆一个圆角矩形
    private func bar(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                     _ cr: Double, _ fill: some ShapeStyle) -> some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: cr * g.size.width, style: .continuous)
                .fill(fill)
                .frame(width: w * g.size.width, height: h * g.size.height)
                .offset(x: x * g.size.width, y: y * g.size.height)
        }
    }

    private var shine: Color { Color.white.opacity(0.45) }

    @ViewBuilder
    private var content: some View {
        switch outfit {
        case .none:
            EmptyView()

        case .beret:                                   // 红贝雷：圆顶渐变 + 深色帽箍 + 小揪揪
            ZStack {
                dot(0.07, 0.30, 0.86, 0.42,
                    vGrad(Color(red: 0.92, green: 0.36, blue: 0.40),
                          Color(red: 0.68, green: 0.15, blue: 0.22)))
                bar(0.44, 0.17, 0.12, 0.15, 0.05, Color(red: 0.62, green: 0.13, blue: 0.20))
                bar(0.17, 0.62, 0.66, 0.13, 0.065, Color(red: 0.55, green: 0.11, blue: 0.18))
                dot(0.18, 0.35, 0.26, 0.12, shine)
            }

        case .crown:                                   // 金皇冠：渐变冠体 + 尖顶圆珠 + 红宝石
            ZStack {
                UnitPoly(pts: [(0.10, 0.74), (0.10, 0.32), (0.30, 0.52),
                               (0.50, 0.24), (0.70, 0.52), (0.90, 0.32), (0.90, 0.74)])
                    .fill(vGrad(Color(red: 0.99, green: 0.86, blue: 0.45),
                                Color(red: 0.83, green: 0.60, blue: 0.16)))
                dot(0.045, 0.245, 0.11, 0.11, Color(red: 0.99, green: 0.80, blue: 0.30))
                dot(0.445, 0.165, 0.11, 0.11, Color(red: 0.99, green: 0.80, blue: 0.30))
                dot(0.845, 0.245, 0.11, 0.11, Color(red: 0.99, green: 0.80, blue: 0.30))
                bar(0.10, 0.66, 0.80, 0.10, 0.05, Color(red: 0.72, green: 0.49, blue: 0.10))
                dot(0.44, 0.48, 0.12, 0.12, Color(red: 0.86, green: 0.19, blue: 0.26))
                dot(0.46, 0.50, 0.045, 0.045, shine)
            }

        case .bow:                                     // 粉蝴蝶结：三角缎带翼 + 外缘弧 + 中心方结
            let wing = Color(red: 0.95, green: 0.47, blue: 0.65)
            let wingD = Color(red: 0.78, green: 0.26, blue: 0.46)
            ZStack {
                UnitPoly(pts: [(0.47, 0.50), (0.06, 0.22), (0.06, 0.78)])
                    .fill(vGrad(wing, wingD))
                UnitPoly(pts: [(0.53, 0.50), (0.94, 0.22), (0.94, 0.78)])
                    .fill(vGrad(wing, wingD))
                dot(0.02, 0.26, 0.10, 0.48, vGrad(wing, wingD))
                dot(0.88, 0.26, 0.10, 0.48, vGrad(wing, wingD))
                UnitPoly(pts: [(0.47, 0.50), (0.14, 0.34), (0.14, 0.44)]).fill(wingD.opacity(0.5))
                UnitPoly(pts: [(0.47, 0.50), (0.14, 0.66), (0.14, 0.56)]).fill(wingD.opacity(0.5))
                UnitPoly(pts: [(0.53, 0.50), (0.86, 0.34), (0.86, 0.44)]).fill(wingD.opacity(0.5))
                UnitPoly(pts: [(0.53, 0.50), (0.86, 0.66), (0.86, 0.56)]).fill(wingD.opacity(0.5))
                bar(0.40, 0.37, 0.20, 0.26, 0.05,
                    vGrad(Color(red: 0.98, green: 0.62, blue: 0.76), wingD))
                dot(0.11, 0.28, 0.11, 0.08, shine)
                dot(0.68, 0.28, 0.11, 0.08, shine)
                dot(0.43, 0.40, 0.07, 0.05, shine)
            }

        case .glasses:                                 // 墨镜：金框 + 蓝紫渐变镜片 + 斜高光
            let frame = Color(red: 0.85, green: 0.65, blue: 0.25)
            let lensT = Color(red: 0.55, green: 0.45, blue: 0.92)
            let lensB = Color(red: 0.14, green: 0.10, blue: 0.34)
            ZStack {
                bar(0.015, 0.295, 0.44, 0.41, 0.15, frame)
                bar(0.545, 0.295, 0.44, 0.41, 0.15, frame)
                bar(0.04, 0.32, 0.39, 0.36, 0.13, vGrad(lensT, lensB))
                bar(0.57, 0.32, 0.39, 0.36, 0.13, vGrad(lensT, lensB))
                bar(0.40, 0.40, 0.20, 0.08, 0.03, frame)
                UnitPoly(pts: [(0.10, 0.62), (0.20, 0.36), (0.27, 0.36), (0.17, 0.62)])
                    .fill(Color.white.opacity(0.55))
                UnitPoly(pts: [(0.63, 0.62), (0.73, 0.36), (0.80, 0.36), (0.70, 0.62)])
                    .fill(Color.white.opacity(0.55))
            }

        case .scarf:                                   // 橙围巾：渐变围条 + 奶白条纹 + 垂尾流苏
            let o1 = Color(red: 0.96, green: 0.56, blue: 0.24)
            let o2 = Color(red: 0.82, green: 0.38, blue: 0.10)
            let cream = Color(red: 1.0, green: 0.93, blue: 0.80)
            ZStack {
                bar(0.06, 0.24, 0.88, 0.22, 0.11, vGrad(o1, o2))
                bar(0.24, 0.24, 0.07, 0.22, 0.02, cream)
                bar(0.44, 0.24, 0.07, 0.22, 0.02, cream)
                bar(0.58, 0.38, 0.18, 0.42, 0.08, vGrad(o2, o1.opacity(0.9)))
                bar(0.58, 0.58, 0.18, 0.06, 0.02, cream)
                bar(0.585, 0.80, 0.04, 0.10, 0.02, o2)
                bar(0.647, 0.80, 0.04, 0.10, 0.02, o2)
                bar(0.709, 0.80, 0.04, 0.10, 0.02, o2)
            }

        case .collar:                                  // 红项圈 + 金铃铛
            let strap = Color(red: 0.85, green: 0.22, blue: 0.26)
            let bellDark = Color(red: 0.55, green: 0.38, blue: 0.08)
            ZStack {
                GeometryReader { g in
                    Ellipse()
                        .strokeBorder(strap, lineWidth: 0.13 * g.size.width)
                        .frame(width: 0.66 * g.size.width, height: 0.48 * g.size.height)
                        .offset(x: 0.17 * g.size.width, y: 0.14 * g.size.height)
                }
                dot(0.35, 0.50, 0.30, 0.30,
                    vGrad(Color(red: 1.0, green: 0.88, blue: 0.52),
                          Color(red: 0.78, green: 0.56, blue: 0.14)))
                bar(0.39, 0.64, 0.22, 0.035, 0.015, bellDark)
                dot(0.47, 0.68, 0.06, 0.06, bellDark)
                dot(0.39, 0.53, 0.08, 0.06, shine)
            }

        case .wizard:                                  // 紫巫师帽：渐变尖顶 + 帽檐 + 金带星月
            let p1 = Color(red: 0.52, green: 0.44, blue: 0.85)
            let p2 = Color(red: 0.28, green: 0.22, blue: 0.56)
            let gold = Color(red: 0.99, green: 0.86, blue: 0.50)
            ZStack {
                UnitPoly(pts: [(0.50, 0.06), (0.25, 0.62), (0.75, 0.62)])
                    .fill(vGrad(p1, p2))
                dot(0.08, 0.56, 0.84, 0.20, vGrad(p2, p1.opacity(0.85)))
                bar(0.29, 0.53, 0.42, 0.075, 0.03, Color(red: 0.96, green: 0.78, blue: 0.34))
                UnitPoly(pts: [(0.50, 0.22), (0.53, 0.31), (0.50, 0.40), (0.47, 0.31)]).fill(gold)
                UnitPoly(pts: [(0.41, 0.31), (0.50, 0.28), (0.59, 0.31), (0.50, 0.34)]).fill(gold)
                dot(0.58, 0.42, 0.05, 0.05, gold)
                dot(0.38, 0.44, 0.04, 0.04, Color.white.opacity(0.7))
            }
        }
    }
}

private struct WardrobeStrip: View {
    @Binding var selectedRaw: String
    @AppStorage("appLanguage") private var appLanguage: String = "zh"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Outfit.allCases) { o in
                    let selected = selectedRaw == o.rawValue
                    Button {
                        selectedRaw = o.rawValue
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 4) {
                            // 只展示配饰本体，不画猫——猫在上方主舞台已经是主体了
                            ZStack {
                                if o == .none {
                                    Image(systemName: "nosign")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(LCD.pixel.opacity(0.55))
                                } else {
                                    OutfitIcon(outfit: o)
                                        .padding(3)
                                }
                            }
                            .frame(width: 46, height: 40)
                            Text(appLanguage == "en" ? o.labelEN : o.label)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LCD.pixel)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LCD.pixel.opacity(selected ? 0.16 : 0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(LCD.pixel.opacity(selected ? 0.9 : 0.25),
                                              lineWidth: selected ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - 局域网电脑桌宠发现与召唤
//
// 桌宠 App（Mac/Windows）常驻时用 Bonjour `_petpal._tcp` 广播自己；这里浏览同一
// 网络并列出，点「召唤」直接对该机器的随机端口发一个裸 HTTP GET /summon
//（走 NWConnection，不经 URLSession/ATS），电脑上的悬浮猫立刻现身。
@MainActor
@Observable
private final class DesktopPetFinder {
    struct Machine: Identifiable {
        let id: String
        let name: String        // 广播名，如 "Mac · 小明的MacBook"
        let platform: String    // "mac" / "windows"
        let result: NWBrowser.Result
    }

    var machines: [Machine] = []
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_petpal._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.update(results) }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
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

    func summon(_ machine: Machine, done: @escaping @MainActor (Bool) -> Void) {
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
                let req = "GET /summon HTTP/1.1\r\nHost: petpal\r\nConnection: close\r\n\r\n"
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
        // 5 秒兜底超时
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish(false) }
    }
}

// MARK: - 延伸面板：把 TA 带到更多屏幕（手机小组件 / 电脑桌宠）

private struct ExtendPetSheet: View {
    var model: TamagotchiModel
    @Environment(\.dismiss) private var dismiss
    @State private var widgetSynced = false
    @State private var finder = DesktopPetFinder()
    @State private var summonState: [String: SummonStatus] = [:]

    private enum SummonStatus { case busy, done, failed }

    var body: some View {
        ZStack {
            LinearGradient(colors: [LCD.screen, LCD.screenDeep],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    widgetCard
                    desktopCard
                    Text("同一只猫 · 同一份数据：装扮、喂食记录、行为状态在手机、小组件、电脑桌宠之间实时同源。")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LCD.pixel.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("带 TA 去更多屏幕")
                    .font(.system(size: 17, weight: .heavy))
                Text("小组件挂桌面 · 桌宠浮在电脑上")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.6)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(LCD.pixel.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(LCD.pixel)
    }

    // MARK: 手机小组件卡

    private var widgetCard: some View {
        extendCard {
            HStack(spacing: 10) {
                Image(systemName: "apps.iphone")
                    .font(.system(size: 22, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("手机小组件")
                        .font(.system(size: 14, weight: .bold))
                    Text("主屏幕 / 锁屏随时看一眼")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.6)
                }
                Spacer()
                readyTag("已就绪")
            }

            stepLine("1", "点下方按钮，把当前形象与三围推上小组件")
            stepLine("2", "回到桌面长按空白处 → 左上角「＋」")
            stepLine("3", "搜「PetCollar」→ 添加「电子宠物」")

            Button {
                model.pushToWidget()
                widgetSynced = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label(widgetSynced ? "已同步到小组件 ✓" : "同步到小组件",
                      systemImage: widgetSynced ? "checkmark.circle.fill" : "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LCD.pixel.opacity(widgetSynced ? 0.16 : 0.85))
                    )
                    .foregroundStyle(widgetSynced ? LCD.pixel : LCD.screen)
            }
            .buttonStyle(TamagotchiButtonStyle())
        }
    }

    // MARK: 电脑桌宠卡（自动发现 + 一键召唤）

    private var desktopCard: some View {
        extendCard {
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 22, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("电脑桌宠")
                        .font(.system(size: 14, weight: .bold))
                    Text("同一 Wi-Fi 下自动找到你的电脑")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.6)
                }
                Spacer()
                readyTag("Mac / Win")
            }

            if finder.machines.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(LCD.pixel)
                    Text("正在搜索附近的电脑…")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                ForEach(finder.machines) { m in
                    machineRow(m)
                }
            }

            Text("没找到？在电脑上启动一次桌宠 App 即可被发现（Mac：DesktopPet.app · Windows：PetPel桌宠.exe），之后手机点一下猫就出来。")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(LCD.pixel.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            finder.start()
        }
        .onDisappear {
            finder.stop()
        }
    }

    private func machineRow(_ m: DesktopPetFinder.Machine) -> some View {
        let status = summonState[m.id]
        return HStack(spacing: 10) {
            Image(systemName: m.platform == "windows" ? "pc" : "macbook")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 24)
            Text(m.name)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
            Spacer()
            Button {
                summonState[m.id] = .busy
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                finder.summon(m) { ok in
                    summonState[m.id] = ok ? .done : .failed
                }
            } label: {
                Group {
                    switch status {
                    case .busy:
                        ProgressView().controlSize(.mini).tint(LCD.screen)
                    case .done:
                        Label("已召唤", systemImage: "checkmark")
                    case .failed:
                        Label("重试", systemImage: "arrow.clockwise")
                    case nil:
                        Label("召唤", systemImage: "sparkles")
                    }
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(LCD.pixel.opacity(status == .done ? 0.16 : 0.85)))
                .foregroundStyle(status == .done ? LCD.pixel : LCD.screen)
            }
            .buttonStyle(TamagotchiButtonStyle())
            .disabled(status == .busy)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(LCD.pixel.opacity(0.06)))
    }

    // MARK: 小部件

    private func extendCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .foregroundStyle(LCD.pixel)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(LCD.pixel.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(LCD.pixel.opacity(0.3), lineWidth: 1.5)
            )
    }

    private func stepLine(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n)
                .font(.system(size: 10, weight: .heavy))
                .frame(width: 16, height: 16)
                .background(Circle().fill(LCD.pixel.opacity(0.12)))
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readyTag(_ text: String, dimmed: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(LCD.pixel.opacity(dimmed ? 0.08 : 0.85)))
            .foregroundStyle(dimmed ? LCD.pixel.opacity(0.5) : LCD.screen)
    }
}

// MARK: - 汤姆猫语音（按住录音 → 升调复读；部位互动 TTS 猫叫）

enum CatPart {
    case head, body, tail
}

@MainActor
@Observable
final class TomVoice {
    var isRecording = false
    var isReplaying = false
    var lastHint: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let pitchUnit = AVAudioUnitTimePitch()
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private var configured = false

    private var recordURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tom_mimic.caf")
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        pitchUnit.pitch = 600    // 升 6 个半音的"汤姆猫嗓"
        pitchUnit.rate = 1.15
        engine.attach(player)
        engine.attach(pitchUnit)
        engine.connect(player, to: pitchUnit, format: nil)
        engine.connect(pitchUnit, to: engine.mainMixerNode, format: nil)
        configured = true
    }

    func startListening() {
        AVAudioApplication.requestRecordPermission { ok in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if ok {
                    self.beginRecording()
                } else {
                    self.lastHint = "没有麦克风权限"
                }
            }
        }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        do {
            try configureIfNeeded()
            try? FileManager.default.removeItem(at: recordURL)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
            ]
            let rec = try AVAudioRecorder(url: recordURL, settings: settings)
            guard rec.record() else {
                lastHint = "麦克风不可用"
                return
            }
            recorder = rec
            isRecording = true
            lastHint = nil
        } catch {
            isRecording = false
            lastHint = "录音失败 \(error.localizedDescription)"
        }
    }

    func stopAndReplay() {
        guard isRecording, let rec = recorder else { return }
        let duration = rec.currentTime
        rec.stop()
        recorder = nil
        isRecording = false
        // 不到 0.25 秒基本是误触，不学
        guard duration > 0.25,
              let readFile = try? AVAudioFile(forReading: recordURL) else { return }
        isReplaying = true
        if !engine.isRunning { try? engine.start() }
        player.stop()
        player.scheduleFile(readFile, at: nil) {
            Task { @MainActor [weak self] in
                self?.isReplaying = false
            }
        }
        player.play()
    }

    /// 部位互动配音：TTS 高音短句当猫叫
    func meow(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.pitchMultiplier = 1.9
        u.rate = 0.45
        synth.speak(u)
    }
}

// MARK: - 3D 卡通猫（汤姆猫风写实卡通，SceneKit 几何体拼装）

struct TomCatView: UIViewRepresentable {
    let outfit: Outfit
    let behavior: TamagotchiModel.Behavior
    var talking: Bool = false
    var onPart: (CatPart) -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false   // 场景自带三点光
        view.allowsCameraControl = true
        view.scene = Self.buildScene(outfit: outfit)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.apply(behavior: behavior, in: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onPart = onPart
        if context.coordinator.outfit != outfit {
            context.coordinator.outfit = outfit
            view.scene?.rootNode.childNode(withName: "cat", recursively: false)?
                .removeFromParentNode()
            view.scene?.rootNode.addChildNode(Self.buildCatNode(outfit: outfit))
            context.coordinator.lastBehavior = nil
            context.coordinator.talking = false
        }
        if context.coordinator.lastBehavior != behavior {
            context.coordinator.apply(behavior: behavior, in: view)
        }
        if context.coordinator.talking != talking {
            context.coordinator.talking = talking
            context.coordinator.setTalking(talking, in: view)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPart: onPart, outfit: outfit)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPart: (CatPart) -> Void
        var outfit: Outfit
        var lastBehavior: TamagotchiModel.Behavior?
        var talking = false

        init(onPart: @escaping (CatPart) -> Void, outfit: Outfit) {
            self.onPart = onPart
            self.outfit = outfit
        }

        /// 命中测试：摸头 / 戳肚子 / 拽尾巴，各有各的反应
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let point = gesture.location(in: view)
            guard let hit = view.hitTest(point, options: nil).first else { return }
            var node: SCNNode? = hit.node
            while let n = node {
                let part: CatPart?
                switch n.name {
                case "head", "outfit-head": part = .head
                case "body", "outfit-body": part = .body
                case "tail": part = .tail
                default: part = nil
                }
                if let part {
                    animate(part, in: view)
                    onPart(part)
                    return
                }
                node = n.parent
            }
        }

        private func animate(_ part: CatPart, in view: SCNView) {
            let name: String
            switch part {
            case .head: name = "head"
            case .body: name = "body"
            case .tail: name = "tail"
            }
            guard let node = view.scene?.rootNode.childNode(withName: name, recursively: true) else { return }
            switch part {
            case .head:
                node.runAction(.sequence([
                    .rotateBy(x: 0.3, y: 0, z: 0, duration: 0.12),
                    .rotateBy(x: -0.3, y: 0, z: 0, duration: 0.12),
                    .rotateBy(x: 0.3, y: 0, z: 0, duration: 0.12),
                    .rotateBy(x: -0.3, y: 0, z: 0, duration: 0.12),
                ]))
            case .body:
                node.runAction(.sequence([
                    .scale(to: 0.88, duration: 0.10),
                    .scale(to: 1.08, duration: 0.12),
                    .scale(to: 1.0, duration: 0.10),
                ]))
            case .tail:
                node.runAction(.repeat(.sequence([
                    .rotateBy(x: 0, y: 0.6, z: 0, duration: 0.08),
                    .rotateBy(x: 0, y: -0.6, z: 0, duration: 0.08),
                ]), count: 3))
            }
        }

        /// 学舌时点头说话
        func setTalking(_ on: Bool, in view: SCNView) {
            guard let head = view.scene?.rootNode.childNode(withName: "head", recursively: true) else { return }
            head.removeAllActions()
            if on {
                head.runAction(.repeatForever(.sequence([
                    .rotateBy(x: 0.22, y: 0, z: 0, duration: 0.12),
                    .rotateBy(x: -0.22, y: 0, z: 0, duration: 0.12),
                ])), forKey: "talk")
            } else {
                head.runAction(.rotateTo(x: 0, y: 0, z: 0, duration: 0.15))
            }
        }

        func apply(behavior: TamagotchiModel.Behavior, in view: SCNView) {
            lastBehavior = behavior
            guard let scene = view.scene,
                  let cat = scene.rootNode.childNode(withName: "cat", recursively: false) else { return }
            let head = cat.childNode(withName: "head", recursively: false)
            let bowl = scene.rootNode.childNode(withName: "bowl", recursively: false)
            let zzz = cat.childNode(withName: "zzz", recursively: false)
            let eyelids = head?.childNode(withName: "eyelids", recursively: false)

            cat.removeAllActions()
            cat.position = SCNVector3(0, 0, 0)
            cat.eulerAngles = SCNVector3(0, 0, 0)
            cat.scale = SCNVector3(1, 1, 1)
            // 头部回正（学舌中不打断说话动画）
            if !talking {
                head?.removeAllActions()
                head?.runAction(.rotateTo(x: 0, y: 0, z: 0, duration: 0.2))
            }

            // 道具按行为显隐：食碗 / 闭眼皮 / Z 泡泡
            bowl?.isHidden = behavior != .eating
            eyelids?.isHidden = behavior != .sleeping
            zzz?.isHidden = behavior != .sleeping

            func eased(_ a: SCNAction) -> SCNAction {
                a.timingMode = .easeInEaseOut
                return a
            }

            let tail = cat.childNode(withName: "tail", recursively: false)

            // 趴姿是基线，走路才站起来长出四条腿
            let walking = behavior == .walking
            let legs = cat.childNode(withName: "legs", recursively: true)
            let lyingLimbs = cat.childNode(withName: "lyingLimbs", recursively: true)
            cat.position = SCNVector3(0, walking ? 0.6 : 0, 0)
            legs?.isHidden = !walking
            lyingLimbs?.isHidden = walking
            if !walking {
                for name in ["legFL", "legFR", "legBL", "legBR"] {
                    if let leg = cat.childNode(withName: name, recursively: true) {
                        leg.removeAllActions()
                        leg.eulerAngles = SCNVector3(0, 0, 0)
                    }
                }
            }
            if walking {
                // 站立时尾巴翘起
                tail?.runAction(eased(.rotateTo(x: -0.9, y: 0, z: 0, duration: 0.4)),
                                forKey: "tailUp")
            } else {
                tail?.runAction(.rotateTo(x: 0, y: 0, z: 0, duration: 0.3), forKey: "tailDown")
            }

            switch behavior {
            case .idle:
                // 轻微浮动打底 + 随机小剧场（张望/歪头/舔爪/甩尾/小跳）
                cat.runAction(.repeatForever(.sequence([
                    eased(.moveBy(x: 0, y: 0.18, z: 0, duration: 1.2)),
                    eased(.moveBy(x: 0, y: -0.18, z: 0, duration: 1.2)),
                ])), forKey: "float")
                cat.runAction(Self.idleVignettes(cat: cat, head: head, tail: tail),
                              forKey: "vignettes")

            case .walking:
                // 台上来回踱步：转身 + 小碎步颠 + 左右摇摆 + 微微昂头
                let patrol = SCNAction.sequence([
                    eased(.rotateTo(x: 0, y: 0.85, z: 0, duration: 0.35)),
                    .moveBy(x: 2.3, y: 0, z: 0, duration: 2.4),
                    eased(.rotateTo(x: 0, y: -0.85, z: 0, duration: 0.6)),
                    .moveBy(x: -4.6, y: 0, z: 0, duration: 4.8),
                    eased(.rotateTo(x: 0, y: 0.85, z: 0, duration: 0.6)),
                    .moveBy(x: 2.3, y: 0, z: 0, duration: 2.4),
                ])
                cat.runAction(.repeatForever(patrol), forKey: "patrol")
                cat.runAction(.repeatForever(.sequence([
                    .moveBy(x: 0, y: 0.1, z: 0, duration: 0.18),
                    .moveBy(x: 0, y: -0.1, z: 0, duration: 0.18),
                ])), forKey: "trot")
                cat.runAction(.repeatForever(.sequence([
                    .rotateBy(x: 0, y: 0, z: 0.05, duration: 0.18),
                    .rotateBy(x: 0, y: 0, z: -0.10, duration: 0.36),
                    .rotateBy(x: 0, y: 0, z: 0.05, duration: 0.18),
                ])), forKey: "waddle")
                if !talking {
                    head?.runAction(eased(.rotateTo(x: -0.12, y: 0, z: 0, duration: 0.3)),
                                    forKey: "headUp")
                }
                // 对角步态：左前+右后一组，右前+左后一组，反相摆动
                for (name, phase) in [("legFL", true), ("legBR", true),
                                      ("legFR", false), ("legBL", false)] {
                    guard let leg = cat.childNode(withName: name, recursively: true) else { continue }
                    let amp: CGFloat = 0.55
                    let swingF = eased(.rotateTo(x: amp, y: 0, z: 0, duration: 0.36))
                    let swingB = eased(.rotateTo(x: -amp, y: 0, z: 0, duration: 0.36))
                    let loop = SCNAction.repeatForever(.sequence(phase ? [swingF, swingB]
                                                                       : [swingB, swingF]))
                    leg.runAction(.sequence([
                        eased(.rotateTo(x: phase ? -amp : amp, y: 0, z: 0, duration: 0.18)),
                        loop,
                    ]), forKey: "swing")
                }

            case .eating:
                // 凑向食碗：低头 → 咀嚼三下 → 抬头回味，节奏随机
                cat.runAction(eased(.moveBy(x: 0, y: 0, z: 0.5, duration: 0.5)))
                if !talking {
                    let chew = SCNAction.sequence([
                        .rotateBy(x: -0.07, y: 0, z: 0, duration: 0.09),
                        .rotateBy(x: 0.07, y: 0, z: 0, duration: 0.09),
                    ])
                    head?.runAction(.repeatForever(.sequence([
                        eased(.rotateBy(x: 0.5, y: 0, z: 0, duration: 0.35)),
                        .repeat(chew, count: 3),
                        eased(.rotateBy(x: -0.5, y: 0, z: 0, duration: 0.4)),
                        .wait(duration: 0.3, withRange: 0.4),
                    ])), forKey: "eat")
                }

            case .happy:
                // 蓄力下蹲再起跳，更有弹性
                cat.runAction(.repeatForever(.sequence([
                    eased(.scale(to: 0.93, duration: 0.1)),
                    eased(.scale(to: 1.0, duration: 0.08)),
                    eased(.moveBy(x: 0, y: 2.2, z: 0, duration: 0.2)),
                    eased(.moveBy(x: 0, y: -2.2, z: 0, duration: 0.22)),
                    .wait(duration: 0.2),
                ])))

            case .sleeping:
                // 下巴贴胸 + 缓慢深呼吸（眼皮和 Z 泡泡已显示）
                if !talking {
                    head?.runAction(eased(.rotateTo(x: 0.22, y: 0, z: 0, duration: 0.6)), forKey: "settle")
                }
                cat.runAction(.repeatForever(.sequence([
                    eased(.scale(to: 1.04, duration: 1.6)),
                    eased(.scale(to: 1.0, duration: 1.6)),
                ])))
            }
        }

        /// 待机随机小剧场：每隔 2~4 秒随机演一个，全部以 rotateTo 收尾保证回正
        private static func idleVignettes(cat: SCNNode, head: SCNNode?, tail: SCNNode?) -> SCNAction {
            func eased(_ a: SCNAction) -> SCNAction {
                a.timingMode = .easeInEaseOut
                return a
            }
            return .repeatForever(.sequence([
                .wait(duration: 2.2, withRange: 2.0),
                .run { node in
                    guard let head, let tail else { return }
                    switch Int.random(in: 0..<5) {
                    case 0:
                        // 左右张望
                        head.runAction(.sequence([
                            eased(.rotateTo(x: 0, y: 0.55, z: 0, duration: 0.4)),
                            .wait(duration: 0.5),
                            eased(.rotateTo(x: 0, y: -0.5, z: 0, duration: 0.55)),
                            .wait(duration: 0.45),
                            eased(.rotateTo(x: 0, y: 0, z: 0, duration: 0.4)),
                        ]), forKey: "vig")
                    case 1:
                        // 歪头杀
                        head.runAction(.sequence([
                            eased(.rotateTo(x: 0, y: 0, z: 0.3, duration: 0.35)),
                            .wait(duration: 0.8),
                            eased(.rotateTo(x: 0, y: 0, z: 0, duration: 0.35)),
                        ]), forKey: "vig")
                    case 2:
                        // 舔爪洗脸：偏头低向右前爪，小口舔三下
                        let lick = SCNAction.sequence([
                            .rotateBy(x: 0.1, y: 0, z: 0, duration: 0.11),
                            .rotateBy(x: -0.1, y: 0, z: 0, duration: 0.11),
                        ])
                        head.runAction(.sequence([
                            eased(.rotateTo(x: 0.35, y: 0.35, z: 0.1, duration: 0.3)),
                            .repeat(lick, count: 3),
                            eased(.rotateTo(x: 0, y: 0, z: 0, duration: 0.35)),
                        ]), forKey: "vig")
                    case 3:
                        // 快速甩尾
                        tail.runAction(.repeat(.sequence([
                            .rotateBy(x: 0, y: 0.7, z: 0, duration: 0.09),
                            .rotateBy(x: 0, y: -0.7, z: 0, duration: 0.09),
                        ]), count: 4), forKey: "vig")
                    default:
                        // 小跳 + 抖身
                        node.runAction(.sequence([
                            eased(.moveBy(x: 0, y: 0.7, z: 0, duration: 0.16)),
                            eased(.moveBy(x: 0, y: -0.7, z: 0, duration: 0.16)),
                            .repeat(.sequence([
                                .rotateBy(x: 0, y: 0, z: 0.05, duration: 0.06),
                                .rotateBy(x: 0, y: 0, z: -0.05, duration: 0.06),
                            ]), count: 4),
                        ]), forKey: "vigBody")
                    }
                },
            ]))
        }
    }

    // MARK: 场景构建

    static func buildScene(outfit: Outfit) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.rootNode.addChildNode(buildCatNode(outfit: outfit))

        let pivot = SCNNode()
        pivot.position = SCNVector3(0, 1.7, 0)
        scene.rootNode.addChildNode(pivot)

        let camNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 40   // 长焦减畸变，更像产品渲染
        camera.screenSpaceAmbientOcclusionIntensity = 0.6
        camera.screenSpaceAmbientOcclusionRadius = 0.8
        camNode.camera = camera
        camNode.position = SCNVector3(3.6, 4.3, 14.2)
        let lookAt = SCNLookAtConstraint(target: pivot)
        camNode.constraints = [lookAt]
        scene.rootNode.addChildNode(camNode)

        // 柔和的卡通三点光 + 真实软阴影
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = UIColor(white: 1.0, alpha: 1)
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowColor = UIColor(white: 0, alpha: 0.3)
        key.light?.shadowRadius = 9
        key.light?.shadowSampleCount = 16
        key.eulerAngles = SCNVector3(-Float.pi / 4, -Float.pi / 6, 0)
        scene.rootNode.addChildNode(key)

        // 隐形接影地面：只显示影子不显示自身
        let floorGeo = SCNFloor()
        floorGeo.reflectivity = 0
        let floorMat = SCNMaterial()
        floorMat.lightingModel = .constant
        floorMat.writesToDepthBuffer = true
        floorMat.colorBufferWriteMask = []
        floorGeo.materials = [floorMat]
        let floor = SCNNode(geometry: floorGeo)
        floor.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(floor)

        // 食碗（吃饭行为时显示）
        let bowl = SCNNode()
        bowl.name = "bowl"
        bowl.isHidden = true
        bowl.position = SCNVector3(0, 0, 3.2)
        bowl.addChildNode(node(SCNCylinder(radius: 0.78, height: 0.42),
                               UIColor(red: 0.36, green: 0.62, blue: 0.66, alpha: 1),
                               pos: SCNVector3(0, 0.21, 0)))
        bowl.addChildNode(node(SCNTorus(ringRadius: 0.74, pipeRadius: 0.09),
                               UIColor(red: 0.30, green: 0.54, blue: 0.58, alpha: 1),
                               pos: SCNVector3(0, 0.43, 0)))
        for (dx, dz, r) in [(Float(0), Float(0), Float(0.17)),
                            (Float(0.25), Float(0.12), Float(0.14)),
                            (Float(-0.22), Float(0.15), Float(0.13)),
                            (Float(0.1), Float(-0.22), Float(0.14)),
                            (Float(-0.15), Float(-0.18), Float(0.12))] {
            bowl.addChildNode(node(SCNSphere(radius: CGFloat(r)),
                                   UIColor(red: 0.62, green: 0.42, blue: 0.25, alpha: 1),
                                   pos: SCNVector3(dx, 0.46, dz)))
        }
        scene.rootNode.addChildNode(bowl)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.color = UIColor(white: 0.35, alpha: 1)
        fill.eulerAngles = SCNVector3(-Float.pi / 8, Float.pi * 0.75, 0)
        scene.rootNode.addChildNode(fill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.color = UIColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 1).withAlphaComponent(0.5)
        rim.eulerAngles = SCNVector3(-Float.pi / 5, Float.pi, 0)
        scene.rootNode.addChildNode(rim)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.52, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        return scene
    }

    // MARK: 卡通猫造型（汤姆猫风：圆头大眼，几何体拼装，无需模型资源）

    private static let furColor = UIColor(red: 0.97, green: 0.63, blue: 0.28, alpha: 1)    // 暖橘
    private static let stripeColor = UIColor(red: 0.89, green: 0.52, blue: 0.23, alpha: 1) // 深橘虎斑（柔和）
    private static let creamColor = UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1)  // 奶白
    private static let creamBody = UIColor(red: 0.99, green: 0.97, blue: 0.92, alpha: 1)    // 暖奶白（身体主色）
    private static let pinkColor = UIColor(red: 0.95, green: 0.62, blue: 0.66, alpha: 1)
    private static let blushColor = UIColor(red: 0.99, green: 0.78, blue: 0.74, alpha: 1)  // 腮红（淡雅）
    private static let eyeGreen = UIColor(red: 0.40, green: 0.75, blue: 0.34, alpha: 1)
    private static let darkColor = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)

    /// gloss: 0=哑光绒毛, 1=水润高光（眼睛/鼻头）
    private static func mat(_ color: UIColor, gloss: CGFloat = 0.1) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .blinn
        m.specular.contents = UIColor(white: gloss, alpha: 1)
        m.shininess = max(0.05, gloss)
        return m
    }

    private static func node(_ geometry: SCNGeometry, _ color: UIColor,
                             pos: SCNVector3,
                             scale: SCNVector3 = SCNVector3(1, 1, 1),
                             euler: SCNVector3 = SCNVector3(0, 0, 0),
                             gloss: CGFloat = 0.1) -> SCNNode {
        geometry.materials = [mat(color, gloss: gloss)]
        let n = SCNNode(geometry: geometry)
        n.position = pos
        n.scale = scale
        n.eulerAngles = euler
        return n
    }

    /// 放样生成一根渐细弯曲的连续锥形尾巴：沿中心曲线采样圆环、半径渐变、连成三角面，
    /// 虎斑环纹与奶白尾尖用顶点颜色画出。一根几何体，光滑连续不断节。
    private static func makeTailNode() -> SCNNode {
        let lengthSegs = 18      // 沿尾巴方向的环数
        let radialSegs = 12      // 每环的顶点数（横截面圆）

        func rgba(_ c: UIColor) -> simd_float4 {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return simd_float4(Float(r), Float(g), Float(b), Float(a))
        }

        // 中心曲线 + 半径 + 颜色采样
        var centers: [simd_float3] = []
        var radii: [Float] = []
        var ringColors: [simd_float4] = []
        for i in 0...lengthSegs {
            let t = Float(i) / Float(lengthSegs)
            let z = 2.2 * t                                                    // 狸花猫尾略短于身长
            let x = 0.30 * sin(t * .pi * 0.7)                                  // 轻微 S 形横摆
            let y = 0.05 * t + (t > 0.6 ? (t - 0.6) * (t - 0.6) * 3.0 : 0)     // 尾尖优雅上翘
            centers.append(simd_float3(x, y, z))
            // 狸花猫尾粗壮、从根到尖不突然变细，仅末端略收
            radii.append(0.27 - 0.085 * t - (t > 0.85 ? (t - 0.85) * 0.6 : 0))
            let c: UIColor
            if t > 0.9 { c = creamColor }                                      // 奶白尾尖
            // 狸花猫尾环纹：多道深色环
            else if abs(t - 0.22) < 0.04 || abs(t - 0.44) < 0.04
                 || abs(t - 0.66) < 0.04 || abs(t - 0.85) < 0.04 { c = stripeColor }
            else { c = furColor }
            ringColors.append(rgba(c))
        }

        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var cols: [simd_float4] = []
        var idx: [Int32] = []
        let n = centers.count

        // 每个中心点建一圈顶点，法平面坐标系由切线 + 固定 up 叉乘得到（曲线平缓不会翻转）
        for i in 0..<n {
            let tangent: simd_float3
            if i == 0 { tangent = simd_normalize(centers[1] - centers[0]) }
            else if i == n - 1 { tangent = simd_normalize(centers[n - 1] - centers[n - 2]) }
            else { tangent = simd_normalize(centers[i + 1] - centers[i - 1]) }
            var up = simd_float3(0, 1, 0)
            if abs(simd_dot(tangent, up)) > 0.9 { up = simd_float3(1, 0, 0) }
            let side = simd_normalize(simd_cross(tangent, up))
            let realUp = simd_normalize(simd_cross(side, tangent))
            for j in 0..<radialSegs {
                let a = Float(j) / Float(radialSegs) * 2 * .pi
                let dir = side * cos(a) + realUp * sin(a)
                let p = centers[i] + dir * radii[i]
                verts.append(SCNVector3(p.x, p.y, p.z))
                norms.append(SCNVector3(dir.x, dir.y, dir.z))
                cols.append(ringColors[i])
            }
        }
        // 相邻两环之间连四边形（两个三角，法线朝外）
        for i in 0..<(n - 1) {
            for j in 0..<radialSegs {
                let j2 = (j + 1) % radialSegs
                let a = Int32(i * radialSegs + j)
                let b = Int32(i * radialSegs + j2)
                let c = Int32((i + 1) * radialSegs + j2)
                let d = Int32((i + 1) * radialSegs + j)
                idx += [a, d, b, b, d, c]
            }
        }
        // 尾尖封口成一个点
        let tipDir = simd_normalize(centers[n - 1] - centers[n - 2])
        let tip = centers[n - 1] + tipDir * radii[n - 1]
        let tipIdx = Int32(verts.count)
        verts.append(SCNVector3(tip.x, tip.y, tip.z))
        norms.append(SCNVector3(tipDir.x, tipDir.y, tipDir.z))
        cols.append(ringColors[n - 1])
        for j in 0..<radialSegs {
            let j2 = (j + 1) % radialSegs
            idx += [Int32((n - 1) * radialSegs + j), tipIdx, Int32((n - 1) * radialSegs + j2)]
        }

        let vSrc = SCNGeometrySource(vertices: verts)
        let nSrc = SCNGeometrySource(normals: norms)
        let cData = cols.withUnsafeBytes { Data($0) }
        let cSrc = SCNGeometrySource(data: cData, semantic: .color, vectorCount: cols.count,
                                     usesFloatComponents: true, componentsPerVector: 4,
                                     bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                     dataStride: MemoryLayout<simd_float4>.stride)
        let elem = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [vSrc, nSrc, cSrc], elements: [elem])

        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = UIColor.white     // 顶点色乘以白 = 显示顶点色
        m.specular.contents = UIColor(white: 0.12, alpha: 1)
        m.shininess = 0.1
        m.isDoubleSided = true
        geo.materials = [m]
        return SCNNode(geometry: geo)
    }

    // MARK: Rigged 模型加载（USDZ/USD/SCN）—— 可选，放入即自动替换程序化猫
    //
    // 放一个带骨骼(SCNSkinner)的猫模型，命名 cat.usdz（或 .usdc/.usda/.scn）：
    //   • 生产：拖进 Xcode 工程，确保在 PetCollar target 的 "Copy Bundle Resources" 里
    //   • 开发热替换：推到 app 沙盒 Documents/（免改工程、免重编）
    //       xcrun simctl get_app_container booted com.petcollar.PetCollar data → 拷到其 Documents/
    // 找不到模型时回退到几何体拼装猫，app 照常运行。
    // 首次进 3D 会在控制台打印 "🦴 skeleton dump"（仅 Debug），里面是真实关节名 ——
    // 拿到名字即可把 睡觉/走动/吃饭/idle 等行为映射到真骨骼。

    private static let modelBaseName = "cat"
    private static let modelExts = ["usdz", "usdc", "usda", "scn"]

    #if DEBUG
    private static func dbg(_ s: String) { print("[TomCat3D] \(s)") }
    #else
    private static func dbg(_ s: String) {}
    #endif

    private static func riggedModelURL() -> URL? {
        for ext in modelExts {
            if let u = Bundle.main.url(forResource: modelBaseName, withExtension: ext) { return u }
        }
        if let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: false) {
            for ext in modelExts {
                let u = docs.appendingPathComponent("\(modelBaseName).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { return u }
            }
        }
        return nil
    }

    /// 加载带骨骼的猫模型；不存在/失败返回 nil → 回退程序化猫
    static func loadRiggedCatNode(outfit: Outfit) -> SCNNode? {
        guard let url = riggedModelURL() else {
            dbg("未找到 \(modelBaseName).usdz/.scn，使用程序化猫（放入模型即自动替换）")
            return nil
        }
        do {
            let scene = try SCNScene(url: url, options: [.checkConsistency: true, .convertToYUp: true])
            let container = SCNNode(); container.name = "cat"   // 外层保持 identity（apply() 会重置它的 transform）
            let model = SCNNode(); model.name = "catModel"      // 缩放/平移挂内层，不被 apply() 清掉
            for child in scene.rootNode.childNodes { model.addChildNode(child) }
            normalize(model, targetHeight: 3.4)
            container.addChildNode(model)
            dumpSkeleton(container)
            dbg("✅ 已加载 rigged 模型 \(url.lastPathComponent)")
            return container
        } catch {
            dbg("⚠️ 加载 \(url.lastPathComponent) 失败，回退程序化猫：\(error.localizedDescription)")
            return nil
        }
    }

    /// 自动把模型缩放到目标高度、底部贴地、水平居中（下载模型单位/原点差异极大）
    private static func normalize(_ node: SCNNode, targetHeight: Float) {
        guard let (lo, hi) = measureBounds(of: node) else { dbg("⚠️ 量不到包围盒，跳过自动缩放"); return }
        let h = hi.y - lo.y
        guard h > 0.0001 else { dbg("⚠️ 包围盒高度≈0，跳过自动缩放"); return }
        let s = targetHeight / h
        node.scale = SCNVector3(s, s, s)               // lo/hi 在 node 局部空间测得，平移需乘 s
        node.position = SCNVector3(-(lo.x + hi.x) * 0.5 * s, -lo.y * s, -(lo.z + hi.z) * 0.5 * s)
        dbg("自动缩放 ×\(String(format: "%.2f", s))（原始高 \(String(format: "%.3f", h))，bbox \(fmt(lo))→\(fmt(hi))）")
    }

    /// 递归合并 model 局部空间下所有 geometry 的包围盒（含 skinned mesh —— flattenedClone 对蒙皮会返回空盒）
    private static func measureBounds(of model: SCNNode) -> (SCNVector3, SCNVector3)? {
        let big = Float.greatestFiniteMagnitude
        var lo = SCNVector3(big, big, big), hi = SCNVector3(-big, -big, -big)
        var found = false
        func recurse(_ n: SCNNode) {
            if n.geometry != nil {
                let (a, b) = n.boundingBox
                if a.x != b.x || a.y != b.y || a.z != b.z {        // 跳过空盒
                    for cx in [a.x, b.x] { for cy in [a.y, b.y] { for cz in [a.z, b.z] {
                        let p = model.convertPosition(SCNVector3(cx, cy, cz), from: n)   // → model 局部
                        lo = SCNVector3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                        hi = SCNVector3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
                        found = true
                    } } }
                }
            }
            n.childNodes.forEach(recurse)
        }
        recurse(model)
        return found ? (lo, hi) : nil
    }

    private static func fmt(_ v: SCNVector3) -> String { String(format: "(%.2f,%.2f,%.2f)", v.x, v.y, v.z) }

    /// 打印节点树 + 每个 SCNSkinner 的骨骼名（用于把动画映射到真骨骼）
    static func dumpSkeleton(_ root: SCNNode) {
        dbg("🦴 ===== skeleton dump =====")
        var total = 0
        func walk(_ n: SCNNode, _ depth: Int) {
            var tags: [String] = []
            if n.geometry != nil { tags.append("mesh") }
            if n.skinner != nil { tags.append("SKINNER") }
            if !n.animationKeys.isEmpty { tags.append("anim×\(n.animationKeys.count)") }
            dbg(String(repeating: "  ", count: depth) + "• " + (n.name ?? "<unnamed>")
                + (tags.isEmpty ? "" : " [\(tags.joined(separator: ","))]"))
            if let sk = n.skinner {
                total += sk.bones.count
                dbg(String(repeating: "  ", count: depth) + "   ⮑ bones(\(sk.bones.count)): "
                    + sk.bones.map { $0.name ?? "?" }.joined(separator: ", "))
            }
            for c in n.childNodes { walk(c, depth + 1) }
        }
        walk(root, 0)
        dbg("🦴 ===== end dump · total bones: \(total) =====")
    }

    static func buildCatNode(outfit: Outfit) -> SCNNode {
        // 有 rigged 模型（cat.usdz/.scn）就用真骨骼，否则回退几何体拼装猫
        if let rigged = loadRiggedCatNode(outfit: outfit) { return rigged }

        let container = SCNNode()
        container.name = "cat"

        // ---- 身体（趴姿"长面包"，轴心在地面，戳肚子的挤压动画贴地更卡通）----
        let body = SCNNode()
        body.name = "body"
        // 主躯干：狸花猫背部基本平坦、体格匀称结实，沿 z 拉长
        body.addChildNode(node(SCNSphere(radius: 1.5), furColor,
                               pos: SCNVector3(0, 1.02, -0.45), scale: SCNVector3(1.08, 0.72, 1.52)))
        // 前胸垫着下巴
        body.addChildNode(node(SCNSphere(radius: 0.95), furColor,
                               pos: SCNVector3(0, 1.0, 0.55), scale: SCNVector3(1.0, 0.9, 0.9)))
        body.addChildNode(node(SCNSphere(radius: 0.85), creamColor,
                               pos: SCNVector3(0, 1.05, 0.95), scale: SCNVector3(0.85, 0.85, 0.5)))
        // 颈部过渡：头和身体的衔接圆滑成一条弧线
        body.addChildNode(node(SCNSphere(radius: 1.0), furColor,
                               pos: SCNVector3(0, 1.55, 0.8), scale: SCNVector3(0.92, 0.78, 0.78)))
        // 后腿臀部（趴着拱起来）
        body.addChildNode(node(SCNSphere(radius: 0.78), furColor,
                               pos: SCNVector3(-0.92, 0.8, -1.35), scale: SCNVector3(1, 0.8, 1.15)))
        body.addChildNode(node(SCNSphere(radius: 0.78), furColor,
                               pos: SCNVector3(0.92, 0.8, -1.35), scale: SCNVector3(1, 0.8, 1.15)))
        // （已去除身体鲭鱼纹，保持纯净橘色背身）
        // 趴姿前肢（走路时隐藏）：前腿向前伸 + 大白爪
        let lyingLimbs = SCNNode()
        lyingLimbs.name = "lyingLimbs"
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            lyingLimbs.addChildNode(node(SCNCapsule(capRadius: 0.24, height: 1.3), furColor,
                                         pos: SCNVector3(x * 0.4, 0.35, 0.95),
                                         euler: SCNVector3(Float.pi / 2, 0, 0)))
            lyingLimbs.addChildNode(node(SCNSphere(radius: 0.34), creamColor,
                                         pos: SCNVector3(x * 0.4, 0.33, 1.6),
                                         scale: SCNVector3(1, 0.8, 1.25)))
        }
        body.addChildNode(lyingLimbs)

        // 站立四肢（走路时长出来）：轴心在肩/髋，摆动像钟摆
        let legs = SCNNode()
        legs.name = "legs"
        legs.isHidden = true
        func makeLeg(_ name: String, x: Float, z: Float) -> SCNNode {
            let leg = SCNNode()
            leg.name = name
            leg.position = SCNVector3(x, 1.05, z)
            leg.addChildNode(node(SCNCapsule(capRadius: 0.2, height: 1.5), furColor,
                                  pos: SCNVector3(0, -0.7, 0)))
            leg.addChildNode(node(SCNSphere(radius: 0.27), creamColor,
                                  pos: SCNVector3(0, -1.42, 0), scale: SCNVector3(1, 0.7, 1.25)))
            return leg
        }
        legs.addChildNode(makeLeg("legFL", x: -0.5, z: 0.75))
        legs.addChildNode(makeLeg("legFR", x: 0.5, z: 0.75))
        legs.addChildNode(makeLeg("legBL", x: -0.8, z: -1.2))
        legs.addChildNode(makeLeg("legBR", x: 0.8, z: -1.2))
        body.addChildNode(legs)
        // 呼吸起伏（持续微动画）
        let inhale = SCNAction.scale(to: 1.03, duration: 1.6)
        inhale.timingMode = .easeInEaseOut
        let exhale = SCNAction.scale(to: 1.0, duration: 1.6)
        exhale.timingMode = .easeInEaseOut
        body.runAction(.repeatForever(.sequence([inhale, exhale])))
        container.addChildNode(body)

        // ---- 头（萌系大头橘猫，趴着搭在前胸上，轴心在头心）----
        let head = SCNNode()
        head.name = "head"
        head.position = SCNVector3(0, 2.35, 1.05)
        head.addChildNode(node(SCNSphere(radius: 1.5), furColor,
                               pos: SCNVector3(0, 0, 0), scale: SCNVector3(1.06, 0.98, 0.94)))
        // 圆短耳：外橘内粉，右耳隔几秒抖一下（持续微动画）
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            let ear = SCNNode()
            ear.position = SCNVector3(x * 0.78, 1.25, 0)
            ear.eulerAngles = SCNVector3(0, 0, -x * 0.32)
            ear.addChildNode(node(SCNCone(topRadius: 0.1, bottomRadius: 0.5, height: 0.62), furColor,
                                  pos: SCNVector3(0, 0, 0)))
            ear.addChildNode(node(SCNCone(topRadius: 0.05, bottomRadius: 0.28, height: 0.4), pinkColor,
                                  pos: SCNVector3(-x * 0.03, -0.05, 0.16)))
            if sx > 0 {
                ear.runAction(.repeatForever(.sequence([
                    .wait(duration: 3.5),
                    .rotateBy(x: 0, y: 0, z: -0.3, duration: 0.07),
                    .rotateBy(x: 0, y: 0, z: 0.3, duration: 0.12),
                    .wait(duration: 5.0),
                    .rotateBy(x: 0, y: 0, z: -0.2, duration: 0.07),
                    .rotateBy(x: 0, y: 0, z: 0.2, duration: 0.1),
                ])))
            }
            head.addChildNode(ear)
        }
        // 额头经典"M"虎斑纹
        for (dx, dy, h) in [(Float(-0.42), Float(0.78), Float(0.55)),
                            (Float(0), Float(0.9), Float(0.65)),
                            (Float(0.42), Float(0.78), Float(0.55))] {
            head.addChildNode(node(SCNSphere(radius: 0.3), stripeColor,
                                   pos: SCNVector3(dx, dy, 0.92),
                                   scale: SCNVector3(0.32, h, 0.42)))
        }
        // 水汪大眼：白底 + 大绿瞳 + 黑瞳孔（高光泽水润）+ 双星光（常亮）
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            head.addChildNode(node(SCNSphere(radius: 0.475), stripeColor,
                                   pos: SCNVector3(x * 0.5, 0.12, 1.02), scale: SCNVector3(1, 1.2, 0.55)))
            head.addChildNode(node(SCNSphere(radius: 0.44), creamColor,
                                   pos: SCNVector3(x * 0.5, 0.12, 1.06), scale: SCNVector3(1, 1.2, 0.6),
                                   gloss: 0.55))
            head.addChildNode(node(SCNSphere(radius: 0.25), eyeGreen,
                                   pos: SCNVector3(x * 0.5, 0.1, 1.3), gloss: 0.95))
            head.addChildNode(node(SCNSphere(radius: 0.14), darkColor,
                                   pos: SCNVector3(x * 0.5, 0.09, 1.42), gloss: 0.95))
            let sparkleBig = node(SCNSphere(radius: 0.06), creamColor,
                                  pos: SCNVector3(x * 0.42, 0.22, 1.5))
            sparkleBig.geometry?.firstMaterial?.lightingModel = .constant
            head.addChildNode(sparkleBig)
            let sparkleSmall = node(SCNSphere(radius: 0.03), creamColor,
                                    pos: SCNVector3(x * 0.58, 0.0, 1.5))
            sparkleSmall.geometry?.firstMaterial?.lightingModel = .constant
            head.addChildNode(sparkleSmall)
        }
        // 闭眼皮（睡觉时盖住眼睛）
        let eyelids = SCNNode()
        eyelids.name = "eyelids"
        eyelids.isHidden = true
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            eyelids.addChildNode(node(SCNSphere(radius: 0.5), furColor,
                                      pos: SCNVector3(x * 0.5, 0.12, 1.12),
                                      scale: SCNVector3(1, 1.25, 0.95)))
        }
        head.addChildNode(eyelids)
        // 粉腮红 + 脸颊绒毛
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            head.addChildNode(node(SCNSphere(radius: 0.21), blushColor,
                                   pos: SCNVector3(x * 0.98, -0.32, 1.02),
                                   scale: SCNVector3(1.35, 0.68, 0.4)))
            // 狸花猫面颊宽大：饱满的腮帮绒毛（成年橘猫标志性大脸）
            head.addChildNode(node(SCNSphere(radius: 0.52), furColor,
                                   pos: SCNVector3(x * 1.32, -0.42, 0.42),
                                   scale: SCNVector3(0.62, 0.5, 0.62)))
        }
        // 小巧口鼻（鼻头水润）
        head.addChildNode(node(SCNSphere(radius: 0.4), creamColor,
                               pos: SCNVector3(0, -0.52, 1.05), scale: SCNVector3(1.15, 0.7, 0.55)))
        head.addChildNode(node(SCNSphere(radius: 0.09), pinkColor,
                               pos: SCNVector3(0, -0.32, 1.42), gloss: 0.9))
        // 短胡须
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            for (dy, tilt) in [(Float(0.1), Float(0.12)), (Float(-0.02), Float(0.0)), (Float(-0.14), Float(-0.12))] {
                head.addChildNode(node(SCNCylinder(radius: 0.013, height: 0.85), darkColor,
                                       pos: SCNVector3(x * 1.05, -0.48 + dy, 1.0),
                                       euler: SCNVector3(0, 0, Float.pi / 2 + x * tilt)))
            }
        }
        if let dress = buildOutfitNode(outfit), dress.name == "outfit-head" {
            head.addChildNode(dress)
        }
        container.addChildNode(head)

        if let dress = buildOutfitNode(outfit), dress.name == "outfit-body" {
            body.addChildNode(dress)
        }

        // ---- 尾巴（一根渐细弯曲的连续锥形管，放样几何，虎斑/白尖用顶点色）----
        let tail = SCNNode()
        tail.name = "tail"
        tail.position = SCNVector3(0.75, 0.32, -1.5)
        tail.addChildNode(makeTailNode())
        // 尾巴慢慢扫地（持续微动画）
        let swishL = SCNAction.rotateBy(x: 0, y: 0.45, z: 0, duration: 1.4)
        swishL.timingMode = .easeInEaseOut
        let swishR = SCNAction.rotateBy(x: 0, y: -0.45, z: 0, duration: 1.4)
        swishR.timingMode = .easeInEaseOut
        tail.runAction(.repeatForever(.sequence([swishL, swishR])))
        container.addChildNode(tail)

        // 睡觉 Z 字泡泡（升起渐隐循环，睡觉时显示）
        let zzz = SCNNode()
        zzz.name = "zzz"
        zzz.isHidden = true
        zzz.position = SCNVector3(1.2, 3.9, 1.0)
        for i in 0..<3 {
            let textGeo = SCNText(string: "Z", extrusionDepth: 0.5)
            textGeo.font = UIFont.boldSystemFont(ofSize: 10)
            textGeo.flatness = 0.3
            textGeo.materials = [mat(stripeColor)]
            let zNode = SCNNode(geometry: textGeo)
            let s = Float(0.10 + Double(i) * 0.03)
            zNode.scale = SCNVector3(s, s, s)
            let base = SCNVector3(Float(i) * 0.35, Float(i) * 0.5, 0)
            zNode.position = base
            zNode.opacity = 0
            let cycle = SCNAction.sequence([
                .wait(duration: Double(i) * 0.6),
                .run { n in
                    n.position = base
                    n.opacity = 0
                },
                .fadeIn(duration: 0.35),
                .group([
                    .moveBy(x: 0.4, y: 1.4, z: 0, duration: 2.0),
                    .sequence([.wait(duration: 1.0), .fadeOut(duration: 0.9)]),
                ]),
            ])
            zNode.runAction(.repeatForever(cycle))
            zzz.addChildNode(zNode)
        }
        container.addChildNode(zzz)

        // 接地软阴影（透明背景下隐形接影地面不稳定，保留淡椭圆兜底）
        let shadow = node(SCNSphere(radius: 1.0), UIColor.black,
                          pos: SCNVector3(0.2, 0.02, -0.2), scale: SCNVector3(2.4, 0.03, 2.7))
        shadow.geometry?.firstMaterial?.lightingModel = .constant
        shadow.geometry?.firstMaterial?.transparency = 0.13
        container.addChildNode(shadow)

        return container
    }

    /// 配饰立体造型：帽类挂在头上（跟着点头动），围巾/项圈挂在身上。
    /// 与 PetKit.CatScene.buildOutfitNode 同步（离屏渲染校准过埋没问题），改动请两边一起。
    private static func buildOutfitNode(_ outfit: Outfit) -> SCNNode? {
        let group = SCNNode()
        let c = outfit.uiColor
        let gold = UIColor(red: 0.93, green: 0.76, blue: 0.28, alpha: 1)
        switch outfit {
        case .none:
            return nil
        case .beret:
            group.name = "outfit-head"
            let darkWine = UIColor(red: 0.60, green: 0.15, blue: 0.21, alpha: 1)
            group.addChildNode(node(SCNTorus(ringRadius: 0.82, pipeRadius: 0.16), darkWine,
                                    pos: SCNVector3(0.08, 1.05, 0.05),
                                    euler: SCNVector3(0, 0, -0.15)))
            group.addChildNode(node(SCNSphere(radius: 1.1), c,
                                    pos: SCNVector3(0.12, 1.2, 0.05),
                                    scale: SCNVector3(1.05, 0.4, 1.05),
                                    euler: SCNVector3(0, 0, -0.18)))
            group.addChildNode(node(SCNCapsule(capRadius: 0.08, height: 0.3), darkWine,
                                    pos: SCNVector3(0.2, 1.62, 0.05),
                                    euler: SCNVector3(0, 0, -0.18)))
        case .crown:
            group.name = "outfit-head"
            group.addChildNode(node(SCNCylinder(radius: 0.65, height: 0.42), c,
                                    pos: SCNVector3(0, 1.45, 0), gloss: 0.85))
            group.addChildNode(node(SCNTorus(ringRadius: 0.65, pipeRadius: 0.08), c,
                                    pos: SCNVector3(0, 1.66, 0), gloss: 0.85))
            let gems: [(Float, Float, UIColor)] = [
                (0.48, 0, UIColor(red: 0.85, green: 0.20, blue: 0.25, alpha: 1)),
                (-0.48, 0, UIColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 1)),
                (0, 0.48, UIColor(red: 0.30, green: 0.72, blue: 0.40, alpha: 1)),
                (0, -0.48, UIColor(red: 0.65, green: 0.35, blue: 0.80, alpha: 1)),
            ]
            for (dx, dz, gemColor) in gems {
                group.addChildNode(node(SCNCone(topRadius: 0.01, bottomRadius: 0.14, height: 0.36), c,
                                        pos: SCNVector3(dx, 1.83, dz), gloss: 0.85))
                group.addChildNode(node(SCNSphere(radius: 0.08), gemColor,
                                        pos: SCNVector3(dx, 2.05, dz), gloss: 0.95))
            }
            group.addChildNode(node(SCNSphere(radius: 0.11),
                                    UIColor(red: 0.85, green: 0.20, blue: 0.25, alpha: 1),
                                    pos: SCNVector3(0, 1.45, 0.63), gloss: 0.95))
        case .bow:
            group.name = "outfit-head"
            let lightPink = UIColor(red: 0.99, green: 0.68, blue: 0.80, alpha: 1)
            for sx in [-1.0, 1.0] {
                group.addChildNode(node(SCNSphere(radius: 0.3), c,
                                        pos: SCNVector3(0.78 + Float(sx) * 0.32, 1.12, 0.42),
                                        scale: SCNVector3(1, 0.72, 0.55), gloss: 0.4))
                group.addChildNode(node(SCNCapsule(capRadius: 0.09, height: 0.34), c,
                                        pos: SCNVector3(0.78 + Float(sx) * 0.12, 0.84, 0.42),
                                        euler: SCNVector3(0, 0, Float(sx) * -0.4), gloss: 0.4))
            }
            group.addChildNode(node(SCNSphere(radius: 0.16), lightPink,
                                    pos: SCNVector3(0.78, 1.12, 0.5), gloss: 0.5))
        case .glasses:
            // 脸面椭球在眼位 z≈1.34，镜片平面要顶到 z≈1.42 才不被埋
            group.name = "outfit-head"
            let dark = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
            for sx in [-1.0, 1.0] {
                group.addChildNode(node(SCNSphere(radius: 0.40), dark,
                                        pos: SCNVector3(Float(sx) * 0.5, 0.12, 1.42),
                                        scale: SCNVector3(1, 1, 0.30), gloss: 0.95))
                group.addChildNode(node(SCNTorus(ringRadius: 0.42, pipeRadius: 0.045), gold,
                                        pos: SCNVector3(Float(sx) * 0.5, 0.12, 1.45),
                                        euler: SCNVector3(Float.pi / 2, 0, 0), gloss: 0.8))
                group.addChildNode(node(SCNCylinder(radius: 0.04, height: 0.8), gold,
                                        pos: SCNVector3(Float(sx) * 0.98, 0.16, 0.85),
                                        euler: SCNVector3(Float.pi / 2, Float(sx) * -0.18, 0), gloss: 0.8))
            }
            group.addChildNode(node(SCNCylinder(radius: 0.04, height: 0.28), gold,
                                    pos: SCNVector3(0, 0.16, 1.45),
                                    euler: SCNVector3(0, 0, Float.pi / 2), gloss: 0.8))
        case .scarf:
            // 脖围在头球与身体球交界（趴姿身体球前沿 z≈1.83），要围大圈并前压
            group.name = "outfit-body"
            group.addChildNode(node(SCNTorus(ringRadius: 1.15, pipeRadius: 0.24), c,
                                    pos: SCNVector3(0, 1.85, 0.95),
                                    euler: SCNVector3(0.55, 0, 0)))
            group.addChildNode(node(SCNTorus(ringRadius: 1.15, pipeRadius: 0.11), creamColor,
                                    pos: SCNVector3(0, 2.02, 0.88),
                                    euler: SCNVector3(0.55, 0, 0)))
            group.addChildNode(node(SCNCapsule(capRadius: 0.18, height: 0.8), c,
                                    pos: SCNVector3(0.40, 1.05, 1.95),
                                    euler: SCNVector3(0.30, 0, 0.12)))
            for (i, fx) in [Float(0.26), 0.40, 0.54].enumerated() {
                group.addChildNode(node(SCNCylinder(radius: 0.045, height: 0.22), creamColor,
                                        pos: SCNVector3(fx, 0.62, 2.06 + Float(i % 2) * 0.04),
                                        euler: SCNVector3(0.30, 0, 0)))
            }
        case .collar:
            group.name = "outfit-body"
            group.addChildNode(node(SCNTorus(ringRadius: 1.08, pipeRadius: 0.14), c,
                                    pos: SCNVector3(0, 1.85, 1.02),
                                    euler: SCNVector3(0.58, 0, 0), gloss: 0.35))
            group.addChildNode(node(SCNTorus(ringRadius: 0.09, pipeRadius: 0.03), gold,
                                    pos: SCNVector3(0, 1.44, 1.92),
                                    euler: SCNVector3(Float.pi / 2, 0, 0), gloss: 0.8))
            group.addChildNode(node(SCNSphere(radius: 0.18), gold,
                                    pos: SCNVector3(0, 1.28, 1.95), gloss: 0.9))
            group.addChildNode(node(SCNCapsule(capRadius: 0.02, height: 0.12), darkColor,
                                    pos: SCNVector3(0, 1.22, 2.12)))
        case .wizard:
            group.name = "outfit-head"
            group.addChildNode(node(SCNCylinder(radius: 0.88, height: 0.10), c,
                                    pos: SCNVector3(0, 1.30, 0)))
            group.addChildNode(node(SCNCone(topRadius: 0.05, bottomRadius: 0.54, height: 1.15), c,
                                    pos: SCNVector3(0, 1.90, 0)))
            group.addChildNode(node(SCNCylinder(radius: 0.56, height: 0.16), gold,
                                    pos: SCNVector3(0, 1.42, 0), gloss: 0.8))
            group.addChildNode(node(SCNSphere(radius: 0.10), gold,
                                    pos: SCNVector3(0.18, 2.46, 0), gloss: 0.8))
            for (sx, sy, sz) in [(Float(0.24), Float(1.72), Float(0.26)),
                                 (Float(-0.20), Float(1.98), Float(0.17)),
                                 (Float(0.08), Float(2.22), Float(0.12))] {
                group.addChildNode(node(SCNSphere(radius: 0.055), gold,
                                        pos: SCNVector3(sx, sy, sz), gloss: 0.9))
            }
        }
        return group
    }
}

#Preview {
    NavigationStack {
        TamagotchiHomeView(path: .constant(NavigationPath()))
            .environment(AppState())
            .environment(AlertEngine())
    }
}

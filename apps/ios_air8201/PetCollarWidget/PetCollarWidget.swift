import WidgetKit
import SwiftUI
import PetKit

// MARK: - 电子宠物小组件
//
// 「桌宠」在手机上的形态：主屏/锁屏小组件。数据同源——只读主 App 写进 App Group 的
// PetSnapshot，绝不自己联网（小组件有严格刷新预算，不能硬轮询后端）。主 App 每变化
// 一次就 WidgetCenter.reloadAllTimelines() 推一把；离线时按 15 分钟兜底刷新。
//
// 「会动的猫」：WidgetKit 不能跑实时 SceneKit，只能显示静态快照。折中做法是把首页那只
// 骨骼真猫(cat_idle.usdz)预渲染成 PetProvider.frameCount 帧匀速转台（每帧 360°/frameCount，
// 首尾无缝接圈），用一条 timeline 把「未来一段时间」每隔 frameStep 秒排一帧，系统到点自动
// 切帧，帧间再叠交叉淡化 → 看起来是持续匀速旋转而不是一下一下跳。注意：主屏刷新被系统
// 节流，真机上换帧会比这里排的慢（几十秒~几分钟一帧），非连续；模拟器较宽松。

struct PetEntry: TimelineEntry {
    let date: Date
    let snapshot: PetSnapshot?
    var frame: Int = 0     // 当前显示第几帧动画（cat_anim_XX）
}

struct PetProvider: TimelineProvider {
    static let frameCount = 24          // 预渲染的动画帧数（cat_anim_00…23），每帧转 15°
    static let frameStep: TimeInterval = 1   // 每帧停留秒数（真机会被系统拉长）
    static let coverEntries = 180       // 一条 timeline 排多少帧 ≈ 覆盖 3 分钟，到点自刷

    func placeholder(in context: Context) -> PetEntry {
        PetEntry(date: Date(), snapshot: Self.demo, frame: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        completion(PetEntry(date: Date(), snapshot: PetSnapshotStore.load() ?? Self.demo, frame: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        // 主 App 同源数据优先；沙盒内读不到（Demo 未配 App Group）就退回演示猫，
        // 保证桌面上永远有一只活猫，而不是空占位。
        let snap = PetSnapshotStore.load() ?? Self.demo
        let now = Date()
        // 排一串未来时刻，每隔 frameStep 秒循环切一帧 → 翻页动画。
        var entries: [PetEntry] = []
        for i in 0..<Self.coverEntries {
            let date = now.addingTimeInterval(Double(i) * Self.frameStep)
            entries.append(PetEntry(date: date, snapshot: snap, frame: i % Self.frameCount))
        }
        // 排完到点重新生成下一段，动画持续下去。
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static let demo = PetSnapshot(
        petName: "喵喵", satiety: 72, mood: 88, energy: 64,
        behavior: .happy, outfit: nil, connected: true,
        catOnCamera: true, adoptedDays: 12, updatedAt: Date()
    )
}

// MARK: - 渲染（按小组件尺寸自适应）

struct PetCollarWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: PetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:   circular
        case .accessoryRectangular: rectangular
        case .accessoryInline:     inline
        case .systemMedium:        medium
        default:                   small
        }
    }

    private var snap: PetSnapshot? { entry.snapshot }

    // 主屏小尺寸：只放 3D 猫。主屏小组件底板去不掉真透明（系统会垫白），
    // 索性主动配一个「小舞台」背景 —— 暖奶油→天蓝渐变 + 脚下柔光聚光，比默认白板耐看。
    private var small: some View {
        catImage
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) {
                // 名字·天数角标：毛玻璃胶囊压在猫脚边，不抢戏但一眼可读
                HStack(spacing: 4) {
                    Text(snap?.petName ?? "喵喵")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                    Text(subtitleShort)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .overlay(alignment: .topTrailing) {
                connectionDot.padding(3)
            }
            .containerBackground(for: .widget) { catStage }
    }

    // 主屏中尺寸：左边动画猫，右边数据面板（名字/天数/三条状态/变装标签）。
    private var medium: some View {
        HStack(spacing: 10) {
            catImage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(snap?.petName ?? "喵喵")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                    catFace.font(.system(size: 13))
                    Spacer(minLength: 0)
                    connectionDot
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                meters
                if let tag = outfitTag {
                    Text(tag)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .frame(width: 128)
        }
        .padding(10)
        .containerBackground(for: .widget) { catStage }
    }

    // 「小舞台」背景：毛玻璃透出模糊壁纸。主屏 widget 拿不到真身后壁纸，这里用预先烘焙的
    // 「小组件位置壁纸裁剪 + 高斯模糊」当底(frost_bg)，再叠一层奶白磨砂让它像玻璃、猫脚下柔光。
    // 注意：这是障眼法——只对当前这张壁纸+当前位置严丝合缝，换壁纸/挪位置需重新烘焙。
    private var catStage: some View {
        Image("frost_bg")
            .resizable()
            .scaledToFill()
            .overlay(Color.white.opacity(0.16))   // 奶白磨砂玻璃感
            .overlay(
                RadialGradient(
                    colors: [Color.white.opacity(0.40), Color.white.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.66),
                    startRadius: 2, endRadius: 110
                )
            )
    }

    // 锁屏矩形
    private var rectangular: some View {
        HStack(spacing: 8) {
            catFace.font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(snap?.petName ?? "喵喵") · \(behaviorLabel)")
                    .font(.system(size: 13, weight: .semibold))
                Text("饱\(pct(snap?.satiety)) 心\(pct(snap?.mood)) 力\(pct(snap?.energy))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // 锁屏行内：表盘顶部一行字
    private var inline: some View {
        Text("\(faceEmoji) \(snap?.petName ?? "喵喵") · \(subtitleShort)")
            .containerBackground(for: .widget) { Color.clear }
    }

    // 锁屏圆形：用活力做进度环
    private var circular: some View {
        Gauge(value: (snap?.energy ?? 0) / 100) {
            catFace.font(.system(size: 14))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: 组件

    private var meters: some View {
        VStack(spacing: 5) {
            meter("饱食", snap?.satiety, .orange)
            meter("心情", snap?.mood, .pink)
            meter("活力", snap?.energy, .green)
        }
    }

    private func meter(_ label: String, _ value: Double?, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 9, weight: .medium)).frame(width: 26, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat((value ?? 0) / 100))
                }
            }
            .frame(height: 6)
        }
    }

    // 首页那只骨骼真猫的离屏渲染帧：呼吸 + 匀速转台整圈（每帧 15°，帧 23→0 无缝接圈）。
    // entry.frame 由 timeline 定时递进；换帧过渡=运动插值（2.5D）：出场帧继续往前转半步
    // 淡出、进场帧从早半步的角度转进来淡入，动画铺满整个停留时长 → 任意时刻画面都在同
    // 方向连续扫动，看不出离散换帧。帧由 PetKit 的 AssetRenderTests 生成，别手工替换：
    //   cd PetKit && WIDGET_FRAME_DIR=../ios_app/PetCollarWidget/Assets.xcassets \
    //     swift test --filter testRenderWidgetFrames
    private var catImage: some View {
        Image(String(format: "cat_anim_%02d", entry.frame))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .id(entry.frame)   // 换帧=换视图身份，触发 transition 运动插值
            .transition(.asymmetric(
                insertion: .modifier(active: TurnStep(angle: -TurnStep.halfStep, opacity: 0),
                                     identity: TurnStep(angle: 0, opacity: 1)),
                removal: .modifier(active: TurnStep(angle: TurnStep.halfStep, opacity: 0),
                                   identity: TurnStep(angle: 0, opacity: 1))
            ).animation(.linear(duration: PetProvider.frameStep)))
    }

    /// 行为驱动表情；离线/没数据给个黑猫。字符串形态，锁屏 inline 直接拼接。
    private var faceEmoji: String {
        switch snap?.behavior {
        case .eating:   return "😋"
        case .sleeping: return "😴"
        case .walking:  return "🐈"
        case .happy:    return "😺"
        case .idle:     return "🐱"
        case .none:     return "🐈‍⬛"
        }
    }

    private var catFace: Text { Text(faceEmoji) }

    private var behaviorLabel: String {
        switch snap?.behavior {
        case .idle: return "发呆"
        case .walking: return "溜达"
        case .eating: return "进食"
        case .sleeping: return "睡觉"
        case .happy: return "开心"
        case .none: return "离线"
        }
    }

    private var subtitle: String {
        guard let s = snap else { return "等待主 App 同步" }
        let mode = s.connected ? "已连接" : "云养猫"
        return "第\(s.adoptedDays)天 · \(mode)"
    }

    // 小尺寸列窄，只放天数，别让「已连接」把它挤成省略号。
    private var subtitleShort: String {
        guard let s = snap else { return "待同步" }
        return "第\(s.adoptedDays)天"
    }

    private var outfitTag: String? {
        guard let raw = snap?.outfit, let o = Outfit(rawValue: raw), o != .none else { return nil }
        return o.label
    }

    private var connectionDot: some View {
        Circle().fill((snap?.connected ?? false) ? .green : .secondary)
            .frame(width: 7, height: 7)
    }

    private func pct(_ v: Double?) -> String { "\(Int(v ?? 0))" }

    private var bg: some View {
        LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// 换帧运动插值：绕竖轴的小角度 2.5D 旋转 + 淡入淡出。相邻转台帧只差 15°，
/// 平面 rotation3DEffect ±7.5° 内的透视畸变可忽略，肉眼读到的是连续转动。
private struct TurnStep: ViewModifier, Animatable {
    static let halfStep = 360.0 / Double(PetProvider.frameCount) / 2   // 相邻帧夹角的一半
    var angle: Double     // 度
    var opacity: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, opacity) }
        set { angle = newValue.first; opacity = newValue.second }
    }
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(opacity)
    }
}

// MARK: - Widget 声明

struct PetCollarWidget: Widget {
    let kind = "PetCollarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PetProvider()) { entry in
            PetCollarWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "petpalair://pet"))   // 点小组件 → 打开 App 的 3D 桌宠
        }
        .configurationDisplayName("宠宝PetPel")
        .description("桌面上的会动小猫：饱食 / 心情 / 活力一眼可见，与 App、项圈同源。")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct PetCollarWidgetBundle: WidgetBundle {
    var body: some Widget {
        PetCollarWidget()
    }
}

import SwiftUI
import UIKit

// MARK: - 主题模式（用户可在「我的」里切换，存 @AppStorage("themeMode")）

/// App 内语言
enum AppLanguage: String, CaseIterable, Identifiable {
    case zh, en
    var id: String { rawValue }
    var label: String { self == .zh ? "中文" : "English" }
}

/// 当前是否英文。带插值的文案没法走查表，直接用它分支。
var isEN: Bool { UserDefaults.standard.string(forKey: "appLanguage") == "en" }

/// 发现页界面文案查表。中文原文即 key，英文缺失时回落中文。
/// 只翻界面，帖子正文/商品名等内容数据保持原样（真实产品也不会机翻 UGC）。
func L(_ zh: String) -> String {
    guard UserDefaults.standard.string(forKey: "appLanguage") == "en" else { return zh }
    return discoverEN[zh] ?? zh
}

private let discoverEN: [String: String] = [
    "社交": "Social",
    "发现": "Discover",
    "纪念": "Memorial",
    "配种": "Mating",
    "配种 · 绝育": "Mating · Neutering",
    "绝育预约": "Neutering",
    "帖子": "Post",
    "发布动态": "New Post",
    "删除这条动态": "Delete post",
    "已加入购物车": "Added to cart",
    "评论": "Comments",
    "还没有评论，来抢沙发吧": "No comments yet — be the first",
    "回复": "Reply",
    "已关注": "Following",
    "照片": "Photos",
    "添加照片": "Add photo",
    "封面图案": "Cover icon",
    "封面颜色": "Cover color",
    "标题": "Title",
    "正文": "Body",
    "标签": "Tags",
    "发布": "Post",
    "取消": "Cancel",
    "关闭": "Close",
    "完成": "Done",
    "确认取消": "Confirm cancel",
    "保留预约": "Keep booking",
    "取消后将退还费用（Demo 演示）": "The fee will be refunded (demo)",
    "我的配种预约": "My mating bookings",
    "我的预约": "My bookings",
    "预约配种": "Book mating",
    "预约绝育": "Book neutering",
    "立即预约": "Book now",
    "预约成功": "Booked",
    "配种预约成功": "Mating booked",
    "选择服务": "Pick a service",
    "选择日期": "Pick a date",
    "选择时段": "Pick a time",
    "订单确认": "Order summary",
    "费用": "Fee",
    "支付预约": "Pay & book",
    "确认支付": "Confirm payment",
    "支付状态": "Payment status",
    "已支付": "Paid",
    "匹配成功！": "It's a match!",
    "附近的猫都看完了": "No more cats nearby",
    "访客留言": "Visitor messages",
    "点亮一盏灯": "Light a candle",
    "纪念模式未开启": "Memorial mode is off",
    "开启纪念模式（演示）": "Enable Memorial (demo)",
    "关闭纪念模式": "Turn off Memorial",
    "当宠物离开后，可在此为它建立纪念页\n保留照片、回忆和访客的祝福":
        "When your pet passes on, build a memorial page here —\nkeeping photos, memories and visitors' wishes",
    "Demo 演示 · 假数据 · 不联网 · 不传输任何信息":
        "Demo · mock data · offline · nothing is transmitted",
    "Demo 演示 · 不会真预约真扣款": "Demo · no real booking or charge",
]

enum ThemeMode: String, CaseIterable, Identifiable {
    case system   // 跟随系统
    case light    // 浅色（暖奶油）
    case dark     // 深色（深空灰 Liquid Glass）

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.stars.fill"
        }
    }

    var labelEN: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    /// 传给 .preferredColorScheme；nil = 跟随系统
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// 动态色：浅/深两套 RGB，随 colorScheme 自动解析（配合 .preferredColorScheme 即可整体切换）
private func dyn(_ l: (Double, Double, Double), _ d: (Double, Double, Double), alphaL: Double = 1, alphaD: Double = 1) -> Color {
    Color(uiColor: UIColor { tc in
        let dark = tc.userInterfaceStyle == .dark
        let c = dark ? d : l
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: dark ? alphaD : alphaL)
    })
}

// 浅/深两套主题。Token 名保持不变，仅值改为动态——全 app 自动跟随，无需改任何视图。
enum PetPalTheme {
    // 品牌点缀色——两套通用（暖珊瑚/粉）
    static let primary    = Color(red: 1.00, green: 0.541, blue: 0.396)   // #FF8A65
    static let primaryDeep = Color(red: 1.00, green: 0.439, blue: 0.263)  // #FF7043

    static let accentPink = dyn((1.00, 0.757, 0.800), (1.00, 0.620, 0.560))
    static let blush      = dyn((1.00, 0.878, 0.835), (0.95, 0.55, 0.45))

    // surface 语义：浅=奶油，深=抬升的深空灰玻璃面
    static let cream      = dyn((1.00, 0.973, 0.961), (0.149, 0.149, 0.165))
    static let creamDeep  = dyn((0.988, 0.918, 0.882), (0.110, 0.110, 0.125))

    // 文字
    static let inkPrimary   = dyn((0.137, 0.149, 0.184), (0.961, 0.961, 0.969))
    static let inkSecondary = dyn((0.420, 0.435, 0.475), (0.620, 0.627, 0.667))

    // 语义色（深底略提亮保证可读性）
    static let success = dyn((0.298, 0.808, 0.580), (0.314, 0.847, 0.616))
    static let warning = dyn((1.00, 0.722, 0.302), (1.00, 0.776, 0.376))
    static let danger  = dyn((0.957, 0.357, 0.420), (1.00, 0.451, 0.510))

    // 页面渐变（两端各自动态）
    static let backgroundGradient = LinearGradient(
        colors: [dyn((1.00, 0.918, 0.871), (0.137, 0.125, 0.137)),
                 dyn((1.00, 0.835, 0.847), (0.094, 0.090, 0.106))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let brandGradient = LinearGradient(
        colors: [primary, Color(red: 1.00, green: 0.494, blue: 0.557)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // 阴影：浅色浅而紧，深色深而扩散
    static let softShadow = Shadow(
        color: dyn((0, 0, 0), (0, 0, 0), alphaL: 0.08, alphaD: 0.45),
        radius: 18, x: 0, y: 8
    )

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

/// 液态毛玻璃卡面：iOS 26 走系统 Liquid Glass（自带镜面高光与折射），
/// 低版本回退到「提亮材质 + 镜面高光描边」。两者都带白色 tint 提亮，
/// 解决裸 ultraThinMaterial 在彩色底纹上与背景融掉的问题。
struct LiquidGlassSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 18

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(scheme == .dark ? Color.white.opacity(0.06)
                                                           : Color.white.opacity(0.32)),
                             in: shape)
                .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.10),
                        radius: 10, x: 0, y: 5)
        } else {
            content
                .background(
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(scheme == .dark ? Color.white.opacity(0.05)
                                                            : Color.white.opacity(0.38)))
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: scheme == .dark
                                       ? [Color.white.opacity(0.25), Color.white.opacity(0.04)]
                                       : [Color.white.opacity(0.90), Color.white.opacity(0.25)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.10),
                        radius: 10, x: 0, y: 5)
        }
    }
}

struct PetPalCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 24
    /// 液态毛玻璃模式：彩色底纹（爪印/奖杯）上裸材质会和背景融掉，
    /// glass 换成 LiquidGlassSurface（iOS 26 原生 Liquid Glass）；默认 false 不影响既有页面
    var glass: Bool = false
    @ViewBuilder var content: () -> Content

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        if glass {
            content()
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(LiquidGlassSurface(cornerRadius: cornerRadius))
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)   // 材质随明暗自动渲染
            )
            .overlay(
                // Liquid Glass 顶部高光描边——深色更明显，浅色更克制
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.18), Color.white.opacity(0.03)]
                                : [Color.white.opacity(0.65), Color.white.opacity(0.20)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: isDark ? 0.8 : 0.5
                    )
            )
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.06),
                    radius: isDark ? 18 : 14, x: 0, y: isDark ? 8 : 6)
    }
}

struct PetPalPrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(enabled ? AnyShapeStyle(PetPalTheme.brandGradient)
                                  : AnyShapeStyle(Color.gray.opacity(0.35)))
            )
            .shadow(color: PetPalTheme.primary.opacity(enabled ? 0.38 : 0), radius: 13, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(enabled ? 1.0 : 0.6)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PetPalGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(PetPalTheme.inkSecondary)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                Capsule().fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PetPalTextFieldStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(scheme == .dark
                          ? AnyShapeStyle(.ultraThinMaterial)        // 深色玻璃输入框
                          : AnyShapeStyle(Color.white.opacity(0.85))) // 浅色白底
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(scheme == .dark
                                  ? Color.white.opacity(0.10)
                                  : PetPalTheme.primary.opacity(0.12), lineWidth: 1)
            )
    }
}

extension View {
    func petPalField() -> some View { modifier(PetPalTextFieldStyle()) }
    func frostedPage() -> some View { FrostedPage { self } }
    func pawPatternPage() -> some View { PawPatternPage { self } }
}

struct FrostedPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            GlassPageBackground()
            content()
                .scrollContentBackground(.hidden)
        }
    }
}

/// 分析页功能详情的统一容器：沿用分析首页的浅绿爪印底纹，
/// 同时隐藏 List/Form/ScrollView 自带的系统底色，让背景能够透出。
struct PawPatternPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            PawPatternBackground()
            content()
                .scrollContentBackground(.hidden)
        }
    }
}

struct GlassPageBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            // 底色：浅=近白灰，深=深空灰
            (isDark ? Color(red: 0.110, green: 0.106, blue: 0.122)
                    : Color(red: 0.955, green: 0.955, blue: 0.965))
                .ignoresSafeArea()

            // 暖珊瑚辉光——主光源
            Ellipse()
                .fill(PetPalTheme.primary.opacity(isDark ? 0.28 : 0.30))
                .frame(width: isDark ? 360 : 340, height: isDark ? 300 : 280)
                .blur(radius: isDark ? 90 : 80)
                .offset(x: -110, y: -300)
                .ignoresSafeArea()

            // 紫调辉光
            Ellipse()
                .fill(Color.purple.opacity(isDark ? 0.22 : 0.16))
                .frame(width: 300, height: 260)
                .blur(radius: isDark ? 80 : 70)
                .offset(x: 140, y: 60)
                .ignoresSafeArea()

            // 蓝调辉光——纵深
            Ellipse()
                .fill(Color.blue.opacity(isDark ? 0.16 : 0.12))
                .frame(width: isDark ? 260 : 240, height: isDark ? 240 : 220)
                .blur(radius: isDark ? 70 : 60)
                .offset(x: -70, y: 360)
                .ignoresSafeArea()
        }
    }
}

// MARK: - 浅绿爪印底纹（分析/发现页，配色与排行页 TrophyPatternBackground 一致，只是图案换成爪印）

struct PawPatternBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }

    /// 手摆的伪随机爪印：x/y 为比例坐标，s 字号，r 旋转角，o 不透明度权重
    private static let paws: [(x: CGFloat, y: CGFloat, s: CGFloat, r: Double, o: Double)] = [
        (0.08, 0.05, 34, -20, 0.50), (0.53, 0.03, 28, 15, 0.38),
        (0.90, 0.11, 40, 25, 0.55), (0.30, 0.16, 25, -10, 0.33),
        (0.09, 0.27, 30, 10, 0.45), (0.68, 0.23, 36, -18, 0.50),
        (0.42, 0.34, 29, 20, 0.40), (0.88, 0.37, 27, -8, 0.42),
        (0.06, 0.47, 34, 18, 0.50), (0.52, 0.51, 25, -22, 0.33),
        (0.80, 0.57, 38, 10, 0.50), (0.16, 0.65, 29, -12, 0.42),
        (0.60, 0.69, 27, 22, 0.38), (0.90, 0.75, 32, -15, 0.45),
        (0.33, 0.79, 35, 8, 0.50),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                (isDark ? Color(red: 0.118, green: 0.137, blue: 0.098)
                        : Color(red: 0.914, green: 0.933, blue: 0.804))

                ForEach(Array(Self.paws.enumerated()), id: \.offset) { _, p in
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: p.s))
                        .foregroundStyle(
                            (isDark ? Color(red: 0.34, green: 0.38, blue: 0.24)
                                    : Color(red: 0.812, green: 0.855, blue: 0.667))
                                .opacity(p.o)
                        )
                        .rotationEffect(.degrees(p.r))
                        .position(x: geo.size.width * p.x, y: geo.size.height * p.y)
                }

                dune(size: geo.size, lift: 0.155,
                     color: isDark ? Color(red: 0.150, green: 0.172, blue: 0.122)
                                   : Color(red: 0.878, green: 0.906, blue: 0.749))
                dune(size: geo.size, lift: 0.075,
                     color: isDark ? Color(red: 0.180, green: 0.204, blue: 0.145)
                                   : Color(red: 0.847, green: 0.882, blue: 0.702))
            }
        }
        .ignoresSafeArea()
    }

    private func dune(size: CGSize, lift: CGFloat, color: Color) -> some View {
        Path { p in
            let w = size.width, h = size.height
            let top = h * (1 - lift)
            p.move(to: CGPoint(x: 0, y: top))
            p.addQuadCurve(to: CGPoint(x: w * 0.52, y: top + 20),
                           control: CGPoint(x: w * 0.24, y: top - 30))
            p.addQuadCurve(to: CGPoint(x: w, y: top - 12),
                           control: CGPoint(x: w * 0.80, y: top + 46))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
        }
        .fill(color)
    }
}

// MARK: - 浅绿奖杯底纹（排行页，参考 CatGo Rating 页）

struct TrophyPatternBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }

    private static let trophies: [(x: CGFloat, y: CGFloat, s: CGFloat, o: Double)] = [
        (0.06, 0.03, 40, 0.55), (0.52, 0.03, 34, 0.45), (0.86, 0.02, 30, 0.40),
        (0.31, 0.11, 36, 0.50), (0.79, 0.10, 38, 0.52),
        (0.08, 0.20, 32, 0.42), (0.53, 0.21, 34, 0.48), (0.92, 0.24, 30, 0.38),
        (0.33, 0.29, 38, 0.50), (0.72, 0.33, 34, 0.45),
        (0.10, 0.38, 36, 0.48), (0.50, 0.41, 30, 0.38), (0.88, 0.43, 34, 0.45),
        (0.28, 0.49, 34, 0.46), (0.66, 0.52, 38, 0.50),
        (0.05, 0.57, 32, 0.42), (0.45, 0.60, 36, 0.48), (0.90, 0.62, 30, 0.38),
        (0.24, 0.69, 34, 0.45), (0.70, 0.72, 36, 0.48),
        (0.09, 0.79, 30, 0.40), (0.52, 0.82, 34, 0.45), (0.87, 0.85, 32, 0.42),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                (isDark ? Color(red: 0.118, green: 0.137, blue: 0.098)
                        : Color(red: 0.914, green: 0.933, blue: 0.804))

                ForEach(Array(Self.trophies.enumerated()), id: \.offset) { _, t in
                    Image(systemName: "trophy.fill")
                        .font(.system(size: t.s))
                        .foregroundStyle(
                            (isDark ? Color(red: 0.34, green: 0.38, blue: 0.24)
                                    : Color(red: 0.812, green: 0.855, blue: 0.667))
                                .opacity(t.o)
                        )
                        .position(x: geo.size.width * t.x, y: geo.size.height * t.y)
                }

                dune(size: geo.size, lift: 0.145,
                     color: isDark ? Color(red: 0.150, green: 0.172, blue: 0.122)
                                   : Color(red: 0.878, green: 0.906, blue: 0.749))
                dune(size: geo.size, lift: 0.068,
                     color: isDark ? Color(red: 0.180, green: 0.204, blue: 0.145)
                                   : Color(red: 0.847, green: 0.882, blue: 0.702))
            }
        }
        .ignoresSafeArea()
    }

    private func dune(size: CGSize, lift: CGFloat, color: Color) -> some View {
        Path { p in
            let w = size.width, h = size.height
            let top = h * (1 - lift)
            p.move(to: CGPoint(x: 0, y: top))
            p.addQuadCurve(to: CGPoint(x: w * 0.48, y: top + 22),
                           control: CGPoint(x: w * 0.22, y: top - 26))
            p.addQuadCurve(to: CGPoint(x: w, y: top - 10),
                           control: CGPoint(x: w * 0.78, y: top + 42))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
        }
        .fill(color)
    }
}

// MARK: - 淡蓝星空（我的页，参考 CatGo Settings 页）

struct StarrySkyBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }

    /// sparkle 四角星；dot 光点
    private static let stars: [(x: CGFloat, y: CGFloat, s: CGFloat, o: Double, dot: Bool)] = [
        (0.12, 0.04, 16, 0.85, false), (0.85, 0.03, 11, 0.6, false),
        (0.55, 0.07, 6, 0.5, true),   (0.93, 0.12, 18, 0.9, false),
        (0.25, 0.14, 8, 0.45, true),  (0.70, 0.18, 12, 0.65, false),
        (0.06, 0.24, 13, 0.7, false), (0.45, 0.28, 6, 0.4, true),
        (0.88, 0.33, 15, 0.8, false), (0.20, 0.40, 10, 0.55, false),
        (0.62, 0.45, 7, 0.45, true),  (0.05, 0.55, 16, 0.8, false),
        (0.83, 0.58, 9, 0.5, false),  (0.35, 0.63, 6, 0.4, true),
        (0.65, 0.72, 14, 0.75, false),(0.12, 0.80, 8, 0.5, true),
        (0.90, 0.85, 12, 0.65, false),(0.40, 0.90, 10, 0.55, false),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: isDark
                        ? [Color(red: 0.085, green: 0.105, blue: 0.200),
                           Color(red: 0.140, green: 0.165, blue: 0.270)]
                        : [Color(red: 0.700, green: 0.780, blue: 0.940),
                           Color(red: 0.845, green: 0.885, blue: 0.975)],
                    startPoint: .top, endPoint: .bottom
                )

                ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                    Group {
                        if star.dot {
                            Circle()
                                .fill(Color.white)
                                .frame(width: star.s, height: star.s)
                        } else {
                            Image(systemName: "sparkle")
                                .font(.system(size: star.s))
                                .foregroundStyle(.white)
                        }
                    }
                    .opacity(star.o * (isDark ? 0.55 : 0.9))
                    .position(x: geo.size.width * star.x, y: geo.size.height * star.y)
                }
            }
        }
        .ignoresSafeArea()
    }
}

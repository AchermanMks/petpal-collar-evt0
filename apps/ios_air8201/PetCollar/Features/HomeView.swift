import SwiftUI
import PhotosUI

// MARK: - Main Tab Container

struct MainTabView: View {
    @Environment(AlertEngine.self) private var engine
    @Environment(PetRouter.self) private var router
    @State private var selectedTab: AppTab = .home
    @AppStorage("appLanguage") private var appLanguage: String = "zh"

    enum AppTab: Hashable {
        case home, analysis, discover, rating, profile
    }

    private var en: Bool { appLanguage == "en" }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label(en ? "Home" : "首页", systemImage: "house.fill")
                }
                .tag(AppTab.home)

            AnalysisTab()
                .tabItem {
                    Label(en ? "Analysis" : "分析", systemImage: "chart.xyaxis.line")
                }
                .tag(AppTab.analysis)

            DiscoverTab()
                .tabItem {
                    Label(en ? "Discover" : "发现", systemImage: "sparkles")
                }
                .tag(AppTab.discover)

            RatingTab()
                .tabItem {
                    Label(en ? "Rating" : "排行", systemImage: "trophy.fill")
                }
                .tag(AppTab.rating)

            ProfileTab()
                .tabItem {
                    Label(en ? "Profile" : "我的", systemImage: "person.fill")
                }
                .tag(AppTab.profile)
        }
        .tint(PetPalTheme.primary)
        // 小组件「打开桌宠」深链接：无论当前在哪个 tab，都切回首页（桌宠所在）。
        .onChange(of: router.openPetNonce) { selectedTab = .home }
        // 「我的」页点等级卡跳排行榜
        .onChange(of: router.openRatingNonce) { selectedTab = .rating }
        // 首页上滑 → 发现页（FeedView 内部再把栏目切到商城）
        .onChange(of: router.openShopNonce) { selectedTab = .discover }
    }
}

// MARK: - Home Tab

struct HomeView: View {
    @Namespace private var heroNS
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            TamagotchiHomeView(path: $path)
                .navigationDestination(for: HomeRoute.self) { route in
                    route.destination
                        .frostedPage()
                        .zoomTransition(sourceID: route, in: heroNS)
                }
        }
    }
}

// MARK: - Analysis Tab

// 「分析」仪表盘：概览数据置顶，实况大卡 + 监控小块 + 互动快捷钮 + 洞察列表
struct AnalysisTab: View {
    @Environment(AppState.self) private var state
    @Environment(AlertEngine.self) private var engine
    @Namespace private var heroNS
    @State private var feeding: FeedingSummary?
    @State private var activity: ActivitySummary?
    @State private var showTools = false   // 功能钮（监控小块+项圈互动）默认收起，点「全部功能」一并展开
    @AppStorage("appLanguage") private var appLanguage: String = "zh"

    private var en: Bool { appLanguage == "en" }
    private func tr(_ zh: String, _ english: String) -> String { en ? english : zh }

    private var isConnected: Bool {
        if case .connected = state.status { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PawPatternBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        overviewCard
                        liveHeroCard
                        toolsToggle
                        if showTools {
                            miniMonitorRow
                                .transition(toolsTransition(delay: 0))
                            interactionCard
                                .transition(toolsTransition(delay: 0.06))
                        }
                        insightList
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(tr("分析", "Analysis"))
            .navigationDestination(for: HomeRoute.self) { route in
                route.destination
                    .pawPatternPage()
                    .zoomTransition(sourceID: route, in: heroNS)
            }
            .task(id: isConnected) {
                guard isConnected, let api = state.api else {
                    feeding = nil
                    activity = nil
                    return
                }
                feeding = try? await api.feedingEvents()
                activity = try? await api.activitySummary()
            }
        }
    }

    // MARK: 实时概览

    private var overviewCard: some View {
        PetPalCard(padding: 16, glass: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    StatusPill(label: tr(isConnected ? "在家" : "离线", isConnected ? "Home" : "Offline"),
                               color: isConnected ? PetPalTheme.success : .gray)
                    Text(isConnected ? tr("后端已连接 · 数据实时同步", "Backend connected · Live sync")
                                     : tr("未连接后端 · 去「我的」配置服务器", "Backend offline · Configure in Profile"))
                        .font(.caption)
                        .foregroundStyle(PetPalTheme.inkSecondary)
                    Spacer()
                }
                HStack(spacing: 0) {
                    overviewStat(value: "\(feeding?.todayCount ?? 0)", unit: tr("次", ""), label: tr("今日进食", "Meals Today"))
                    Divider().frame(height: 28)
                    overviewStat(value: "\(Int(activity?.todayMeters ?? 0))", unit: "m", label: tr("今日活动", "Activity Today"))
                    Divider().frame(height: 28)
                    overviewStat(value: "\(Int(activity?.lastHourMeters ?? 0))", unit: "m", label: tr("最近1小时", "Last Hour"))
                }
            }
        }
    }

    private func overviewStat(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(PetPalTheme.inkSecondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(PetPalTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 实况大卡（最高频入口）

    private var liveHeroCard: some View {
        NavigationLink(value: HomeRoute.camera) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 54, height: 54)
                    Image(systemName: "video.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("实况直播", "Live Stream"))
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Text(tr("项圈摄像头实时画面", "Live feed from collar camera"))
                        .font(.caption)
                        .foregroundStyle(PetPalTheme.inkSecondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
            }
            .padding(16)
            .modifier(LiquidGlassSurface(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .modifier(ZoomSourceModifier(id: .camera, namespace: heroNS))
        .buttonStyle(.plain)
    }

    // MARK: 功能区开关（监控小块 + 项圈互动一并展开/收起）

    private var toolsToggle: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { showTools.toggle() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PetPalTheme.primary)
                Text(tr(showTools ? "收起功能" : "全部功能", showTools ? "Hide Tools" : "All Tools"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkSecondary)
                    .rotationEffect(.degrees(showTools ? -180 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .modifier(LiquidGlassSurface(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    /// 展开时自上而下微错峰滑入（spring 回弹），收起时快速淡出不拖泥带水
    private func toolsTransition(delay: Double) -> AnyTransition {
        .asymmetric(
            insertion: AnyTransition.opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.96, anchor: .top))
                .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(delay)),
            removal: AnyTransition.opacity
                .combined(with: .scale(scale: 0.97, anchor: .top))
                .animation(.easeIn(duration: 0.16))
        )
    }

    // MARK: 监控小块一行

    private var miniMonitorRow: some View {
        HStack(spacing: 10) {
            miniTile(route: .live, icon: "play.tv.fill", title: tr("实时预览", "Live View"), color: .cyan)
            miniTile(route: .viz3d, icon: "cube.transparent", title: tr("3D空间", "3D Space"), color: .indigo)
            miniTile(route: .gps, icon: "location.fill", title: "GPS", color: .green)
            miniTile(route: .alerts, icon: "bell.badge.fill", title: tr("告警", "Alerts"), color: .red,
                     badge: engine.history.isEmpty ? nil : engine.history.count)
        }
    }

    private func miniTile(route: HomeRoute, icon: String, title: String,
                          color: Color, badge: Int? = nil) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(color.opacity(0.13)))
                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(PetPalTheme.danger))
                            .offset(x: 8, y: -4)
                    }
                }
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .modifier(LiquidGlassSurface(cornerRadius: 16))
        }
        .modifier(ZoomSourceModifier(id: route, namespace: heroNS))
        .buttonStyle(.plain)
    }

    // MARK: 项圈互动快捷钮

    private var interactionCard: some View {
        PetPalCard(padding: 14, glass: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("项圈互动", "Collar Controls"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                HStack(spacing: 0) {
                    quickButton(route: .light, icon: "lightbulb.fill", title: tr("灯光", "Light"), color: .orange)
                    quickButton(route: .speaker, icon: "speaker.wave.2.fill", title: tr("扬声器", "Speaker"), color: .purple)
                    quickButton(route: .motor, icon: "waveform.path", title: tr("震动", "Vibrate"), color: .pink)
                    quickButton(route: .arc, icon: "bolt.fill", title: tr("电击", "Shock"), color: .red)
                }
            }
        }
    }

    private func quickButton(route: HomeRoute, icon: String, title: String, color: Color) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(color.opacity(0.13)))
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .modifier(ZoomSourceModifier(id: route, namespace: heroNS))
        .buttonStyle(.plain)
    }

    // MARK: 行为与健康列表

    private var insightList: some View {
        PetPalCard(padding: 14, glass: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("行为与健康", "Behavior & Health"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                    .padding(.bottom, 4)
                insightRow(route: .vlm, icon: "brain.head.profile", color: .mint,
                           title: tr("场景分析", "Scene Analysis"), subtitle: tr("AI 描述猫咪当前行为", "AI describes current behavior"))
                Divider().padding(.leading, 46)
                insightRow(route: .detections, icon: "list.bullet.rectangle", color: .yellow,
                           title: tr("检测", "Detections"), subtitle: tr("实时识别结果列表", "Live detection results"))
                Divider().padding(.leading, 46)
                insightRow(route: .stats, icon: "chart.bar.doc.horizontal", color: .brown,
                           title: tr("统计", "Stats"), subtitle: tr("检测计数与趋势", "Detection counts & trends"))
                Divider().padding(.leading, 46)
                insightRow(route: .health, icon: "heart.text.square.fill", color: .pink,
                           title: tr("健康", "Health"), subtitle: tr("体重、疫苗与就诊记录", "Weight, vaccines & visits"))
                Divider().padding(.leading, 46)
                insightRow(route: .trajectory, icon: "map.fill", color: .teal,
                           title: tr("轨迹", "Trajectory"), subtitle: tr("运动路径回放", "Movement path replay"))
                Divider().padding(.leading, 46)
                insightRow(route: .collarData, icon: "sensor.tag.radiowaves.forward.fill", color: PetPalTheme.primaryDeep,
                           title: tr("项圈数据", "Collar Data"), subtitle: tr("电量、信号、运动、定位的真实上报", "Live battery, signal, motion & GNSS reports"))
            }
        }
    }

    private func insightRow(route: HomeRoute, icon: String, color: Color,
                            title: String, subtitle: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.13))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(PetPalTheme.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.5))
            }
            .padding(.vertical, 10)
        }
        .modifier(ZoomSourceModifier(id: route, namespace: heroNS))
        .buttonStyle(.plain)
    }
}

// MARK: - Discover Tab

// 「动态」聚合页：原发现页的全部功能收进顶部栏（动态/商城/纪念/训猫/配种/绝育）
struct DiscoverTab: View {
    @Namespace private var heroNS
    // 切语言时让整棵发现页子树重建，L() 才会取到新值
    @AppStorage("appLanguage") private var appLanguage: String = "zh"

    var body: some View {
        NavigationStack {
            ZStack {
                PawPatternBackground()

                FeedEntryView()
            }
            .navigationDestination(for: HomeRoute.self) { route in
                route.destination
                    .frostedPage()
                    .zoomTransition(sourceID: route, in: heroNS)
            }
        }
    }
}

// MARK: - Rating Tab（排行榜，布局仿 CatGo Rating 页）

/// 成就档位：按累计 XP 解锁，对应参考图的 By rarity 五行
struct AchievementTier: Identifiable {
    let id: String
    let zh: String
    let en: String
    let threshold: Int
    let color: Color
    let lightColor: Color
    let deepColor: Color
    /// 档位专属图标：爪印→星→钻→冠→杯，越往上越贵气
    let icon: String

    static let all: [AchievementTier] = [
        .init(id: "legendary", zh: "传说", en: "Legendary", threshold: 3000,
              color: Color(red: 0.93, green: 0.61, blue: 0.12),
              lightColor: Color(red: 1.00, green: 0.90, blue: 0.48),
              deepColor: Color(red: 0.58, green: 0.31, blue: 0.04), icon: "trophy.fill"),
        .init(id: "epic", zh: "史诗", en: "Epic", threshold: 1500,
              color: Color(red: 0.59, green: 0.35, blue: 0.84),
              lightColor: Color(red: 0.86, green: 0.67, blue: 1.00),
              deepColor: Color(red: 0.31, green: 0.15, blue: 0.53), icon: "crown.fill"),
        .init(id: "rare", zh: "稀有", en: "Rare", threshold: 800,
              color: Color(red: 0.18, green: 0.49, blue: 0.86),
              lightColor: Color(red: 0.51, green: 0.80, blue: 1.00),
              deepColor: Color(red: 0.06, green: 0.22, blue: 0.50), icon: "diamond.fill"),
        .init(id: "uncommon", zh: "优秀", en: "Uncommon", threshold: 300,
              color: Color(red: 0.16, green: 0.64, blue: 0.52),
              lightColor: Color(red: 0.55, green: 0.93, blue: 0.77),
              deepColor: Color(red: 0.04, green: 0.33, blue: 0.26), icon: "star.fill"),
        .init(id: "common", zh: "普通", en: "Common", threshold: 100,
              color: Color(red: 0.56, green: 0.49, blue: 0.40),
              lightColor: Color(red: 0.88, green: 0.82, blue: 0.70),
              deepColor: Color(red: 0.27, green: 0.24, blue: 0.21), icon: "pawprint.fill"),
    ]
}

/// 排行榜条目。Demo 假数据 + 用户自己按真实 XP 插入排序。
struct RankEntry: Identifiable {
    let id: String
    let name: String
    let xp: Int
    let tint: Color
    var isMe: Bool = false

    static let demo: [RankEntry] = [
        .init(id: "d1", name: "麻薯妈 🐱", xp: 34_642, tint: Color(red: 0.80, green: 0.25, blue: 0.45)),
        .init(id: "d2", name: "黑米爸爸", xp: 20_336, tint: Color(red: 0.68, green: 0.32, blue: 0.80)),
        .init(id: "d3", name: "雪糕控 🍦", xp: 6_869, tint: Color(red: 0.76, green: 0.55, blue: 0.36)),
        .init(id: "d4", name: "豆豆麻 🌿", xp: 6_230, tint: Color(red: 0.85, green: 0.30, blue: 0.50)),
        .init(id: "d5", name: "橘座本座", xp: 5_606, tint: Color(red: 0.40, green: 0.68, blue: 0.85)),
        .init(id: "d6", name: "三花小姐", xp: 3_180, tint: Color(red: 0.90, green: 0.60, blue: 0.30)),
        .init(id: "d7", name: "狸花猎手", xp: 1_940, tint: Color(red: 0.45, green: 0.55, blue: 0.35)),
        .init(id: "d8", name: "布丁爸", xp: 860, tint: Color(red: 0.55, green: 0.60, blue: 0.75)),
        .init(id: "d9", name: "煤球日记", xp: 410, tint: Color(red: 0.35, green: 0.30, blue: 0.28)),
    ]
}

struct RatingTab: View {
    @AppStorage("xp") private var xp: Int = 0
    @AppStorage("interactionCount") private var interactionCount: Int = 0
    @AppStorage("petName") private var petName: String = "喵喵"
    @AppStorage("appLanguage") private var appLanguage: String = "zh"
    @Environment(\.colorScheme) private var scheme

    private var en: Bool { appLanguage == "en" }
    private func tr(_ zh: String, _ english: String) -> String { en ? english : zh }

    private var cardFill: Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.62)
    }

    /// 我 + demo 一起按 XP 排序
    private var ranked: [RankEntry] {
        let me = RankEntry(id: "me", name: en ? "You · \(petName)" : "我 · \(petName)",
                           xp: xp, tint: PetPalTheme.primary, isMe: true)
        return (RankEntry.demo + [me]).sorted { $0.xp > $1.xp }
    }

    /// (名次, 条目)，名次按完整榜单算，置顶卡和下方列表共用同一套编号
    private var rankedWithPlace: [(place: Int, entry: RankEntry)] {
        ranked.enumerated().map { (place: $0.offset + 1, entry: $0.element) }
    }

    private var myPlace: (place: Int, entry: RankEntry)? {
        rankedWithPlace.first { $0.entry.isMe }
    }

    private var myRank: Int { myPlace?.place ?? 1 }

    /// 自己排最前，其余保持名次顺序
    private var myFirstRows: [(place: Int, entry: RankEntry)] {
        let all = rankedWithPlace
        return all.filter { $0.entry.isMe } + all.filter { !$0.entry.isMe }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TrophyPatternBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        summaryCard
                        passEntry
                        tierSection
                        leaderboardSection
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(tr("排行", "Rating"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeRoute.self) { route in
                route.destination
            }
        }
    }

    // MARK: 通行证入口（与本页半透白卡同风格）

    @AppStorage("passClaimedFree") private var passClaimedFreeRaw: String = ""
    @AppStorage("passClaimedPro") private var passClaimedProRaw: String = ""
    @AppStorage("isPro") private var isPro: Bool = false

    private var passClaimable: Int {
        let tier = min(10, xp / 100)
        let free = Set(passClaimedFreeRaw.split(separator: ",").compactMap { Int($0) })
        let pro = Set(passClaimedProRaw.split(separator: ",").compactMap { Int($0) })
        var n = (1...10).filter { $0 <= tier && !free.contains($0) }.count
        if isPro { n += (1...10).filter { $0 <= tier && !pro.contains($0) }.count }
        return n
    }

    private var passEntry: some View {
        NavigationLink(value: HomeRoute.pass) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(PassGold.mid.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Circle()
                        .strokeBorder(PassGold.border, lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: "medal.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(PassGold.gradient)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(tr("通行证", "Pass"))
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(PassGold.gradient)
                        if passClaimable > 0 {
                            ClaimBadge(text: tr("\(passClaimable) 份待领", "\(passClaimable) to claim"))
                        }
                    }
                    Text(tr("攒活跃度 · 领赛季奖励", "Earn activity · claim rewards"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.60))
                }
                Spacer(minLength: 8)
                Text(tr("等级 \(min(10, xp / 100))", "Tier \(min(10, xp / 100))"))
                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                    .foregroundStyle(PassGold.light)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PassGold.mid.opacity(0.75))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PassGold.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(PassGold.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.34), radius: 14, x: 0, y: 7)
            .shadow(color: PassGold.mid.opacity(0.16), radius: 9, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: 顶部概览（排名 / 总经验 / 互动，一张卡说完）

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryStat(value: "#\(myRank)", label: tr("当前排名", "Rank"),
                        tint: PetPalTheme.primary)
            Divider().frame(height: 30)
            summaryStat(value: "\(xp)", label: tr("总经验", "Total XP"),
                        tint: Color(red: 0.94, green: 0.55, blue: 0.20))
            Divider().frame(height: 30)
            summaryStat(value: "\(interactionCount)", label: tr("互动次数", "Actions"),
                        tint: Color(red: 0.20, green: 0.70, blue: 0.35))
        }
        .padding(.vertical, 14)
        .modifier(LiquidGlassSurface(cornerRadius: 20))
    }

    private func summaryStat(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(PetPalTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 成就档位（五枚徽章一行 + 一条进阶进度，替代五条重复大条）

    /// 从低到高（普通→传说），符合进阶阅读顺序
    private var tiersAscending: [AchievementTier] { AchievementTier.all.reversed() }

    /// 下一个未达成的档位；全部达成则为 nil
    private var nextTier: AchievementTier? {
        tiersAscending.first { xp < $0.threshold }
    }

    /// 当前档到下一档的进度（0~1）
    private var tierProgress: Double {
        guard let next = nextTier else { return 1 }
        let prev = tiersAscending.last { xp >= $0.threshold }?.threshold ?? 0
        return Double(xp - prev) / Double(next.threshold - prev)
    }

    /// 现实奖牌上方的织带，底部燕尾由奖牌遮住一部分，形成悬挂关系。
    private struct MedalRibbon: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY * 0.78))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }

    private struct MedalPalette {
        let metalLight: Color
        let metalMid: Color
        let metalDeep: Color
        let ribbonLight: Color
        let ribbonMid: Color
        let ribbonDeep: Color
    }

    /// 现实奖牌以金属材质区分等级，以高饱和织带保留 App 内的档位识别度。
    private func medalPalette(for tier: AchievementTier) -> MedalPalette {
        switch tier.id {
        case "common":
            return MedalPalette(
                metalLight: Color(red: 1.00, green: 0.87, blue: 0.61),
                metalMid: Color(red: 0.79, green: 0.48, blue: 0.21),
                metalDeep: Color(red: 0.49, green: 0.24, blue: 0.08),
                ribbonLight: Color(red: 1.00, green: 0.58, blue: 0.43),
                ribbonMid: Color(red: 0.91, green: 0.31, blue: 0.25),
                ribbonDeep: Color(red: 0.58, green: 0.12, blue: 0.12)
            )
        case "uncommon":
            return MedalPalette(
                metalLight: Color(red: 1.00, green: 1.00, blue: 1.00),
                metalMid: Color(red: 0.76, green: 0.82, blue: 0.88),
                metalDeep: Color(red: 0.42, green: 0.49, blue: 0.57),
                ribbonLight: Color(red: 0.45, green: 0.94, blue: 0.72),
                ribbonMid: Color(red: 0.12, green: 0.70, blue: 0.48),
                ribbonDeep: Color(red: 0.03, green: 0.39, blue: 0.27)
            )
        case "rare":
            return MedalPalette(
                metalLight: Color(red: 1.00, green: 0.97, blue: 0.66),
                metalMid: Color(red: 0.96, green: 0.74, blue: 0.22),
                metalDeep: Color(red: 0.65, green: 0.38, blue: 0.03),
                ribbonLight: Color(red: 0.51, green: 0.77, blue: 1.00),
                ribbonMid: Color(red: 0.16, green: 0.48, blue: 0.94),
                ribbonDeep: Color(red: 0.04, green: 0.22, blue: 0.60)
            )
        case "epic":
            return MedalPalette(
                metalLight: Color(red: 1.00, green: 0.88, blue: 0.80),
                metalMid: Color(red: 0.91, green: 0.59, blue: 0.49),
                metalDeep: Color(red: 0.59, green: 0.29, blue: 0.22),
                ribbonLight: Color(red: 0.86, green: 0.67, blue: 1.00),
                ribbonMid: Color(red: 0.61, green: 0.34, blue: 0.86),
                ribbonDeep: Color(red: 0.34, green: 0.13, blue: 0.57)
            )
        default: // Legendary
            return MedalPalette(
                metalLight: Color(red: 1.00, green: 0.98, blue: 0.72),
                metalMid: Color(red: 0.96, green: 0.78, blue: 0.25),
                metalDeep: Color(red: 0.63, green: 0.40, blue: 0.03),
                ribbonLight: Color(red: 1.00, green: 0.50, blue: 0.43),
                ribbonMid: Color(red: 0.88, green: 0.18, blue: 0.20),
                ribbonDeep: Color(red: 0.54, green: 0.06, blue: 0.10)
            )
        }
    }

    /// 每档使用不同的现实织带纹样：单线、宽线、双线、三线、冠军星带。
    @ViewBuilder
    private func medalRibbonPattern(_ tier: AchievementTier, palette: MedalPalette) -> some View {
        switch tier.id {
        case "common":
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 3, height: 15)
                .offset(y: 1)
        case "uncommon":
            Rectangle()
                .fill(Color.white.opacity(0.58))
                .frame(width: 5, height: 17)
        case "rare":
            HStack(spacing: 8) {
                Rectangle().fill(Color.white.opacity(0.68)).frame(width: 2, height: 17)
                Rectangle().fill(Color.white.opacity(0.68)).frame(width: 2, height: 17)
            }
        case "epic":
            HStack(spacing: 3) {
                Rectangle().fill(Color.white.opacity(0.54)).frame(width: 2, height: 17)
                Rectangle().fill(palette.ribbonLight.opacity(0.86)).frame(width: 3, height: 17)
                Rectangle().fill(Color.white.opacity(0.54)).frame(width: 2, height: 17)
            }
        default:
            VStack(spacing: 0) {
                Image(systemName: "star.fill")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(Color(red: 1.00, green: 0.91, blue: 0.45))
                Rectangle()
                    .fill(Color(red: 1.00, green: 0.88, blue: 0.37).opacity(0.90))
                    .frame(width: 4, height: 8)
            }
            .offset(y: 1)
        }
    }

    /// 高阶档位专属光效：史诗是紫粉虹彩魔法环，传说是金色冠军日芒。
    /// 未解锁时仍保留较弱光色，提前建立两档不同的视觉记忆。
    @ViewBuilder
    private func medalTierGlow(_ tier: AchievementTier, reached: Bool) -> some View {
        switch tier.id {
        case "epic":
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [
                            Color(red: 0.93, green: 0.72, blue: 1.00).opacity(0.58),
                            Color(red: 0.67, green: 0.36, blue: 0.96).opacity(0.24),
                            .clear
                        ], center: .center, startRadius: 7, endRadius: 29)
                    )

                Circle()
                    .stroke(
                        AngularGradient(colors: [
                            Color(red: 0.78, green: 0.45, blue: 1.00),
                            Color(red: 1.00, green: 0.57, blue: 0.87),
                            Color.white,
                            Color(red: 0.60, green: 0.42, blue: 1.00),
                            Color(red: 0.78, green: 0.45, blue: 1.00)
                        ], center: .center),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 3])
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color(red: 1.00, green: 0.67, blue: 0.93))
                    .offset(x: -22, y: -17)

                Image(systemName: "sparkle")
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(Color(red: 0.76, green: 0.72, blue: 1.00))
                    .offset(x: 23, y: 15)
            }
            .frame(width: 56, height: 56)
            .offset(y: 10)
            .opacity(reached ? 0.92 : 0.62)

        case "legendary":
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [
                            Color.white.opacity(0.92),
                            Color(red: 1.00, green: 0.84, blue: 0.27).opacity(0.52),
                            Color(red: 1.00, green: 0.55, blue: 0.09).opacity(0.12),
                            .clear
                        ], center: .center, startRadius: 5, endRadius: 32)
                    )

                ForEach(0..<8, id: \.self) { ray in
                    Capsule()
                        .fill(
                            LinearGradient(colors: [
                                Color.white.opacity(0.92),
                                Color(red: 1.00, green: 0.70, blue: 0.10).opacity(0.18)
                            ], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: ray.isMultiple(of: 2) ? 2.2 : 1.4,
                               height: ray.isMultiple(of: 2) ? 8 : 5)
                        .offset(y: -27)
                        .rotationEffect(.degrees(Double(ray) * 45))
                }

                Circle()
                    .stroke(Color(red: 1.00, green: 0.84, blue: 0.31).opacity(0.68), lineWidth: 1.2)
                    .frame(width: 51, height: 51)

                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(red: 1.00, green: 0.91, blue: 0.48))
                    .offset(x: 21, y: -19)
            }
            .frame(width: 62, height: 62)
            .offset(y: 7)
            .opacity(reached ? 1 : 0.70)

        default:
            EmptyView()
        }
    }

    /// 档位勋章：上方织带 + 金属连接环 + 悬挂式铸币奖章，接近现实奖牌的结构。
    /// 达成 = 明亮金属、织带原色和达成章；未达成仍清晰可见，只降低饱和度。
    private func tierMedal(_ tier: AchievementTier, reached: Bool) -> some View {
        let palette = medalPalette(for: tier)

        return ZStack(alignment: .top) {
            medalTierGlow(tier, reached: reached)

            // 奖牌后的柔和反光，避免在浅色玻璃卡上失去轮廓。
            Circle()
                .fill(palette.metalLight.opacity(reached ? 0.42 : 0.24))
                .frame(width: 47, height: 47)
                .blur(radius: reached ? 7 : 4)
                .offset(y: 12)

            // 明亮织带采用横向多段渐变，模拟织物中缝与两侧阴影。
            MedalRibbon()
                .fill(
                    LinearGradient(colors: [palette.ribbonDeep,
                                            palette.ribbonMid,
                                            palette.ribbonLight,
                                            palette.ribbonMid,
                                            palette.ribbonDeep],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: 27, height: 23)
                .overlay {
                    MedalRibbon()
                        .stroke(Color.white.opacity(reached ? 0.48 : 0.28), lineWidth: 0.8)
                }
                .shadow(color: palette.ribbonDeep.opacity(0.28), radius: 2, y: 2)

            medalRibbonPattern(tier, palette: palette)

            // 连接扣与吊环，明确表现“织带悬挂奖牌”。
            Capsule()
                .fill(LinearGradient(colors: [palette.metalLight, palette.metalMid],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 12, height: 6)
                .offset(y: 13)

            Circle()
                .stroke(
                    LinearGradient(colors: [palette.metalLight, palette.metalMid, palette.metalDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 3
                )
                .frame(width: 10, height: 10)
                .offset(y: 15)

            // 铸币式外圈：高亮受光边 + 深色侧边，视觉上更接近真实金属。
            Circle()
                .fill(
                    LinearGradient(colors: [palette.metalLight, palette.metalMid, palette.metalDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 42, height: 42)
                .offset(y: 18)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(reached ? 0.88 : 0.54), lineWidth: 1.2)
                        .padding(1)
                        .offset(y: 18)
                }
                .shadow(color: palette.metalDeep.opacity(0.32), radius: 4, y: 3)

            Circle()
                .fill(
                    RadialGradient(colors: [palette.metalLight,
                                            palette.metalMid,
                                            palette.metalDeep.opacity(0.92)],
                                   center: .topLeading, startRadius: 1, endRadius: 24)
                )
                .frame(width: 32, height: 32)
                .offset(y: 23)
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(colors: [Color.white.opacity(0.92),
                                                    palette.metalLight.opacity(0.64),
                                                    palette.metalDeep.opacity(0.55)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.4
                        )
                        .offset(y: 23)
                }

            // 铸币边缘的细密齿纹。
            Circle()
                .stroke(palette.metalDeep.opacity(0.34),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1.3, 2.1]))
                .frame(width: 36, height: 36)
                .offset(y: 21)

            // 小块珐琅内芯沿用织带主色，让五档即使缩小后仍能一眼区分。
            Circle()
                .fill(palette.ribbonMid.opacity(reached ? 0.20 : 0.13))
                .frame(width: 23, height: 23)
                .overlay {
                    Circle().stroke(palette.ribbonLight.opacity(0.48), lineWidth: 0.8)
                }
                .offset(y: 27.5)

            Image(systemName: tier.icon)
                .font(.system(size: 14, weight: .black))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(palette.ribbonDeep)
                .shadow(color: Color.white.opacity(0.58), radius: 0, x: -0.7, y: -0.7)
                .offset(y: 32)

            // 奖章弧形镜面高光。
            Circle()
                .trim(from: 0.08, to: 0.42)
                .stroke(Color.white.opacity(reached ? 0.84 : 0.50),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 34, height: 34)
                .rotationEffect(.degrees(180))
                .offset(y: 25)
        }
        .frame(width: 46, height: 61, alignment: .top)
        .saturation(reached ? 1 : (tier.id == "epic" || tier.id == "legendary" ? 0.58 : 0.30))
        .brightness(reached ? 0 : 0.10)
        .opacity(reached ? 1 : 0.68)
        .overlay(alignment: .topLeading) {
            if reached {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.metalLight)
                    .shadow(color: palette.metalMid.opacity(0.8), radius: 3)
                    .offset(x: -1, y: 14)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if reached {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.white, palette.metalLight],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 15, height: 15)
                    Circle()
                        .stroke(palette.metalDeep.opacity(0.50), lineWidth: 0.8)
                        .frame(width: 15, height: 15)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(palette.metalDeep)
                }
                .offset(x: 1, y: -3)
            }
        }
        .shadow(color: reached ? palette.metalMid.opacity(0.34) : Color.black.opacity(0.08),
                radius: reached ? 8 : 2, x: 0, y: 5)
    }

    private var tierSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("成就档位", "By rarity"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Spacer()
                if let next = nextTier {
                    Text(tr("距\(next.zh)还差 \(next.threshold - xp)",
                            "\(next.threshold - xp) to \(next.en)"))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(PetPalTheme.inkSecondary)
                } else {
                    Text(tr("已达传说", "Maxed"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AchievementTier.all[0].color)
                }
            }

            // 五枚现实奖牌：铜 → 银 → 金 → 玫瑰金 → 冠军金
            HStack(spacing: 3) {
                ForEach(tiersAscending) { tier in
                    let reached = xp >= tier.threshold
                    let palette = medalPalette(for: tier)
                    VStack(spacing: 4) {
                        tierMedal(tier, reached: reached)
                        Text(en ? tier.en : tier.zh)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(reached ? palette.ribbonDeep
                                                     : PetPalTheme.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // 进阶条：下一档颜色的渐变，收口亮一点
            GeometryReader { geo in
                let tint = (nextTier ?? AchievementTier.all[0]).color
                ZStack(alignment: .leading) {
                    Capsule().fill(PetPalTheme.inkSecondary.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.75), tint],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * tierProgress))
                }
            }
            .frame(height: 7)
        }
        .padding(14)
        .modifier(LiquidGlassSurface(cornerRadius: 20))
    }

    // MARK: 排行榜

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("排行榜", "Leaderboard"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PetPalTheme.inkPrimary)
                .padding(.leading, 2)

            // 同一份榜单，只把自己那行提到最前面（名次仍是真实名次）
            VStack(spacing: 0) {
                let rows = myFirstRows
                ForEach(Array(rows.enumerated()), id: \.element.entry.id) { idx, item in
                    rankRow(rank: item.place, entry: item.entry)
                    if idx < rows.count - 1 {
                        Divider().padding(.leading, 66)
                    }
                }
            }
            .padding(.vertical, 4)
            .modifier(LiquidGlassSurface(cornerRadius: 20))
        }
    }

    /// 前三名金银铜徽章色；其余仅数字
    private func medalColor(_ rank: Int) -> Color? {
        switch rank {
        case 1: return Color(red: 0.95, green: 0.75, blue: 0.25)
        case 2: return Color(red: 0.72, green: 0.76, blue: 0.82)
        case 3: return Color(red: 0.82, green: 0.58, blue: 0.38)
        default: return nil
        }
    }

    private func rankRow(rank: Int, entry: RankEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if let medal = medalColor(rank) {
                    Circle().fill(medal).frame(width: 24, height: 24)
                    Text("\(rank)")
                        .font(.system(size: 13, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.white)
                } else {
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(PetPalTheme.inkSecondary)
                }
            }
            .frame(width: 26)

            ZStack {
                Circle()
                    .fill(entry.tint)
                    .frame(width: 36, height: 36)
                Text(String(entry.name.prefix(1)))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(entry.name)
                .font(.system(size: 15, weight: entry.isMe ? .heavy : .bold))
                .foregroundStyle(PetPalTheme.inkPrimary)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text("\(entry.xp)")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(Color(red: 0.94, green: 0.55, blue: 0.20))
            Text("XP")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(PetPalTheme.inkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            entry.isMe
                ? AnyView(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PetPalTheme.primary.opacity(0.14))
                    .padding(.horizontal, 6))
                : AnyView(Color.clear)
        )
    }
}

// MARK: - 经验与等级制度
//
// XP 来源：首页与猫互动（喂食 +20 / 抚摸 +10 / 呼唤 +10 / 换装 +5，见 TamagotchiHomeView.gainXP）。
// 每 500 XP 升一级，称号按等级阶梯取。
enum PetLevel {
    static let perLevel = 500

    static let titles = ["新手铲屎官", "见习猫友", "熟练捕手", "资深猫奴",
                         "金牌铲屎官", "猫语者", "传奇猫伙伴"]
    static let titlesEN = ["Rookie Keeper", "Cat Friend", "Skilled Catcher", "Cat Devotee",
                           "Gold Keeper", "Cat Whisperer", "Legend Companion"]

    static func level(_ xp: Int) -> Int { xp / perLevel + 1 }
    static func title(_ level: Int, en: Bool = false) -> String {
        (en ? titlesEN : titles)[min(max(level - 1, 0), titles.count - 1)]
    }
    static func progress(_ xp: Int) -> Double { Double(xp % perLevel) / Double(perLevel) }
    static func xpToNext(_ xp: Int) -> Int { perLevel - xp % perLevel }
}

// MARK: - Profile Tab

struct ProfileTab: View {
    @Environment(AppState.self) private var state
    @Environment(PetRouter.self) private var router
    @AppStorage("petName") private var petName: String = "喵喵"
    @AppStorage("petAvatarData") private var petAvatarData: Data = Data()
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("userPhone") private var userPhone: String = ""
    @AppStorage("lastBaseURL") private var lastBaseURL: String = ""
    @AppStorage("espHost") private var espHost: String = "esp32-led.local"
    @AppStorage("themeMode") private var themeMode: ThemeMode = .dark
    @AppStorage("xp") private var xp: Int = 0
    @AppStorage("interactionCount") private var interactionCount: Int = 0
    @AppStorage("tama.adoptedAt") private var adoptedAt: Double = 0
    @AppStorage("appLanguage") private var appLanguage: String = "zh"
    @Environment(\.colorScheme) private var scheme

    private var en: Bool { appLanguage == "en" }
    private func tr(_ zh: String, _ english: String) -> String { en ? english : zh }

    @Namespace private var heroNS
    @State private var showNameEditor = false
    @State private var nameInput: String = ""
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var urlInput: String = ""
    @State private var espInput: String = ""
    @State private var serverExpanded = false
    @State private var espExpanded = false
    @State private var themeExpanded = false
    @State private var langExpanded = false
    @State private var espConnected = false

    var body: some View {
        NavigationStack {
            ZStack {
                StarrySkyBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        userCard
                        levelCard
                        passCard
                        proCard
                        petProfileCard
                        appearanceCard
                        languageCard
                        serverCard
                        espCard
                        aboutCard
                        logoutButton
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(tr("我的", "Profile"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        nameInput = petName
                        showNameEditor = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(scheme == .dark ? Color(white: 0.22) : .white)
                                .frame(width: 38, height: 38)
                            Image(systemName: "person.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(scheme == .dark ? .white : Color(white: 0.25))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                route.destination
                    .frostedPage()
                    .zoomTransition(sourceID: route, in: heroNS)
            }
            .onAppear {
                if urlInput.isEmpty {
                    let migrated = BackendEndpoint.migratedSavedURL(lastBaseURL)
                    urlInput = migrated
                    lastBaseURL = migrated
                }
                if espInput.isEmpty { espInput = espHost }
                checkESPConnection()
            }
        }
    }

    // MARK: - 设备连通性探测

    private func checkESPConnection() {
        guard let url = ESPClient.makeLEDBaseURL(from: espHost) else {
            espConnected = false
            return
        }
        Task {
            do {
                _ = try await ESPClient(baseURL: url).status()
                await MainActor.run { espConnected = true }
            } catch {
                await MainActor.run { espConnected = false }
            }
        }
    }

    // MARK: - 用户卡（布局仿 CatGo Settings：金环头像 + 昵称 + 内嵌三格统计）

    private var companionDays: Int {
        guard adoptedAt > 0 else { return 1 }
        return max(1, Int(Date().timeIntervalSince1970 - adoptedAt) / 86400 + 1)
    }

    private var cardFill: Color {
        scheme == .dark ? Color(white: 0.15) : .white
    }

    private var userCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    PetAvatarView(avatarData: petAvatarData, size: 76)
                        .overlay(
                            Circle().strokeBorder(
                                LinearGradient(colors: [Color(red: 0.99, green: 0.87, blue: 0.47),
                                                        Color(red: 0.83, green: 0.58, blue: 0.16)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 3
                            )
                        )

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack {
                            Circle()
                                .fill(cardFill)
                                .frame(width: 28, height: 28)
                                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(PetPalTheme.inkPrimary)
                        }
                        .offset(x: 6, y: 4)
                    }
                    .onChange(of: photoItem) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self) {
                                petAvatarData = data
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        nameInput = petName
                        showNameEditor = true
                    } label: {
                        HStack(spacing: 8) {
                            Text(petName)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(PetPalTheme.inkPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.footnote)
                        Text(en ? "\(userPhone.isEmpty ? "Guest" : userPhone) · Day \(companionDays)"
                                : "\(userPhone.isEmpty ? "游客模式" : userPhone) · 陪伴第 \(companionDays) 天")
                            .font(.subheadline)
                    }
                    .foregroundStyle(PetPalTheme.inkSecondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                statCell(icon: "pawprint.fill", tint: Color(red: 0.93, green: 0.68, blue: 0.20),
                         value: "\(companionDays)", label: tr("陪伴天数", "DAYS"))
                statCell(icon: "hand.tap.fill", tint: .pink,
                         value: "\(interactionCount)", label: tr("互动次数", "ACTIONS"))
                statCell(icon: "shield.lefthalf.filled", tint: Color(red: 0.93, green: 0.68, blue: 0.20),
                         value: "\(xp)", label: "XP")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(cardFill)
                .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 12, x: 0, y: 4)
        )
    }

    private func statCell(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(PetPalTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(scheme == .dark ? Color(white: 0.10) : Color(red: 0.936, green: 0.936, blue: 0.949))
        )
    }

    /// 深底金字的等级卡——布局仿 CatGo Settings 的 Cat Spotter 卡，两种主题下都用固定深色。
    /// 整卡可点，跳到排行页。
    private var levelCard: some View {
        Button {
            router.requestOpenRating()
        } label: {
            levelCardBody
        }
        .buttonStyle(.plain)
        .alert(tr("修改名字", "Rename"), isPresented: $showNameEditor) {
            TextField(tr("宠物名字", "Pet name"), text: $nameInput)
            Button(tr("保存", "Save")) {
                if !nameInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    petName = nameInput
                }
            }
            Button(tr("取消", "Cancel"), role: .cancel) {}
        }
    }

    private var levelCardBody: some View {
        let lv = PetLevel.level(xp)
        let gold = Color(red: 0.98, green: 0.84, blue: 0.40)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [gold, Color(red: 0.88, green: 0.62, blue: 0.18)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 54, height: 54)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(red: 0.45, green: 0.30, blue: 0.05))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(PetLevel.title(lv, en: en))
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Level \(lv)")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(xp == 0 ? tr("旅程刚刚开始", "Just getting started")
                                 : tr("和\(petName)一起攒的经验", "XP earned with \(petName)"))
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }

            // 进度条：左端金色圆点是当前进度头
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 7)
                    Capsule()
                        .fill(gold)
                        .frame(width: max(14, geo.size.width * PetLevel.progress(xp)), height: 7)
                    Circle()
                        .fill(gold)
                        .frame(width: 14, height: 14)
                        .offset(x: max(0, geo.size.width * PetLevel.progress(xp) - 7))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)

            Text(en ? "\(PetLevel.xpToNext(xp)) XP to next level"
                    : "还差 \(PetLevel.xpToNext(xp)) XP 升到下一级")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.11))
        )
    }

    /// 金框高亮卡——对应参考图的 Unlock CatGO，Demo 纯展示
    // MARK: - Season Pass Card

    @AppStorage("passClaimedFree") private var passClaimedFreeRaw: String = ""
    @AppStorage("passClaimedPro") private var passClaimedProRaw: String = ""
    @AppStorage("isPro") private var isPro: Bool = false

    /// 已达成但未领取的奖励数（免费轨 + 已解锁 Pro 时的 Pro 轨）
    private var passClaimable: Int {
        let tier = min(10, xp / 100)
        let free = Set(passClaimedFreeRaw.split(separator: ",").compactMap { Int($0) })
        let pro = Set(passClaimedProRaw.split(separator: ",").compactMap { Int($0) })
        var n = (1...10).filter { $0 <= tier && !free.contains($0) }.count
        if isPro { n += (1...10).filter { $0 <= tier && !pro.contains($0) }.count }
        return n
    }

    private var passCard: some View {
        NavigationLink(value: HomeRoute.pass) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(PassGold.mid.opacity(0.16))
                        .frame(width: 46, height: 46)
                    Circle()
                        .strokeBorder(PassGold.border, lineWidth: 1)
                        .frame(width: 46, height: 46)
                    Image(systemName: "medal.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(PassGold.gradient)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(tr("通行证", "Pass"))
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(PassGold.gradient)
                        if passClaimable > 0 {
                            ClaimBadge(text: tr("\(passClaimable) 个待领", "\(passClaimable) to claim"))
                        }
                    }
                    // 赛季总进度（10 级 × 100 活跃度）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.13))
                            Capsule().fill(PassGold.gradient)
                                .frame(width: max(6, geo.size.width * min(1, Double(xp) / 1000)))
                        }
                    }
                    .frame(height: 6)
                }
                Spacer(minLength: 8)
                Text(tr("等级 \(min(10, xp / 100))", "Tier \(min(10, xp / 100))"))
                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                    .foregroundStyle(PassGold.light)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PassGold.mid.opacity(0.75))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(PassGold.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(PassGold.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.34), radius: 14, x: 0, y: 7)
            .shadow(color: PassGold.mid.opacity(0.16), radius: 9, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var proCard: some View {
        NavigationLink(value: HomeRoute.pro) {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(red: 0.99, green: 0.85, blue: 0.42),
                                                Color(red: 0.87, green: 0.62, blue: 0.15)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("解锁宠宝 Pro", "Unlock PetPel Pro"))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Text(tr("全部功能 · 永久使用", "Lifetime access to all features"))
                        .font(.subheadline)
                        .foregroundStyle(PetPalTheme.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.6))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill((scheme == .dark ? Color(red: 0.28, green: 0.24, blue: 0.12)
                                           : Color(red: 0.96, green: 0.93, blue: 0.80)).opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color(red: 0.93, green: 0.76, blue: 0.28), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .modifier(ZoomSourceModifier(id: .pro, namespace: heroNS))
    }

    // MARK: - Pet Profile Card

    private var petProfileCard: some View {
        PetPalCard {
            VStack(spacing: 0) {
                NavigationLink(value: HomeRoute.profile) {
                    profileRow(icon: "person.text.rectangle", title: tr("宠物档案", "Pet Profile"), color: .purple)
                }
                .modifier(ZoomSourceModifier(id: .profile, namespace: heroNS))
                Divider().padding(.leading, 50)
                NavigationLink(value: HomeRoute.health) {
                    profileRow(icon: "heart.text.square", title: tr("健康记录", "Health Records"), color: .pink)
                }
                .modifier(ZoomSourceModifier(id: .health, namespace: heroNS))
            }
        }
    }

    private func profileRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(PetPalTheme.inkPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.5))
        }
        .padding(.vertical, 12)
    }

    // MARK: - Appearance Card

    private var appearanceCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { themeExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paintbrush.fill")
                            .foregroundStyle(PetPalTheme.primary)
                        Text(tr("主题", "Theme"))
                            .font(.headline)
                            .foregroundStyle(PetPalTheme.inkPrimary)
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: themeMode.icon)
                            Text(en ? themeMode.labelEN : themeMode.label)
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PetPalTheme.inkSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.5))
                            .rotationEffect(.degrees(themeExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if themeExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider().padding(.top, 12)
                        Picker(tr("主题", "Theme"), selection: $themeMode) {
                            ForEach(ThemeMode.allCases) { mode in
                                Text(en ? mode.labelEN : mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: themeMode)
    }

    // MARK: - Language Card

    private var languageCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { langExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .foregroundStyle(.teal)
                        Text(tr("语言", "Language"))
                            .font(.headline)
                            .foregroundStyle(PetPalTheme.inkPrimary)
                        Spacer()
                        Text(AppLanguage(rawValue: appLanguage)?.label ?? "中文")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.5))
                            .rotationEffect(.degrees(langExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if langExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider().padding(.top, 12)
                        Picker(tr("语言", "Language"), selection: $appLanguage) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.label).tag(lang.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appLanguage)
    }

    // MARK: - Server Card

    private var backendBusy: Bool {
        switch state.status {
        case .connecting, .reconnecting: return true
        case .disconnected, .connected, .failed: return false
        }
    }

    @ViewBuilder
    private var backendStatusBadge: some View {
        switch state.status {
        case .connected:
            Text(tr("已连接", "Connected"))
                .foregroundStyle(PetPalTheme.success)
        case .connecting:
            Text(tr("连接中", "Connecting"))
                .foregroundStyle(PetPalTheme.primary)
        case .reconnecting:
            Text(tr("重连中", "Reconnecting"))
                .foregroundStyle(.orange)
        case .failed:
            Text(tr("连接失败", "Failed"))
                .foregroundStyle(PetPalTheme.danger)
        case .disconnected:
            EmptyView()
        }
    }

    @ViewBuilder
    private var backendStatusDetail: some View {
        switch state.status {
        case .connected:
            Label(tr("Linux 真后端已连接", "Linux backend connected"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(PetPalTheme.success)
        case .connecting:
            Label(tr("正在验证健康接口和系统信息…", "Checking backend…"), systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(PetPalTheme.primary)
        case .reconnecting(let message):
            Label(tr("自动重连：\(message)", "Reconnecting: \(message)"), systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(PetPalTheme.danger)
        case .disconnected:
            Text(tr("未连接", "Disconnected"))
                .foregroundStyle(PetPalTheme.inkSecondary)
        }
    }

    private var serverCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { serverExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.blue)
                        Text(tr("后端服务器", "Backend Server"))
                            .font(.headline)
                            .foregroundStyle(PetPalTheme.inkPrimary)
                        Spacer()
                        backendStatusBadge
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(PetPalTheme.inkPrimary.opacity(0.06), in: Capsule())
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.5))
                            .rotationEffect(.degrees(serverExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if serverExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider().padding(.top, 12)
                        TextField("http://<ip>:5008", text: $urlInput)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task {
                                guard await state.connect(urlString: urlInput), let connectedURL = state.baseURL else { return }
                                let canonical = connectedURL.absoluteString
                                lastBaseURL = canonical
                                urlInput = canonical
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if backendBusy { ProgressView().tint(.white) }
                                Text(tr(backendBusy ? "连接中…" : "应用并连接",
                                        backendBusy ? "Connecting…" : "Apply & Connect"))
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(PetPalTheme.primary)
                            )
                        }
                        .disabled(urlInput.isEmpty || backendBusy)
                        backendStatusDetail
                            .font(.caption)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - ESP Card

    private var espCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { espExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .foregroundStyle(.green)
                        Text(tr("设备", "Device"))
                            .font(.headline)
                            .foregroundStyle(PetPalTheme.inkPrimary)
                        Spacer()
                        if espConnected {
                            Text(tr("已连接", "Connected"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(PetPalTheme.success)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(PetPalTheme.success.opacity(0.1), in: Capsule())
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.5))
                            .rotationEffect(.degrees(espExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if espExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider().padding(.top, 12)
                        HStack(spacing: 10) {
                            TextField("192.168.x.x", text: $espInput)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button(tr("保存", "Save")) {
                                espHost = espInput
                                checkESPConnection()
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(PetPalTheme.success)
                            )
                            .disabled(espInput.isEmpty)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - About Card

    private var aboutCard: some View {
        PetPalCard {
            VStack(spacing: 0) {
                aboutRow(tr("名称", "Name"), value: tr("宠宝 PetPel", "PetPel"))
                Divider().padding(.leading, 12)
                aboutRow(tr("版本", "Version"), value: "1.0")
            }
        }
    }

    private func aboutRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(PetPalTheme.inkPrimary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(PetPalTheme.inkSecondary)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            userPhone = ""
            isLoggedIn = false
            // 退出登录后重新走双入口分流（连同上次收敛的虚拟猫/孪生流一起重置）
            UserDefaults.standard.set("", forKey: "entryMode")
            UserDefaults.standard.set("", forKey: "virtualBreed")
            UserDefaults.standard.set(false, forKey: "twinReady")
            state.disconnect()
        } label: {
            Text(tr("退出登录", "Log Out"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PetPalTheme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PetPalTheme.danger.opacity(0.08))
                )
        }
    }
}

// MARK: - Pet Avatar View

struct PetAvatarView: View {
    let avatarData: Data
    let size: CGFloat

    var body: some View {
        Group {
            if let uiImage = UIImage(data: avatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    PetPalTheme.blush
                    Text("🐈")
                        .font(.system(size: size * 0.55))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Feature Tile (shared)

struct FeatureTile: View {
    let route: HomeRoute
    let icon: String
    let title: String
    let color: Color
    var badge: Int? = nil
    var namespace: Namespace.ID

    var body: some View {
        NavigationLink(value: route) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(color)
                        )
                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(PetPalTheme.danger))
                            .offset(x: 6, y: -2)
                    }
                }
                Text(title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
        }
        .modifier(ZoomSourceModifier(id: route, namespace: namespace))
        .buttonStyle(.plain)
    }
}

// MARK: - Status badges

struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption.weight(.bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct BatteryBadge: View {
    let level: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption)
            Text("\(level)%").font(.caption.monospacedDigit())
        }
        .foregroundStyle(level > 20 ? PetPalTheme.success : PetPalTheme.danger)
    }
    private var icon: String {
        switch level {
        case 0..<25: "battery.25"
        case 25..<50: "battery.50"
        case 50..<75: "battery.75"
        default: "battery.100"
        }
    }
}

struct SignalBadge: View {
    let level: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi").font(.caption)
            Text(label).font(.caption)
        }
        .foregroundStyle(PetPalTheme.inkSecondary)
    }
    private var label: String {
        switch level {
        case 0: "无"
        case 1: "弱"
        case 2: "中"
        default: "强"
        }
    }
}

// MARK: - Navigation routes

enum HomeRoute: Hashable {
    case camera, light, speaker, motor, arc, gps, viz3d
    case live, trajectory, vlm, detections, stats, alerts, health, profile, shop, social, training, breeding
    case feed, memorial, neutering, matching, pro, pass
    case collarData

    @ViewBuilder
    var destination: some View {
        switch self {
        case .camera:     CameraStreamView()
        case .light:      LightControlView()
        case .speaker:    SpeakerControlView()
        case .motor:      MotorControlView()
        case .arc:        ArcControlView()
        case .gps:        GPSView()
        case .viz3d:      Visualization3DView()
        case .live:       LivePreviewView()
        case .trajectory: TrajectoryView()
        case .vlm:        VLMPanelView()
        case .detections: DetectionsPanelView()
        case .stats:      StatsPanelView()
        case .alerts:     AlertsView()
        case .health:     HealthView()
        case .profile:    PetProfileView()
        case .shop:       ShopView()
        case .social:     SocialView()
        case .training:   TrainingView()
        case .breeding:   BreedingView()
        case .feed:       FeedEntryView()
        case .memorial:   MemorialEntryView()
        case .neutering:  NeuteringEntryView()
        case .matching:   MatchingEntryView()
        case .pro:        ProUnlockView()
        case .pass:       PassView()
        case .collarData: CollarDataView()
        }
    }
}

// MARK: - Settings sheet (kept for compatibility)

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @AppStorage("lastBaseURL") private var lastBaseURL: String = ""
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("userPhone") private var userPhone: String = ""
    @AppStorage("espHost") private var espHost: String = "esp32-led.local"

    @State private var urlInput: String = ""
    @State private var espInput: String = ""

    private var backendBusy: Bool {
        switch state.status {
        case .connecting, .reconnecting: return true
        case .disconnected, .connected, .failed: return false
        }
    }

    @ViewBuilder
    private var backendStatus: some View {
        switch state.status {
        case .connected:
            Label("已连接 Linux 真后端", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .connecting:
            Label("连接中…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.blue)
        case .reconnecting(let message):
            Label("重连中：\(message)", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .disconnected:
            Text("未连接").foregroundStyle(.secondary)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账号") {
                    HStack {
                        Label(userPhone.isEmpty ? "游客模式" : userPhone, systemImage: "person.crop.circle.fill")
                        Spacer()
                    }
                    Button(role: .destructive) {
                        userPhone = ""
                        isLoggedIn = false
                        // 退出登录后重新走双入口分流（连同上次收敛的虚拟猫/孪生流一起重置）
                        UserDefaults.standard.set("", forKey: "entryMode")
                        UserDefaults.standard.set("", forKey: "virtualBreed")
                        UserDefaults.standard.set(false, forKey: "twinReady")
                        state.disconnect()
                        dismiss()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section {
                    TextField("http://<ip>:5008", text: $urlInput)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    HStack {
                        Button(backendBusy ? "连接中…" : "应用并连接") {
                            Task {
                                guard await state.connect(urlString: urlInput), let connectedURL = state.baseURL else { return }
                                let canonical = connectedURL.absoluteString
                                lastBaseURL = canonical
                                urlInput = canonical
                            }
                        }
                        .disabled(urlInput.isEmpty || backendBusy)
                        Spacer()
                        backendStatus.font(.caption)
                    }
                } header: {
                    Text("后端服务器")
                } footer: {
                    Text("真机优先使用 Linux 的 Tailscale 固定主机名；连接失败时自动回退到 Tailscale IP、.local 和局域网 IP。")
                }

                Section {
                    TextField("192.168.x.x 或 esp32-led.local", text: $espInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("保存") {
                        espHost = espInput
                    }
                    .disabled(espInput.isEmpty)
                } header: {
                    Text("设备")
                } footer: {
                    Text("当前：\(espHost)")
                }

                Section("关于") {
                    HStack {
                        Text("名称"); Spacer(); Text("宠宝PetPel").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("版本"); Spacer(); Text("1.0").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                if urlInput.isEmpty {
                    let migrated = BackendEndpoint.migratedSavedURL(lastBaseURL)
                    urlInput = migrated
                    lastBaseURL = migrated
                }
                if espInput.isEmpty { espInput = espHost }
            }
        }
    }
}

// MARK: - Zoom Transition Helpers

// MARK: - 通行证黑金配色

/// 通行证专用黑金调：金属渐变（亮→主→暗）压在微暖炭黑底上，
/// 与全局珊瑚橙主题刻意区隔，让通行证在一堆白卡里自成一档。
private enum PassGold {
    static let light = Color(red: 0.98, green: 0.87, blue: 0.55)   // 亮金·高光
    static let mid   = Color(red: 0.85, green: 0.68, blue: 0.30)   // 主金
    static let deep  = Color(red: 0.62, green: 0.46, blue: 0.13)   // 暗金·阴影
    static let ink   = Color(red: 0.10, green: 0.09, blue: 0.08)   // 金底上的黑字

    /// 金属质感：斜向三段，模拟受光面到背光面
    static let gradient = LinearGradient(
        colors: [light, mid, deep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 卡片黑底（微暖炭黑，避免死黑发闷）
    static let cardFill = LinearGradient(
        colors: [Color(red: 0.17, green: 0.155, blue: 0.14),
                 Color(red: 0.07, green: 0.068, blue: 0.075)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 描边：上缘亮金下缘暗金，模拟金属边受光
    static let border = LinearGradient(
        colors: [mid.opacity(0.85), deep.opacity(0.30)],
        startPoint: .top, endPoint: .bottom
    )
}

/// 待领取徽章：金底黑字 + 持续呼吸（缩放 + 辉光同步脉动），
/// 只在有奖励可领时出现，用动态把视线拉过去。
private struct ClaimBadge: View {
    let text: String
    @State private var breathe = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(PassGold.ink)
            .padding(.horizontal, 8).padding(.vertical, 3.5)
            .background(Capsule().fill(PassGold.gradient))
            .overlay(
                Capsule().strokeBorder(PassGold.light.opacity(breathe ? 0.9 : 0.35),
                                       lineWidth: 0.8)
            )
            .shadow(color: PassGold.mid.opacity(breathe ? 0.80 : 0.22),
                    radius: breathe ? 9 : 3)
            .scaleEffect(breathe ? 1.06 : 0.96)
            .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true),
                       value: breathe)
            .onAppear { breathe = true }
            .accessibilityLabel(text)
    }
}

private struct ZoomSourceModifier: ViewModifier {
    let id: HomeRoute
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

extension View {
    func zoomTransition(sourceID: HomeRoute, in ns: Namespace.ID) -> some View {
        modifier(ZoomDestinationModifier(id: sourceID, namespace: ns))
    }
}

private struct ZoomDestinationModifier: ViewModifier {
    let id: HomeRoute
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
        .environment(AlertEngine())
}

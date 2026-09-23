import SwiftUI

// MARK: - 通行证
//
// 活跃度 = 既有 XP 体系（喂食/抚摸/换装/逛商城都在攒），每 100 点升 1 级，共 10 级。
// 双轨奖励：免费轨人人可领；Pro 轨同等级额外多送一份，未解锁 Pro 时带锁，
// 点击锁定奖励直接跳 Pro 解锁页（HomeRoute.pro）。
//
// 视觉：整页黑金赛季舞台，与排行页那张黑金入口卡同一身份（PassGold 同调），
// 点进来不换气质。颜色分层：炭黑舞台底 → 银 = 免费轨 → 金 = Pro 轨/等级成就
// → 红 = 待领行动点 → 绿 = 已领取。页面恒定深色，文字用写死的亮色，不跟系统翻转。
// 领取状态持久化在 AppStorage（逗号分隔的等级号），Demo 阶段奖励为展示性发放。

struct PassView: View {
    @AppStorage("xp") private var xp: Int = 0
    @AppStorage("isPro") private var isPro: Bool = false
    @AppStorage("passClaimedFree") private var claimedFreeRaw: String = ""
    @AppStorage("passClaimedPro") private var claimedProRaw: String = ""
    @AppStorage("appLanguage") private var appLanguage: String = "zh"

    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var isEarnSectionExpanded = false

    private var en: Bool { appLanguage == "en" }
    private func tr(_ zh: String, _ english: String) -> String { en ? english : zh }

    // MARK: 黑金舞台配色（与排行页入口卡 PassGold 同调）

    private enum Noir {
        // 金属金：亮→主→暗，模拟受光面到背光面
        static let goldLight = Color(red: 0.98, green: 0.87, blue: 0.55)
        static let gold      = Color(red: 0.85, green: 0.68, blue: 0.30)
        static let goldDeep  = Color(red: 0.62, green: 0.46, blue: 0.13)
        static let ink       = Color(red: 0.10, green: 0.09, blue: 0.08)   // 金面上的黑字
        static let goldGradient = LinearGradient(
            colors: [goldLight, gold, goldDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        static let goldBorder = LinearGradient(
            colors: [gold.opacity(0.85), goldDeep.opacity(0.30)],
            startPoint: .top, endPoint: .bottom)

        // 银：免费轨的一层，刻意比金低半档
        static let silver    = Color(red: 0.89, green: 0.90, blue: 0.93)
        static let silverDim = Color(red: 0.63, green: 0.65, blue: 0.70)

        // 暖炭舞台：比纯黑提亮一档，保留黑金氛围但不压暗页面
        static let stageTop    = Color(red: 0.180, green: 0.155, blue: 0.125)
        static let stageBottom = Color(red: 0.082, green: 0.074, blue: 0.090)
        static let cardFill = LinearGradient(
            colors: [Color(red: 0.170, green: 0.155, blue: 0.140),
                     Color(red: 0.070, green: 0.068, blue: 0.075)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        static let rowFill  = Color.white.opacity(0.045)
        static let hairline = Color.white.opacity(0.08)

        // 恒定亮色文字（页面不跟系统深浅翻转）
        static let textHi = Color(red: 0.97, green: 0.96, blue: 0.94)
        static let textLo = Color(red: 0.67, green: 0.65, blue: 0.61)
    }

    // MARK: 赛季配置

    private static let pointsPerTier = 100
    private static let seasonEnd = DateComponents(calendar: .current, year: 2026, month: 9, day: 30).date ?? .now

    private var daysLeft: Int {
        max(0, Calendar.current.dateComponents([.day], from: .now, to: Self.seasonEnd).day ?? 0)
    }

    struct Tier: Identifiable {
        let level: Int
        let freeIcon: String, freeTitle: String
        let proIcon: String, proTitle: String
        var id: Int { level }
        var need: Int { level * PassView.pointsPerTier }
    }

    private var tiers: [Tier] {
        [
            Tier(level: 1,  freeIcon: "fish.fill",            freeTitle: tr("小鱼干 ×5", "Fish ×5"),
                            proIcon: "paintbrush.fill",       proTitle: tr("限定·金爪皮肤", "Gold Paw Skin")),
            Tier(level: 2,  freeIcon: "sparkles",             freeTitle: tr("经验卡 +50", "XP Card +50"),
                            proIcon: "crown.fill",            proTitle: tr("限定·皇冠变装", "Crown Outfit")),
            Tier(level: 3,  freeIcon: "gift.fill",            freeTitle: tr("蝴蝶结变装", "Bow Outfit"),
                            proIcon: "ticket.fill",           proTitle: tr("商城 8 折券", "Shop 20% Off")),
            Tier(level: 4,  freeIcon: "takeoutbag.and.cup.and.straw.fill", freeTitle: tr("猫粮试用装", "Food Sample"),
                            proIcon: "gift.fill",             proTitle: tr("猫零食大礼包", "Treat Bundle")),
            Tier(level: 5,  freeIcon: "bell.fill",            freeTitle: tr("铃铛项圈变装", "Bell Collar"),
                            proIcon: "wand.and.stars",        proTitle: tr("限定·巫师帽变装", "Wizard Hat")),
            Tier(level: 6,  freeIcon: "ticket.fill",          freeTitle: tr("商城 9 折券", "Shop 10% Off"),
                            proIcon: "ticket.fill",           proTitle: tr("商城 7 折券", "Shop 30% Off")),
            Tier(level: 7,  freeIcon: "eyeglasses",           freeTitle: tr("墨镜变装", "Sunglasses"),
                            proIcon: "teddybear.fill",        proTitle: tr("限定款逗猫玩具", "Limited Cat Toy")),
            Tier(level: 8,  freeIcon: "fish.fill",            freeTitle: tr("小鱼干 ×20", "Fish ×20"),
                            proIcon: "moon.stars.fill",       proTitle: tr("限定·星空皮肤", "Starry Skin")),
            Tier(level: 9,  freeIcon: "tshirt.fill",          freeTitle: tr("围巾变装", "Scarf Outfit"),
                            proIcon: "ticket.fill",           proTitle: tr("智能项圈 5 折券", "Collar 50% Off")),
            Tier(level: 10, freeIcon: "medal.fill",           freeTitle: tr("星空徽章", "Starry Badge"),
                            proIcon: "star.circle.fill",      proTitle: tr("传说·星空猫皮肤", "Legend Starry Skin")),
        ]
    }

    // MARK: 领取状态

    private var claimedFree: Set<Int> { Set(claimedFreeRaw.split(separator: ",").compactMap { Int($0) }) }
    private var claimedPro: Set<Int> { Set(claimedProRaw.split(separator: ",").compactMap { Int($0) }) }

    private var currentTier: Int { min(10, xp / Self.pointsPerTier) }

    private var claimableCount: Int {
        var n = (1...10).filter { $0 <= currentTier && !claimedFree.contains($0) }.count
        if isPro { n += (1...10).filter { $0 <= currentTier && !claimedPro.contains($0) }.count }
        return n
    }

    private func claimFree(_ t: Tier) {
        var s = claimedFree; s.insert(t.level)
        claimedFreeRaw = s.sorted().map(String.init).joined(separator: ",")
        showToast(tr("已领取：\(t.freeTitle)", "Claimed: \(t.freeTitle)"))
    }

    private func claimPro(_ t: Tier) {
        var s = claimedPro; s.insert(t.level)
        claimedProRaw = s.sorted().map(String.init).joined(separator: ",")
        showToast(tr("已领取：\(t.proTitle)", "Claimed: \(t.proTitle)"))
    }

    private func showToast(_ msg: String) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { toast = nil }
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            PassStageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    seasonCard
                    earnSection
                    trackSection
                    if !isPro { proBanner }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle(tr("通行证", "Pass"))
        .navigationBarTitleDisplayMode(.inline)
        // 实底深色导航栏：状态栏文字转白、滚动内容不穿透标题区
        .toolbarBackground(Noir.stageTop, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Noir.goldLight)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(Noir.ink.opacity(0.92)))
                    .overlay(Capsule().strokeBorder(Noir.goldDeep.opacity(0.6), lineWidth: 1))
                    .padding(.bottom, 30)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: toast)
    }

    // MARK: 赛季头卡（黑金主卡：金渐变大数字 + 辉光分段进度）

    private var seasonCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Noir.goldGradient)
                        Text(tr("星空季 · S1", "Starry Season · S1"))
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Noir.goldGradient)
                    }
                    Text(tr("剩余 \(daysLeft) 天", "\(daysLeft) days left"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Noir.textLo)
                        .padding(.horizontal, 9).padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Noir.hairline, lineWidth: 1))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(xp)")
                        .font(.system(size: 36, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Noir.goldGradient)
                        .shadow(color: Noir.gold.opacity(0.35), radius: 8, y: 2)
                    Text(tr("活跃度", "Activity"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Noir.textLo)
                }
            }

            // 10 段式等级进度条：达成实填金渐变带辉光、当前段按比例、其余留暗
            let inTier = xp - currentTier * Self.pointsPerTier
            let frac = Double(inTier) / Double(Self.pointsPerTier)
            HStack(spacing: 5) {
                ForEach(1...10, id: \.self) { level in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            if level <= currentTier {
                                Capsule().fill(Noir.goldGradient)
                                    .shadow(color: Noir.gold.opacity(0.55), radius: 3, y: 1)
                            } else if level == currentTier + 1 {
                                Capsule().fill(Noir.goldGradient)
                                    .frame(width: max(0, geo.size.width * frac))
                            }
                        }
                    }
                    .frame(height: 9)
                }
            }

            HStack {
                Text(tr("等级 \(currentTier)", "Tier \(currentTier)"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Noir.textHi)
                if claimableCount > 0 {
                    Text(tr("\(claimableCount) 份待领", "\(claimableCount) to claim"))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(PetPalTheme.danger))
                }
                Spacer()
                Text(currentTier >= 10
                     ? tr("已满级", "Maxed")
                     : tr("还差 \(Self.pointsPerTier - inTier) 点升级", "\(Self.pointsPerTier - inTier) pts to next"))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Noir.textLo)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Noir.cardFill))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Noir.goldBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.34), radius: 14, y: 7)
        .shadow(color: Noir.gold.opacity(0.16), radius: 9, y: 2)
    }

    // MARK: 攒活跃度（默认收起，点击标题展开暗底金字芯片）

    private var earnSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isEarnSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tr("怎么攒活跃度", "Earn activity"))
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(Noir.textHi)

                        Text(isEarnSectionExpanded
                             ? tr("点击收起", "Tap to collapse")
                             : tr("点击展开查看获取方式", "Tap to see how to earn"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Noir.textLo)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Noir.goldLight)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .overlay(Circle().strokeBorder(Noir.goldDeep.opacity(0.35), lineWidth: 1))
                        .rotationEffect(.degrees(isEarnSectionExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("怎么攒活跃度", "Earn activity"))
            .accessibilityValue(isEarnSectionExpanded ? tr("已展开", "Expanded") : tr("已收起", "Collapsed"))
            .accessibilityHint(isEarnSectionExpanded
                               ? tr("轻点收起获取方式", "Tap to hide earning methods")
                               : tr("轻点展开获取方式", "Tap to show earning methods"))

            if isEarnSectionExpanded {
                FlexWrap(spacing: 8) {
                    ForEach([
                        tr("喂食 +5", "Feed +5"),
                        tr("抚摸 +5", "Pet +5"),
                        tr("换装 +5", "Outfit +5"),
                        tr("查看实况 +10", "Live +10"),
                        tr("逛商城 +5", "Shop +5"),
                        tr("每日登录 +10", "Daily +10"),
                    ], id: \.self) { text in
                        Text(text)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Noir.goldLight)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.05)))
                            .overlay(Capsule().strokeBorder(Noir.goldDeep.opacity(0.35), lineWidth: 1))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 节标题：亮字 + 短金杠，把层级从字号交给颜色
    private func sectionTitle(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Noir.textHi)
            Capsule().fill(Noir.goldGradient)
                .frame(width: 34, height: 3)
        }
    }

    // MARK: 赛季奖励（银轨 / 金轨双列）

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(tr("赛季奖励", "Season rewards"))

            Text(tr("同样的活跃度，Pro 双份领取", "Same activity, Pro claims both"))
                .font(.system(size: 13))
                .foregroundStyle(Noir.textLo)

            trackHeader

            VStack(spacing: 10) {
                ForEach(tiers) { tierRow($0) }
            }

        }
    }

    /// 双轨提示栏：与下方等级行的两列严格对齐。免费轨=银、Pro 轨=金，一眼分层。
    private var trackHeader: some View {
        HStack(spacing: 10) {
            // 占位对齐等级徽章列
            Color.clear.frame(width: 44, height: 1)

            // 免费轨表头（银）
            VStack(spacing: 2) {
                Text(tr("免费奖励", "FREE"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Noir.silver)
                Text(tr("人人可领", "For everyone"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Noir.silverDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Noir.silver.opacity(0.35), lineWidth: 1)
            )

            // Pro 轨表头（金渐变实底 + 黑字）
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(tr("PRO 专属", "PRO ONLY"))
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundStyle(Noir.ink)
                Text(tr("限定皮肤 · 商品 · 折扣券", "Skins · Goods · Coupons"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Noir.ink.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Noir.goldGradient)
            )
            .shadow(color: Noir.goldDeep.opacity(0.45), radius: 8, y: 3)
        }
    }

    private func tierRow(_ t: Tier) -> some View {
        let reached = xp >= t.need
        let isCurrent = t.level == currentTier + 1
        return HStack(spacing: 10) {
            // 等级徽章：达成金渐变黑字，下一级金描边高亮，未达成留暗
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(reached ? AnyShapeStyle(Noir.goldGradient)
                                      : AnyShapeStyle(Color.white.opacity(0.08)))
                    if isCurrent {
                        Circle().strokeBorder(Noir.goldLight, lineWidth: 2)
                    }
                    Text("\(t.level)")
                        .font(.system(size: 15, weight: .heavy).monospacedDigit())
                        .foregroundStyle(reached ? Noir.ink : Noir.textLo)
                }
                .frame(width: 34, height: 34)
                Text("\(t.need)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(Noir.textLo)
            }
            .frame(width: 44)

            // 免费轨（银）
            rewardCell(icon: t.freeIcon, title: t.freeTitle,
                       reached: reached, claimed: claimedFree.contains(t.level),
                       pro: false) { claimFree(t) }

            // Pro 轨（金）
            if isPro {
                rewardCell(icon: t.proIcon, title: t.proTitle,
                           reached: reached, claimed: claimedPro.contains(t.level),
                           pro: true) { claimPro(t) }
            } else {
                NavigationLink(value: HomeRoute.pro) {
                    lockedProCell(icon: t.proIcon, title: t.proTitle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isCurrent ? AnyShapeStyle(Noir.gold.opacity(0.07)) : AnyShapeStyle(Noir.rowFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isCurrent ? AnyShapeStyle(Noir.goldDeep.opacity(0.55))
                                        : AnyShapeStyle(Noir.hairline), lineWidth: 1)
        )
    }

    private func rewardCell(icon: String, title: String,
                            reached: Bool, claimed: Bool, pro: Bool,
                            claim: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(pro ? Noir.goldLight.opacity(0.16) : Color.white.opacity(0.07))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(pro ? AnyShapeStyle(Noir.goldGradient)
                                         : AnyShapeStyle(Noir.silver))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                if pro {
                    Text("PRO")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Noir.goldLight)
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Noir.textHi)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)

            if claimed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(PetPalTheme.success)
            } else if reached {
                Button(action: claim) {
                    Text(tr("领", "Get"))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Noir.ink)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(pro ? AnyShapeStyle(Noir.goldGradient)
                                                       : AnyShapeStyle(Noir.silver)))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "hourglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Noir.textLo.opacity(0.5))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(pro ? Noir.goldLight.opacity(0.07) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(pro ? Noir.goldDeep.opacity(0.35) : Color.white.opacity(0.06),
                              lineWidth: 1)
        )
        .opacity(reached ? 1 : 0.55)
    }

    private func lockedProCell(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Noir.goldLight.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Noir.goldDeep)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("PRO")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Noir.goldLight.opacity(0.8))
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Noir.textHi.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)

            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Noir.gold.opacity(0.8))
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Noir.goldLight.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Noir.goldDeep.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: 底部 Pro 引导

    private var proBanner: some View {
        NavigationLink(value: HomeRoute.pro) {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Noir.goldGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("解锁宠宝 Pro，双轨全领", "Unlock Pro — claim both tracks"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Noir.textHi)
                    Text(tr("同样的活跃度，多领 10 份专属奖励", "Same activity, 10 extra rewards"))
                        .font(.system(size: 12))
                        .foregroundStyle(Noir.textLo)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Noir.gold)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Noir.cardFill))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Noir.goldBorder, lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.30), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 黑金舞台背景
//
// 炭黑纵向渐变 + 头部一団金色辉光（把视线引向赛季主卡）+ 低调金色奖杯底纹。
// 底纹沿用排行页 TrophyPatternBackground 的散布 DNA，但换成暗金、密度减半，
// 保持「同一个 App」的血缘又不抢前景。

private struct PassStageBackground: View {
    private static let trophies: [(x: CGFloat, y: CGFloat, s: CGFloat, o: Double)] = [
        (0.08, 0.05, 36, 0.10), (0.62, 0.04, 30, 0.08), (0.90, 0.09, 32, 0.09),
        (0.30, 0.14, 34, 0.09), (0.74, 0.20, 30, 0.07),
        (0.12, 0.28, 32, 0.08), (0.52, 0.33, 34, 0.08), (0.88, 0.38, 30, 0.07),
        (0.26, 0.45, 34, 0.08), (0.68, 0.52, 32, 0.07),
        (0.09, 0.60, 30, 0.07), (0.48, 0.66, 34, 0.07), (0.86, 0.71, 30, 0.06),
        (0.22, 0.79, 32, 0.06), (0.64, 0.86, 34, 0.06), (0.10, 0.93, 30, 0.05),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.180, green: 0.155, blue: 0.125),
                             Color(red: 0.082, green: 0.074, blue: 0.090)],
                    startPoint: .top, endPoint: .bottom)

                // 头部金色辉光：光源感，喂给赛季主卡
                RadialGradient(
                    colors: [Color(red: 0.85, green: 0.68, blue: 0.30).opacity(0.27), .clear],
                    center: UnitPoint(x: 0.5, y: 0.02),
                    startRadius: 10, endRadius: geo.size.width * 0.95)

                ForEach(Array(Self.trophies.enumerated()), id: \.offset) { _, t in
                    Image(systemName: "trophy.fill")
                        .font(.system(size: t.s))
                        .foregroundStyle(Color(red: 0.85, green: 0.68, blue: 0.30).opacity(t.o))
                        .position(x: geo.size.width * t.x, y: geo.size.height * t.y)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// 简易流式布局（iOS 16+ Layout）
private struct FlexWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

#Preview {
    NavigationStack { PassView() }
}

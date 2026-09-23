import SwiftUI

// MARK: - 宠宝 Pro 解锁页
//
// 展示件：只做外观（looks-like），不接真实 IAP / StoreKit。
// 点「立即解锁」走 demo 提示，不产生任何交易。

struct ProUnlockView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage: String = "zh"
    @AppStorage("isPro") private var isPro: Bool = false

    @State private var plan: Plan = .yearly
    @State private var showDemoNotice = false
    @State private var heroGlow = false

    private var en: Bool { appLanguage == "en" }
    private func tr(_ zh: String, _ english: String) -> String { en ? english : zh }

    // MARK: 金色（与「我的」页 proCard 同一套）

    private enum Gold {
        static let bright = Color(red: 0.99, green: 0.85, blue: 0.42)
        static let deep   = Color(red: 0.87, green: 0.62, blue: 0.15)
        static let stroke = Color(red: 0.93, green: 0.76, blue: 0.28)
        static let gradient = LinearGradient(colors: [bright, deep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: 套餐

    enum Plan: String, CaseIterable, Identifiable {
        case monthly, yearly, lifetime
        var id: String { rawValue }
    }

    private func planTitle(_ p: Plan) -> String {
        switch p {
        case .monthly:  return tr("月卡", "Monthly")
        case .yearly:   return tr("年卡", "Yearly")
        case .lifetime: return tr("永久", "Lifetime")
        }
    }

    private func planPrice(_ p: Plan) -> String {
        switch p {
        case .monthly:  return "¥18"
        case .yearly:   return "¥98"
        case .lifetime: return "¥298"
        }
    }

    private func planUnit(_ p: Plan) -> String {
        switch p {
        case .monthly:  return tr("/ 月", "/ mo")
        case .yearly:   return tr("/ 年", "/ yr")
        case .lifetime: return tr("一次买断", "one-time")
        }
    }

    private func planNote(_ p: Plan) -> String {
        switch p {
        case .monthly:  return tr("随时取消", "Cancel anytime")
        case .yearly:   return tr("折合 ¥8.2 / 月", "≈ ¥8.2 / mo")
        case .lifetime: return tr("不再续费", "No renewal")
        }
    }

    private func planBadge(_ p: Plan) -> String? {
        switch p {
        case .yearly:   return tr("省 55%", "Save 55%")
        case .lifetime: return tr("最超值", "Best value")
        case .monthly:  return nil
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            StarrySkyBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    hero
                    benefitsSection
                    comparisonCard
                    planSection
                    Color.clear.frame(height: 130)   // 给底部固定 CTA 留位
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
        }
        .safeAreaInset(edge: .bottom) { ctaBar }
        .navigationTitle(tr("宠宝 Pro", "PetPel Pro"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                heroGlow = true
            }
        }
        .alert(tr("敬请期待", "Coming Soon"), isPresented: $showDemoNotice) {
            Button(tr("好的", "OK"), role: .cancel) {}
        } message: {
            Text(tr("正式版将接入 App Store 内购，当前版本不会产生任何扣费。",
                    "The shipping build will use App Store in-app purchase. No charge will be made in this build."))
        }
    }

    // MARK: 顶部：皇冠 + 标题

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Gold.bright.opacity(0.22))
                    .frame(width: 132, height: 132)
                    .blur(radius: 18)
                    .scaleEffect(heroGlow ? 1.12 : 0.94)

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 104, height: 104)
                    .overlay(Circle().strokeBorder(Gold.stroke.opacity(0.55), lineWidth: 1.2))

                Image(systemName: "crown.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(Gold.gradient)
                    .shadow(color: Gold.deep.opacity(0.4), radius: 10, y: 4)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(tr("宠宝 Pro", "PetPel Pro"))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Gold.gradient)
                Text(tr("解锁全部能力，把 TA 照顾得更好", "Unlock everything. Care for them better."))
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.68))
                    .multilineTextAlignment(.center)
            }

            if isPro {
                Label(tr("已是 Pro 会员", "You're a Pro member"), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Gold.deep)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Gold.bright.opacity(0.2)))
            }
        }
    }

    // MARK: 权益（两列玻璃卡）

    private struct Benefit: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let desc: String
        let tint: Color
    }

    private var benefits: [Benefit] {
        [
            Benefit(icon: "waveform.path.ecg", title: tr("AI 健康分析", "AI Health"),
                    desc: tr("无限次体检报告与异常预警", "Unlimited reports & alerts"), tint: PetPalTheme.danger),
            Benefit(icon: "video.fill", title: tr("高清实时画面", "HD Live"),
                    desc: tr("1080P 直播 + 7 天云回放", "1080P + 7-day cloud replay"), tint: .blue),
            Benefit(icon: "location.fill", title: tr("寻猫模式", "Find My Cat"),
                    desc: tr("高频定位与轨迹回溯", "High-rate GPS & trails"), tint: PetPalTheme.success),
            Benefit(icon: "tshirt.fill", title: tr("全部 3D 变装", "All Outfits"),
                    desc: tr("20+ 套帽子围巾项圈皮肤", "20+ hats, scarves, collars"), tint: .purple),
            Benefit(icon: "desktopcomputer", title: tr("电脑桌宠", "Desktop Pet"),
                    desc: tr("Mac / Win 桌宠 + 全部小组件", "Mac/Win pet + all widgets"), tint: .indigo),
            Benefit(icon: "bubble.left.and.bubble.right.fill", title: tr("专属顾问", "Priority Care"),
                    desc: tr("1v1 养宠答疑 · 新功能抢先", "1:1 advice · early access"), tint: PetPalTheme.primary),
        ]
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(tr("Pro 权益", "What you get"))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(benefits) { b in
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack {
                            Circle().fill(b.tint.opacity(0.18))
                            Image(systemName: b.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(b.tint)
                        }
                        .frame(width: 36, height: 36)

                        Text(b.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(PetPalTheme.inkPrimary)
                        Text(b.desc)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(PetPalTheme.inkPrimary.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: 免费 vs Pro 对比

    private struct CompareRow {
        let label: String
        let free: String
        let pro: String
    }

    private var compareRows: [CompareRow] {
        [
            CompareRow(label: tr("实时画面", "Live video"), free: tr("标清", "SD"), pro: tr("1080P", "1080P")),
            CompareRow(label: tr("云端回放", "Cloud replay"), free: "—", pro: tr("7 天", "7 days")),
            CompareRow(label: tr("AI 体检", "AI checkup"), free: tr("3 次 / 月", "3 / mo"), pro: tr("无限", "Unlimited")),
            CompareRow(label: tr("3D 变装", "3D outfits"), free: tr("2 款", "2"), pro: tr("全部", "All")),
            CompareRow(label: tr("桌宠 & 小组件", "Desktop & widgets"), free: "—", pro: "✓"),
            CompareRow(label: tr("广告", "Ads"), free: tr("有", "Yes"), pro: tr("无", "None")),
        ]
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(tr("免费版 vs Pro", "Free vs Pro"))

            PetPalCard(padding: 16) {
                VStack(spacing: 0) {
                    HStack {
                        Text("").frame(maxWidth: .infinity, alignment: .leading)
                        Text(tr("免费", "Free"))
                            .frame(width: 78)
                            .foregroundStyle(PetPalTheme.inkSecondary)
                        Text("Pro")
                            .frame(width: 78)
                            .foregroundStyle(Gold.deep)
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.bottom, 10)

                    ForEach(Array(compareRows.enumerated()), id: \.offset) { idx, row in
                        if idx > 0 { Divider().opacity(0.5) }
                        HStack {
                            Text(row.label)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(PetPalTheme.inkPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.free)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(PetPalTheme.inkSecondary)
                                .frame(width: 78)
                            Text(row.pro)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Gold.deep)
                                .frame(width: 78)
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
        }
    }

    // MARK: 套餐选择

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(tr("选择套餐", "Choose a plan"))

            HStack(spacing: 10) {
                ForEach(Plan.allCases) { p in
                    planCard(p)
                }
            }
        }
    }

    private func planCard(_ p: Plan) -> some View {
        let selected = plan == p
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { plan = p }
        } label: {
            VStack(spacing: 6) {
                Text(planTitle(p))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Text(planPrice(p))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected ? AnyShapeStyle(Gold.gradient)
                                              : AnyShapeStyle(PetPalTheme.inkPrimary))
                Text(planUnit(p))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSecondary)
                Text(planNote(p))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(selected ? Gold.stroke : PetPalTheme.inkPrimary.opacity(0.08),
                                  lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .top) {
                if let badge = planBadge(p) {
                    Text(badge)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Gold.gradient))
                        .offset(y: -8)
                }
            }
            .shadow(color: Gold.deep.opacity(selected ? 0.22 : 0), radius: 10, y: 4)
            .scaleEffect(selected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: 底部固定 CTA

    private var ctaBar: some View {
        VStack(spacing: 8) {
            Button {
                showDemoNotice = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                    Text(plan == .lifetime
                         ? tr("一次买断 \(planPrice(plan))", "Buy once \(planPrice(plan))")
                         : tr("立即解锁 \(planPrice(plan))\(planUnit(plan))",
                              "Unlock \(planPrice(plan))\(planUnit(plan))"))
                }
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.24, green: 0.18, blue: 0.03))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Gold.gradient))
                .shadow(color: Gold.deep.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.plain)

            HStack(spacing: 14) {
                Button(tr("恢复购买", "Restore")) { showDemoNotice = true }
                Text("·")
                Button(tr("会员协议", "Terms")) { showDemoNotice = true }
                Text("·")
                Button(tr("隐私政策", "Privacy")) { showDemoNotice = true }
            }
            .font(.system(size: 11))
            .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.45))

        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: 小工具

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.75))
            .padding(.leading, 4)
    }
}

#Preview {
    NavigationStack {
        ProUnlockView()
    }
}

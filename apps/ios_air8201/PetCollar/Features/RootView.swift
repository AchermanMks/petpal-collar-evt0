import SwiftUI
import PhotosUI
import PetKit

/// 双入口：无真实宠物 → 电子宠物；已养宠 → 数字孪生
enum EntryMode: String {
    case virtual   // 电子宠物入口
    case twin      // 数字孪生入口
}

struct RootView: View {
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("hasOnboarded") private var hasOnboarded: Bool = false
    @AppStorage("entryMode") private var entryMode: String = ""
    @AppStorage("virtualBreed") private var virtualBreed: String = ""
    @AppStorage("twinReady") private var twinReady: Bool = false
    @AppStorage("petName") private var petName: String = "喵喵"
    @AppStorage("petAvatarData") private var petAvatarData: Data = Data()

    var body: some View {
        Group {
            if entryMode.isEmpty {
                EntryGateView { mode in
                    // 回到入口=对应流程重走，清掉可能残留的完成标记
                    if mode == .twin { twinReady = false } else { virtualBreed = "" }
                    entryMode = mode.rawValue
                }
                .transition(.opacity)
            } else if entryMode == EntryMode.virtual.rawValue && virtualBreed.isEmpty {
                // 电子宠物入口：偏好点选收敛，生成专属虚拟猫
                BreedMatchView { breed in
                    virtualBreed = breed.id
                    petName = breed.petName
                }
                .transition(.opacity)
            } else if entryMode == EntryMode.twin.rawValue && !twinReady {
                // 数字孪生入口：相册照片生成分身，日常称呼作默认名
                TwinSetupView { photo, name in
                    petAvatarData = photo
                    petName = name
                    twinReady = true
                }
                .transition(.opacity)
            } else if isLoggedIn {
                // 硬件配置向导只对数字孪生（有真宠）用户有意义。
                // 写成显式分支而非 fullScreenCover——cover 挂在条件分支上会在
                // 其它分支（登录页）渲染时也弹出，把整个路由盖死
                if entryMode == EntryMode.twin.rawValue && !hasOnboarded {
                    OnboardingView(onDone: { hasOnboarded = true })
                        .transition(.opacity)
                } else {
                    MainTabView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            } else {
                LoginView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isLoggedIn)
        .animation(.easeInOut(duration: 0.5), value: entryMode)
        .animation(.easeInOut(duration: 0.5), value: virtualBreed)
        .animation(.easeInOut(duration: 0.5), value: twinReady)
        .animation(.easeInOut(duration: 0.5), value: hasOnboarded)
    }
}

// MARK: - 首启开场：深色毛玻璃，骨骼真猫弹出，选择入口

struct EntryGateView: View {
    let onChoose: (EntryMode) -> Void

    @State private var catShown = false
    @State private var choicesShown = false
    @State private var bubble: String?
    @State private var petNonce = 0
    @State private var chosen = false

    var body: some View {
        ZStack {
            StarrySkyBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack(alignment: .top) {
                    RiggedCatSceneView(outfit: .none,
                                       petNonce: petNonce,
                                       onPart: { _ in react() })
                        .frame(height: 470)

                    if let bubble {
                        Text(bubble)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(PetPalTheme.inkPrimary)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(PetPalTheme.inkPrimary.opacity(0.12), lineWidth: 1)
                            )
                            .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                    }
                }
                .scaleEffect(catShown ? 1 : 0.01, anchor: .bottom)
                .opacity(catShown ? 1 : 0)

                VStack(spacing: 16) {
                    Text("你现在养猫了吗？")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkPrimary)

                    VStack(spacing: 10) {
                        choiceButton(
                            title: "还没有猫",
                            subtitle: "领养一只专属电子猫",
                            filled: true
                        ) { choose(.virtual, cheer: "以后请多关照喵！") }

                        choiceButton(
                            title: "已经有猫啦",
                            subtitle: "给它造一个数字分身",
                            filled: false
                        ) { choose(.twin, cheer: "带我去认识它喵！") }
                    }
                    .padding(.horizontal, 40)
                }
                .padding(.top, 4)
                .opacity(choicesShown ? 1 : 0)
                .offset(y: choicesShown ? 0 : 24)

                Spacer(minLength: 0)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.65), value: catShown)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: choicesShown)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: bubble)
        .task { await playOpening() }
    }

    /// 开场节奏：静场 → 猫弹出打招呼 → 问题与选项浮现
    private func playOpening() async {
        try? await Task.sleep(for: .seconds(0.6))
        catShown = true
        petNonce += 1
        bubble = "喵！"
        try? await Task.sleep(for: .seconds(1.6))
        guard !chosen else { return }
        bubble = nil
        choicesShown = true
    }

    private func react() {
        guard !chosen else { return }
        bubble = "呼噜呼噜～"
        petNonce += 1
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !chosen else { return }
            bubble = nil
        }
    }

    private func choose(_ mode: EntryMode, cheer: String) {
        guard !chosen else { return }
        chosen = true
        bubble = cheer
        petNonce += 1
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            onChoose(mode)
        }
    }

    private func choiceButton(title: String, subtitle: String,
                              filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(filled ? PetPalTheme.primary.opacity(0.2) : PetPalTheme.inkPrimary.opacity(0.08))
                    Image(systemName: filled ? "star.circle.fill" : "camera.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(filled ? PetPalTheme.primary : PetPalTheme.inkPrimary)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Text(subtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.65))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if filled {
                            Label("免费", systemImage: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(PetPalTheme.primary.opacity(0.15)))
                                .foregroundStyle(PetPalTheme.primary)
                            Label("专属", systemImage: "heart.fill")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(PetPalTheme.primary.opacity(0.15)))
                                .foregroundStyle(PetPalTheme.primary)
                        } else {
                            Label("拍照生成", systemImage: "photo.fill")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(PetPalTheme.inkPrimary.opacity(0.1)))
                                .foregroundStyle(PetPalTheme.inkPrimary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(PetPalTheme.inkPrimary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 猫品种库（电子宠物入口的偏好收敛数据）

struct VirtualBreed: Identifiable, Equatable {
    let id: String
    let name: String
    let blurb: String          // 一句话人设
    let tags: [String]
    let tint: Color            // 像素猫上色
    let glow: [Color]          // 卡片毛玻璃底下的辉光
    let petName: String        // 收敛后的默认名
    /// 特征向量：毛长 / 圆润 / 花纹 / 粘人 / 活泼，各 0~1
    let traits: [Double]

    /// 真实照片资产名（Assets.xcassets/breed_<id>，来源见 docs/breed_photo_credits.md）
    var photo: String { "breed_\(id)" }

    static func distance(_ a: VirtualBreed, _ b: VirtualBreed) -> Double {
        zip(a.traits, b.traits).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
    }

    /// 相似度 0~1：选了某只，相近的品种也跟着涨分——这就是收敛
    static func similarity(_ a: VirtualBreed, _ b: VirtualBreed) -> Double {
        1 - distance(a, b) / Double(5).squareRoot()
    }

    static let all: [VirtualBreed] = [
        VirtualBreed(id: "orange", name: "田园橘猫", blurb: "圆滚滚的干饭王，见人就蹭",
                     tags: ["贪吃", "亲人", "圆胖"],
                     tint: Color(red: 0.95, green: 0.58, blue: 0.20),
                     glow: [.orange, .yellow],
                     petName: "橘座", traits: [0.2, 0.7, 0.4, 0.9, 0.5]),
        VirtualBreed(id: "lihua", name: "狸花猫", blurb: "身手矫健的小猎手，又酷又飒",
                     tags: ["矫健", "独立", "虎斑"],
                     tint: Color(red: 0.62, green: 0.45, blue: 0.28),
                     glow: [Color(red: 0.55, green: 0.40, blue: 0.25), .green],
                     petName: "大狸", traits: [0.2, 0.4, 0.9, 0.3, 0.8]),
        VirtualBreed(id: "cow", name: "奶牛猫", blurb: "黑白配色戏精，精力无限",
                     tags: ["戏精", "活泼", "黑白"],
                     tint: Color(white: 0.92),
                     glow: [Color(white: 0.85), Color(white: 0.3)],
                     petName: "奶牛", traits: [0.1, 0.4, 0.7, 0.5, 0.9]),
        VirtualBreed(id: "sanhua", name: "三花猫", blurb: "三色小仙女，温柔又机灵",
                     tags: ["三色", "温柔", "机灵"],
                     tint: Color(red: 0.93, green: 0.55, blue: 0.35),
                     glow: [.orange, .pink, Color(white: 0.9)],
                     petName: "花花", traits: [0.3, 0.5, 0.9, 0.7, 0.6]),
        VirtualBreed(id: "blue", name: "英短蓝猫", blurb: "包子脸小绅士，稳重不闹腾",
                     tags: ["包子脸", "沉稳", "蓝灰"],
                     tint: Color(red: 0.55, green: 0.60, blue: 0.68),
                     glow: [Color(red: 0.45, green: 0.52, blue: 0.65), .indigo],
                     petName: "蓝豆", traits: [0.3, 1.0, 0.0, 0.6, 0.2]),
        VirtualBreed(id: "bluewhite", name: "英短蓝白", blurb: "自带小西装，圆润又亲人",
                     tags: ["蓝白", "圆润", "亲人"],
                     tint: Color(red: 0.68, green: 0.73, blue: 0.80),
                     glow: [Color(red: 0.55, green: 0.62, blue: 0.75), Color(white: 0.9)],
                     petName: "汤圆", traits: [0.3, 0.9, 0.3, 0.7, 0.3]),
        VirtualBreed(id: "golden", name: "金渐层", blurb: "自带土豪金光环的粘人精",
                     tags: ["金色", "粘人", "圆润"],
                     tint: Color(red: 0.90, green: 0.72, blue: 0.42),
                     glow: [.yellow, .orange],
                     petName: "富贵", traits: [0.5, 0.9, 0.3, 0.8, 0.4]),
        VirtualBreed(id: "amshort", name: "美短虎斑", blurb: "结实皮实小坦克，怎么玩都行",
                     tags: ["虎斑", "皮实", "活泼"],
                     tint: Color(red: 0.62, green: 0.64, blue: 0.68),
                     glow: [Color(white: 0.7), .gray],
                     petName: "虎虎", traits: [0.2, 0.6, 0.9, 0.5, 0.9]),
        VirtualBreed(id: "ragdoll", name: "布偶猫", blurb: "蓝眼睛小仙子，抱着就不想撒手",
                     tags: ["长毛", "仙气", "温顺"],
                     tint: Color(red: 0.88, green: 0.85, blue: 0.80),
                     glow: [Color(red: 0.85, green: 0.82, blue: 0.75), .blue],
                     petName: "布丁", traits: [1.0, 0.6, 0.5, 0.9, 0.3]),
        VirtualBreed(id: "siamese", name: "暹罗猫", blurb: "挖煤小话痨，走哪儿跟哪儿",
                     tags: ["话痨", "粘人", "重点色"],
                     tint: Color(red: 0.75, green: 0.62, blue: 0.50),
                     glow: [Color(red: 0.60, green: 0.45, blue: 0.32), Color(red: 0.30, green: 0.22, blue: 0.18)],
                     petName: "煤球", traits: [0.1, 0.2, 0.6, 0.9, 0.8]),
        VirtualBreed(id: "exotic", name: "加菲猫", blurb: "扁脸呆萌大王，最爱躺平",
                     tags: ["扁脸", "呆萌", "安静"],
                     tint: Color(red: 0.90, green: 0.60, blue: 0.35),
                     glow: [.orange, Color(red: 0.85, green: 0.75, blue: 0.60)],
                     petName: "菲菲", traits: [0.4, 1.0, 0.2, 0.6, 0.1]),
    ]
}

// MARK: - 偏好收敛流：Pinterest 式多轮点选 → 生成专属虚拟猫

struct BreedMatchView: View {
    let onDone: (VirtualBreed) -> Void

    static let totalRounds = 5

    @State private var scores: [String: Double] = [:]
    @State private var shownIDs: Set<String> = []
    @State private var round = 1
    @State private var pair: (VirtualBreed, VirtualBreed)?
    @State private var pickedID: String?
    @State private var result: VirtualBreed?

    var body: some View {
        ZStack {
            StarrySkyBackground()

            if let result {
                resultView(result)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                pickView
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: result)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pickedID)
        .onAppear { if pair == nil { advance() } }
    }

    // MARK: 多轮点选

    private var pickView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(1...Self.totalRounds, id: \.self) { i in
                    Capsule()
                        .fill(i <= round ? PetPalTheme.primary : PetPalTheme.inkPrimary.opacity(0.15))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 24)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Text("哪只更心动？")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Text("点你更喜欢的那只 · 喵会记住你的口味")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSecondary)
            }

            if let pair {
                VStack(spacing: 16) {
                    breedCard(pair.0)
                    Text("VS")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSecondary)
                    breedCard(pair.1)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .id(round)   // 换轮时整组转场
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }

            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: round)
    }

    private func breedCard(_ breed: VirtualBreed) -> some View {
        Button {
            pick(breed)
        } label: {
            HStack(spacing: 18) {
                Image(breed.photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(PetPalTheme.inkPrimary.opacity(0.15), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 7) {
                    Text(breed.name)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Text(breed.blurb)
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSecondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        ForEach(breed.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(PetPalTheme.inkSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(PetPalTheme.inkPrimary.opacity(0.1), in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background {
                let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
                ZStack {
                    shape.fill(LinearGradient(colors: breed.glow.map { $0.opacity(0.55) },
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(pickedID == breed.id ? PetPalTheme.primary : PetPalTheme.inkPrimary.opacity(0.1),
                                  lineWidth: pickedID == breed.id ? 2 : 1)
            )
            .scaleEffect(pickedID == breed.id ? 1.05 : 1)
        }
        .buttonStyle(.plain)
    }

    private func pick(_ breed: VirtualBreed) {
        guard pickedID == nil else { return }
        pickedID = breed.id
        // 收敛：相似度平方扩散（拉开梯度，防止特征居中的品种躺赢），直接点选再加权
        for b in VirtualBreed.all {
            let s = VirtualBreed.similarity(breed, b)
            scores[b.id, default: 0] += s * s
        }
        scores[breed.id, default: 0] += 0.6
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            pickedID = nil
            round += 1
            advance()
        }
    }

    /// 出下一对：当前得分最高的未出场品种 vs 和它反差最大的未出场品种。
    /// 高分测的是"确认口味"，反差测的是"探索边界"，几轮就能收敛。
    private func advance() {
        guard round <= Self.totalRounds else {
            let winner = VirtualBreed.all.max { scores[$0.id, default: 0] < scores[$1.id, default: 0] }
            result = winner ?? VirtualBreed.all[0]
            return
        }
        let unseen = VirtualBreed.all.filter { !shownIDs.contains($0.id) }
        guard unseen.count >= 2 else {
            round = Self.totalRounds + 1
            advance()
            return
        }
        let front = unseen.max { scores[$0.id, default: 0] < scores[$1.id, default: 0] }!
        let rival = unseen.filter { $0.id != front.id }
            .max { VirtualBreed.distance($0, front) < VirtualBreed.distance($1, front) }!
        shownIDs.insert(front.id)
        shownIDs.insert(rival.id)
        pair = (front, rival)
    }

    // MARK: 收敛结果

    private func resultView(_ breed: VirtualBreed) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text("找到啦！")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Text("按你的口味，这只和你最合拍")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSecondary)
            }

            VStack(spacing: 14) {
                Image(breed.photo)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(PetPalTheme.inkPrimary.opacity(0.15), lineWidth: 1)
                    )
                Text(breed.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Text(breed.blurb)
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSecondary)
                HStack(spacing: 8) {
                    ForEach(breed.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PetPalTheme.inkSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(PetPalTheme.inkPrimary.opacity(0.1), in: Capsule())
                    }
                }
            }
            .padding(.vertical, 30).padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background {
                let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
                ZStack {
                    shape.fill(LinearGradient(colors: breed.glow.map { $0.opacity(0.55) },
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(PetPalTheme.inkPrimary.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 32)

            Text("就叫它「\(breed.petName)」吧，回头可以在档案里改名")
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSecondary)

            VStack(spacing: 12) {
                Button {
                    onDone(breed)
                } label: {
                    Text("带它回家")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(PetPalTheme.primary))
                }
                .buttonStyle(.plain)

                Button {
                    scores = [:]
                    shownIDs = []
                    round = 1
                    pickedID = nil
                    result = nil
                    advance()
                } label: {
                    Text("重新挑选")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 48)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - 数字孪生流：相册照片 → AI 生成分身 → 日常称呼作默认名

struct TwinSetupView: View {
    /// (照片数据, 日常称呼)。照片同时充当全 app 头像（petAvatarData）
    let onDone: (Data, String) -> Void

    private enum Step { case photo, generating, naming }

    @State private var step: Step = .photo
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var stage = 0
    @State private var scanning = false
    @State private var catShown = false
    @State private var petNonce = 0
    @State private var nickname = ""
    @FocusState private var nameFocused: Bool

    // Demo：真实版本把照片交给局域网后端生成模型，App 端只演进度节奏
    private static let stages = ["识别毛色与花纹…", "重建三维形态…", "绑定骨骼与动作…", "唤醒它的小脾气…"]

    var body: some View {
        ZStack {
            StarrySkyBackground()

            switch step {
            case .photo:      photoStep.transition(.opacity)
            case .generating: generatingStep.transition(.opacity)
            case .naming:     namingStep.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: step)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: photoData)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: stage)
    }

    // MARK: 选照片

    private var photoStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text("先来一张它的照片")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Text("挑一张看得清正脸或全身的，AI 会照着它生成数字分身")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // 布局尺寸由底座 shape 决定，照片走 overlay——scaledToFill 的照片
            // 一旦参与布局会把宽度撑破屏幕（frame 不缩超宽子视图）
            PhotosPicker(selection: $photoItem, matching: .images) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if let data = photoData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundStyle(PetPalTheme.primary)
                                Text("从相册选择")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(PetPalTheme.inkSecondary)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: photoData == nil ? 1.5 : 1,
                                                             dash: photoData == nil ? [7, 6] : []))
                            .foregroundStyle(PetPalTheme.inkSecondary.opacity(photoData == nil ? 0.25 : 0.15))
                    )
            }
            .buttonStyle(.plain)
            .frame(height: 400)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }

            Text("点照片可以换一张")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSecondary)
                .padding(.top, 8)
                .opacity(photoData == nil ? 0 : 1)

            Spacer(minLength: 0)

            Button(action: startGeneration) {
                Text("生成数字分身")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(PetPalTheme.primary))
                    .opacity(photoData == nil ? 0.35 : 1)
            }
            .buttonStyle(.plain)
            .disabled(photoData == nil)
            .padding(.horizontal, 48)
            .padding(.bottom, 36)
        }
    }

    // MARK: 生成中（Demo 动画）

    private var generatingStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text("AI 正在认识它")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkPrimary)

            if let data = photoData, let img = UIImage(data: data) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    }
                    .overlay {
                        GeometryReader { geo in
                            LinearGradient(colors: [.clear, PetPalTheme.primary.opacity(0.85), .clear],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 90)
                                .offset(y: scanning ? geo.size.height - 45 : -45)
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(PetPalTheme.primary.opacity(0.6), lineWidth: 1.5)
                    )
                    .frame(height: 420)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                            scanning = true
                        }
                    }
            }

            HStack(spacing: 8) {
                ProgressView()
                    .tint(PetPalTheme.inkSecondary)
                    .controlSize(.small)
                Text(Self.stages[stage])
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSecondary)
                    .id(stage)
                    .transition(.push(from: .bottom).combined(with: .opacity))
            }
            .padding(.top, 22)

            Spacer(minLength: 0)
        }
    }

    private func startGeneration() {
        guard photoData != nil else { return }
        scanning = false
        stage = 0
        step = .generating
        Task {
            for i in Self.stages.indices {
                stage = i
                try? await Task.sleep(for: .seconds(1.2))
            }
            step = .naming
            try? await Task.sleep(for: .seconds(0.15))
            catShown = true
            petNonce += 1
            try? await Task.sleep(for: .seconds(0.5))
            nameFocused = true
        }
    }

    // MARK: 揭晓 + 称呼命名

    private var namingStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            RiggedCatSceneView(outfit: .none,
                               petNonce: petNonce,
                               onPart: { _ in petNonce += 1 })
                .frame(height: 470)
                .scaleEffect(catShown ? 1 : 0.01, anchor: .bottom)
                .opacity(catShown ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.65), value: catShown)

            VStack(spacing: 5) {
                Text("它的分身来啦！")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Text("平时你都怎么叫它？这就是分身的名字")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSecondary)
            }
            .padding(.top, 4)

            TextField("", text: $nickname,
                      prompt: Text("比如：咪咪、蛋黄、豆豆").foregroundStyle(PetPalTheme.inkSecondary))
                .focused($nameFocused)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkPrimary)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .onSubmit(confirmName)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(PetPalTheme.inkPrimary.opacity(nameFocused ? 0.3 : 0.12), lineWidth: 1)
                )
                .padding(.horizontal, 56)
                .padding(.top, 18)

            Button(action: confirmName) {
                Text("就这么叫")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(PetPalTheme.primary))
                    .opacity(trimmedName.isEmpty ? 0.35 : 1)
            }
            .buttonStyle(.plain)
            .disabled(trimmedName.isEmpty)
            .padding(.horizontal, 56)
            .padding(.top, 12)

            Text("回头可以在「我的」里改名和换头像")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSecondary)
                .padding(.top, 10)

            Spacer(minLength: 0)
        }
    }

    private var trimmedName: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func confirmName() {
        guard let photoData, !trimmedName.isEmpty else { return }
        nameFocused = false
        onDone(photoData, trimmedName)
    }
}

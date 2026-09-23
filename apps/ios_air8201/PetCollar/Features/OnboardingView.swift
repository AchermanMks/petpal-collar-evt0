import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void

    @AppStorage("lastBaseURL") private var lastBaseURL: String = ""
    @AppStorage("espHost") private var espHost: String = "esp32-led.local"

    @State private var step: Int = 0
    @State private var backendInput: String = ""
    @State private var espInput: String = ""
    @State private var backendCheck: CheckState = .idle
    @State private var espCheck: CheckState = .idle

    enum CheckState: Equatable {
        case idle, checking, ok, fail(String)
    }

    var body: some View {
        ZStack {
            StarrySkyBackground()

            VStack(spacing: 0) {
                // 顶部：进度条 + 跳过（并排，避免叠在一起）
                HStack(spacing: 14) {
                    progressBar
                    Button("跳过") { onDone() }
                        .buttonStyle(PetPalGhostButtonStyle())
                        .opacity(step < 3 ? 1 : 0)
                        .disabled(step >= 3)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                // 内容
                TabView(selection: $step) {
                    welcomeStep.tag(0)
                    backendStep.tag(1)
                    espStep.tag(2)
                    doneStep.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: step)

                // 底部
                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            let migrated = BackendEndpoint.migratedSavedURL(lastBaseURL)
            backendInput = migrated
            lastBaseURL = migrated
            espInput = espHost
        }
    }

    // MARK: - 顶部进度

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i <= step
                          ? AnyShapeStyle(PetPalTheme.brandGradient)
                          : AnyShapeStyle(PetPalTheme.inkPrimary.opacity(0.12)))
                    .frame(height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - 4 个 Step

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            PetPalLogo(size: 110)

            VStack(spacing: 8) {
                Text("宠宝 PetPel")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Text("智能项圈 · 实时陪伴 · 一生健康")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.65))
            }

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                featureBullet("location.fill", "GPS 定位 + 寻猫模式", PetPalTheme.success)
                featureBullet("heart.text.square.fill", "进食与活动量监测", PetPalTheme.primary)
                featureBullet("video.fill", "摄像头实时画面", .blue)
                featureBullet("person.2.fill", "猫圈社交 + 商城", .indigo)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 12)
        }
        .padding(.top, 20)
    }

    private var backendStep: some View {
        VStack(spacing: 18) {
            stepHeader(
                icon: "server.rack",
                title: "连接监控后端",
                desc: "项圈数据走后端服务器分析。请填入后端地址（局域网或 Tailscale）。"
            )

            PetPalCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("后端 URL")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PetPalTheme.inkSecondary)
                    TextField("http://192.168.x.x:5008", text: $backendInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .petPalField()

                    HStack {
                        Button("测试连接") { testBackend() }
                            .buttonStyle(PetPalGhostButtonStyle())
                            .disabled(backendInput.isEmpty || backendCheck == .checking)
                        Spacer()
                        checkBadge(backendCheck)
                    }
                }
            }
            .padding(.horizontal, 24)

            Text("提示：跳过测试也能下一步，回主页后可在「我的」改")
                .font(.caption2)
                .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.45))

            Spacer()
        }
        .padding(.top, 30)
    }

    private var espStep: some View {
        VStack(spacing: 18) {
            stepHeader(
                icon: "antenna.radiowaves.left.and.right",
                title: "找到你的项圈",
                desc: "项圈通电后会自动加入 Wi-Fi。默认 mDNS 主机名 esp32-led.local，模拟器下建议用 IP。"
            )

            PetPalCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("项圈地址")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PetPalTheme.inkSecondary)
                    TextField("esp32-led.local 或 192.168.x.x", text: $espInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .petPalField()

                    HStack {
                        Button("测试连接") { testESP() }
                            .buttonStyle(PetPalGhostButtonStyle())
                            .disabled(espInput.isEmpty || espCheck == .checking)
                        Spacer()
                        checkBadge(espCheck)
                    }
                }
            }
            .padding(.horizontal, 24)

            Text("提示：如果项圈刚通电，等 10 秒再测；hostname 漂移时直接填 IP")
                .font(.caption2)
                .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 30)
    }

    private var doneStep: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(PetPalTheme.success.opacity(0.18))
                    .frame(width: 150, height: 150)
                Circle()
                    .strokeBorder(PetPalTheme.success.opacity(0.35), lineWidth: 1)
                    .frame(width: 150, height: 150)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(PetPalTheme.success)
            }
            Text("准备就绪")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkPrimary)
            Text("接下来可以去「档案」给你的宠物起个名字\n或者直接进主页玩起来")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.65))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    // MARK: - 通用组件

    /// 卡片行：与入口页 choiceButton 同一套玻璃卡视觉
    private func featureBullet(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 40, height: 40)

            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(PetPalTheme.inkPrimary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stepHeader(icon: String, title: String, desc: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(PetPalTheme.primary.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(PetPalTheme.primary)
            }
            .frame(width: 72, height: 72)

            Text(title)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkPrimary)
            Text(desc)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }

    @ViewBuilder
    private func checkBadge(_ state: CheckState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .ok:
            Label("已连接", systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(PetPalTheme.success)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(PetPalTheme.success.opacity(0.12), in: Capsule())
        case .fail(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(PetPalTheme.danger)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(PetPalTheme.danger.opacity(0.12), in: Capsule())
        }
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Label("上一步", systemImage: "chevron.left")
                }
                .buttonStyle(PetPalGhostButtonStyle())
            }
            Button {
                if step < 3 {
                    if step == 1 { persistBackendInputIfValid() }
                    if step == 2, !espInput.isEmpty { espHost = espInput }
                    withAnimation { step += 1 }
                } else {
                    persistBackendInputIfValid()
                    if !espInput.isEmpty { espHost = espInput }
                    onDone()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(step < 3 ? "下一步" : "进入主页")
                    Image(systemName: step < 3 ? "chevron.right" : "arrow.right.circle.fill")
                }
            }
            .buttonStyle(PetPalPrimaryButtonStyle())
        }
    }

    // MARK: - 连接测试

    private func testBackend() {
        backendCheck = .checking
        let candidates: [URL]
        do {
            candidates = try BackendEndpoint.connectionCandidates(from: backendInput)
        } catch {
            backendCheck = .fail(error.localizedDescription)
            return
        }
        Task {
            var lastError: Error?
            for url in candidates {
                do {
                    let client = APIClient(baseURL: url)
                    _ = try await client.health()
                    _ = try await client.systemInfo()
                    await MainActor.run {
                        backendInput = url.absoluteString
                        lastBaseURL = url.absoluteString
                        backendCheck = .ok
                    }
                    return
                } catch {
                    lastError = error
                }
            }
            await MainActor.run {
                backendCheck = .fail("无法连接: \(lastError?.localizedDescription ?? "未知错误")")
            }
        }
    }

    private func persistBackendInputIfValid() {
        guard let url = try? BackendEndpoint.normalizedURL(from: backendInput) else { return }
        backendInput = url.absoluteString
        lastBaseURL = url.absoluteString
    }

    private func testESP() {
        espCheck = .checking
        guard let url = ESPClient.makeLEDBaseURL(from: espInput) else {
            espCheck = .fail("地址格式错")
            return
        }
        let client = ESPClient(baseURL: url)
        Task {
            do {
                _ = try await client.status()
                await MainActor.run { espCheck = .ok }
            } catch {
                await MainActor.run { espCheck = .fail("无法连接: \(error.localizedDescription)") }
            }
        }
    }
}

import SwiftUI

/// 电击控制（台面 demo 专用）
struct ArcControlView: View {
    @AppStorage("espHost") private var espHost: String = "esp32-led.local"
    @State private var hostInput: String = ""
    @State private var client: ESPClient?
    @State private var lastError: String?
    @State private var lastInfo: String?

    @State private var duration: Double = 200
    @State private var status: ESPClient.ArcStatus?
    @State private var pollTask: Task<Void, Never>?
    @State private var firePressing = false
    @State private var fireProgress: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    private let holdSeconds: Double = 0.4

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                warningBanner
                if client != nil {
                    statusCard
                    durationCard
                    fireCard
                    feedbackCard
                }
                hostCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("电击")
        .onAppear {
            if hostInput.isEmpty { hostInput = espHost }
            if client == nil && !hostInput.isEmpty { connect() }
        }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: - Warning Banner

    private var warningBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("高压注意")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text("3-5 kV · 远离皮肤/动物/电池")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.85, green: 0.18, blue: 0.18),
                                 Color(red: 0.95, green: 0.35, blue: 0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: Color.red.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    // MARK: - Host Card

    private var hostCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(client != nil ? PetPalTheme.success : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text("ESP32 设备")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PetPalTheme.inkSecondary)
                    Spacer()
                }
                HStack(spacing: 10) {
                    TextField("esp32-led.local 或 IP", text: $hostInput)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button(client == nil ? "连接" : "断开") {
                        client == nil ? connect() : disconnect()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(client == nil ? PetPalTheme.primary : .gray)
                    .disabled(hostInput.isEmpty)
                }
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .foregroundStyle(PetPalTheme.primary)
                    Text("状态")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                }

                HStack(spacing: 0) {
                    statusItem(
                        icon: "bolt.fill",
                        label: "状态",
                        value: status?.on == true ? "放电中" : "待机",
                        color: status?.on == true ? PetPalTheme.danger : PetPalTheme.success
                    )
                    Spacer()
                    statusItem(
                        icon: "number",
                        label: "累计",
                        value: "\(status?.count ?? 0) 次",
                        color: PetPalTheme.primary
                    )
                    Spacer()
                    statusItem(
                        icon: "timer",
                        label: "冷却",
                        value: cooldownText,
                        color: isCoolingDown ? PetPalTheme.warning : PetPalTheme.inkSecondary
                    )
                }

                if isCoolingDown, let s = status {
                    ProgressView(value: Double(s.cooldownMs - s.cooldownRemainMs),
                                 total: Double(s.cooldownMs))
                        .tint(PetPalTheme.warning)
                        .animation(.linear(duration: 0.25), value: s.cooldownRemainMs)
                }
            }
        }
    }

    private func statusItem(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(PetPalTheme.inkSecondary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(PetPalTheme.inkPrimary)
        }
    }

    private var cooldownText: String {
        guard let s = status, s.cooldownRemainMs > 0 else { return "就绪" }
        let sec = Double(s.cooldownRemainMs) / 1000.0
        return String(format: "%.1fs", sec)
    }

    private var isCoolingDown: Bool {
        (status?.cooldownRemainMs ?? 0) > 0
    }

    // MARK: - Duration Card

    private var durationCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(PetPalTheme.primary)
                    Text("放电时长")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Spacer()
                    Text("\(Int(duration)) ms")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(PetPalTheme.primaryDeep)
                }
                Slider(value: $duration, in: 100...800, step: 50)
                    .tint(PetPalTheme.danger)
                HStack {
                    Text("100ms")
                    Spacer()
                    Text("800ms (上限)")
                }
                .font(.caption2)
                .foregroundStyle(PetPalTheme.inkSecondary)
            }
        }
    }

    // MARK: - Fire Card

    private var fireCard: some View {
        VStack(spacing: 14) {
            // Main fire button
            ZStack {
                // Outer pulse ring
                Circle()
                    .stroke(PetPalTheme.danger.opacity(status?.on == true ? 0.4 : 0), lineWidth: 3)
                    .frame(width: 170, height: 170)
                    .scaleEffect(pulseScale)
                    .animation(
                        status?.on == true
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: status?.on
                    )
                    .onChange(of: status?.on) { _, newVal in
                        pulseScale = newVal == true ? 1.15 : 1.0
                    }

                // Background circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: fireDisabled
                                ? [Color.gray.opacity(0.3), Color.gray.opacity(0.15)]
                                : [Color(red: 0.95, green: 0.2, blue: 0.15),
                                   Color(red: 0.85, green: 0.1, blue: 0.1)],
                            center: .center,
                            startRadius: 5,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .shadow(color: fireDisabled ? .clear : PetPalTheme.danger.opacity(0.5),
                            radius: 20, x: 0, y: 8)

                // Progress ring
                if firePressing {
                    Circle()
                        .trim(from: 0, to: fireProgress)
                        .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 130, height: 130)
                        .rotationEffect(.degrees(-90))
                }

                // Icon + text
                VStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                    Text(fireButtonTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(height: 180)
            .gesture(longPressGesture)
            .disabled(fireDisabled)

            Text(firePressing ? "继续按住..." : "长按按钮 \(Int(holdSeconds * 1000))ms 触发电击")
                .font(.caption)
                .foregroundStyle(PetPalTheme.inkSecondary)

            // Emergency stop
            Button {
                Task { await stop() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                    Text("紧急停止")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PetPalTheme.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            }
            .padding(.horizontal, 40)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Feedback Card

    private var feedbackCard: some View {
        Group {
            if let lastError {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PetPalTheme.danger)
                    Text(lastError)
                        .font(.callout)
                        .foregroundStyle(PetPalTheme.danger)
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PetPalTheme.danger.opacity(0.08))
                )
            } else if let lastInfo {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PetPalTheme.success)
                    Text(lastInfo)
                        .font(.callout)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PetPalTheme.success.opacity(0.08))
                )
            }
        }
    }

    private var fireDisabled: Bool {
        guard let s = status else { return false }
        return s.on || s.cooldownRemainMs > 0
    }

    private var fireButtonTitle: String {
        if status?.on == true { return "放电中" }
        if isCoolingDown { return "冷却中" }
        return "电击"
    }

    // MARK: - Gestures & Actions

    private var longPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !firePressing && !fireDisabled {
                    firePressing = true
                    fireProgress = 0
                    startHoldAnimation()
                }
            }
            .onEnded { _ in
                let completed = fireProgress >= 1.0
                firePressing = false
                fireProgress = 0
                if completed { Task { await fire() } }
            }
    }

    private func startHoldAnimation() {
        let start = Date()
        Task { @MainActor in
            while firePressing && fireProgress < 1.0 {
                let elapsed = Date().timeIntervalSince(start)
                fireProgress = min(1.0, elapsed / holdSeconds)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func connect() {
        guard let url = ESPClient.makeLEDBaseURL(from: hostInput) else {
            lastError = "地址格式不合法"
            return
        }
        let normalized = url.host.map { host -> String in
            if let port = url.port { return "\(host):\(port)" }
            return host
        } ?? hostInput
        hostInput = normalized
        espHost = normalized
        client = ESPClient(baseURL: url)
        lastError = nil
        lastInfo = nil
        startPolling()
    }

    private func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        client = nil
        status = nil
        lastError = nil
        lastInfo = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let c = client else { break }
                do {
                    status = try await c.arcStatus()
                } catch {}
                let interval: Duration = isCoolingDown ? .milliseconds(250) : .seconds(1)
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func fire() async {
        guard let c = client else { return }
        lastError = nil
        do {
            let r = try await c.arcFire(duration: Int(duration))
            if r.ok {
                lastInfo = "已放电 \(r.duration ?? 0)ms（第 \(r.count ?? 0) 次）"
            } else if let err = r.err {
                if err == "cooldown" {
                    lastInfo = "冷却中，剩余 \(r.remainMs ?? 0)ms"
                } else if err == "busy" {
                    lastInfo = "正在放电，未受理"
                } else {
                    lastInfo = "未触发: \(err)"
                }
            }
            if let s = try? await c.arcStatus() { status = s }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stop() async {
        guard let c = client else { return }
        do {
            try await c.arcStop()
            lastInfo = "已紧急停止"
            if let s = try? await c.arcStatus() { status = s }
        } catch {
            lastError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { ArcControlView() }
}

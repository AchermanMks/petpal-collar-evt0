import SwiftUI

struct MotorControlView: View {
    @AppStorage("espHost") private var espHost: String = "esp32-led.local"
    @State private var hostInput: String = ""
    @State private var client: ESPClient?
    @State private var lastError: String?
    @State private var lastInfo: String?

    @State private var intensity: Double = 255
    @State private var duration: Double = 500
    @State private var isVibrating = false
    @State private var wavePhase: Double = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if client != nil {
                    vibeButton
                    controlCard
                    presetsCard
                    feedbackCard
                }
                hostCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("震动")
        .onAppear {
            if hostInput.isEmpty { hostInput = espHost }
            if client == nil && !hostInput.isEmpty { connect() }
        }
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

    // MARK: - Vibe Button

    private var vibeButton: some View {
        VStack(spacing: 14) {
            ZStack {
                // Outer ripple rings when vibrating
                if isVibrating {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(PetPalTheme.primary.opacity(0.15), lineWidth: 2)
                            .frame(width: 140 + CGFloat(i) * 30,
                                   height: 140 + CGFloat(i) * 30)
                            .scaleEffect(isVibrating ? 1.1 : 0.9)
                            .opacity(isVibrating ? 0.0 : 0.5)
                            .animation(
                                .easeOut(duration: 1.0)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.3),
                                value: isVibrating
                            )
                    }
                }

                // Main button
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isVibrating
                                ? [PetPalTheme.primary, PetPalTheme.primaryDeep]
                                : [PetPalTheme.primary.opacity(0.9), PetPalTheme.primaryDeep.opacity(0.85)],
                            center: .center,
                            startRadius: 5,
                            endRadius: 65
                        )
                    )
                    .frame(width: 130, height: 130)
                    .shadow(color: PetPalTheme.primary.opacity(isVibrating ? 0.5 : 0.3),
                            radius: isVibrating ? 24 : 16, x: 0, y: 8)
                    .scaleEffect(isVibrating ? 1.04 : 1.0)
                    .animation(
                        isVibrating
                            ? .easeInOut(duration: 0.08).repeatForever(autoreverses: true)
                            : .default,
                        value: isVibrating
                    )

                VStack(spacing: 6) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, isActive: isVibrating)
                    Text(isVibrating ? "震动中..." : "震动")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(height: 200)
            .onTapGesture {
                isVibrating ? stopMotor() : vibrate()
            }

            // Stop button
            Button {
                stopMotor()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                    Text("停止")
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
            .opacity(isVibrating ? 1 : 0.4)
            .disabled(!isVibrating)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Control Card

    private var controlCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(PetPalTheme.primary)
                    Text("参数调节")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                }

                // Intensity
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("强度")
                            .font(.subheadline)
                            .foregroundStyle(PetPalTheme.inkPrimary)
                        Spacer()
                        Text("\(Int(intensity))")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(PetPalTheme.primaryDeep)
                    }
                    Slider(value: $intensity, in: 50...255, step: 5)
                        .tint(PetPalTheme.primary)
                    HStack {
                        Text("50 (轻)")
                        Spacer()
                        Text("255 (最强)")
                    }
                    .font(.caption2)
                    .foregroundStyle(PetPalTheme.inkSecondary)
                }

                Divider()

                // Duration
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("时长")
                            .font(.subheadline)
                            .foregroundStyle(PetPalTheme.inkPrimary)
                        Spacer()
                        Text("\(Int(duration)) ms")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(PetPalTheme.primaryDeep)
                    }
                    Slider(value: $duration, in: 100...3000, step: 100)
                        .tint(PetPalTheme.primary)
                    HStack {
                        Text("100ms")
                        Spacer()
                        Text("3000ms")
                    }
                    .font(.caption2)
                    .foregroundStyle(PetPalTheme.inkSecondary)
                }
            }
        }
    }

    // MARK: - Presets Card

    private var presetsCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(PetPalTheme.primary)
                    Text("快捷模式")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    presetTile("轻触提醒", icon: "hand.tap", color: .teal,
                               intensity: 100, duration: 200)
                    presetTile("短震", icon: "bell.fill", color: .blue,
                               intensity: 200, duration: 500)
                    presetTile("强震警告", icon: "exclamationmark.triangle.fill", color: .orange,
                               intensity: 255, duration: 1000)
                    presetTile("长震呼唤", icon: "megaphone.fill", color: .purple,
                               intensity: 180, duration: 2000)
                }
            }
        }
    }

    private func presetTile(_ title: String, icon: String, color: Color,
                            intensity val: Int, duration dur: Int) -> some View {
        Button {
            intensity = Double(val)
            duration = Double(dur)
            vibrate()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Text("\(val) / \(dur)ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(PetPalTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isVibrating)
        .opacity(isVibrating ? 0.5 : 1)
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

    // MARK: - Actions

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
    }

    private func disconnect() {
        client = nil
        lastError = nil
        lastInfo = nil
    }

    private func vibrate() {
        guard let c = client else { return }
        isVibrating = true
        lastError = nil
        Task {
            do {
                try await c.motorVibrate(intensity: Int(intensity), duration: Int(duration))
                lastInfo = "已震动 \(Int(duration))ms（强度 \(Int(intensity))）"
                try await Task.sleep(for: .milliseconds(Int(duration)))
            } catch {
                lastError = error.localizedDescription
            }
            isVibrating = false
        }
    }

    private func stopMotor() {
        guard let c = client else { return }
        Task {
            do {
                try await c.motorStop()
                isVibrating = false
                lastInfo = "已停止"
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack { MotorControlView() }
}

import SwiftUI
import UIKit

struct LightControlView: View {
    @AppStorage("espHost") private var espHost: String = "esp32-led.local"
    @State private var hostInput: String = ""
    @State private var client: ESPClient?
    @State private var lastError: String?
    @State private var lastOK: String?
    @State private var color: Color = .white
    @State private var r: Double = 64
    @State private var g: Double = 64
    @State private var b: Double = 64
    @State private var pendingRGB: (Int, Int, Int)?
    @State private var streamTask: Task<Void, Never>?
    @State private var isOn: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if client != nil {
                    previewBulb
                    quickActions
                    rgbCard
                    presetsCard
                    feedbackCard
                }
                hostCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("灯光")
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

    // MARK: - Preview Bulb

    private var currentColor: Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    private var previewBulb: some View {
        VStack(spacing: 12) {
            ZStack {
                // Glow effect
                Circle()
                    .fill(currentColor.opacity(isOn ? 0.3 : 0))
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)

                // Main bulb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isOn
                                ? [currentColor.opacity(0.9), currentColor]
                                : [Color.gray.opacity(0.2), Color.gray.opacity(0.15)],
                            center: .center,
                            startRadius: 5,
                            endRadius: 55
                        )
                    )
                    .frame(width: 110, height: 110)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: isOn ? currentColor.opacity(0.5) : .clear,
                            radius: 20, x: 0, y: 8)

                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(isOn ? .white : .gray.opacity(0.5))
            }
            .frame(height: 170)

            Text("RGB(\(Int(r)), \(Int(g)), \(Int(b)))")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(PetPalTheme.inkSecondary)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(.ultraThinMaterial))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickButton("开灯", icon: "power", color: PetPalTheme.success) {
                isOn = true
                send { try await self.client?.setOn() }
            }
            quickButton("关灯", icon: "power", color: .gray) {
                isOn = false
                r = 0; g = 0; b = 0
                send { try await self.client?.setOff() }
            }
            quickButton("呼吸", icon: "wind", color: PetPalTheme.primaryDeep) {
                isOn = true
                send { try await self.client?.setBreathe() }
            }
            quickButton("满亮", icon: "sun.max.fill", color: PetPalTheme.warning) {
                isOn = true
                r = 255; g = 255; b = 255
                applyRGBNow()
            }
        }
    }

    private func quickButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - RGB Card

    private var rgbCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(PetPalTheme.primary)
                    Text("颜色调节")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Spacer()
                    ColorPicker("", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: color) { _, new in
                            syncColorToSliders(new)
                            streamApply()
                        }
                }

                rgbSlider(label: "R", value: $r, sliderColor: .red)
                rgbSlider(label: "G", value: $g, sliderColor: .green)
                rgbSlider(label: "B", value: $b, sliderColor: .blue)
            }
        }
        .onChange(of: r) { _, _ in isOn = true; streamApply() }
        .onChange(of: g) { _, _ in isOn = true; streamApply() }
        .onChange(of: b) { _, _ in isOn = true; streamApply() }
    }

    private func rgbSlider(label: String, value: Binding<Double>, sliderColor: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(sliderColor)
                .frame(width: 18)
            Slider(value: value, in: 0...255, step: 1)
                .tint(sliderColor)
            Text("\(Int(value.wrappedValue))")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(PetPalTheme.inkSecondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Presets Card

    private var presetsCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(PetPalTheme.primary)
                    Text("预设颜色")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                }

                let presets: [(String, Int, Int, Int)] = [
                    ("红", 255, 0, 0), ("绿", 0, 255, 0), ("蓝", 0, 0, 255),
                    ("黄", 255, 255, 0), ("青", 0, 255, 255), ("紫", 255, 0, 255),
                ]

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(presets, id: \.0) { item in
                        let c = Color(red: Double(item.1) / 255, green: Double(item.2) / 255, blue: Double(item.3) / 255)
                        Button {
                            isOn = true
                            r = Double(item.1); g = Double(item.2); b = Double(item.3)
                            applyRGBNow()
                        } label: {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(c)
                                    .frame(width: 36, height: 36)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .shadow(color: c.opacity(0.4), radius: 6, x: 0, y: 3)
                                Text(item.0)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PetPalTheme.inkPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(c.opacity(0.2), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
            } else if let lastOK {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PetPalTheme.success)
                    Text(lastOK)
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
        lastOK = "已就绪"
    }

    private func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        pendingRGB = nil
        client = nil
        lastError = nil
        lastOK = nil
    }

    private func syncColorToSliders(_ c: Color) {
        let ui = UIColor(c)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        r = Double(Int((rr * 255).rounded()))
        g = Double(Int((gg * 255).rounded()))
        b = Double(Int((bb * 255).rounded()))
    }

    private func streamApply() {
        pendingRGB = (Int(r), Int(g), Int(b))
        if streamTask != nil { return }
        guard let c = client else { return }
        streamTask = Task { @MainActor in
            defer { streamTask = nil }
            while let target = pendingRGB {
                pendingRGB = nil
                guard !Task.isCancelled else { return }
                do {
                    try await c.setRGB(r: target.0, g: target.1, b: target.2)
                    if lastError != nil { lastError = nil }
                } catch {
                    lastError = humanMessage(error)
                    return
                }
            }
        }
    }

    private func applyRGBNow() {
        streamApply()
    }

    private func send(_ op: @escaping @Sendable () async throws -> Void) {
        Task {
            do {
                try await op()
                self.lastError = nil
            } catch {
                self.lastError = humanMessage(error)
            }
        }
    }

    private func humanMessage(_ error: Error) -> String {
        if case ESPClientError.httpStatus(404) = error {
            return "404：地址里没有 /led 端点（可能填的是 :81，应填 :80 或裸 IP）"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost: return "无法连接到 ESP"
            case .timedOut: return "连接超时"
            case .cannotFindHost: return "找不到主机"
            case .notConnectedToInternet: return "网络未连接"
            case .networkConnectionLost: return "网络连接中断"
            default: return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

#Preview {
    NavigationStack { LightControlView() }
}

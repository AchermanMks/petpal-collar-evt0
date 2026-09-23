import SwiftUI

struct CameraStreamView: View {
    @AppStorage("espStreamHost") private var espStreamHost: String = "esp32-led.local:81"
    @AppStorage("espStreamPath") private var streamPath: String = "/stream"
    @State private var hostInput: String = ""
    @State private var pathInput: String = ""
    @State private var showConfig: Bool = false

    private var stream: MJPEGStream { MJPEGStream.espCamera }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            if let img = stream.currentFrame {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholderView
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if showConfig {
                    configPanel
                } else {
                    bottomBar
                }
            }
        }
        .navigationTitle("实况")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if hostInput.isEmpty { hostInput = espStreamHost }
            if pathInput.isEmpty { pathInput = streamPath }
            if !stream.isRunning && !hostInput.isEmpty {
                connect()
            }
        }
    }

    // MARK: - Placeholder

    @ViewBuilder
    private var placeholderView: some View {
        if stream.streamServerDown {
            deviceRestartHint
        } else {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.06))
                        .frame(width: 100, height: 100)
                    if stream.isRunning && stream.currentFrame == nil {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white.opacity(0.5))
                    } else {
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                Text(!stream.isRunning ? "未配置流地址" : (stream.lastError ?? "正在连接..."))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                if let url = stream.currentURL {
                    Text(url.absoluteString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
    }

    private var deviceRestartHint: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
            }
            Text("流服务无响应")
                .font(.headline)
                .foregroundStyle(.white)
            Text("LED 端口在线，但 :81 流服务器无响应\n请按 RST 键或断电重启 ESP32")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Text("重启后自动恢复")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 30)
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBar: some View {
        if stream.isRunning {
            HStack(spacing: 10) {
                // Live indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                // Stats
                HStack(spacing: 4) {
                    Image(systemName: "photo.stack")
                        .font(.caption2)
                    Text("\(stream.framesReceived)")
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption2)
                    Text(formatBytes(stream.bytesReceived))
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.5), in: Capsule())
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var statusColor: Color {
        if stream.currentFrame != nil { return .green }
        if stream.isReconnecting { return .orange }
        return .red
    }

    private var statusText: String {
        if stream.currentFrame != nil { return "LIVE" }
        if stream.isReconnecting { return "重连中" }
        return "等待"
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Connect/Disconnect
            Button {
                stream.isRunning ? disconnect() : connect()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: stream.isRunning ? "stop.fill" : "play.fill")
                    Text(stream.isRunning ? "停止" : "开启")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(
                    Capsule().fill(stream.isRunning ? Color.red.opacity(0.7) : Color.green.opacity(0.7))
                )
            }

            Spacer()

            // Config gear
            Button {
                showConfig = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(10)
                    .background(.ultraThinMaterial.opacity(0.4), in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Config Panel

    private var configPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("流配置")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    showConfig = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("主机")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("esp32-led.local:81", text: $hostInput)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("路径")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("/stream", text: $pathInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .frame(maxWidth: 100)
                }
            }

            HStack(spacing: 12) {
                Button {
                    connect()
                    showConfig = false
                } label: {
                    Text("连接")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.green.opacity(0.7))
                        )
                }
                .disabled(hostInput.isEmpty)

                Button {
                    disconnect()
                    showConfig = false
                } label: {
                    Text("断开")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Actions

    private func connect() {
        guard let base = ESPClient.makeBaseURL(from: hostInput) else { return }
        var path = pathInput.trimmingCharacters(in: .whitespaces)
        if path.isEmpty { path = "/stream" }
        if !path.hasPrefix("/") { path = "/" + path }
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else { return }
        espStreamHost = hostInput
        streamPath = path
        stream.ensureRunning(url: url)
    }

    private func disconnect() {
        stream.stop()
    }

    private func formatBytes(_ n: Int) -> String {
        let mb = Double(n) / (1024 * 1024)
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        let kb = Double(n) / 1024
        return String(format: "%.0f KB", kb)
    }
}

#Preview {
    NavigationStack { CameraStreamView() }
}

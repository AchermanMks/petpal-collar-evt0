import SwiftUI

struct SpeakerControlView: View {
    @AppStorage("espHost") private var espHost: String = "esp32-led.local"
    @State private var hostInput: String = ""
    @State private var client: ESPClient?
    @State private var lastError: String?
    @State private var lastOK: String?

    @State private var freq: Double = 1000
    @State private var duration: Double = 2000
    @State private var volume: Double = 80
    @State private var isPlaying = false

    @State private var audioFiles: [ESPClient.SpeakerFile] = []
    @State private var storageTotal: Int = 0
    @State private var storageUsed: Int = 0
    @State private var isLoadingFiles = false

    @State private var musicExpanded = false
    @State private var controlExpanded = false
    @State private var espExpanded = false
    @State private var isUploadingRadar = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if client != nil {
                    volumeCard
                    presetsCard
                    musicFilesCard
                    controlCard
                    feedbackCard
                }
                hostCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("扬声器")
        .onAppear {
            if hostInput.isEmpty { hostInput = espHost }
            if client == nil && !hostInput.isEmpty { connect() }
        }
    }

    // MARK: - Host Card

    private var hostCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        espExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(client != nil ? PetPalTheme.success : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text("ESP32 设备")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkSecondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkSecondary)
                            .rotationEffect(.degrees(espExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if espExpanded {
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
    }

    // MARK: - Volume Card

    private var volumeCard: some View {
        PetPalCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(PetPalTheme.success.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: volumeIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(PetPalTheme.success)
                }
                Slider(value: $volume, in: 0...100, step: 5)
                    .tint(PetPalTheme.success)
                Text("\(Int(volume))%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(PetPalTheme.primaryDeep)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private var volumeIcon: String {
        if volume == 0 { return "speaker.slash.fill" }
        if volume < 33 { return "speaker.fill" }
        if volume < 66 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    // MARK: - Presets Card

    private var presetsCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.purple)
                    Text("快捷音效")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                }

                // Meow button (featured)
                Button {
                    playMeow()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.pink.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "cat.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.pink)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("猫叫")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(PetPalTheme.inkPrimary)
                            Text("合成喵叫声")
                                .font(.caption2)
                                .foregroundStyle(PetPalTheme.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.pink)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.pink.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                // Preset grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    soundPreset("提示音", icon: "bell.fill", color: .blue, freq: 880, dur: 300, vol: 60)
                    soundPreset("警报", icon: "exclamationmark.triangle.fill", color: .red, freq: 2000, dur: 3000, vol: 100)
                    soundPreset("低沉", icon: "speaker.zzz.fill", color: .brown, freq: 200, dur: 1000, vol: 70)
                    soundPreset("高音", icon: "bolt.fill", color: .orange, freq: 3000, dur: 500, vol: 50)
                    soundPreset("叮咚", icon: "bell.badge.fill", color: .teal, freq: 1200, dur: 200, vol: 80)
                    soundPreset("嘟嘟", icon: "horn.fill", color: .purple, freq: 600, dur: 1500, vol: 60)
                }

                // Stop + Test
                HStack(spacing: 12) {
                    Button {
                        stopBeep()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("停止")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PetPalTheme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        send { try await client?.speakerTest() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.wave.3.fill")
                            Text("测试")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.blue.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func soundPreset(_ title: String, icon: String, color: Color,
                             freq f: Int, dur: Int, vol: Int) -> some View {
        Button {
            freq = Double(f); duration = Double(dur); volume = Double(vol)
            playBeep()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPlaying)
        .opacity(isPlaying ? 0.5 : 1)
    }

    // MARK: - Music Files Card

    private var musicFilesCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 12) {
                collapsibleHeader(
                    "音乐文件", icon: "music.note.list", color: .blue,
                    expanded: $musicExpanded,
                    badge: audioFiles.isEmpty ? nil : "\(audioFiles.count)"
                )

                if musicExpanded {
                    if storageTotal > 0 {
                        let usedMB = Double(storageUsed) / 1_048_576
                        let totalMB = Double(storageTotal) / 1_048_576
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: Double(storageUsed), total: Double(storageTotal))
                                .tint(.blue)
                            Text(String(format: "%.1f / %.1f MB", usedMB, totalMB))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(PetPalTheme.inkSecondary)
                        }
                    }

                    if audioFiles.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "music.note")
                                    .font(.title2)
                                    .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.4))
                                Text("暂无音频文件")
                                    .font(.caption)
                                    .foregroundStyle(PetPalTheme.inkSecondary)
                            }
                            .padding(.vertical, 12)
                            Spacer()
                        }
                    } else {
                        ForEach(audioFiles, id: \.name) { file in
                            audioFileRow(file)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            uploadRadar()
                        } label: {
                            HStack(spacing: 6) {
                                if isUploadingRadar {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: "alarm.fill")
                                }
                                Text("添加雷达音效")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                        }
                        .disabled(isUploadingRadar)

                        Spacer()

                        Button {
                            loadFiles()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("刷新")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.blue)
                        }
                        .disabled(isLoadingFiles)
                    }
                }
            }
        }
    }

    private func audioFileRow(_ file: ESPClient.SpeakerFile) -> some View {
        let displayName = file.name.replacingOccurrences(of: ".pcm", with: "")
        let sizeKB = Double(file.bytes) / 1024
        let durationSec = Double(file.bytes) / (16000 * 2)
        return HStack(spacing: 12) {
            Button {
                playFile(displayName)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkPrimary)
                        Text(String(format: "%.1fs · %.0f KB", durationSec, sizeKB))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(PetPalTheme.inkSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                deleteFile(displayName)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(PetPalTheme.danger.opacity(0.6))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Control Card

    private var controlCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 14) {
                collapsibleHeader("音调控制", icon: "slider.horizontal.3", color: .orange, expanded: $controlExpanded)

                if controlExpanded {
                    paramSlider(label: "频率", value: $freq, range: 100...4000, step: 50,
                                unit: "Hz", color: .orange)
                    paramSlider(label: "时长", value: $duration, range: 100...5000, step: 100,
                                unit: "ms", color: .blue)
                    paramSlider(label: "音量", value: $volume, range: 0...100, step: 5,
                                unit: "%", color: PetPalTheme.success)

                    HStack(spacing: 12) {
                        Button {
                            playBeep()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("播放")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(colors: [.orange, PetPalTheme.primaryDeep],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isPlaying)
                        .opacity(isPlaying ? 0.6 : 1)

                        Button {
                            stopBeep()
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
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func paramSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>,
                             step: Double, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(PetPalTheme.primaryDeep)
            }
            Slider(value: value, in: range, step: step)
                .tint(color)
        }
    }

    // MARK: - Collapsible Header

    private func collapsibleHeader(_ title: String, icon: String, color: Color,
                                   expanded: Binding<Bool>, badge: String? = nil) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                expanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PetPalTheme.inkPrimary)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkSecondary)
                    .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
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
        loadFiles()
    }

    private func disconnect() {
        client = nil
        lastError = nil
        lastOK = nil
        isPlaying = false
        audioFiles = []
    }

    private func loadFiles() {
        guard let c = client else { return }
        isLoadingFiles = true
        Task {
            do {
                let resp = try await c.speakerFiles()
                audioFiles = resp.files
                storageTotal = resp.total
                storageUsed = resp.used
            } catch {
                lastError = humanMessage(error)
            }
            isLoadingFiles = false
        }
    }

    private func playFile(_ name: String) {
        guard let c = client else { return }
        let v = Int(volume)
        Task {
            do {
                try await c.speakerPlayFile(name: name, volume: v)
                lastError = nil
                lastOK = "播放 \(name)"
            } catch {
                lastError = humanMessage(error)
            }
        }
    }

    private func deleteFile(_ name: String) {
        guard let c = client else { return }
        Task {
            do {
                try await c.speakerDeleteFile(name: name)
                lastError = nil
                lastOK = "已删除 \(name)"
                loadFiles()
            } catch {
                lastError = humanMessage(error)
            }
        }
    }

    private func playMeow() {
        guard let c = client else { return }
        let v = Int(volume)
        Task {
            do {
                try await c.speakerMeow(volume: v)
                lastError = nil
                lastOK = "喵~"
            } catch {
                lastError = humanMessage(error)
            }
        }
    }

    private func playBeep() {
        guard let c = client else { return }
        isPlaying = true
        let f = Int(freq), d = Int(duration), v = Int(volume)
        Task {
            do {
                try await c.speakerBeep(freq: f, duration: d, volume: v)
                lastError = nil
                lastOK = "播放 \(f)Hz / \(d)ms / \(v)%"
                try? await Task.sleep(for: .milliseconds(d))
            } catch {
                lastError = humanMessage(error)
            }
            isPlaying = false
        }
    }

    private func stopBeep() {
        send { try await client?.speakerStop() }
        isPlaying = false
    }

    private func send(_ op: @escaping @Sendable () async throws -> Void) {
        Task {
            do {
                try await op()
                lastError = nil
            } catch {
                lastError = humanMessage(error)
            }
        }
    }

    // MARK: - Radar Sound Generator

    /// Generate Apple-style "Radar" alarm PCM: raw 16-bit signed LE mono @ 16kHz
    /// Pattern: 3 quick beeps (~1175Hz, 80ms each, 60ms gap) then 400ms silence, repeat 4x
    private func generateRadarPCM() -> Data {
        let sampleRate = 16000
        let freq: Float = 1175.0  // Radar tone frequency
        let beepSamples = Int(0.08 * Float(sampleRate))  // 80ms
        let gapSamples = Int(0.06 * Float(sampleRate))   // 60ms
        let pauseSamples = Int(0.40 * Float(sampleRate))  // 400ms
        let repeats = 4
        let amplitude: Float = 28000

        var samples: [Int16] = []

        for _ in 0..<repeats {
            // 3 beeps
            for beep in 0..<3 {
                for i in 0..<beepSamples {
                    let t = Float(i) / Float(sampleRate)
                    // Envelope: short fade in/out to avoid click
                    let fadeLen = min(80, beepSamples / 8)
                    var env: Float = 1.0
                    if i < fadeLen { env = Float(i) / Float(fadeLen) }
                    if i > beepSamples - fadeLen { env = Float(beepSamples - i) / Float(fadeLen) }
                    let s = Int16(amplitude * env * sinf(2.0 * .pi * freq * t))
                    samples.append(s)
                }
                // Gap between beeps (not after last beep in group)
                if beep < 2 {
                    samples.append(contentsOf: [Int16](repeating: 0, count: gapSamples))
                }
            }
            // Pause between groups
            samples.append(contentsOf: [Int16](repeating: 0, count: pauseSamples))
        }

        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func uploadRadar() {
        guard let c = client else { return }
        isUploadingRadar = true
        Task {
            do {
                let pcm = generateRadarPCM()
                try await c.speakerUpload(name: "radar", pcmData: pcm)
                lastError = nil
                lastOK = "已上传雷达音效"
                loadFiles()
            } catch {
                lastError = humanMessage(error)
            }
            isUploadingRadar = false
        }
    }

    private func humanMessage(_ error: Error) -> String {
        if case ESPClientError.httpStatus(404) = error {
            return "404：固件不支持该端点"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost: return "无法连接到 ESP"
            case .timedOut: return "连接超时"
            case .cannotFindHost: return "找不到主机"
            default: return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

#Preview {
    NavigationStack { SpeakerControlView() }
}

import SwiftUI
import os.log

private let dbg = Logger(subsystem: "PetCollar", category: "Training")

// MARK: - 数据模型

enum TrainingSound: Codable, Equatable, Hashable {
    case none
    case meow
    case beep
    case file(String)

    var label: String {
        switch self {
        case .none:        return "不响"
        case .meow:        return "猫叫"
        case .beep:        return "蜂鸣"
        case .file(let n): return n
        }
    }

    var icon: String {
        switch self {
        case .none:    return "speaker.slash"
        case .meow:    return "cat.fill"
        case .beep:    return "waveform"
        case .file:    return "music.note"
        }
    }
}

struct TrainingRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var icon: String              // SF Symbol
    var ledRed: Int = 0           // 0–255，0,0,0 视为关灯
    var ledGreen: Int = 0
    var ledBlue: Int = 0
    var sound: TrainingSound = .none
    var vibrationMs: Int = 0      // 0 = 不振
    var note: String = ""

    var hasLED: Bool { ledRed + ledGreen + ledBlue > 0 }
    var ledColor: Color { Color(red: Double(ledRed)/255, green: Double(ledGreen)/255, blue: Double(ledBlue)/255) }

    var summary: String {
        var parts: [String] = []
        if hasLED { parts.append(ledHexLabel) }
        parts.append(sound.label)
        if vibrationMs > 0 { parts.append("振 \(vibrationMs)ms") }
        return parts.joined(separator: " · ")
    }

    private var ledHexLabel: String {
        // 常见颜色给名字，其他用 hex
        let palette: [(Int, Int, Int, String)] = [
            (255, 0, 0, "红灯"), (0, 255, 0, "绿灯"), (0, 0, 255, "蓝灯"),
            (255, 255, 0, "黄灯"), (255, 0, 255, "紫灯"), (0, 255, 255, "青灯"),
            (255, 255, 255, "白灯"),
        ]
        for (r, g, b, name) in palette where r == ledRed && g == ledGreen && b == ledBlue {
            return name
        }
        return String(format: "#%02X%02X%02X", ledRed, ledGreen, ledBlue)
    }
}

// MARK: - Catalog（预置规则）

enum TrainingCatalog {
    static let preset: [TrainingRule] = [
        TrainingRule(name: "上桌警告", icon: "exclamationmark.triangle.fill",
                     ledRed: 255, ledGreen: 255, ledBlue: 0,
                     sound: .meow, vibrationMs: 500,
                     note: "猫跳上桌时触发，提醒它下来"),
        TrainingRule(name: "欢迎回家", icon: "house.fill",
                     ledRed: 0, ledGreen: 255, ledBlue: 0,
                     sound: .meow, vibrationMs: 0,
                     note: "你回家时跟它打招呼，让它知道你来了"),
        TrainingRule(name: "吃饭提醒", icon: "fork.knife",
                     ledRed: 0, ledGreen: 0, ledBlue: 255,
                     sound: .beep, vibrationMs: 200,
                     note: "到点喂饭，叫它来食盆旁"),
        TrainingRule(name: "静音召回", icon: "moon.fill",
                     ledRed: 0, ledGreen: 0, ledBlue: 0,
                     sound: .none, vibrationMs: 1000,
                     note: "深夜不打扰别人，只用振动召回"),
        TrainingRule(name: "紧急寻找", icon: "bell.badge.fill",
                     ledRed: 255, ledGreen: 0, ledBlue: 0,
                     sound: .meow, vibrationMs: 1500,
                     note: "找不到它时，全开 LED + 声音 + 振动一起来"),
    ]
}

// MARK: - 主视图

struct TrainingView: View {
    var searchText: String = ""
    @AppStorage("trainingRulesJson") private var rulesJson: String = ""
    @AppStorage("espHost") private var espHost: String = "esp32-led.local"

    @State private var rules: [TrainingRule] = []
    @State private var hostInput: String = ""
    @State private var client: ESPClient?
    @State private var connecting: Bool = false
    @State private var lastError: String?
    @State private var editingRule: TrainingRule?
    @State private var lastTestedAt: [UUID: Date] = [:]

    /// 搜索过滤：规则名 / 备注
    private var filteredRules: [TrainingRule] {
        guard !searchText.isEmpty else { return rules }
        return rules.filter { r in
            r.name.lowercased().contains(searchText)
                || r.note.lowercased().contains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                hintCard
                ForEach(filteredRules) { rule in
                    ruleCard(rule)
                }
                addButton
                if let lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding()
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                hostCard
            }
            .padding()
        }
        .navigationTitle("训猫与看管")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .sheet(item: $editingRule) { rule in
            RuleEditor(rule: rule, onSave: { updated in
                if let i = rules.firstIndex(where: { $0.id == updated.id }) {
                    rules[i] = updated
                } else {
                    rules.append(updated)
                }
                save()
                editingRule = nil
            }, onCancel: { editingRule = nil })
        }
    }

    // MARK: - Cards

    private var hostCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(client != nil ? .green : .gray).frame(width: 8, height: 8)
                Text("项圈连接").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if connecting { ProgressView().controlSize(.small) }
            }
            HStack {
                TextField("esp32-led.local 或 IP", text: $hostInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button(client == nil ? "连接" : "断开") {
                    client == nil ? connect() : disconnect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(hostInput.isEmpty)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// 顶部 hero：猫爪搭人手实拍，点题「握手训练」
    private var heroCard: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.orange.opacity(0.1))
            .aspectRatio(2.2, contentMode: .fit)
            .overlay {
                Image("training_hero")
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.55), .clear],
                               startPoint: .bottom, endPoint: .center)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("科学训猫")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("灯光 · 声音 · 振动，让项圈帮你立规矩")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var hintCard: some View {
        HStack {
            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
            Text("点「测试」按钮 = 项圈真的会响 / 闪 / 振，请先连接项圈")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func ruleCard(_ rule: TrainingRule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: rule.icon)
                    .font(.title2)
                    .foregroundStyle(rule.hasLED ? rule.ledColor : .secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        (rule.hasLED ? rule.ledColor : .secondary).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name).font(.headline)
                    Text(rule.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button {
                        editingRule = rule
                    } label: { Label("编辑", systemImage: "pencil") }
                    Button(role: .destructive) {
                        rules.removeAll { $0.id == rule.id }
                        save()
                    } label: { Label("删除", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }
            if !rule.note.isEmpty {
                Text(rule.note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 56)
            }
            HStack {
                Spacer()
                if let last = lastTestedAt[rule.id], Date.now.timeIntervalSince(last) < 30 {
                    Text("已触发 \(Int(Date.now.timeIntervalSince(last))) 秒前")
                        .font(.caption2).foregroundStyle(.green)
                }
                Button {
                    test(rule)
                } label: {
                    Label("测试", systemImage: "play.fill")
                        .font(.callout.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(client != nil ? Color.accentColor : Color.secondary.opacity(0.3),
                                    in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(client == nil)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var addButton: some View {
        Button {
            editingRule = TrainingRule(name: "新规则", icon: "star.fill", note: "")
        } label: {
            Label("添加自定义规则", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Logic

    private func load() {
        hostInput = espHost
        if !rulesJson.isEmpty,
           let data = rulesJson.data(using: .utf8),
           let arr = try? JSONDecoder().decode([TrainingRule].self, from: data) {
            rules = arr
        } else {
            rules = TrainingCatalog.preset
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules),
           let s = String(data: data, encoding: .utf8) {
            rulesJson = s
        }
    }

    private func connect() {
        guard let url = ESPClient.makeLEDBaseURL(from: hostInput) else {
            lastError = "地址格式不合法"
            return
        }
        let normalized: String = {
            if let host = url.host, let port = url.port { return "\(host):\(port)" }
            return url.host ?? hostInput
        }()
        hostInput = normalized
        espHost = normalized
        client = ESPClient(baseURL: url)
        connecting = true
        lastError = nil
        Task {
            do {
                _ = try await client?.status()
                await MainActor.run { connecting = false }
            } catch {
                await MainActor.run {
                    connecting = false
                    lastError = "连接失败：\(error.localizedDescription)"
                    client = nil
                }
            }
        }
    }

    private func disconnect() {
        client = nil
    }

    private func test(_ rule: TrainingRule) {
        guard let c = client else { return }
        lastTestedAt[rule.id] = .now
        Task {
            await execute(rule, with: c)
        }
    }

    private func execute(_ rule: TrainingRule, with c: ESPClient) async {
        async let ledTask: Void = {
            do {
                if rule.hasLED {
                    try await c.setRGB(r: rule.ledRed, g: rule.ledGreen, b: rule.ledBlue)
                } else {
                    try await c.setOff()
                }
            } catch {
                dbg.error("led: \(error.localizedDescription, privacy: .public)")
            }
        }()

        async let soundTask: Void = {
            do {
                switch rule.sound {
                case .none: break
                case .meow: try await c.speakerMeow()
                case .beep: try await c.speakerBeep()
                case .file(let n): try await c.speakerPlayFile(name: n)
                }
            } catch {
                dbg.error("speaker: \(error.localizedDescription, privacy: .public)")
            }
        }()

        async let vibTask: Void = {
            do {
                if rule.vibrationMs > 0 {
                    try await c.motorVibrate(intensity: 255, duration: rule.vibrationMs)
                }
            } catch {
                dbg.error("motor: \(error.localizedDescription, privacy: .public)")
            }
        }()

        _ = await (ledTask, soundTask, vibTask)
    }
}

// MARK: - 规则编辑器

struct RuleEditor: View {
    @State var rule: TrainingRule
    let onSave: (TrainingRule) -> Void
    let onCancel: () -> Void

    private let iconChoices = [
        "exclamationmark.triangle.fill", "house.fill", "fork.knife", "moon.fill",
        "bell.badge.fill", "star.fill", "heart.fill", "pawprint.fill",
        "shield.fill", "bolt.fill"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("名字", text: $rule.name)
                    HStack {
                        Text("图标")
                        Spacer()
                        Menu {
                            ForEach(iconChoices, id: \.self) { ico in
                                Button {
                                    rule.icon = ico
                                } label: {
                                    Label(ico, systemImage: ico)
                                }
                            }
                        } label: {
                            Image(systemName: rule.icon).font(.title3)
                        }
                    }
                    TextField("场景描述（可选）", text: $rule.note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("LED 颜色") {
                    colorPresets
                    HStack {
                        sliderLabel("R", value: $rule.ledRed, color: .red)
                        sliderLabel("G", value: $rule.ledGreen, color: .green)
                        sliderLabel("B", value: $rule.ledBlue, color: .blue)
                    }
                    HStack {
                        Text("预览")
                        Spacer()
                        RoundedRectangle(cornerRadius: 6)
                            .fill(rule.ledColor)
                            .frame(width: 60, height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary, lineWidth: 0.5))
                    }
                }

                Section("扬声器") {
                    Picker("声音", selection: Binding(
                        get: { soundIndex(rule.sound) },
                        set: { rule.sound = soundFromIndex($0) }
                    )) {
                        Text("不响").tag(0)
                        Text("猫叫").tag(1)
                        Text("蜂鸣").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section("振动") {
                    HStack {
                        Text("时长")
                        Spacer()
                        Text("\(rule.vibrationMs) ms")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(rule.vibrationMs) },
                        set: { rule.vibrationMs = Int($0 / 100) * 100 }
                    ), in: 0...3000, step: 100)
                }
            }
            .navigationTitle(rule.name.isEmpty ? "新规则" : rule.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(rule) }
                        .disabled(rule.name.isEmpty)
                }
            }
        }
    }

    private var colorPresets: some View {
        HStack(spacing: 8) {
            ForEach(presetColors, id: \.0) { (name, r, g, b) in
                Button {
                    rule.ledRed = r; rule.ledGreen = g; rule.ledBlue = b
                } label: {
                    Circle()
                        .fill(Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(.secondary, lineWidth: 0.5))
                }
            }
        }
    }

    private let presetColors: [(String, Int, Int, Int)] = [
        ("off", 0, 0, 0), ("red", 255, 0, 0), ("green", 0, 255, 0),
        ("blue", 0, 0, 255), ("yellow", 255, 255, 0), ("purple", 255, 0, 255),
        ("white", 255, 255, 255),
    ]

    private func sliderLabel(_ name: String, value: Binding<Int>, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(name).font(.caption).foregroundStyle(color)
            Text("\(value.wrappedValue)").font(.caption.monospacedDigit())
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) }
            ), in: 0...255)
            .tint(color)
        }
    }

    private func soundIndex(_ s: TrainingSound) -> Int {
        switch s {
        case .none: return 0
        case .meow: return 1
        case .beep: return 2
        case .file: return 2  // demo 编辑器不支持选文件
        }
    }

    private func soundFromIndex(_ i: Int) -> TrainingSound {
        switch i {
        case 1: return .meow
        case 2: return .beep
        default: return .none
        }
    }
}

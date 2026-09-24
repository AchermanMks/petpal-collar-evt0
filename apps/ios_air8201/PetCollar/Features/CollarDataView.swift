import SwiftUI
import Charts

// 「分析 → 项圈数据」：项圈真实上报的数据面板（USB 台架或 4G 云端）。
// 只显示服务返回里存在的字段；缺失就显示「—」，不用默认值或演示数据填充。

struct CollarDataView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "zh"
    @State private var snapshot: [String: Any]?
    @State private var history: [[String: Any]]?
    @State private var historyAvailable = true
    @State private var error: String?
    @State private var lastRefresh: Date?
    @State private var refreshTask: Task<Void, Never>?

    private var en: Bool { appLanguage == "en" }
    private func tr(_ zh: String, _ english: String) -> String { en ? english : zh }

    private var telemetry: [String: Any] { snapshot?["telemetry"] as? [String: Any] ?? [:] }
    private var state: [String: Any] { snapshot?["state"] as? [String: Any] ?? [:] }
    private func dict(_ key: String) -> [String: Any] { telemetry[key] as? [String: Any] ?? [:] }
    private func num(_ d: [String: Any], _ key: String) -> Double? {
        if let n = d[key] as? NSNumber, !(d[key] is Bool) { return n.doubleValue }
        return nil
    }
    private func bool(_ d: [String: Any], _ key: String) -> Bool? { d[key] as? Bool }
    private func str(_ d: [String: Any], _ key: String) -> String? { d[key] as? String }
    private func fmt(_ v: Double?, _ digits: Int = 0, _ unit: String = "") -> String {
        guard let v else { return "—" }
        return String(format: "%.\(digits)f", v) + unit
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if let error { errorCard(error) }
                statusCard
                batteryCard
                motionCard
                gnssCard
                radioOutputsCard
                historyCard
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle(tr("项圈数据", "Collar Data"))
        .onAppear(perform: start)
        .onDisappear { refreshTask?.cancel(); refreshTask = nil }
    }

    // MARK: - Sections

    private var statusCard: some View {
        let online = snapshot?["online"] as? Bool
        let transport = snapshot?["transport"] as? String
        let seen = (snapshot?["last_seen_ts"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return PetPalCard(padding: 16, glass: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle().fill(online == true ? PetPalTheme.success : PetPalTheme.danger).frame(width: 10, height: 10)
                    Text(online == nil ? tr("未知", "Unknown") : (online! ? tr("在线", "Online") : tr("离线", "Offline")))
                        .font(.headline).foregroundStyle(PetPalTheme.inkPrimary)
                    Spacer()
                    Text(transport == "mqtt-4g" ? "4G" : (transport == "usb-bench" ? "USB" : (transport ?? "—")))
                        .font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(PetPalTheme.primary.opacity(0.15), in: Capsule()).foregroundStyle(PetPalTheme.primaryDeep)
                }
                row(tr("设备编号", "Device"), str(telemetry, "device_id") ?? (snapshot?["device_id"] as? String) ?? "—")
                row(tr("固件", "Firmware"), str(telemetry, "fw") ?? str(state, "fw") ?? "—")
                row(tr("开机次数", "Boot count"), fmt(num(telemetry, "boot_count") ?? num(state, "boot_count")))
                row(tr("最后上报", "Last report"), seen.map { relative($0) } ?? "—")
                row(tr("时钟同步", "Clock synced"), yesNo(bool(telemetry, "clock_synced")))
                row(tr("模式", "Mode"), str(telemetry, "mode") ?? "—")
            }
        }
    }

    private var batteryCard: some View {
        let b = dict("battery")
        return PetPalCard(padding: 16, glass: true) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(tr("电池", "Battery"), "battery.75percent")
                if bool(b, "ready") == true {
                    HStack(alignment: .firstTextBaseline) {
                        Text(fmt(num(b, "pct"), 0, "%")).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(PetPalTheme.inkPrimary)
                        Text(fmt(num(b, "mv"), 0, " mV")).font(.subheadline).foregroundStyle(PetPalTheme.inkSecondary)
                        Spacer()
                        if bool(b, "charging") == true {
                            Label(tr("充电中", "Charging"), systemImage: "bolt.fill").font(.caption.weight(.bold)).foregroundStyle(PetPalTheme.success)
                        }
                    }
                    if let t = num(b, "temp_c") { row(tr("温度", "Temperature"), fmt(t, 1, " °C")) }
                    else { row(tr("温度", "Temperature"), tr("无传感器", "No sensor")) }
                } else {
                    Text(tr("项圈尚未上报电池数据", "No battery data reported yet")).font(.subheadline).foregroundStyle(PetPalTheme.inkSecondary)
                }
            }
        }
    }

    private var motionCard: some View {
        let m = dict("motion")
        let accel = (m["accel_g"] as? [NSNumber])?.map { $0.doubleValue }
        return PetPalCard(padding: 16, glass: true) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(tr("运动", "Motion"), "figure.walk.motion")
                if let paused = m["paused"] {
                    Text(tr("传感器暂停中：\(String(describing: paused)) 占用 I2C 总线", "Sensor paused: bus used by \(String(describing: paused))"))
                        .font(.caption).foregroundStyle(PetPalTheme.warning)
                }
                if bool(m, "ready") == true {
                    row(tr("状态", "State"), motionLabel(str(m, "state")))
                    row(tr("活动", "Activity"), str(m, "activity").map { $0 == "active" ? tr("活跃", "Active") : tr("休息", "Resting") } ?? "—")
                    row(tr("今日活跃", "Active today"), num(m, "active_s").map { duration($0) } ?? "—")
                    row(tr("动作峰值计数", "Peak count"), fmt(num(m, "steps")))
                    if let a = accel, a.count == 3 {
                        row(tr("加速度 (g)", "Accel (g)"), String(format: "x %.2f  y %.2f  z %.2f", a[0], a[1], a[2]))
                    }
                    if let r = num(m, "reads"), let f = num(m, "read_fails"), r > 0 {
                        row(tr("传感器读取", "Sensor reads"), String(format: "%.0f · %@ %.1f%%", r, tr("失败", "failed"), 100 * f / r))
                    }
                    Text(tr("活动量为加速度幅值估计，不是校准计步，也不是健康指标。", "Activity is an acceleration-magnitude estimate, not calibrated steps or a health metric."))
                        .font(.caption2).foregroundStyle(PetPalTheme.inkSecondary)
                } else {
                    Text(tr("加速度传感器未就绪", "Motion sensor not ready")).font(.subheadline).foregroundStyle(PetPalTheme.inkSecondary)
                }
            }
        }
    }

    private var gnssCard: some View {
        let g = dict("gnss")
        let p = telemetry["position"] as? [String: Any]
        let fix = bool(g, "fix") ?? false
        return PetPalCard(padding: 16, glass: true) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(tr("定位", "GNSS"), "location.fill")
                if let paused = g["paused"] {
                    Text(tr("定位暂停中：\(String(describing: paused)) 使用期间关闭", "GNSS paused while \(String(describing: paused)) is in use"))
                        .font(.caption).foregroundStyle(PetPalTheme.warning)
                }
                row(tr("状态", "Status"), fix ? tr("已定位", "Fixed") : tr("搜星中", "Searching"))
                if let p {
                    row(tr("经纬度 (WGS-84)", "Lat / Lng (WGS-84)"), String(format: "%.5f, %.5f", num(p, "lat") ?? 0, num(p, "lng") ?? 0))
                    row(tr("定位年龄", "Fix age"), num(p, "fix_age_s").map { duration($0) } ?? "—")
                    row(tr("卫星数", "Satellites"), fmt(num(p, "sats")))
                    row(tr("精度估计", "Accuracy"), num(p, "accuracy_m").map { "≈ " + fmt($0, 0, " m") } ?? tr("未知", "Unknown"))
                    row(tr("海拔 / 速度", "Alt / Speed"), fmt(num(p, "alt_m"), 0, " m") + " / " + fmt(num(p, "speed_kmh"), 1, " km/h"))
                } else {
                    Text(tr("尚无定位。需要天线能看到天空。", "No fix yet. The antenna needs a view of the sky.")).font(.subheadline).foregroundStyle(PetPalTheme.inkSecondary)
                }
                if let inView = num(g, "sats_in_view") {
                    row(tr("可见 / 有信号", "In view / with signal"), "\(Int(inView)) / \(Int(num(g, "sats_with_signal") ?? 0))  ·  SNR \(fmt(num(g, "snr_max")))")
                }
                if let ttff = num(g, "ttff_s") { row(tr("首次定位耗时", "Time to first fix"), fmt(ttff, 0, " s")) }
            }
        }
    }

    private var radioOutputsCard: some View {
        let r = dict("radio"), o = dict("outputs"), c = dict("capabilities")
        return PetPalCard(padding: 16, glass: true) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(tr("信号与输出", "Signal & Outputs"), "antenna.radiowaves.left.and.right")
                row("4G RSRP / RSSI", "\(fmt(num(r, "rsrp_dbm"), 0, " dBm")) / \(fmt(num(r, "rssi_dbm"), 0, " dBm"))")
                row(tr("灯 / 马达 / 喇叭", "LED / Motor / Speaker"),
                    [bool(o, "led_on"), bool(o, "motor_on"), bool(o, "speaker_on")].map { $0 == true ? tr("开", "On") : ($0 == false ? tr("关", "Off") : "—") }.joined(separator: " / "))
                let caps = c.keys.sorted().filter { c[$0] as? Bool == true }
                if !caps.isEmpty { row(tr("已就绪能力", "Ready capabilities"), caps.joined(separator: ", ")) }
            }
        }
    }

    private var historyCard: some View {
        PetPalCard(padding: 16, glass: true) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(tr("24 小时趋势", "24-hour trend"), "chart.xyaxis.line")
                if !historyAvailable {
                    Text(tr("当前连接的是 USB 台架，没有云端历史。", "Connected via the USB bench: no cloud history."))
                        .font(.subheadline).foregroundStyle(PetPalTheme.inkSecondary)
                } else if let h = history, !h.isEmpty {
                    let pts = h.compactMap { s -> (Date, Double, Bool)? in
                        guard let ts = (s["ts"] as? NSNumber)?.doubleValue, let pct = (s["pct"] as? NSNumber)?.doubleValue else { return nil }
                        return (Date(timeIntervalSince1970: ts), pct, s["motion"] as? String == "moving")
                    }
                    Text(tr("电量 %", "Battery %")).font(.caption).foregroundStyle(PetPalTheme.inkSecondary)
                    Chart(Array(pts.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("t", p.0), y: .value("pct", p.1)).foregroundStyle(PetPalTheme.primaryDeep).interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: 0...100).frame(height: 120)
                    Text(tr("运动（每分钟一个点）", "Motion (one sample per minute)")).font(.caption).foregroundStyle(PetPalTheme.inkSecondary)
                    Chart(Array(pts.enumerated()), id: \.offset) { _, p in
                        BarMark(x: .value("t", p.0), y: .value("moving", p.2 ? 1 : 0), width: 2).foregroundStyle(p.2 ? PetPalTheme.success : Color.clear)
                    }
                    .chartYAxis(.hidden).chartYScale(domain: 0...1).frame(height: 40)
                    Text(tr("\(h.count) 条上报", "\(h.count) reports")).font(.caption2).foregroundStyle(PetPalTheme.inkSecondary)
                } else {
                    Text(tr("还没有历史数据", "No history yet")).font(.subheadline).foregroundStyle(PetPalTheme.inkSecondary)
                }
            }
        }
    }

    private var footer: some View {
        Text(lastRefresh.map { tr("刷新于 ", "Refreshed ") + relative($0) + tr("，每 30 秒自动刷新", ", auto-refresh every 30 s") } ?? tr("正在读取…", "Loading…"))
            .font(.caption2).foregroundStyle(PetPalTheme.inkSecondary)
    }

    private func errorCard(_ msg: String) -> some View {
        PetPalCard(padding: 14, glass: true) {
            Label(msg, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(PetPalTheme.danger)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ t: String, _ icon: String) -> some View {
        Label(t, systemImage: icon).font(.subheadline.weight(.bold)).foregroundStyle(PetPalTheme.inkPrimary)
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.caption).foregroundStyle(PetPalTheme.inkSecondary); Spacer(); Text(v).font(.caption.weight(.medium)).foregroundStyle(PetPalTheme.inkPrimary).multilineTextAlignment(.trailing) }
    }
    private func yesNo(_ b: Bool?) -> String { b == nil ? "—" : (b! ? tr("是", "Yes") : tr("否", "No")) }
    private func motionLabel(_ s: String?) -> String {
        switch s { case "moving": return tr("运动", "Moving"); case "still": return tr("静止", "Still"); case "unknown": return tr("未知", "Unknown"); default: return s ?? "—" }
    }
    private func duration(_ s: Double) -> String {
        let v = Int(s); if v < 60 { return "\(v) s" }; if v < 3600 { return "\(v / 60) min \(v % 60) s" }; return "\(v / 3600) h \(v % 3600 / 60) min"
    }
    private func relative(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d)); if s < 5 { return tr("刚刚", "just now") }; if s < 60 { return "\(s) s " + tr("前", "ago") }
        if s < 3600 { return "\(s / 60) min " + tr("前", "ago") }; return "\(s / 3600) h " + tr("前", "ago")
    }

    private func start() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
    private func refresh() async {
        do {
            let c = try AirHardwareBackend.defaultClient()
            let snap = try await c.rawSnapshot()
            let hist = await c.history(hours: 24)
            await MainActor.run {
                snapshot = snap; error = nil; lastRefresh = .now
                if let hist { history = hist; historyAvailable = true } else { history = nil; historyAvailable = false }
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription; lastRefresh = .now }
        }
    }
}

import SwiftUI
import MapKit
import CoreLocation
import Observation

// MARK: - Data Models

struct LastKnownFix: Codable, Equatable {
    var lat: Double
    var lng: Double
    var alt: Double
    var sats: Int
    var gpsDatetime: String
    var receivedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct GPSTrackPoint: Codable, Hashable {
    var lat: Double
    var lng: Double
    var time: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Track Store

enum GPSTrackStore {
    static let fileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("track_history.json")
    }()

    static func load() -> [GPSTrackPoint] {
        guard let data = try? Data(contentsOf: fileURL),
              let points = try? JSONDecoder().decode([GPSTrackPoint].self, from: data) else { return [] }
        return points
    }

    static func save(_ points: [GPSTrackPoint]) {
        guard let data = try? JSONEncoder().encode(points) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Phone Location

@MainActor
@Observable
final class PhoneLocationProvider: NSObject, CLLocationManagerDelegate {
    var phoneLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.phoneLocation = loc }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in self.authorizationStatus = s }
    }
}

// MARK: - GPS View

struct GPSView: View {
    @AppStorage("espHost") private var espHost: String = "esp32-led.local"
    @AppStorage("lastKnownFixJson") private var lastKnownFixJson: String = ""
    @State private var hostInput: String = ""
    @State private var client: ESPClient?
    @State private var lastError: String?

    @State private var gpsData: ESPClient.GPSData?
    @State private var isPolling = false
    @State private var pollTask: Task<Void, Never>?

    @State private var mapPosition = MapCameraPosition.automatic
    @State private var trackHistory: [GPSTrackPoint] = []
    @State private var trackSaveCounter: Int = 0

    @State private var huntMode: Bool = false
    @State private var phoneProvider = PhoneLocationProvider()

    private var lastKnownFix: LastKnownFix? {
        guard let data = lastKnownFixJson.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LastKnownFix.self, from: data)
    }

    private func saveLastKnownFix(_ fix: LastKnownFix) {
        if let data = try? JSONEncoder().encode(fix),
           let s = String(data: data, encoding: .utf8) {
            lastKnownFixJson = s
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if client != nil {
                    signalCard
                    failureBanner
                    mapCard
                    huntCard
                    detailCard
                    feedbackCard
                }
                hostCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("GPS")
        .onAppear {
            if hostInput.isEmpty { hostInput = espHost }
            if trackHistory.isEmpty { trackHistory = GPSTrackStore.load() }
            phoneProvider.start()
            if client == nil && !hostInput.isEmpty { connect() }
        }
        .onDisappear {
            pollTask?.cancel()
            phoneProvider.stop()
            if !trackHistory.isEmpty { GPSTrackStore.save(trackHistory) }
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
                    if isPolling {
                        ProgressView().controlSize(.small)
                    }
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

    // MARK: - Signal Card

    private var signalCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.green)
                    Text("定位状态")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                }

                if let data = gpsData {
                    HStack(spacing: 0) {
                        signalItem(
                            icon: data.fix ? "location.fill" : "location.slash",
                            label: "状态",
                            value: data.fix ? "已定位" : "搜星中",
                            color: data.fix ? PetPalTheme.success : PetPalTheme.warning
                        )
                        Spacer()
                        signalItem(
                            icon: "antenna.radiowaves.left.and.right",
                            label: "卫星",
                            value: "\(data.sats) 颗",
                            color: data.sats >= 4 ? .blue : .gray
                        )
                        Spacer()
                        signalItem(
                            icon: "speedometer",
                            label: "速度",
                            value: String(format: "%.1f km/h", data.speedKmh),
                            color: PetPalTheme.primary
                        )
                    }
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            ProgressView()
                            Text("等待数据...")
                                .font(.caption)
                                .foregroundStyle(PetPalTheme.inkSecondary)
                        }
                        .padding(.vertical, 8)
                        Spacer()
                    }
                }
            }
        }
    }

    private func signalItem(icon: String, label: String, value: String, color: Color) -> some View {
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

    // MARK: - Failure Banner

    @ViewBuilder
    private var failureBanner: some View {
        if let data = gpsData, let age = data.lastNmeaAgeMs, age > 10_000 {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(PetPalTheme.warning)
                Text("GNSS 已 \(age / 1000) 秒无数据，可能被遮挡")
                    .font(.callout)
                    .foregroundStyle(PetPalTheme.warning)
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PetPalTheme.warning.opacity(0.1))
            )
        }
    }

    // MARK: - Map Card

    private var mapCard: some View {
        PetPalCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .foregroundStyle(.indigo)
                    Text("地图")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Spacer()
                    if gpsData?.fix == true {
                        Button {
                            if let data = gpsData {
                                mapPosition = .region(MKCoordinateRegion(
                                    center: CLLocationCoordinate2D(latitude: data.lat, longitude: data.lng),
                                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                                ))
                            }
                        } label: {
                            Image(systemName: "location.viewfinder")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.indigo)
                                .padding(8)
                                .background(Circle().fill(.indigo.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Map(position: $mapPosition) {
                    UserAnnotation()

                    if let data = gpsData, data.fix {
                        Annotation("Pet", coordinate: CLLocationCoordinate2D(latitude: data.lat, longitude: data.lng)) {
                            ZStack {
                                Circle()
                                    .fill(.blue.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "pawprint.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .background(Circle().fill(.white).frame(width: 26, height: 26))
                            }
                        }
                    }

                    if (gpsData?.fix ?? false) == false, let last = lastKnownFix {
                        Annotation("上次", coordinate: last.coordinate) {
                            Image(systemName: "pawprint.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .background(Circle().fill(.white).frame(width: 26, height: 26))
                        }
                    }

                    if trackHistory.count >= 2 {
                        MapPolyline(coordinates: trackHistory.map(\.coordinate))
                            .stroke(.blue.opacity(0.5), lineWidth: 2)
                    }
                }
                .frame(height: 260)
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24)
                    )
                )
            }
        }
    }

    // MARK: - Hunt Card

    private var targetCoordinate: CLLocationCoordinate2D? {
        if let data = gpsData, data.fix {
            return CLLocationCoordinate2D(latitude: data.lat, longitude: data.lng)
        }
        return lastKnownFix?.coordinate
    }

    private var distanceFromPhone: CLLocationDistance? {
        guard let phone = phoneProvider.phoneLocation, let target = targetCoordinate else { return nil }
        return phone.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
    }

    private var huntCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "binoculars.fill")
                            .foregroundStyle(.orange)
                        Text("寻猫模式")
                            .font(.headline)
                            .foregroundStyle(PetPalTheme.inkPrimary)
                    }
                    Spacer()
                    Toggle("", isOn: $huntMode)
                        .labelsHidden()
                        .tint(.orange)
                        .onChange(of: huntMode) { _, on in
                            if on, pollTask != nil { startPolling() }
                        }
                }

                if huntMode {
                    if let dist = distanceFromPhone {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(.orange.opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "ruler")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("距离项圈")
                                    .font(.caption)
                                    .foregroundStyle(PetPalTheme.inkSecondary)
                                Text(formatDistance(dist))
                                    .font(.title2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(PetPalTheme.inkPrimary)
                            }
                            Spacer()
                        }
                    } else if phoneProvider.authorizationStatus == .denied || phoneProvider.authorizationStatus == .restricted {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.slash")
                                .foregroundStyle(.orange)
                            Text("位置权限被拒，无法算距离")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if let last = lastKnownFix {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(PetPalTheme.inkSecondary)
                                .font(.caption)
                            Text("上次位置 · \(formatAge(last.receivedAt))")
                                .font(.caption)
                                .foregroundStyle(PetPalTheme.inkSecondary)
                        }
                    }

                    if let target = targetCoordinate,
                       let url = URL(string: "http://maps.apple.com/?daddr=\(target.latitude),\(target.longitude)") {
                        Link(destination: url) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                Text("Apple Maps 导航")
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
                    }
                }
            }
        }
    }

    // MARK: - Detail Card

    private var detailCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("详细信息")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                }

                if let data = gpsData {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        detailItem("纬度", value: String(format: "%.6f", data.lat))
                        detailItem("经度", value: String(format: "%.6f", data.lng))
                        detailItem("海拔", value: String(format: "%.1f m", data.alt))
                        detailItem("速度", value: String(format: "%.1f km/h", data.speedKmh))
                        detailItem("卫星数", value: "\(data.sats)")
                        detailItem("数据延迟", value: "\(data.ageMs) ms")
                        detailItem("UART 字符", value: data.charsTotal.map { "\($0)" } ?? "--")
                        detailItem("有效句子", value: data.sentencesWithFix.map { "\($0)" } ?? "--")
                        detailItem("NMEA 延迟", value: formatNmeaAge(data.lastNmeaAgeMs))
                    }
                    if !data.datetime.isEmpty {
                        HStack {
                            Text("GPS 时间")
                                .font(.caption)
                                .foregroundStyle(PetPalTheme.inkSecondary)
                            Spacer()
                            Text(data.datetime)
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(PetPalTheme.inkPrimary)
                        }
                        .padding(.top, 4)
                    }
                } else {
                    HStack {
                        Spacer()
                        Text("暂无数据")
                            .font(.caption)
                            .foregroundStyle(PetPalTheme.inkSecondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func detailItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(PetPalTheme.inkSecondary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(PetPalTheme.inkPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gray.opacity(0.04))
        )
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
            }
        }
    }

    // MARK: - Helpers

    private func formatDistance(_ m: CLLocationDistance) -> String {
        if m < 1000 { return String(format: "%.0f m", m) }
        return String(format: "%.2f km", m / 1000)
    }

    private func formatAge(_ ref: Date) -> String {
        let s = Int(Date.now.timeIntervalSince(ref))
        if s < 60 { return "\(s) 秒前" }
        if s < 3600 { return "\(s / 60) 分钟前" }
        if s < 86400 { return "\(s / 3600) 小时前" }
        return "\(s / 86400) 天前"
    }

    private func formatNmeaAge(_ ms: Int?) -> String {
        guard let ms else { return "--" }
        if ms == 4_294_967_295 { return "从未" }
        if ms < 1_000 { return "\(ms) ms" }
        if ms < 60_000 { return String(format: "%.1f s", Double(ms) / 1000) }
        return "> 1 min"
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
        startPolling()
    }

    private func disconnect() {
        pollTask?.cancel()
        if !trackHistory.isEmpty { GPSTrackStore.save(trackHistory) }
        client = nil
        gpsData = nil
        lastError = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await fetchGPS()
                let interval: Duration = huntMode ? .seconds(1) : .seconds(2)
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func fetchGPS() async {
        guard let c = client else { return }
        isPolling = true
        do {
            let data = try await c.gps()
            gpsData = data
            lastError = nil

            if data.fix {
                let point = GPSTrackPoint(lat: data.lat, lng: data.lng, time: .now)
                trackHistory.append(point)
                if trackHistory.count > 500 {
                    trackHistory.removeFirst(trackHistory.count - 500)
                }

                trackSaveCounter += 1
                if trackSaveCounter >= 5 {
                    trackSaveCounter = 0
                    GPSTrackStore.save(trackHistory)
                }

                saveLastKnownFix(LastKnownFix(
                    lat: data.lat, lng: data.lng, alt: data.alt,
                    sats: data.sats, gpsDatetime: data.datetime, receivedAt: .now
                ))

                if trackHistory.count == 1 {
                    mapPosition = .region(MKCoordinateRegion(
                        center: point.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    ))
                }
            }
        } catch {
            if !Task.isCancelled {
                lastError = humanMessage(error)
            }
        }
        isPolling = false
    }

    private func humanMessage(_ error: Error) -> String {
        if case ESPClientError.httpStatus(404) = error {
            return "404：固件不支持 GPS"
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
    NavigationStack { GPSView() }
}

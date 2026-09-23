import SwiftUI
import os.log

private let dbg = Logger(subsystem: "PetCollar", category: "Stats")

struct StatsPanelView: View {
    @Environment(AppState.self) private var state
    @State private var tracks: [Int: TrackStats] = [:]
    @State private var classSummary: [String: ClassSummary] = [:]
    @State private var pollTask: Task<Void, Never>?
    @State private var nowTick: Date = .now

    private let pollInterval: Duration = .milliseconds(500)
    private let staleCutoff: TimeInterval = 5

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                summaryRow
                if !classSummary.isEmpty {
                    classSection
                }
                if visibleTracks.isEmpty {
                    emptyHint
                } else {
                    trackSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("统计")
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private var visibleTracks: [TrackStats] {
        tracks.values
            .filter { nowTick.timeIntervalSince1970 - $0.lastTs < staleCutoff }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        let active = visibleTracks.count
        let totalDist = visibleTracks.reduce(0.0) { $0 + $1.distanceMeters }
        let mostActive = visibleTracks.max(by: { $0.distanceMeters < $1.distanceMeters })

        return HStack(spacing: 10) {
            summaryTile(icon: "pawprint.fill", title: "活跃", value: "\(active)", color: .green)
            summaryTile(icon: "arrow.triangle.swap", title: "距离",
                        value: String(format: "%.1fm", totalDist), color: .blue)
            summaryTile(icon: "flame.fill", title: "最活跃",
                        value: mostActive.map { "#\($0.id)" } ?? "--", color: .orange)
        }
    }

    private func summaryTile(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(PetPalTheme.inkPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(PetPalTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // MARK: - Class Section

    private var classSection: some View {
        VStack(spacing: 12) {
            ForEach(classSummary.keys.sorted(), id: \.self) { klass in
                if let cs = classSummary[klass] {
                    classCard(cs)
                }
            }
        }
    }

    private func classCard(_ cs: ClassSummary) -> some View {
        let color: Color = cs.klass == "猫" ? .green : .orange
        let icon = cs.klass == "猫" ? "cat.fill" : "dog.fill"
        return PetPalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .foregroundStyle(color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cs.klass)
                            .font(.headline)
                            .foregroundStyle(PetPalTheme.inkPrimary)
                        Text("\(cs.trackIds.count) 个追踪 ID")
                            .font(.caption)
                            .foregroundStyle(PetPalTheme.inkSecondary)
                    }
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    classMetric("采样", "\(cs.totalSamples) 次")
                    classMetric("时长", formatDuration(cs.durationSec))
                    classMetric("质量", String(format: "%.2f", cs.avgQuality))
                    classMetric("置信", String(format: "%.0f%%", cs.lastConf * 100))
                    classMetric("位置", String(format: "(%.2f, %.2f)", cs.lastX, cs.lastY))
                }
            }
        }
    }

    private func classMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(PetPalTheme.inkSecondary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(PetPalTheme.inkPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gray.opacity(0.04))
        )
    }

    // MARK: - Track Section

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .foregroundStyle(PetPalTheme.primary)
                Text("活跃追踪")
                    .font(.headline)
                    .foregroundStyle(PetPalTheme.inkPrimary)
            }
            .padding(.top, 4)

            ForEach(visibleTracks, id: \.id) { t in
                trackCard(t)
            }
        }
    }

    private func trackCard(_ t: TrackStats) -> some View {
        let color = palette[abs(t.id) % palette.count]
        let staleness = nowTick.timeIntervalSince1970 - t.lastTs
        let isFresh = staleness < 1.0

        return PetPalCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Circle().fill(color).frame(width: 10, height: 10)
                        Text("\(t.klass) #\(t.id)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(PetPalTheme.inkPrimary)
                    }
                    Spacer()
                    if isFresh {
                        Text("活跃")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(color.opacity(0.12), in: Capsule())
                    } else {
                        Text(String(format: "静止 %.0fs", staleness))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.gray.opacity(0.08), in: Capsule())
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    trackMetric("时长", formatDuration(t.durationSec))
                    trackMetric("距离", String(format: "%.2f m", t.distanceMeters))
                    trackMetric("质量", String(format: "%.2f", t.avgQuality))
                    trackMetric("位置", String(format: "(%.2f, %.2f)", t.lastX, t.lastY))
                    trackMetric("采样", "\(t.samples)")
                }
            }
        }
    }

    private func trackMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(PetPalTheme.inkSecondary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(PetPalTheme.inkPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty Hint

    private var emptyHint: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(PetPalTheme.blush)
                    .frame(width: 64, height: 64)
                Image(systemName: "tray")
                    .font(.system(size: 24))
                    .foregroundStyle(PetPalTheme.primary.opacity(0.5))
            }
            Text("等待检测数据...")
                .font(.callout)
                .foregroundStyle(PetPalTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding()
    }

    // MARK: - Actions

    private func start() {
        guard let api = state.api else { return }
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let resp = try await api.detections()
                    await MainActor.run {
                        ingest(resp.recent)
                        nowTick = .now
                    }
                } catch {
                    await MainActor.run { nowTick = .now }
                }
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    private func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func ingest(_ detections: [Detection]) {
        let sorted = detections.sorted { $0.ts < $1.ts }
        for det in sorted {
            guard let trackId = det.trackId else { continue }
            var s = tracks[trackId] ?? TrackStats(
                id: trackId, klass: det.klass,
                firstTs: det.ts, lastTs: det.ts,
                lastX: det.physicalCoords.x, lastY: det.physicalCoords.y
            )
            if det.ts <= s.lastTs && s.samples > 0 { continue }
            // 本次位移只算一次，track 与 class 汇总共用（此前 class 侧在 lastX/lastY
            // 被覆盖后才做差，恒为 0，类别总距离从不累积）
            var stepMeters = 0.0
            if s.samples > 0 {
                let dx = det.physicalCoords.x - s.lastX
                let dy = det.physicalCoords.y - s.lastY
                let step = (dx * dx + dy * dy).squareRoot()
                if step < 5.0 {
                    stepMeters = step
                    s.distanceMeters += step
                }
            }
            s.klass = det.klass
            s.lastTs = det.ts
            s.lastX = det.physicalCoords.x
            s.lastY = det.physicalCoords.y
            s.qualitySum += det.qualityScore
            s.samples += 1
            tracks[trackId] = s

            var cs = classSummary[det.klass] ?? ClassSummary(klass: det.klass)
            cs.trackIds.insert(trackId)
            cs.totalSamples += 1
            cs.totalQualitySum += det.qualityScore
            cs.firstTs = min(cs.firstTs, det.ts)
            cs.lastTs = max(cs.lastTs, det.ts)
            cs.lastX = det.physicalCoords.x
            cs.lastY = det.physicalCoords.y
            cs.lastConf = det.confidence
            cs.totalDistance += stepMeters
            classSummary[det.klass] = cs
        }

        // 淘汰长时间未更新的 track，防止跨小时会话字典无限膨胀
        let evictCutoff = Date.now.timeIntervalSince1970 - 300
        for (id, s) in tracks where s.lastTs < evictCutoff {
            tracks.removeValue(forKey: id)
        }
    }

    private func formatDuration(_ sec: Double) -> String {
        if sec < 60 { return String(format: "%.0fs", sec) }
        let m = Int(sec / 60)
        let s = Int(sec) % 60
        return "\(m)m \(s)s"
    }

    private let palette: [Color] = [.green, .orange, .blue, .purple, .pink, .yellow, .cyan, .mint]
}

private struct TrackStats {
    let id: Int
    var klass: String
    let firstTs: Double
    var lastTs: Double
    var lastX: Double
    var lastY: Double
    var distanceMeters: Double = 0
    var qualitySum: Double = 0
    var samples: Int = 0

    var durationSec: Double { max(0, lastTs - firstTs) }
    var avgQuality: Double { samples > 0 ? qualitySum / Double(samples) : 0 }
}

struct ClassSummary {
    var klass: String
    var totalDistance: Double = 0
    var totalSamples: Int = 0
    var totalQualitySum: Double = 0
    var trackIds: Set<Int> = []
    var firstTs: Double = .infinity
    var lastTs: Double = 0
    var lastX: Double = 0
    var lastY: Double = 0
    var lastConf: Double = 0

    var avgQuality: Double { totalSamples > 0 ? totalQualitySum / Double(totalSamples) : 0 }
    var durationSec: Double { firstTs < .infinity ? max(0, lastTs - firstTs) : 0 }
}

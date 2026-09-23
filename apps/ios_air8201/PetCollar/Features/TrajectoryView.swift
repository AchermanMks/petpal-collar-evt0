import SwiftUI
import os.log

private let dbg = Logger(subsystem: "PetCollar", category: "Trajectory")

struct TrajectoryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    @State private var tracks: [Int: TrackHistory] = [:]
    @State private var pollTask: Task<Void, Never>?
    @State private var nowTick: Date = .now

    private let maxPointsPerTrack = 500
    private let trackTtl: TimeInterval = 30

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            GeometryReader { geo in
                Canvas { context, size in
                    _ = nowTick
                    let room = roomSize
                    let layout = fittedFrame(content: room, inside: size, margin: 48)
                    drawRoom(in: context, rect: layout, roomDim: room)
                    drawTracks(in: context, rect: layout, roomDim: room)
                }
            }

            VStack(spacing: 0) {
                // Top bar
                HStack(alignment: .top) {
                    legendCard
                    Spacer()
                    clearButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                if tracks.isEmpty {
                    emptyHint
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("轨迹")
        .onAppear(perform: start)
    }

    private var roomSize: CGSize {
        if let dim = state.systemInfo?.room.dimensionsM {
            return CGSize(width: max(0.1, dim.width), height: max(0.1, dim.depth))
        }
        return CGSize(width: 4, height: 3)
    }

    // MARK: - Legend Card

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.caption)
                    .foregroundStyle(.indigo)
                Text(String(format: "%.1f x %.1f m", roomSize.width, roomSize.height))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
            }
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("活跃 \(tracks.count)")
                    .font(.caption2)
                    .foregroundStyle(PetPalTheme.inkSecondary)
            }
            if state.systemInfo?.room.calibrated == false {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("未标定")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var clearButton: some View {
        Button {
            tracks.removeAll()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                Text("清空")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(PetPalTheme.danger)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                Capsule().fill(PetPalTheme.danger.opacity(0.1))
            )
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "pawprint")
                .font(.title)
                .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.4))
            Text("等待检测数据...")
                .font(.callout)
                .foregroundStyle(PetPalTheme.inkSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Polling

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
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func ingest(_ detections: [Detection]) {
        let now = Date().timeIntervalSince1970
        let sorted = detections.sorted { $0.ts < $1.ts }
        for det in sorted {
            guard let trackId = det.trackId else { continue }
            var history = tracks[trackId] ?? TrackHistory(id: trackId, klass: det.klass)
            let lastTs = history.points.last?.ts ?? 0
            guard det.ts > lastTs else { continue }
            history.points.append(TrackPoint(x: det.physicalCoords.x, y: det.physicalCoords.y, ts: det.ts))
            if history.points.count > maxPointsPerTrack {
                history.points.removeFirst(history.points.count - maxPointsPerTrack)
            }
            history.klass = det.klass
            history.lastTs = det.ts
            history.lastQuality = det.qualityScore
            tracks[trackId] = history
        }
        tracks = tracks.filter { now - $0.value.lastTs < trackTtl }
    }

    // MARK: - Drawing

    private func drawRoom(in context: GraphicsContext, rect: CGRect, roomDim: CGSize) {
        // Room fill
        let roomPath = Path(roundedRect: rect, cornerRadius: 8)
        context.fill(roomPath, with: .color(Color.white.opacity(scheme == .dark ? 0.06 : 0.6)))
        context.stroke(roomPath, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)

        let gridColor = GraphicsContext.Shading.color(.secondary.opacity(0.12))
        let scaleX = rect.width / roomDim.width
        let scaleY = rect.height / roomDim.height

        var x = 1.0
        while x < roomDim.width {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + x * scaleX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + x * scaleX, y: rect.maxY))
            context.stroke(p, with: gridColor, lineWidth: 0.5)
            x += 1
        }
        var y = 1.0
        while y < roomDim.height {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + y * scaleY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + y * scaleY))
            context.stroke(p, with: gridColor, lineWidth: 0.5)
            y += 1
        }

        // 后端坐标系原点是 left_bottom（system_info.origin），此前画在左上角导致 y 轴镜像
        let origin = CGPoint(x: rect.minX, y: rect.maxY)
        context.fill(
            Path(ellipseIn: CGRect(x: origin.x - 3, y: origin.y - 3, width: 6, height: 6)),
            with: .color(.blue)
        )
        context.draw(
            Text("(0,0)").font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: origin.x + 22, y: origin.y - 10),
            anchor: .leading
        )
        context.draw(
            Text(String(format: "x → %.1fm", roomDim.width))
                .font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: rect.maxX - 4, y: rect.maxY + 12),
            anchor: .trailing
        )
        context.draw(
            Text(String(format: "y ↑ %.1fm", roomDim.height))
                .font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: rect.minX - 6, y: rect.minY + 8),
            anchor: .trailing
        )
    }

    private func drawTracks(in context: GraphicsContext, rect: CGRect, roomDim: CGSize) {
        let scaleX = rect.width / roomDim.width
        let scaleY = rect.height / roomDim.height
        let now = Date().timeIntervalSince1970

        let ordered = tracks.values.sorted { $0.lastTs < $1.lastTs }
        for track in ordered {
            guard !track.points.isEmpty else { continue }
            let color = trackColor(for: track.id)

            var path = Path()
            var prev: TrackPoint? = nil
            for pt in track.points {
                // y 翻转匹配 left_bottom 原点
                let p = CGPoint(x: rect.minX + pt.x * scaleX, y: rect.maxY - pt.y * scaleY)
                // 断线规则：时间空窗 >2s 或单步 >1.5m（track 丢失重捕/ID 漂移）不连线，
                // 否则瞬移会画成横穿房间的假直线
                if let pr = prev,
                   pt.ts - pr.ts <= 2.0,
                   ((pt.x - pr.x) * (pt.x - pr.x) + (pt.y - pr.y) * (pt.y - pr.y)).squareRoot() <= 1.5 {
                    path.addLine(to: p)
                } else {
                    path.move(to: p)
                }
                prev = pt
            }
            context.stroke(
                path,
                with: .color(color.opacity(0.55)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            let last = track.points.last!
            let pLast = CGPoint(x: rect.minX + last.x * scaleX, y: rect.maxY - last.y * scaleY)
            let staleness = now - last.ts
            let isFresh = staleness < 1.0

            let dot: CGFloat = 11
            let dotRect = CGRect(x: pLast.x - dot/2, y: pLast.y - dot/2, width: dot, height: dot)
            if isFresh {
                context.fill(Path(ellipseIn: dotRect), with: .color(color))
                context.stroke(Path(ellipseIn: dotRect.insetBy(dx: -3, dy: -3)),
                               with: .color(color.opacity(0.35)), lineWidth: 2)
            } else {
                context.stroke(Path(ellipseIn: dotRect),
                               with: .color(color.opacity(0.6)),
                               style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            }

            let label = "\(track.klass) #\(track.id)"
            context.draw(
                Text(label).font(.caption.weight(.bold)).foregroundStyle(color),
                at: CGPoint(x: pLast.x + 10, y: pLast.y - 10),
                anchor: .leading
            )
        }
    }

    private func trackColor(for id: Int) -> Color {
        let palette: [Color] = [.green, .orange, .blue, .purple, .pink, .yellow, .cyan, .mint]
        return palette[abs(id) % palette.count]
    }

    private func fittedFrame(content: CGSize, inside container: CGSize, margin: CGFloat) -> CGRect {
        let available = CGSize(
            width: max(1, container.width - margin * 2),
            height: max(1, container.height - margin * 2)
        )
        guard content.width > 0, content.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(available.width / content.width, available.height / content.height)
        let w = content.width * scale
        let h = content.height * scale
        let x = (container.width - w) / 2
        let y = (container.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

private struct TrackHistory {
    let id: Int
    var klass: String
    var points: [TrackPoint] = []
    var lastTs: Double = 0
    var lastQuality: Double = 0
}

private struct TrackPoint {
    let x: Double
    let y: Double
    let ts: Double
}

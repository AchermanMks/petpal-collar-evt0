import SwiftUI

struct LivePreviewView: View {
    @Environment(AppState.self) private var state
    private var stream: MJPEGStream { MJPEGStream.backendFeed }
    @State private var detections: [Detection] = []
    @State private var stats: Stats?
    @State private var pollTask: Task<Void, Never>?
    @State private var showStats = false

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            if let img = stream.currentFrame {
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                        DetectionOverlay(
                            detections: detections,
                            frameSize: frameSize,
                            displaySize: geo.size
                        )
                    }
                }
            } else {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.06))
                            .frame(width: 100, height: 100)
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white.opacity(0.5))
                    }
                    Text(stream.lastError ?? "连接视频流...")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Overlays
            VStack(spacing: 0) {
                topBar
                Spacer()
                if showStats {
                    statsBar
                }
            }
        }
        .navigationTitle("实时预览")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 10) {
            if stream.isReconnecting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text(stream.lastError ?? "重连中")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.orange.opacity(0.85), in: Capsule())
            } else if stream.currentFrame != nil {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("LIVE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial.opacity(0.5), in: Capsule())
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showStats.toggle() }
            } label: {
                Image(systemName: showStats ? "info.circle.fill" : "info.circle")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(8)
                    .background(.ultraThinMaterial.opacity(0.4), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 16) {
            statPill(icon: "photo.stack", value: "\(stream.framesReceived)", color: .blue)
            if let s = stats {
                statPill(icon: "cat.fill", value: "\(s.uniqueCats)", color: .green)
                statPill(icon: "dog.fill", value: "\(s.uniqueDogs)", color: .orange)
                statPill(icon: "number", value: "\(s.totalDetections)", color: .purple)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.5))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func statPill(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.2), in: Capsule())
    }

    // MARK: - Helpers

    private var frameSize: CGSize {
        if let res = state.systemInfo?.video.resolution {
            return CGSize(width: res.width, height: res.height)
        }
        return stream.currentFrame?.size ?? CGSize(width: 960, height: 540)
    }

    private func start() {
        guard let api = state.api else { return }
        stream.ensureRunning(url: api.videoFeedURL())
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let resp = try await api.detections()
                    let s = try await api.stats()
                    await MainActor.run {
                        self.detections = resp.recent
                        self.stats = s
                    }
                } catch {}
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stop() {
        pollTask?.cancel()
        pollTask = nil
    }
}

// MARK: - Detection Overlay

private struct DetectionOverlay: View {
    let detections: [Detection]
    let frameSize: CGSize
    let displaySize: CGSize

    var body: some View {
        let layout = fittedFrame(content: frameSize, inside: displaySize)
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(detections) { det in
                box(for: det, layout: layout)
            }
        }
    }

    @ViewBuilder
    private func box(for det: Detection, layout: CGRect) -> some View {
        let scaleX = layout.width / frameSize.width
        let scaleY = layout.height / frameSize.height
        let x = layout.minX + CGFloat(det.bbox[0]) * scaleX
        let y = layout.minY + CGFloat(det.bbox[1]) * scaleY
        let w = CGFloat(det.bbox[2] - det.bbox[0]) * scaleX
        let h = CGFloat(det.bbox[3] - det.bbox[1]) * scaleY

        let label = "q=\(String(format: "%.2f", det.qualityScore))"

        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(.green, style: StrokeStyle(
                    lineWidth: 2,
                    dash: det.isStale ? [6, 4] : []
                ))
                .frame(width: max(1, w), height: max(1, h))

            Text(label)
                .font(.caption2.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.85))
                .foregroundStyle(.black)
                .offset(y: -18)
        }
        .offset(x: x, y: y)
    }

    private func fittedFrame(content: CGSize, inside container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / content.width, container.height / content.height)
        let w = content.width * scale
        let h = content.height * scale
        let x = (container.width - w) / 2
        let y = (container.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

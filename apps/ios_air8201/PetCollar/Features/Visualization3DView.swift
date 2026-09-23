import SwiftUI
import UIKit
import os.log

private let dbg = Logger(subsystem: "PetCollar", category: "Viz3D")

struct Visualization3DView: View {
    @Environment(AppState.self) private var state
    @State private var image: UIImage?
    @State private var azim: Double = 45
    @State private var elev: Double = 25
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var lastParams: (Double, Double)?
    @State private var refreshTask: Task<Void, Never>?

    @State private var dragBaseAzim: Double = 45
    @State private var dragBaseElev: Double = 25
    @State private var isDragging = false
    @State private var dragRequestTask: Task<Void, Never>?

    @State private var zoom: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0

    private let autoRefreshInterval: Duration = .seconds(2)

    private struct CameraPreset: Identifiable {
        let id: String
        let name: String
        let icon: String
        let azim: Double
        let elev: Double
    }

    private let presets: [CameraPreset] = [
        .init(id: "top", name: "俯视", icon: "arrow.down.circle", azim: 0, elev: 89),
        .init(id: "front", name: "正面", icon: "arrow.right.circle", azim: 0, elev: 15),
        .init(id: "side", name: "侧面", icon: "arrow.up.right.circle", azim: 90, elev: 20),
        .init(id: "corner", name: "对角", icon: "cube", azim: 45, elev: 25),
        .init(id: "back", name: "背面", icon: "arrow.left.circle", azim: 180, elev: 20),
    ]

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            GeometryReader { geo in
                Group {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(zoom)
                            .animation(.interactiveSpring(response: 0.3), value: zoom)
                    } else {
                        emptyState
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .contentShape(Rectangle())
                .gesture(orbitGesture)
                .gesture(pinchGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.4)) {
                        zoom = 1.0
                        azim = 45; elev = 25
                    }
                    requestRefresh()
                }
            }

            // Overlay UI
            VStack(spacing: 0) {
                topOverlay
                Spacer()
                presetBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .navigationTitle("3D 空间")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.04))
                    .frame(width: 100, height: 100)
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white.opacity(0.5))
                } else {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            Text(errorText ?? "加载 3D 空间...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
            if errorText != nil {
                Button {
                    requestRefresh()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("重试")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.1)))
                }
            }
        }
    }

    // MARK: - Top Overlay

    private var topOverlay: some View {
        HStack(spacing: 10) {
            // Angle pills
            anglePill(icon: "arrow.triangle.2.circlepath", value: String(format: "%.0f°", azim), color: .blue)
            anglePill(icon: "arrow.up.and.down", value: String(format: "%.0f°", elev), color: .green)
            if zoom != 1.0 {
                anglePill(icon: "magnifyingglass", value: String(format: "%.1fx", zoom), color: .orange)
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.5))
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func anglePill(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.5), in: Capsule())
    }

    // MARK: - Preset Bar

    private var presetBar: some View {
        HStack(spacing: 6) {
            ForEach(presets) { preset in
                let active = isActivePreset(preset)
                Button {
                    withAnimation(.spring(response: 0.4)) {
                        azim = preset.azim
                        elev = preset.elev
                    }
                    requestRefresh()
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(active ? Color.blue.opacity(0.3) : Color.white.opacity(0.06))
                                .frame(width: 36, height: 36)
                            Image(systemName: preset.icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(active ? .blue : .white.opacity(0.6))
                        }
                        Text(preset.name)
                            .font(.caption2.weight(active ? .bold : .regular))
                            .foregroundStyle(active ? .blue : .white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.4), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func isActivePreset(_ preset: CameraPreset) -> Bool {
        abs(azim - preset.azim) < 5 && abs(elev - preset.elev) < 5
    }

    // MARK: - Gestures

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragBaseAzim = azim
                    dragBaseElev = elev
                }
                let sensitivity: Double = 0.3
                azim = wrap360(dragBaseAzim + value.translation.width * sensitivity)
                elev = clamp(dragBaseElev + value.translation.height * sensitivity, to: -85...85)

                dragRequestTask?.cancel()
                dragRequestTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if !Task.isCancelled {
                        await refreshNow()
                    }
                }
            }
            .onEnded { _ in
                isDragging = false
                requestRefresh()
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = clampZoom(baseZoom * value.magnification)
            }
            .onEnded { value in
                baseZoom = clampZoom(baseZoom * value.magnification)
                zoom = baseZoom
            }
    }

    private func clampZoom(_ v: CGFloat) -> CGFloat {
        min(max(v, 0.5), 3.0)
    }

    // MARK: - Networking

    private func start() {
        refreshTask?.cancel()
        refreshTask = Task {
            await refreshNow()
            while !Task.isCancelled {
                try? await Task.sleep(for: autoRefreshInterval)
                if !isDragging {
                    await refreshIfNeeded()
                }
            }
        }
    }

    private func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        dragRequestTask?.cancel()
    }

    private func requestRefresh() {
        Task { await refreshNow() }
    }

    private func refreshNow() async {
        guard let api = state.api else { return }
        let params = (roundTo1(azim), roundTo1(elev))
        await MainActor.run { isLoading = true }
        do {
            let data = try await api.visualization3DImageData(azim: params.0, elev: params.1)
            if data.isEmpty {
                await MainActor.run {
                    isLoading = false
                    errorText = "等待追踪数据..."
                }
                return
            }
            if let img = UIImage(data: data) {
                await MainActor.run {
                    image = img
                    lastParams = params
                    errorText = nil
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                    errorText = "图像解码失败"
                }
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run {
                    isLoading = false
                    errorText = friendly(error)
                }
            }
        }
    }

    private func refreshIfNeeded() async {
        let params = (roundTo1(azim), roundTo1(elev))
        if lastParams.map({ $0 == params }) == true && image != nil {
            return
        }
        await refreshNow()
    }

    // MARK: - Helpers

    private func friendly(_ err: Error) -> String {
        if let api = err as? APIClientError { return api.errorDescription ?? "\(err)" }
        if let url = err as? URLError { return url.localizedDescription }
        return "\(err)"
    }

    private func wrap360(_ v: Double) -> Double {
        var x = v.truncatingRemainder(dividingBy: 360)
        if x < 0 { x += 360 }
        return x
    }

    private func clamp(_ v: Double, to range: ClosedRange<Double>) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }

    private func roundTo1(_ v: Double) -> Double {
        (v * 10).rounded() / 10
    }
}

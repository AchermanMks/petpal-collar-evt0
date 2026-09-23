import SwiftUI
import os.log

private let dbg = Logger(subsystem: "PetCollar", category: "Detections")

struct DetectionsPanelView: View {
    @Environment(AppState.self) private var state
    @State private var detections: [Detection] = []
    @State private var task: Task<Void, Never>?

    var body: some View {
        Group {
            if detections.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        summaryBar
                        ForEach(detections) { det in
                            DetectionCard(detection: det)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("检测")
        .onAppear { start() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(PetPalTheme.blush)
                    .frame(width: 80, height: 80)
                Image(systemName: "pawprint")
                    .font(.system(size: 32))
                    .foregroundStyle(PetPalTheme.primary.opacity(0.6))
            }
            Text("暂无检测")
                .font(.headline)
                .foregroundStyle(PetPalTheme.inkPrimary)
            Text("后端还没有活跃的 track")
                .font(.callout)
                .foregroundStyle(PetPalTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryBar: some View {
        let cats = detections.filter { $0.klass == "猫" }.count
        let dogs = detections.filter { $0.klass == "狗" }.count
        return HStack(spacing: 12) {
            summaryPill(icon: "pawprint.fill", label: "总计", value: "\(detections.count)", color: .purple)
            if cats > 0 {
                summaryPill(icon: "cat.fill", label: "猫", value: "\(cats)", color: .green)
            }
            if dogs > 0 {
                summaryPill(icon: "dog.fill", label: "狗", value: "\(dogs)", color: .orange)
            }
            Spacer()
        }
    }

    private func summaryPill(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(PetPalTheme.inkPrimary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(color.opacity(0.1), in: Capsule())
    }

    private func start() {
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                if let api = state.api {
                    do {
                        let resp = try await api.detections()
                        await MainActor.run { detections = resp.recent }
                    } catch {}
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

private struct DetectionCard: View {
    let detection: Detection

    private var color: Color {
        detection.klass == "猫" ? .green : .orange
    }

    var body: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(color.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: detection.klass == "猫" ? "cat.fill" : "dog.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(color)
                        }
                        Text("\(detection.klass) \(detection.trackIdLabel)")
                            .font(.headline)
                            .foregroundStyle(PetPalTheme.inkPrimary)
                    }
                    Spacer()
                    Text("q=\(String(format: "%.2f", detection.qualityScore))")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(PetPalTheme.inkSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.gray.opacity(0.08), in: Capsule())
                }

                HStack(spacing: 16) {
                    metricItem("位置", value: String(
                        format: "(%.2f, %.2f, %.2f)",
                        detection.physicalCoords.x,
                        detection.physicalCoords.y,
                        detection.physicalCoords.z
                    ))
                    metricItem("置信", value: String(format: "%.0f%%", detection.confidence * 100))
                    metricItem("类型", value: detection.detectionType)
                }

                Text("bbox [\(detection.bbox.map(String.init).joined(separator: ", "))]")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.6))
            }
        }
    }

    private func metricItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(PetPalTheme.inkSecondary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(PetPalTheme.inkPrimary)
        }
    }
}

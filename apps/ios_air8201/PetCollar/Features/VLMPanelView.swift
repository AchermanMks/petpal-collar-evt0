import SwiftUI
import os.log

private let dbg = Logger(subsystem: "PetCollar", category: "VLM")

struct VLMPanelView: View {
    @Environment(AppState.self) private var state
    @State private var analysis: VLMAnalysis?
    @State private var lastUpdated: Date?
    @State private var history: [VLMEntry] = []
    @State private var errorText: String?
    @State private var pollTask: Task<Void, Never>?

    private let pollInterval: Duration = .seconds(2)
    private let maxHistory = 20

    var body: some View {
        Group {
            if state.systemInfo?.capabilities.vlm == false {
                ContentUnavailableView(
                    "VLM 未启用",
                    systemImage: "brain",
                    description: Text("后端未加载视觉语言模型")
                )
            } else {
                content
            }
        }
        .navigationTitle("场景分析")
        .onAppear(perform: start)
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                headerCard
                sceneCard
                behaviorCard
                if !history.isEmpty {
                    historyCard
                }
                if let errorText {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(PetPalTheme.danger)
                        Text(errorText)
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
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.mint.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 22))
                    .foregroundStyle(.mint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AI 场景分析")
                    .font(.headline)
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(PetPalTheme.inkSecondary)
            }

            Spacer()

            if analysis != nil && errorText == nil {
                ProgressView().controlSize(.small)
            }
        }
        .padding(16)
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

    private var statusLine: String {
        if let err = errorText { return "拉取失败: \(err)" }
        guard let ts = lastUpdated else { return "等待后端分析..." }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return "更新于 \(fmt.localizedString(for: ts, relativeTo: .now))"
    }

    // MARK: - Scene Card

    private var sceneCard: some View {
        analysisCard(
            title: "场景",
            icon: "photo.fill",
            color: .blue,
            text: analysis?.scene,
            placeholder: analysis?.sceneIsPlaceholder ?? true
        )
    }

    private var behaviorCard: some View {
        analysisCard(
            title: "行为",
            icon: "figure.walk.motion",
            color: .orange,
            text: analysis?.behavior,
            placeholder: analysis?.behaviorIsPlaceholder ?? true
        )
    }

    private func analysisCard(title: String, icon: String, color: Color,
                              text: String?, placeholder: Bool) -> some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(color)
                    }
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Spacer()
                    if placeholder {
                        Text("等待中")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(PetPalTheme.inkSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.gray.opacity(0.1), in: Capsule())
                    }
                }
                Text(text ?? "--")
                    .font(.body)
                    .foregroundStyle(placeholder ? PetPalTheme.inkSecondary : PetPalTheme.inkPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - History Card

    private var historyCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.purple)
                        Text("历史")
                            .font(.headline)
                            .foregroundStyle(PetPalTheme.inkPrimary)
                    }
                    Spacer()
                    Button {
                        history.removeAll()
                    } label: {
                        Text("清空")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PetPalTheme.danger)
                    }
                }

                ForEach(history) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(entry.at, format: .dateTime.hour().minute().second())
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(PetPalTheme.inkSecondary)
                            if entry.changedScene {
                                Text("场景")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.blue.opacity(0.1), in: Capsule())
                            }
                            if entry.changedBehavior {
                                Text("行为")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.orange.opacity(0.1), in: Capsule())
                            }
                        }
                        if entry.changedScene {
                            Text(entry.scene)
                                .font(.callout)
                                .foregroundStyle(PetPalTheme.inkPrimary)
                        }
                        if entry.changedBehavior {
                            Text(entry.behavior)
                                .font(.callout)
                                .foregroundStyle(PetPalTheme.inkSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    if entry.id != history.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func start() {
        guard let api = state.api else { return }
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let a = try await api.vlmAnalysis()
                    await MainActor.run { ingest(a) }
                } catch {
                    await MainActor.run { errorText = friendly(error) }
                }
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    private func ingest(_ a: VLMAnalysis) {
        errorText = nil
        let prev = analysis
        analysis = a
        lastUpdated = .now

        let sceneChanged = prev?.scene != a.scene && !a.sceneIsPlaceholder
        let behaviorChanged = prev?.behavior != a.behavior && !a.behaviorIsPlaceholder
        guard sceneChanged || behaviorChanged else { return }

        history.insert(
            VLMEntry(
                at: .now, scene: a.scene, behavior: a.behavior,
                changedScene: sceneChanged, changedBehavior: behaviorChanged
            ), at: 0
        )
        if history.count > maxHistory {
            history.removeLast(history.count - maxHistory)
        }
    }

    private func friendly(_ err: Error) -> String {
        if let api = err as? APIClientError { return api.errorDescription ?? "\(err)" }
        if let url = err as? URLError { return url.localizedDescription }
        return "\(err)"
    }
}

private struct VLMEntry: Identifiable {
    let id = UUID()
    let at: Date
    let scene: String
    let behavior: String
    let changedScene: Bool
    let changedBehavior: Bool
}

import SwiftUI

struct AlertsView: View {
    @Environment(AlertEngine.self) private var engine
    @Environment(AppState.self) private var state
    @State private var editing: AlertRule?

    var body: some View {
        @Bindable var engineBinding = engine

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if !engine.authorizationGranted {
                    permissionCard
                }
                rulesCard
                historyCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("告警")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editing = .staleTimeout()
                    } label: {
                        Label("静止超时", systemImage: "timer")
                    }
                    Button {
                        let room = state.systemInfo?.room.dimensionsM
                        let w = room?.width ?? 4
                        let h = room?.depth ?? 3
                        editing = .forbiddenZone(x: 0, y: 0, w: min(1, w), h: min(1, h))
                    } label: {
                        Label("进入禁区", systemImage: "square.dashed")
                    }
                    Button {
                        editing = .vlmKeyword()
                    } label: {
                        Label("VLM 关键词", systemImage: "text.magnifyingglass")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PetPalTheme.primary)
                }
            }
        }
        .sheet(item: $editing) { rule in
            AlertRuleEditor(
                rule: rule,
                roomSize: state.systemInfo?.room.dimensionsM,
                onSave: { updated in
                    if engine.rules.contains(where: { $0.id == updated.id }) {
                        engine.update(updated)
                    } else {
                        engine.add(updated)
                    }
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
    }

    // MARK: - Permission Card

    private var permissionCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "bell.badge")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("通知权限未开启")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PetPalTheme.inkPrimary)
                Text("开启后才能收到告警推送")
                    .font(.caption)
                    .foregroundStyle(PetPalTheme.inkSecondary)
            }

            Spacer()

            Button("开启") {
                Task { await engine.requestAuthorization() }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(.orange))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .orange.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    // MARK: - Rules Card

    private var rulesCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .foregroundStyle(.blue)
                    Text("规则")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Text("\(engine.rules.count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                    Spacer()
                }

                if engine.rules.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.dashed")
                                .font(.title2)
                                .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.4))
                            Text("点右上角 + 新增规则")
                                .font(.caption)
                                .foregroundStyle(PetPalTheme.inkSecondary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    ForEach(engine.rules) { rule in
                        ruleRow(rule)
                        if rule.id != engine.rules.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: AlertRule) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rule.enabled ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: rule.kind.iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(rule.enabled ? Color.accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(rule.enabled ? PetPalTheme.inkPrimary : PetPalTheme.inkSecondary)
                Text(rule.summary)
                    .font(.caption)
                    .foregroundStyle(PetPalTheme.inkSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in engine.toggle(rule) }
            ))
            .labelsHidden()
            .tint(PetPalTheme.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = rule }
    }

    // MARK: - History Card

    private var historyCard: some View {
        PetPalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.purple)
                    Text("触发历史")
                        .font(.headline)
                        .foregroundStyle(PetPalTheme.inkPrimary)
                    Text("\(engine.history.count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.purple.opacity(0.1), in: Capsule())
                    Spacer()
                    if !engine.history.isEmpty {
                        Button {
                            engine.clearHistory()
                        } label: {
                            Text("清空")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PetPalTheme.danger)
                        }
                    }
                }

                if engine.history.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                                .foregroundStyle(PetPalTheme.success.opacity(0.5))
                            Text("暂无触发")
                                .font(.caption)
                                .foregroundStyle(PetPalTheme.inkSecondary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    ForEach(engine.history) { ev in
                        historyRow(ev)
                        if ev.id != engine.history.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ ev: AlertEvent) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: ev.kind.iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(ev.message)
                    .font(.subheadline)
                    .foregroundStyle(PetPalTheme.inkPrimary)
                HStack(spacing: 6) {
                    Text(ev.ruleName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PetPalTheme.inkSecondary)
                    Text(ev.triggeredAt.formatted(date: .omitted, time: .standard))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(PetPalTheme.inkSecondary.opacity(0.7))
                }
            }

            Spacer()
        }
    }
}

// MARK: - Rule Editor (unchanged logic, refreshed style)

private struct AlertRuleEditor: View {
    @State var rule: AlertRule
    let roomSize: SystemInfo.Dimensions?
    let onSave: (AlertRule) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $rule.name)
                    Toggle("启用", isOn: $rule.enabled)
                        .tint(PetPalTheme.primary)
                    HStack {
                        Text("类型")
                        Spacer()
                        Text(rule.kind.displayName).foregroundStyle(.secondary)
                    }
                }

                switch rule.kind {
                case .staleTimeout:
                    Section("阈值") {
                        HStack {
                            Text("无活动秒数")
                            Spacer()
                            TextField("秒", value: $rule.thresholdSec, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        Text("track 最后一次检测后超过该时长即触发")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .forbiddenZone:
                    Section("禁区坐标（米）") {
                        doubleRow("X 起", value: $rule.zoneMinX)
                        doubleRow("Y 起", value: $rule.zoneMinY)
                        doubleRow("X 止", value: $rule.zoneMaxX)
                        doubleRow("Y 止", value: $rule.zoneMaxY)
                        if let r = roomSize {
                            Text(String(format: "房间 %.1f x %.1f m", r.width, r.depth))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                case .vlmKeyword:
                    Section("关键词") {
                        TextField("例如 进食 / 跳跃 / 呕吐", text: $rule.keyword)
                            .autocorrectionDisabled()
                        Text("在 VLM 场景+行为文本里子串命中即触发")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(rule) }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        guard !rule.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch rule.kind {
        case .staleTimeout:
            return rule.thresholdSec > 0
        case .forbiddenZone:
            return rule.zoneMaxX > rule.zoneMinX && rule.zoneMaxY > rule.zoneMinY
        case .vlmKeyword:
            return !rule.keyword.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func doubleRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }
}

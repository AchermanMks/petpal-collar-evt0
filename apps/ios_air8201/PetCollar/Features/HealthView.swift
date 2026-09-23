import SwiftUI
import Charts
import os.log

private let dbg = Logger(subsystem: "PetCollar", category: "Health")

struct HealthView: View {
    @Environment(AppState.self) private var state
    @State private var summary: FeedingSummary?
    @State private var activity: ActivitySummary?
    @State private var lastError: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var nowTick: Date = .now

    private let pollInterval: Duration = .seconds(5)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                todayCard
                statusCard
                activityCard
                if let summary, !summary.recentEvents.isEmpty {
                    eventsList(summary.recentEvents)
                } else if summary != nil {
                    emptyHint
                }
                if let lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding()
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
        }
        .navigationTitle("健康")
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    // MARK: - Cards

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("今日进食", systemImage: "fork.knife")
                .font(.headline)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(summary?.todayCount ?? 0)")
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                Text("次")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                if (summary?.todayCount ?? 0) == 0 {
                    Label("今日尚未观察到进食", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            if summary?.inProgress == true {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("正在进食").font(.subheadline.weight(.bold))
                        Text(String(format: "已持续 %.0f 秒", summary?.currentDurationSec ?? 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label {
                    Text("当前未观察到猫在进食").font(.subheadline)
                } icon: {
                    Image(systemName: "pause.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text("累计")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("\(summary?.totalCount ?? 0)")
                    .font(.title3.monospacedDigit())
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Activity Card

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("活动量", systemImage: "figure.walk")
                    .font(.headline)
                Spacer()
                Text("YOLO 位移代理（无 IMU）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 16) {
                metricBlock(
                    label: "今日累计",
                    value: String(format: "%.1f", activity?.todayMeters ?? 0),
                    unit: "m",
                    color: .blue
                )
                metricBlock(
                    label: "近 1 小时",
                    value: String(format: "%.1f", activity?.lastHourMeters ?? 0),
                    unit: "m",
                    color: .green
                )
            }

            // 柱状图：最近 12 桶（= 1 小时 @ 5min/桶）
            if let buckets = activity?.recentBuckets, !buckets.isEmpty {
                let last12 = Array(buckets.suffix(12))
                Chart(last12) { bucket in
                    BarMark(
                        x: .value("时间", bucket.start),
                        y: .value("米", bucket.meters)
                    )
                    .foregroundStyle(.green.gradient)
                    .cornerRadius(3)
                }
                .frame(height: 100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .minute, count: 15)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            } else {
                Text("还没有活动数据（等检测到猫开始运动）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func metricBlock(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value).font(.title2.monospacedDigit().weight(.bold)).foregroundStyle(color)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func eventsList(_ events: [FeedingEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近事件")
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(events.reversed()) { ev in
                HStack {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.green)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ev.start, style: .time)
                            .font(.callout.monospacedDigit())
                        Text(ev.start, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.0f 秒", ev.durationSec))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
            Text("还没有进食事件").foregroundStyle(.secondary)
            Text("摄像头看到猫和食碗 bbox 重叠持续 ≥3 秒就会记录一次")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding()
    }

    // MARK: - Polling

    private func start() {
        guard let api = state.api else {
            lastError = "未连接后端"
            return
        }
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                async let feed = api.feedingEvents()
                async let act  = api.activitySummary()
                do {
                    let (f, a) = try await (feed, act)
                    await MainActor.run {
                        self.summary = f
                        self.activity = a
                        self.lastError = nil
                        self.nowTick = .now
                    }
                } catch {
                    dbg.error("health poll: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        self.lastError = error.localizedDescription
                    }
                }
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    private func stop() {
        pollTask?.cancel()
        pollTask = nil
    }
}

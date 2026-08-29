import SwiftUI
import Charts
import FallLineCore

/// 进步曲线视图：展示周汇总折线图、里程碑徽章与关键统计。
///
/// 采用 Ice Sport Technology 主题（`AppTheme.swift`）：深空蓝底 + 冰蓝色曲线 + 玻璃拟态卡片。
struct TrendView: View {
    @ObservedObject var store: TrendStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if let report = store.lastReport, !report.weeklyPoints.isEmpty {
                    statsRow(report: report)
                    chartCard(points: report.weeklyPoints)
                    milestonesCard(report: report)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(LinearGradient.fallLineBackground.ignoresSafeArea())
        .onAppear { store.refreshReport() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("进步曲线")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(.themeTextPrimary)
            Text("按周记录你的滑雪姿态变化")
                .font(.system(size: 13))
                .foregroundColor(.themeTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statsRow(report: TrendReport) -> some View {
        HStack(spacing: 12) {
            statCard(
                title: "最高分",
                value: report.personalBest.map { "\(Int($0.rounded()))" } ?? "-"
            )
            statCard(
                title: "近 7 天均分",
                value: report.last7DaysAverage.map { String(format: "%.1f", $0) } ?? "-"
            )
            statCard(
                title: "近 30 天均分",
                value: report.last30DaysAverage.map { String(format: "%.1f", $0) } ?? "-"
            )
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.themeTextTertiary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.themeTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.themeCard.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.themeDivider, lineWidth: 0.8)
                )
        )
    }

    @ViewBuilder
    private func chartCard(points: [WeeklySummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("周均分趋势")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.themeTextPrimary)
                Spacer()
                Text("\(points.count) 周")
                    .font(.system(size: 11))
                    .foregroundColor(.themeTextTertiary)
            }

            Chart(points, id: \.weekStart) { point in
                LineMark(
                    x: .value("周", point.weekStart),
                    y: .value("均分", point.averageScore)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.fallLineCyan)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                PointMark(
                    x: .value("周", point.weekStart),
                    y: .value("均分", point.averageScore)
                )
                .foregroundStyle(Color.fallLineMint)
                .symbolSize(60)

                AreaMark(
                    x: .value("周", point.weekStart),
                    y: .value("均分", point.averageScore)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.fallLineCyan.opacity(0.28), Color.fallLineCyan.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { _ in
                    AxisGridLine().foregroundStyle(Color.themeDivider)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.themeTextTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisGridLine().foregroundStyle(Color.themeDivider.opacity(0.5))
                    AxisValueLabel(format: .dateTime.month().day(), centered: true)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.themeTextTertiary)
                }
            }
            .frame(height: 220)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.themeCard.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.themeDivider, lineWidth: 0.8)
                )
        )
    }

    @ViewBuilder
    private func milestonesCard(report: TrendReport) -> some View {
        if !report.newMilestones.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("本次新解锁")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.themeTextPrimary)
                ForEach(Array(report.newMilestones.enumerated()), id: \.offset) { _, m in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.fallLineMint)
                            .frame(width: 8, height: 8)
                        Text(m.displayTitle)
                            .font(.system(size: 13))
                            .foregroundColor(.themeTextPrimary)
                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.themeCard.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.fallLineMint.opacity(0.3), lineWidth: 0.8)
                    )
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44, weight: .thin))
                .foregroundColor(.themeTextTertiary)
            Text("暂无进步曲线")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.themeTextPrimary)
            Text("完成第一次视频分析后，这里会显示你的周均分趋势与里程碑")
                .font(.system(size: 12))
                .foregroundColor(.themeTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 60)
    }
}

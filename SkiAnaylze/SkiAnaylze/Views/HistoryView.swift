import SwiftUI
import FallLineCore

struct HistoryView: View {
    @EnvironmentObject var manager: VideoAnalysisManager
    @State private var selectedOutput: AnalysisOutput?

    var body: some View {
        NavigationStack {
            ZStack {
                FallLineBackground()
                Group {
                    if manager.historyURLs.isEmpty {
                        emptyState
                    } else {
                        historyList
                    }
                }
            }
            .navigationTitle("训练记录")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedOutput) { output in
                ReportDetailView(output: output)
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "figure.skiing.downhill")
                .font(.system(size: 50, weight: .bold))
                .foregroundColor(.themePrimary)

            Text("还没有训练记录")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.themeTextPrimary)

            Text("完成一次视频分析后，这里会显示你的分数、主要问题和训练进展。")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.themeTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
        }
        .padding(40)
    }

    // MARK: - 历史列表

    private var historyList: some View {
        List {
            ForEach(Array(manager.historyURLs.enumerated()), id: \.element) { index, url in
                historyRow(url: url, index: index)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onTapGesture {
                        if let output = manager.output(for: url) {
                            selectedOutput = output
                        }
                    }
            }
            .onDelete { indexSet in
                manager.removeHistory(at: indexSet)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 历史记录行

    private func historyRow(url: URL, index: Int) -> some View {
        let output = manager.output(for: url)
        let dateText = formattedDate(for: index)
        let score = output?.summary.averageScore ?? 0
        let stage = output?.summary.overallLevel ?? "未知"

        return HStack(spacing: 14) {
            ScoreRing(score: score, size: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(url.lastPathComponent)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.themeTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(stage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.fallLineNight)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.scoreColor(score), in: Capsule())

                    Text(dateText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.themeTextTertiary)
                }

                if let output = output {
                    Text("主要问题：\(mainIssueSummary(from: output))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.themeTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(.themeTextTertiary)
        }
        .padding(14)
        .background(Color.fallLineSnow.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.fallLineSnow.opacity(0.10), lineWidth: 1)
        )
    }

    private func mainIssueSummary(from output: AnalysisOutput) -> String {
        let report = ReportGenerator.generate(output: output)
        // 简单提取第一个问题
        for line in report.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("1.") || trimmed.hasPrefix("2.") {
                return trimmed
                    .replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
            }
        }
        return "无突出问题"
    }

    private func formattedDate(for index: Int) -> String {
        // 简单模拟，实际应该从文件元数据读取
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: -index, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

#Preview {
    HistoryView()
        .environmentObject(VideoAnalysisManager.shared)
        .preferredColorScheme(.dark)
}

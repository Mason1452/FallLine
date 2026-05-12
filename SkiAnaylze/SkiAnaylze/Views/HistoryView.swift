import SwiftUI
//import FallLineCore

struct HistoryView: View {
    @EnvironmentObject var manager: VideoAnalysisManager
    @State private var selectedOutput: AnalysisOutput?

    var body: some View {
        NavigationStack {
            Group {
                if manager.historyURLs.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .background(Color.themeBackground.ignoresSafeArea())
            .navigationTitle("历史报告")
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

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.themeTextTertiary)

            Text("暂无历史报告")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.themeTextPrimary)

            Text("完成一次视频分析后，\n报告会出现在这里")
                .font(.system(size: 14))
                .foregroundColor(.themeTextTertiary)
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
                for index in indexSet {
                    if index < manager.historyURLs.count {
                        manager.historyURLs.remove(at: index)
                    }
                }
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
            // 分数圆环
            ZStack {
                Circle()
                    .stroke(Color.themeTextTertiary.opacity(0.2), lineWidth: 3)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: CGFloat(score / 100))
                    .stroke(Color.scoreColor(score), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(score.rounded()))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.scoreColor(score))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.themeTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(stage)
                        .font(.system(size: 12))
                        .foregroundColor(.themePrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.themePrimary.opacity(0.12))
                        .cornerRadius(4)

                    Text(dateText)
                        .font(.system(size: 12))
                        .foregroundColor(.themeTextTertiary)
                }

                if let output = output {
                    Text("主要问题：\(mainIssueSummary(from: output))")
                        .font(.system(size: 12))
                        .foregroundColor(.themeTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.themeTextTertiary)
        }
        .padding(14)
        .background(Color.themeCard)
        .cornerRadius(12)
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

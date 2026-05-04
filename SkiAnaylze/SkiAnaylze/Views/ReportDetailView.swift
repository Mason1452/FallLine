import SwiftUI
import AVKit
//import VideoVisionCore

struct ReportDetailView: View {
    let output: AnalysisOutput

    @Environment(\.dismiss) var dismiss
    @State private var player: AVPlayer?
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. 视频播放器
                    videoPlayerSection

                    // 2. 综合评分卡
                    scoreCardSection

                    // 3. 教练观察
                    if !coachObservation.isEmpty {
                        coachObservationSection
                    }

                    // 4. 关键时刻
                    if !output.keyMoments.isEmpty {
                        keyMomentsSection
                    }

                    // 5. 滑雪维度评分
                    skiMetricsSection

                    // 6. 主要问题
                    mainIssuesSection

                    // 7. 训练建议
                    trainingSuggestionSection

                    // 8. 分享按钮
                    shareButton

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color.themeBackground.ignoresSafeArea())
            .navigationTitle("分析报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(.themeTextSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        generateShareImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.themePrimary)
                    }
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
    }

    // MARK: - 设置播放器

    private func setupPlayer() {
        let videoURL = URL(fileURLWithPath: output.videoPath)
        if FileManager.default.fileExists(atPath: videoURL.path) {
            player = AVPlayer(url: videoURL)
        }
    }

    // MARK: - 1. 视频播放器

    private var videoPlayerSection: some View {
        VStack(spacing: 8) {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(12)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.themeCard)
                        .aspectRatio(16/9, contentMode: .fit)

                    VStack(spacing: 8) {
                        Image(systemName: "play.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.themeTextTertiary)
                        Text("视频文件未找到")
                            .font(.system(size: 14))
                            .foregroundColor(.themeTextTertiary)
                    }
                }
            }

            // 进度条
            if !output.keyMoments.isEmpty {
                momentTimeline
            }
        }
    }

    // MARK: - 关键时刻时间线

    private var momentTimeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(output.keyMoments, id: \.seconds) { moment in
                    Button {
                        seekTo(seconds: moment.seconds)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: moment.type.contains("best") ? "star.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(moment.type.contains("best") ? .themeSuccess : .themeWarning)
                            Text(moment.time)
                                .font(.system(size: 12, weight: .medium))
                            Text(moment.title)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            moment.type.contains("best")
                                ? Color.themeSuccess.opacity(0.15)
                                : Color.themeWarning.opacity(0.15)
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    moment.type.contains("best")
                                        ? Color.themeSuccess.opacity(0.3)
                                        : Color.themeWarning.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func seekTo(seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        player?.play()
    }

    // MARK: - 2. 综合评分卡

    private var scoreCardSection: some View {
        let score = output.summary.averageScore
        return VStack(spacing: 16) {
            // 大分数
            VStack(spacing: 4) {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(Color.scoreColor(score))

                Text("/ 100")
                    .font(.system(size: 18))
                    .foregroundColor(.themeTextTertiary)
            }

            // 阶段
            Text(output.summary.overallLevel)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.themeTextPrimary)

            // 阶段描述
            Text(stageDescription)
                .font(.system(size: 14))
                .foregroundColor(.themeTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .card()
    }

    // MARK: - 3. 教练观察

    private var coachObservation: String {
        let report = ReportGenerator.generate(output: output)
        // 提取教练观察段落（以🗣开头的行为止）
        let lines = report.components(separatedBy: .newlines)
        var inSection = false
        var text = ""
        for line in lines {
            if line.contains("🗣") || line.contains("教练观察") {
                inSection = true
                continue
            }
            if inSection {
                if line.hasPrefix("#") || line.hasPrefix("##") || line.isEmpty {
                    if !text.isEmpty { break }
                }
                text += line + "\n"
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var coachObservationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("教练观察", systemImage: "person.fill.questionmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.themePrimary)

            Text(coachObservation)
                .font(.system(size: 14))
                .foregroundColor(.themeTextSecondary)
                .lineSpacing(4)
        }
        .card()
    }

    // MARK: - 4. 关键时刻

    private var keyMomentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("关键时刻", systemImage: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.themePrimary)

            ForEach(output.keyMoments, id: \.seconds) { moment in
                Button {
                    seekTo(seconds: moment.seconds)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        // 缩略图占位
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.themeCardSecondary)
                                .frame(width: 60, height: 45)

                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundColor(.themePrimary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: moment.type.contains("best") ? "star.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(moment.type.contains("best") ? .themeSuccess : .themeWarning)

                                Text(moment.time)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.themeTextPrimary)

                                Text(moment.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(moment.type.contains("best") ? .themeSuccess : .themeWarning)
                            }

                            Text(moment.description)
                                .font(.system(size: 12))
                                .foregroundColor(.themeTextTertiary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.themeTextTertiary)
                    }
                    .padding(12)
                    .background(Color.themeCardSecondary)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    // MARK: - 5. 滑雪维度评分

    private var skiMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("滑雪维度", systemImage: "figure.skiing")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.themePrimary)

            ScoreBar(
                label: "走刃质量",
                score: output.skiMetrics.edgeQualityScore,
                color: Color.scoreColor(output.skiMetrics.edgeQualityScore)
            )

            ScoreBar(
                label: "板压支撑",
                score: output.skiMetrics.pressureSupportScore,
                color: Color.scoreColor(output.skiMetrics.pressureSupportScore)
            )

            ScoreBar(
                label: "前后支撑",
                score: output.skiMetrics.foreAftSupportScore,
                color: Color.scoreColor(output.skiMetrics.foreAftSupportScore)
            )

            // 稳定性
            ScoreBar(
                label: "动作稳定性",
                score: output.summary.stabilityScore,
                color: Color.scoreColor(output.summary.stabilityScore)
            )

            // 左右一致性
            if let firstFrame = output.frames.first?.poseScore {
                ScoreBar(
                    label: "左右一致性",
                    score: firstFrame.symmetryScore,
                    color: Color.scoreColor(firstFrame.symmetryScore)
                )
            }
        }
        .card()
    }

    // MARK: - 6. 主要问题

    private var mainIssues: [String] {
        let report = ReportGenerator.generate(output: output)
        let lines = report.components(separatedBy: .newlines)
        var inIssues = false
        var issues: [String] = []
        for line in lines {
            if line.contains("主要问题") || line.contains("问题") && line.contains("#") {
                inIssues = true
                continue
            }
            if inIssues {
                if line.hasPrefix("#") || line.hasPrefix("##") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !issues.isEmpty { break }
                }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
                if !trimmed.isEmpty {
                    issues.append(trimmed)
                }
            }
        }
        return Array(issues.prefix(3))
    }

    private var mainIssuesSection: some View {
        let issues = mainIssues
        guard !issues.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Label("主要问题", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.themeProblem)

                ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.themeProblem)
                        Text(issue)
                            .font(.system(size: 14))
                            .foregroundColor(.themeTextSecondary)
                            .lineSpacing(3)
                    }
                }
            }
            .card()
        )
    }

    // MARK: - 7. 训练建议

    private var trainingSuggestion: String {
        let report = ReportGenerator.generate(output: output)
        let lines = report.components(separatedBy: .newlines)
        var inSection = false
        var text = ""
        for line in lines {
            if line.contains("训练建议") || line.contains("下一次训练") {
                inSection = true
                continue
            }
            if inSection {
                if line.hasPrefix("#") || line.hasPrefix("##") {
                    if !text.isEmpty { break }
                }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    text += trimmed + "\n"
                }
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trainingSuggestionSection: some View {
        let suggestion = trainingSuggestion
        guard !suggestion.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Label("训练建议", systemImage: "target")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.themeSuccess)

                Text(suggestion)
                    .font(.system(size: 14))
                    .foregroundColor(.themeTextSecondary)
                    .lineSpacing(4)

                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.caption)
                        Text("查看这个练习怎么做")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.themePrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Color.themePrimary.opacity(0.12))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .card()
        )
    }

    // MARK: - 8. 分享按钮

    private var shareButton: some View {
        Button {
            generateShareImage()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                Text("分享报告图片")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.themePrimary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 生成分享图片

    private func generateShareImage() {
        // 用简单的文字图片代替
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 690))
        let image = renderer.image { ctx in
            let c = ctx.cgContext
            // 背景
            UIColor(Color.themeBackground).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 390, height: 690))

            // 标题
            let title = "我的滑雪动作分析"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor(Color.themeTextPrimary)
            ]
            title.draw(at: CGPoint(x: 24, y: 40), withAttributes: attrs)

            // 分数
            let score = "\(Int(output.summary.averageScore.rounded()))"
            let scoreAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 56),
                .foregroundColor: UIColor(Color.scoreColor(output.summary.averageScore))
            ]
            score.draw(at: CGPoint(x: 24, y: 80), withAttributes: scoreAttrs)

            // 阶段
            let stage = output.summary.overallLevel
            let stageAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor(Color.themeTextPrimary)
            ]
            stage.draw(at: CGPoint(x: 24, y: 140), withAttributes: stageAttrs)

            // 滑雪维度
            var y: CGFloat = 200
            let dimAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor(Color.themeTextSecondary)
            ]
            let dims = [
                ("走刃质量", output.skiMetrics.edgeQualityScore),
                ("板压支撑", output.skiMetrics.pressureSupportScore),
                ("前后支撑", output.skiMetrics.foreAftSupportScore)
            ]
            for (name, val) in dims {
                let text = "\(name): \(Int(val.rounded()))"
                text.draw(at: CGPoint(x: 24, y: y), withAttributes: dimAttrs)
                y += 24
            }

            // 主要问题
            y += 16
            let issues = mainIssues
            if !issues.isEmpty {
                "主要问题：".draw(at: CGPoint(x: 24, y: y), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor(Color.themeProblem)
                ])
                y += 24
                for issue in issues {
                    issue.draw(at: CGPoint(x: 24, y: y), withAttributes: dimAttrs)
                    y += 22
                }
            }

            // 底部
            "VideoVision 生成".draw(at: CGPoint(x: 24, y: 640), withAttributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor(Color.themeTextTertiary)
            ])
        }
        shareImage = image
        showShareSheet = true
    }

    // MARK: - 阶段描述

    private var stageDescription: String {
        let score = output.summary.averageScore
        switch score {
        case 0..<30:  return "姿态或检测信息不足，需要检查基础站姿"
        case 30..<45: return "能控制速度，但动作质量比较基础"
        case 45..<60: return "能稳定滑下来，转弯依赖搓雪而不是走刃"
        case 60..<75: return "有走刃倾向，部分弯能看到刻滑雏形"
        case 75..<90: return "姿态、稳定性和立刃质量都较好，动作干净"
        default:      return "从姿态指标看非常优秀，动作控制力强"
        }
    }
}

// MARK: - 分享 Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let output = AnalysisOutput(
        videoPath: "/path/to/video.mp4",
        duration: 23,
        totalFrames: 24,
        frames: [],
        summary: VideoSummary(
            averageScore: 63,
            bestFrame: FrameScore(time: 14, timeString: "00:14", score: 78),
            worstFrame: FrameScore(time: 2, timeString: "00:02", score: 45),
            stabilityScore: 72,
            scoreConsistencyScore: 68,
            scoreStdDev: 8.5,
            overallLevel: "稳定滑行阶段"
        ),
        skiMetrics: SkiDerivedMetrics(
            edgeQualityScore: 40,
            edgeQualityLabel: "有立刃尝试",
            pressureSupportScore: 64,
            pressureSupportLabel: "支撑尚可",
            foreAftSupportScore: 79,
            foreAftSupportLabel: "前后支撑尚可"
        ),
        keyMoments: [
            KeyMoment(time: "00:00", seconds: 0, type: "weak_edge", title: "走刃质量偏弱",
                      description: "这一帧立刃幅度和重心条件都偏弱，转弯更像扫雪。", score: 35),
            KeyMoment(time: "00:14", seconds: 14, type: "best_edge", title: "相对较好的走刃时刻",
                      description: "这一帧立刃条件相对较好，可以作为练习参考。", score: 78)
        ]
    )
    ReportDetailView(output: output)
        .preferredColorScheme(.dark)
}

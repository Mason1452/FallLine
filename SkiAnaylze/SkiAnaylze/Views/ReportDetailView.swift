import SwiftUI
import AVKit
//import FallLineCore

struct ReportDetailView: View {
    let output: AnalysisOutput

    @Environment(\.dismiss) var dismiss
    @State private var player: AVPlayer?
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                FallLineBackground(showTrace: false)

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
            }
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
        VStack(spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(9/16, contentMode: .fit)
                } else {
                    missingVideoFallback
                }

                if let bestMoment = output.keyMoments.first {
                    GlassPanel(padding: 10) {
                        HStack {
                            Text(bestMoment.time)
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(.themePrimary)
                            Text(bestMoment.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.themeTextPrimary)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.fallLineSnow.opacity(0.14), lineWidth: 1)
            )

            // 进度条
            if !output.keyMoments.isEmpty {
                momentTimeline
            }
        }
    }

    private var missingVideoFallback: some View {
        ZStack {
            LinearGradient(
                colors: [.fallLinePanel, .fallLineNavy],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                Image(systemName: "play.slash")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.themeTextTertiary)
                Text("视频文件未找到")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.themeTextTertiary)
            }
        }
        .aspectRatio(9/16, contentMode: .fit)
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
        return GlassPanel {
            HStack(spacing: 16) {
                ScoreRing(score: score, size: 96)
                VStack(alignment: .leading, spacing: 10) {
                    Text(output.summary.overallLevel)
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.themeTextPrimary)
                    Text(stageDescription)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.themeTextSecondary)
                        .lineLimit(3)
                    MetricBar(
                        label: "动作稳定性",
                        score: output.summary.stabilityScore,
                        color: Color.scoreColor(output.summary.stabilityScore)
                    )
                }
            }
        }
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
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label("教练观察", systemImage: "person.fill.questionmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.themePrimary)

                Text(coachObservation)
                    .font(.system(size: 14))
                    .foregroundColor(.themeTextSecondary)
                    .lineSpacing(4)
            }
        }
    }

    // MARK: - 4. 关键时刻

    private var keyMomentsSection: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("关键时刻", systemImage: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.themePrimary)

                ForEach(output.keyMoments, id: \.seconds) { moment in
                    Button {
                        seekTo(seconds: moment.seconds)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.fallLineIce.opacity(0.8), .fallLineBlue.opacity(0.5), .fallLinePanel],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 66, height: 48)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.caption)
                                        .foregroundColor(.fallLineNight)
                                )

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
                        .background(Color.fallLineSnow.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 5. 滑雪维度评分

    private var skiMetricsSection: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("滑雪维度", systemImage: "figure.skiing.downhill")
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
        }
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
            GlassPanel {
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
            }
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
            GlassPanel {
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
            }
        )
    }

    // MARK: - 8. 分享按钮

    private var shareButton: some View {
        Button {
            generateShareImage()
        } label: {
            PrimaryIceButtonLabel(title: "分享报告图片", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
    }

    // MARK: - 生成分享图片

    private func generateShareImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 690))
        let image = renderer.image { ctx in
            let c = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: 390, height: 690)

            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(Color.fallLineNavy).cgColor,
                    UIColor(Color.fallLineNight).cgColor
                ] as CFArray,
                locations: [0, 1]
            )
            if let gradient {
                c.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.minX, y: rect.minY),
                    end: CGPoint(x: rect.maxX, y: rect.maxY),
                    options: []
                )
            }

            UIColor(Color.fallLineCyan.opacity(0.45)).setStroke()
            c.setLineWidth(3)
            c.move(to: CGPoint(x: 330, y: 120))
            c.addCurve(
                to: CGPoint(x: 230, y: 520),
                control1: CGPoint(x: 420, y: 250),
                control2: CGPoint(x: 120, y: 360)
            )
            c.strokePath()

            "FallLine Report".draw(at: CGPoint(x: 28, y: 48), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor(Color.fallLineSnow)
            ])

            "Carve\nSharper.".draw(with: CGRect(x: 28, y: 88, width: 280, height: 112), options: [.usesLineFragmentOrigin], attributes: [
                .font: UIFont.boldSystemFont(ofSize: 42),
                .foregroundColor: UIColor(Color.themeTextPrimary)
            ], context: nil)

            "\(Int(output.summary.averageScore.rounded()))".draw(at: CGPoint(x: 28, y: 250), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 92),
                .foregroundColor: UIColor(Color.themeTextPrimary)
            ])

            output.summary.overallLevel.draw(at: CGPoint(x: 34, y: 348), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor(Color.fallLineCyan)
            ])

            let dims = [
                "走刃质量  \(Int(output.skiMetrics.edgeQualityScore.rounded()))",
                "板压支撑  \(Int(output.skiMetrics.pressureSupportScore.rounded()))",
                "动作稳定  \(Int(output.summary.stabilityScore.rounded()))"
            ]
            var y: CGFloat = 414
            for dim in dims {
                dim.draw(at: CGPoint(x: 34, y: y), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 17),
                    .foregroundColor: UIColor(Color.fallLineSnow)
                ])
                y += 34
            }

            "AI Ski Motion Coach".draw(at: CGPoint(x: 28, y: 630), withAttributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
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

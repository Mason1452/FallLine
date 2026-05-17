import Foundation
import AVFoundation
import FallLineCore

struct CLIOptions {
    let videoPath: String
    let debugOverlay: Bool
    let debugOverlayDirectory: String?
    let outputVideo: Bool
}

func printUsage() {
    print("用法: swift run FallLineCLI <视频路径>")
    print("  例: swift run FallLineCLI 1.MP4")
    print("  调试覆盖图: swift run FallLineCLI --debug-overlay 1.MP4")
    print("  指定输出目录: swift run FallLineCLI --debug-overlay --debug-overlay-dir /tmp/debug_frames 1.MP4")
    print("  输出标注视频: swift run FallLineCLI --output-video 1.MP4")
}

func parseOptions(arguments: [String]) -> CLIOptions? {
    var videoPath: String?
    var debugOverlay = false
    var debugOverlayDirectory: String?
    var outputVideo = false

    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-h", "--help":
            return nil
        case "--debug-overlay":
            debugOverlay = true
        case "--debug-overlay-dir":
            let nextIndex = index + 1
            guard nextIndex < arguments.count else { return nil }
            debugOverlayDirectory = arguments[nextIndex]
            index = nextIndex
        case "--output-video":
            outputVideo = true
        default:
            guard !argument.hasPrefix("--"), videoPath == nil else { return nil }
            videoPath = argument
        }
        index += 1
    }

    guard let videoPath else { return nil }
    return CLIOptions(
        videoPath: videoPath,
        debugOverlay: debugOverlay,
        debugOverlayDirectory: debugOverlayDirectory,
        outputVideo: outputVideo
    )
}

guard let options = parseOptions(arguments: CommandLine.arguments) else {
    printUsage()
    exit(1)
}

let videoPath = options.videoPath

let separator = String(repeating: "=", count: 50)
print(separator)
print("  🎬 FallLine - Apple Vision 视频分析工具")
print("  📌 专注滑雪姿态分析")
print(separator)
print()

do {
    let videoURL = URL(fileURLWithPath: videoPath)
    let analyzer = VideoAnalyzer(videoURL: videoURL)
    let duration = try await analyzer.asset.load(.duration)
    let totalSeconds = CMTimeGetSeconds(duration)
    let results = try await analyzer.analyze()

    // 生成基础姿态评分
    let summary = await analyzer.generateSummary(from: results)
    let outputSummary = summary ?? VideoSummary(
        averageScore: 0,
        bestFrame: FrameScore(time: 0, timeString: "00:00", score: 0),
        worstFrame: FrameScore(time: 0, timeString: "00:00", score: 0),
        stabilityScore: 0,
        scoreConsistencyScore: 0,
        scoreStdDev: 0,
        overallLevel: "未检测到人体"
    )

    // 补充 skiMetrics 到每一帧
    let stability = outputSummary.stabilityScore
    let stabilityConfidence = min(1.0, Double(reliablePoseScores(from: results).count) / 5.0)
    let framesWithMetrics = results.map { frame -> DetectionResult in
        var f = frame
        if let score = frame.poseScore {
            let sm = SkiMetricsCalculator.compute(
                from: score,
                stability: stability,
                stabilityConfidence: stabilityConfidence
            )
            f.skiMetrics = sm
        }
        return f
    }

    // 全视频平均滑雪指标
    let avgSkiMetrics = SkiMetricsCalculator.average(from: framesWithMetrics, stability: stability)

    // 关键时刻、高光片段、板身方向、转弯阶段四者独立，并发执行
    async let keyMoments = KeyMomentDetector.detect(
        from: framesWithMetrics,
        duration: totalSeconds,
        summary: outputSummary
    )

    async let highlightMoments = HighlightMomentDetector.detect(
        from: framesWithMetrics,
        summary: outputSummary
    )

    async let boardAnalysis = BoardDirectionAnalyzer.analyze(frames: framesWithMetrics)

    async let turnAnalysis = TurnPhaseDetector.analyze(frames: framesWithMetrics)

    let (km, hm, ba, ta) = await (keyMoments, highlightMoments, boardAnalysis, turnAnalysis)

    // 重心阶段适配依赖转弯阶段分析结果
    let centerOfMassAnalysis = CenterOfMassFitCalculator.analyze(
        frames: framesWithMetrics,
        summary: outputSummary,
        turnAnalysis: ta
    )

    // 构建完整输出
    let output = AnalysisOutput(
        videoPath: videoPath,
        duration: totalSeconds,
        totalFrames: results.count,
        frames: framesWithMetrics,
        summary: outputSummary,
        skiMetrics: avgSkiMetrics,
        keyMoments: km,
        highlightMoments: hm,
        centerOfMassAnalysis: centerOfMassAnalysis,
        boardAnalysis: ba,
        turnAnalysis: ta
    )

    // 输出到同名 JSON 文件（视频同目录）
    let videoURL2 = URL(fileURLWithPath: videoPath)
    let jsonPath = videoURL2
        .deletingPathExtension()
        .appendingPathExtension("json")
        .path

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let jsonData = try? encoder.encode(output) {
        try jsonData.write(to: URL(fileURLWithPath: jsonPath))
        print("\n✅ 结果已保存至: \(jsonPath)")
    }

    // 生成自然语言报告
    let report = ReportGenerator.generate(output: output)

    // 将报告保存为同目录 .md 文件
    let mdPath = videoURL2
        .deletingPathExtension()
        .appendingPathExtension("md")
        .path
    try report.write(to: URL(fileURLWithPath: mdPath), atomically: true, encoding: String.Encoding.utf8)
    print("✅ 报告已保存至: \(mdPath)")

    if options.debugOverlay {
        let overlayDirectory = options.debugOverlayDirectory.map { URL(fileURLWithPath: $0) }
        let overlayResult = try await DebugOverlayRenderer.renderFrameOverlays(
            videoURL: videoURL,
            analysis: output,
            outputDirectory: overlayDirectory
        )
        print("✅ 调试覆盖图已保存至: \(overlayResult.outputDirectory.path)")
        print("   帧数: \(overlayResult.frameCount) · manifest: \(overlayResult.manifestURL.path)")
    }
    print()

    // 打印到控制台
    print(report)

} catch {
    print("❌ 错误: \(error.localizedDescription)")
    print()
    printUsage()
    exit(1)
}

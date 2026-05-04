import Foundation
import AVFoundation
import VideoVisionCore

let arguments = CommandLine.arguments

guard arguments.count >= 2 else {
    print("用法: swift run VideoVision <视频路径>")
    print("  例: swift run VideoVision 1.MP4")
    exit(1)
}

let videoPath = arguments[1]

let separator = String(repeating: "=", count: 50)
print(separator)
print("  🎬 VideoVision - Apple Vision 视频分析工具")
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
    let summary = analyzer.generateSummary(from: results)
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

    // 关键时刻
    let keyMoments = KeyMomentDetector.detect(
        from: framesWithMetrics,
        duration: totalSeconds,
        summary: outputSummary
    )

    // 高光片段
    let highlightMoments = HighlightMomentDetector.detect(
        from: framesWithMetrics,
        summary: outputSummary
    )

    // 板身方向与横滑分析
    let boardAnalysis = BoardDirectionAnalyzer.analyze(frames: framesWithMetrics)

    // 转弯阶段分析
    let turnAnalysis = TurnPhaseDetector.analyze(frames: framesWithMetrics)

    // 重心阶段适配分析
    let centerOfMassAnalysis = CenterOfMassFitCalculator.analyze(
        frames: framesWithMetrics,
        summary: outputSummary,
        turnAnalysis: turnAnalysis
    )

    // 构建完整输出
    let output = AnalysisOutput(
        videoPath: videoPath,
        duration: totalSeconds,
        totalFrames: results.count,
        frames: framesWithMetrics,
        summary: outputSummary,
        skiMetrics: avgSkiMetrics,
        keyMoments: keyMoments,
        highlightMoments: highlightMoments,
        centerOfMassAnalysis: centerOfMassAnalysis,
        boardAnalysis: boardAnalysis,
        turnAnalysis: turnAnalysis
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
    print()

    // 打印到控制台
    print(report)

} catch {
    print("❌ 错误: \(error.localizedDescription)")
    print()
    print("用法: swift run VideoVision <视频路径>")
    exit(1)
}

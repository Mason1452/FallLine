import AVFoundation
import CoreMedia
import CoreImage
//import AppKit

// MARK: - 视频分析器

/// 负责视频抽帧、组装分析流程、生成全视频总结
///
/// 使用 `VisionFrameAnalyzer` → `PoseMetricsCalculator` → `PoseScorer` 的管线
class VideoAnalyzer {
    let videoURL: URL
    let asset: AVAsset

    // 分析管线
    private let frameAnalyzer: VisionFrameAnalyzer
    private let metricsCalculator: PoseMetricsCalculator
    private let poseScorer: PoseScorer

    init(videoPath: String) throws {
        self.videoURL = URL(fileURLWithPath: videoPath)
        self.asset = AVAsset(url: videoURL)

        guard FileManager.default.fileExists(atPath: videoPath) else {
            throw NSError(domain: "VideoAnalyzer", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "视频文件不存在: \(videoPath)"])
        }

        self.frameAnalyzer = VisionFrameAnalyzer()
        self.metricsCalculator = PoseMetricsCalculator(pointConfidenceThreshold: 0.3)
        self.poseScorer = PoseScorer()
    }

    // MARK: - 主分析流程

    /// 分析视频，每秒分析一帧
    /// - Parameter progressHandler: 进度回调（0.0~1.0）
    /// - Returns: 每帧的检测结果数组
    func analyze(progressHandler: ((Double) -> Void)? = nil) async throws -> [DetectionResult] {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw NSError(domain: "VideoAnalyzer", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "视频中没有视频轨道"])
        }

        let duration = try await asset.load(.duration)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let totalSeconds = CMTimeGetSeconds(duration)
        let naturalSize = try await videoTrack.load(.naturalSize)

        print("📹 视频信息:")
        print("   - 时长: \(formatTime(seconds: totalSeconds))")
        print("   - 帧率: \(Int(frameRate)) fps")
        print("   - 分辨率: \(Int(naturalSize.width)) x \(Int(naturalSize.height))")
        print()

        let sampleInterval: Double = 1.0
        var results: [DetectionResult] = []

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 1920, height: 1080)

        print("🔍 开始分析视频...")

        var currentTime: Double = 0.0
        while currentTime < totalSeconds {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)

            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let result = try await analyzeFrame(cgImage: cgImage, at: time)
                results.append(result)
                printResult(result)
            } catch {
                print("  ⚠️ 时间 \(formatTime(seconds: currentTime)) 分析失败: \(error.localizedDescription)")
            }

            currentTime += sampleInterval
            let progress = min(currentTime / totalSeconds, 1.0)
            progressHandler?(progress)
        }

        print("\n✅ 分析完成！共分析 \(results.count) 帧")
        return results
    }

    // MARK: - 单帧分析

    /// 分析单帧图像
    private func analyzeFrame(cgImage: CGImage, at time: CMTime) async throws -> DetectionResult {
        // Step 1: Vision 请求
        let raw = try await frameAnalyzer.analyze(cgImage: cgImage)

        // Step 2: 提取检测结果
        var objects: [ObjectItem] = []
        for human in raw.humanDetections {
            objects.append(ObjectItem(label: "人", confidence: human.confidence))
        }

        // 人脸检测
        var faces: [FaceItem] = []
        for face in raw.faceDetections {
            faces.append(FaceItem(
                x: Double(face.boundingBox.origin.x),
                y: Double(face.boundingBox.origin.y),
                width: Double(face.boundingBox.width),
                height: Double(face.boundingBox.height)
            ))
        }

        // 文字识别
        var textObservations: [String] = []
        for observation in raw.textObservations {
            if let text = observation.topCandidates(1).first?.string, text.count > 2 {
                textObservations.append(text)
            }
        }

        // 场景分类
        let sceneClassifications: [SceneItem] = raw.sceneClassifications
            .filter { $0.confidence > 0.3 }
            .map { SceneItem(label: $0.identifier, confidence: $0.confidence) }

        // Step 3: 姿态指标计算
        let bodyPose: BodyPoseData
        if let observation = raw.bodyPoseObservation {
            bodyPose = metricsCalculator.compute(from: observation)
        } else {
            bodyPose = BodyPoseData(
                detected: false,
                visibility: .none,
                bodyLeanAngle: nil,
                leftBodyLeanAngle: nil,
                rightBodyLeanAngle: nil,
                leftKneeBendAngle: nil,
                rightKneeBendAngle: nil,
                leftCalfLeanAngle: nil,
                rightCalfLeanAngle: nil,
                centerOfGravity: nil
            )
        }

        // Step 4: 评分
        let poseScore = poseScorer.score(pose: bodyPose)

        return DetectionResult(
            time: CMTimeGetSeconds(time),
            objects: objects,
            faces: faces,
            textObservations: textObservations,
            sceneClassifications: sceneClassifications,
            bodyPose: bodyPose,
            poseScore: poseScore
        )
    }

    // MARK: - 全视频总结

    /// 根据所有帧的分析结果生成全视频总结
    func generateSummary(from results: [DetectionResult]) -> VideoSummary? {
        let scores = results.compactMap { $0.poseScore?.totalScore }
        guard !scores.isEmpty else { return nil }

        let avg = scores.reduce(0, +) / Double(scores.count)
        let sumSq = scores.map { pow($0 - avg, 2) }.reduce(0, +)
        let std = sqrt(sumSq / Double(scores.count))
        // 总分一致性只解释评分波动，不代表真实动作稳定性。
        let scoreConsistencyScore = clamp(100 - std * 10, lower: 0, upper: 100)
        let stabilityScore = calculateMotionStability(from: results)

        // 找最佳/最差帧
        var best = (time: 0.0, score: -1.0)
        var worst = (time: 0.0, score: 101.0)

        for result in results {
            if let s = result.poseScore?.totalScore {
                if s > best.score { best = (result.time, s) }
                if s < worst.score { worst = (result.time, s) }
            }
        }

        let overallLevel: String = {
            switch avg {
            case 85...100: return "专业"
            case 75..<85:  return "高级"
            case 60..<75:  return "中级"
            default:       return "初级"
            }
        }()

        return VideoSummary(
            averageScore: avg,
            bestFrame: FrameScore(
                time: best.time,
                timeString: formatTime(seconds: best.time),
                score: best.score
            ),
            worstFrame: FrameScore(
                time: worst.time,
                timeString: formatTime(seconds: worst.time),
                score: worst.score
            ),
            stabilityScore: stabilityScore,
            scoreConsistencyScore: scoreConsistencyScore,
            scoreStdDev: std,
            overallLevel: overallLevel
        )
    }

    // MARK: - 动作稳定性

    /// 基于姿态指标的时间平滑度计算动作稳定性。
    ///
    /// 这个分数衡量相邻有效姿态帧之间的关键角度变化是否平滑，
    /// 与 `scoreConsistencyScore` 区分开：后者只衡量总分波动。
    private func calculateMotionStability(from results: [DetectionResult]) -> Double {
        struct MotionSample {
            let time: Double
            let bodyLean: MetricWithConfidence<Double>?
            let leftKnee: MetricWithConfidence<Double>?
            let rightKnee: MetricWithConfidence<Double>?
            let leftCalf: MetricWithConfidence<Double>?
            let rightCalf: MetricWithConfidence<Double>?
            let gravityLevel: MetricWithConfidence<Double>?
        }

        let samples: [MotionSample] = results.compactMap { result in
            guard result.bodyPose.detected, result.bodyPose.visibility != .minimal else {
                return nil
            }

            return MotionSample(
                time: result.time,
                bodyLean: result.bodyPose.bodyLeanAngle,
                leftKnee: result.bodyPose.leftKneeBendAngle,
                rightKnee: result.bodyPose.rightKneeBendAngle,
                leftCalf: result.bodyPose.leftCalfLeanAngle,
                rightCalf: result.bodyPose.rightCalfLeanAngle,
                gravityLevel: gravityLevelMetric(result.bodyPose.centerOfGravity)
            )
        }

        guard samples.count >= 2 else { return 0 }

        var weightedPenalty = 0.0
        var totalWeight = 0.0

        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let dt = max(current.time - previous.time, 1.0)

            addMotionPenalty(previous.bodyLean, current.bodyLean, dt: dt, tolerancePerSecond: 18, weight: 1.2,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
            addMotionPenalty(previous.leftKnee, current.leftKnee, dt: dt, tolerancePerSecond: 28, weight: 1.0,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
            addMotionPenalty(previous.rightKnee, current.rightKnee, dt: dt, tolerancePerSecond: 28, weight: 1.0,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
            addMotionPenalty(previous.leftCalf, current.leftCalf, dt: dt, tolerancePerSecond: 32, weight: 0.8,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
            addMotionPenalty(previous.rightCalf, current.rightCalf, dt: dt, tolerancePerSecond: 32, weight: 0.8,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
            addMotionPenalty(previous.gravityLevel, current.gravityLevel, dt: dt, tolerancePerSecond: 1.0, weight: 1.1,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
        }

        guard totalWeight > 0 else { return 0 }
        let averagePenalty = weightedPenalty / totalWeight
        return clamp(100 - averagePenalty, lower: 0, upper: 100)
    }

    private func addMotionPenalty(
        _ previous: MetricWithConfidence<Double>?,
        _ current: MetricWithConfidence<Double>?,
        dt: Double,
        tolerancePerSecond: Double,
        weight: Double,
        weightedPenalty: inout Double,
        totalWeight: inout Double
    ) {
        guard let previous, let current else { return }
        let confidence = (previous.confidence + current.confidence) / 2
        guard confidence >= 0.45 else { return }

        let velocity = abs(current.value - previous.value) / dt
        let penalty = clamp(velocity / tolerancePerSecond, lower: 0, upper: 1) * 100
        let effectiveWeight = weight * confidence
        weightedPenalty += penalty * effectiveWeight
        totalWeight += effectiveWeight
    }

    private func gravityLevelMetric(_ metric: MetricWithConfidence<String>?) -> MetricWithConfidence<Double>? {
        guard let metric else { return nil }
        let value: Double
        switch metric.value {
        case "低": value = 0
        case "中": value = 1
        case "高": value = 2
        default: return nil
        }
        return MetricWithConfidence(value: value, confidence: metric.confidence)
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        return min(max(value, lower), upper)
    }

    // MARK: - 输出

    /// 打印单帧分析结果
    private func printResult(_ result: DetectionResult) {
        let timeStr = formatTime(seconds: result.time)
        print("⏱ \(timeStr)")

        // 物体检测
        if !result.objects.isEmpty {
            let sortedObjects = result.objects
                .sorted { $0.confidence > $1.confidence }
                .prefix(5)
            let objectsStr = sortedObjects
                .map { "\($0.label)(\(String(format: "%.2f", $0.confidence)))" }
                .joined(separator: ", ")
            print("  🎯 物体: \(objectsStr)")
        }

        // 人脸检测
        if !result.faces.isEmpty {
            print("  👤 人脸: \(result.faces.count)个")
        }

        // 文字识别
        if !result.textObservations.isEmpty {
            let texts = result.textObservations.prefix(3).joined(separator: ", ")
            print("  📝 文字: \(texts)")
            if result.textObservations.count > 3 {
                print("    ... 还有\(result.textObservations.count - 3)处文字")
            }
        }

        // 场景分类
        if !result.sceneClassifications.isEmpty {
            let sortedScenes = result.sceneClassifications
                .sorted { $0.confidence > $1.confidence }
                .prefix(3)
            let scenesStr = sortedScenes
                .map { "\($0.label)(\(String(format: "%.2f", $0.confidence)))" }
                .joined(separator: ", ")
            print("  🌄 场景: \(scenesStr)")
        }

        // 姿态评分
        if let score = result.poseScore {
            print("  🏆 评分: \(String(format: "%.0f", score.totalScore))/100 (\(score.level))")
            print("     身体前倾 \(String(format: "%.0f", score.forwardLeanScore))分 · "
                  + "膝盖弯曲 \(String(format: "%.0f", score.kneeBendScore))分 · "
                  + "小腿倾斜 \(String(format: "%.0f", score.calfLeanScore))分")
            print("     重心 \(String(format: "%.0f", score.gravityScore))分 · "
                  + "对称性 \(String(format: "%.0f", score.symmetryScore))分")
            // 显示可见性
            print("     可见性: \(result.bodyPose.visibility.rawValue)")
        }

        // 无内容
        if result.objects.isEmpty && result.faces.isEmpty
            && result.textObservations.isEmpty && result.sceneClassifications.isEmpty
            && !result.bodyPose.detected {
            print("  - 未检测到显著内容")
        }
    }

    // MARK: - 工具

    func formatTime(seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

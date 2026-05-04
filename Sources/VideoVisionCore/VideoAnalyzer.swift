import AVFoundation
import CoreMedia
import CoreImage
import Vision

// MARK: - 视频分析器（纯库版本，无控制台输出）

/// 负责视频抽帧、组装分析流程、生成全视频总结
///
/// 使用 `VisionFrameAnalyzer` → `PoseMetricsCalculator` → `PoseScorer` 的管线。
/// 此库版本不包含任何 `print()` 调用或文件系统假定。
public class VideoAnalyzer {
    public let videoURL: URL
    public let asset: AVAsset

    // 分析管线
    private let frameAnalyzer: VisionFrameAnalyzer
    private let metricsCalculator: PoseMetricsCalculator
    private let poseScorer: PoseScorer

    /// 采样间隔（秒）。默认 1.0 = 每秒分析一帧
    public let sampleInterval: Double
    /// 最大帧尺寸。nil 表示使用视频原始分辨率
    private let maxFrameSize: CGSize?

    /// 初始化分析器
    /// - Parameters:
    ///   - videoURL: 视频文件的 URL
    ///   - pointConfidenceThreshold: 关键点检测置信度阈值（默认 0.3）
    ///   - sampleInterval: 采样间隔秒数（默认 1.0）
    ///   - maxFrameSize: 最大帧分辨率，nil 使用视频原始尺寸（默认 1920x1080）
    ///   - visionOptions: Vision 请求选项（默认仅姿态检测）
    public init(
        videoURL: URL,
        pointConfidenceThreshold: VNConfidence = 0.3,
        sampleInterval: Double = 1.0,
        maxFrameSize: CGSize? = CGSize(width: 1920, height: 1080),
        visionOptions: VisionAnalysisOptions = .skiAnalysis
    ) {
        self.videoURL = videoURL
        self.asset = AVAsset(url: videoURL)
        self.sampleInterval = max(0.1, sampleInterval)
        self.maxFrameSize = maxFrameSize
        self.frameAnalyzer = VisionFrameAnalyzer(options: visionOptions)
        self.metricsCalculator = PoseMetricsCalculator(pointConfidenceThreshold: pointConfidenceThreshold)
        self.poseScorer = PoseScorer()
    }

    // MARK: - 主分析流程

    /// 分析视频，每秒分析一帧
    /// - Parameter progressHandler: 进度回调（0.0~1.0），可选
    /// - Returns: 每帧的检测结果数组
    public func analyze(progressHandler: ((Double) -> Void)? = nil) async throws -> [DetectionResult] {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw NSError(domain: "VideoAnalyzer", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "视频中没有视频轨道"])
        }

        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        var results: [DetectionResult] = []

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        if let maxSize = maxFrameSize {
            imageGenerator.maximumSize = maxSize
        }

        var currentTime: Double = 0.0
        while currentTime < totalSeconds {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)

            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let result = try await analyzeFrame(cgImage: cgImage, at: time)
                results.append(result)
            } catch {
                // 单帧失败不中断整体流程，但记录错误信息
                results.append(DetectionResult(
                    time: currentTime,
                    objects: [],
                    faces: [],
                    textObservations: [],
                    sceneClassifications: [],
                    bodyPose: BodyPoseData(
                        detected: false, visibility: .none,
                        bodyLeanAngle: nil, leftBodyLeanAngle: nil, rightBodyLeanAngle: nil,
                        leftKneeBendAngle: nil, rightKneeBendAngle: nil,
                        leftCalfLeanAngle: nil, rightCalfLeanAngle: nil,
                        centerOfGravity: nil
                    ),
                    poseScore: nil,
                    error: "帧提取或分析失败: \(error.localizedDescription)"
                ))
            }

            currentTime += sampleInterval
            let progress = min(currentTime / totalSeconds, 1.0)
            progressHandler?(progress)
        }

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
    public func generateSummary(from results: [DetectionResult]) -> VideoSummary? {
        let reliableFrames = reliablePoseFrames(from: results)
        let scoreEntries = reliableFrames.compactMap { result -> (time: Double, score: Double, confidence: Double)? in
            guard let poseScore = result.poseScore else { return nil }
            return (result.time, poseScore.totalScore, max(0.01, poseScore.totalConfidence))
        }
        guard !scoreEntries.isEmpty else { return nil }

        let rawAvg = weightedAverage(scoreEntries.map { ($0.score, $0.confidence) })
        let bestThirdAvg = bestThirdAverage(scoreEntries.map { ($0.score, $0.confidence) })
        let std = weightedStandardDeviation(scoreEntries.map { ($0.score, $0.confidence) }, mean: rawAvg)
        // 总分一致性只解释评分波动，不代表真实动作稳定性。
        let scoreConsistencyScore = clamp(100 - std * 10, lower: 0, upper: 100)
        let stabilityScore = calculateMotionStability(from: results)
        let stableBaseline = stableCarvingBaseline(from: results, motionStability: stabilityScore)
        let uncappedAverage = max(bestThirdAvg, stableBaseline?.adjustedAverageScore ?? 0)
        let techniqueCappedAverage = applyEdgeEvidenceCaps(
            score: uncappedAverage,
            reliableFrames: reliableFrames,
            stableBaseline: stableBaseline
        )
        let avg = applyEvidenceCaps(
            score: techniqueCappedAverage,
            reliableFrameCount: scoreEntries.count
        )

        // 找最佳/最差帧
        var best = (time: 0.0, score: -1.0)
        var worst = (time: 0.0, score: 101.0)

        for entry in scoreEntries {
            if entry.score > best.score { best = (entry.time, entry.score) }
            if entry.score < worst.score { worst = (entry.time, entry.score) }
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

    private func weightedAverage(_ values: [(value: Double, weight: Double)]) -> Double {
        let totalWeight = values.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return 0 }
        return values.map { $0.value * $0.weight }.reduce(0, +) / totalWeight
    }

    private func bestThirdAverage(_ values: [(value: Double, weight: Double)]) -> Double {
        guard !values.isEmpty else { return 0 }
        let selectedCount = max(1, Int(ceil(Double(values.count) / 3.0)))
        let selected = values.sorted { $0.value > $1.value }.prefix(selectedCount)
        return weightedAverage(Array(selected))
    }

    private func applyEvidenceCaps(score: Double, reliableFrameCount: Int) -> Double {
        if reliableFrameCount < 5 {
            return min(score, 55)
        }
        if reliableFrameCount < 8 {
            return min(score, 65)
        }
        if reliableFrameCount < 12 {
            return min(score, 78)
        }
        return score
    }

    private func applyEdgeEvidenceCaps(
        score: Double,
        reliableFrames: [DetectionResult],
        stableBaseline: StableCarvingBaseline?
    ) -> Double {
        // 稳定刻滑基线是低姿态/大倒伏误识别的保护通道，不再用小腿代理二次封顶。
        guard stableBaseline == nil else { return score }

        guard let averageEdgeEvidence = averageEdgeEvidenceScore(from: reliableFrames) else {
            return min(score, 65)
        }

        if averageEdgeEvidence < 38 {
            return min(score, 58)
        }
        if averageEdgeEvidence < 42 {
            return min(score, 65)
        }
        if averageEdgeEvidence < 50 {
            return min(score, 70)
        }
        return score
    }

    private func weightedStandardDeviation(_ values: [(value: Double, weight: Double)], mean: Double) -> Double {
        let totalWeight = values.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return 0 }
        let variance = values
            .map { pow($0.value - mean, 2) * $0.weight }
            .reduce(0, +) / totalWeight
        return sqrt(variance)
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

        let samples: [MotionSample] = reliablePoseFrames(from: results).compactMap { result in
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
            addMotionPenalty(previous.gravityLevel, current.gravityLevel, dt: dt, tolerancePerSecond: 0.15, weight: 1.1,
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

    /// hipRatio 已是 0~1 连续值，直接用于动作稳定性计算
    /// 注：容忍度在 addMotionPenalty 中针对连续值做了调整
    private func gravityLevelMetric(_ metric: MetricWithConfidence<Double>?) -> MetricWithConfidence<Double>? {
        return metric
    }

    // MARK: - 工具

    public func formatTime(seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

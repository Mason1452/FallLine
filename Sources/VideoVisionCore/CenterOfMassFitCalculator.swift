import Foundation

// MARK: - 重心阶段适配评分器

/// 将旧的“越低越好”重心视角，升级为“是否适合当前滑行阶段/转弯阶段”。
public struct CenterOfMassFitCalculator {
    public init() {}

    private static let nearestTurnFrameTolerance = 0.75
    private static let fullAvailabilityFrameCount = 5.0

    public static func analyze(
        frames: [DetectionResult],
        summary: VideoSummary,
        turnAnalysis: TurnAnalysis
    ) -> CenterOfMassAnalysis {
        let subScores = StageClassifier.averageSubScores(from: frames)
        let stage = StageClassifier.determineStage(
            averageScore: summary.averageScore,
            calfScore: subScores.calfLean,
            kneeScore: subScores.kneeBend,
            stabilityScore: summary.stabilityScore
        )

        let frameAnalyses = reliablePoseFrames(from: frames).compactMap { frame -> CenterOfMassFrameAnalysis? in
            guard frame.bodyPose.detected,
                  let hipRatio = frame.bodyPose.centerOfGravity else {
                return nil
            }

            let turnFrame = nearestTurnFrame(to: frame.time, in: turnAnalysis.frames)
            let phase = turnFrame?.phase
            let range = targetRange(for: stage, phase: phase)
            let score = score(hipRatio: hipRatio.value, targetRange: range)
            let issue = issue(hipRatio: hipRatio.value, targetRange: range)
            let confidence = confidence(
                pose: frame.bodyPose,
                hipRatioConfidence: hipRatio.confidence,
                turnFrame: turnFrame
            )

            return CenterOfMassFrameAnalysis(
                time: frame.time,
                hipRatio: hipRatio.value,
                targetRangeLower: range.lower,
                targetRangeUpper: range.upper,
                phase: phase,
                score: score,
                confidence: confidence,
                issue: issue
            )
        }

        guard !frameAnalyses.isEmpty else { return .empty }

        let rawScore = weightedAverage(frameAnalyses.map { ($0.score, $0.confidence) })
        let availabilityConfidence = min(1, Double(frameAnalyses.count) / fullAvailabilityFrameCount)
        let rawConfidence = average(frameAnalyses.map(\.confidence)) * availabilityConfidence
        let mainIssue = dominantIssue(from: frameAnalyses)

        return CenterOfMassAnalysis(
            cogStageFitScore: rawScore,
            confidence: rawConfidence,
            label: label(for: rawScore, confidence: rawConfidence),
            stage: stage.rawValue,
            frameCount: frameAnalyses.count,
            mainIssue: mainIssue,
            frames: frameAnalyses
        )
    }
}

private extension CenterOfMassFitCalculator {
    static func targetRange(for stage: StageLabel, phase: TurnPhase?) -> (lower: Double, upper: Double) {
        switch stage {
        case .basicDetection:
            return (0.35, 0.65)
        case .basicControl:
            return (0.34, 0.58)
        case .stableSkiing:
            if phase == .shaping { return (0.30, 0.50) }
            return (0.34, 0.56)
        case .carvingEmerging:
            switch phase {
            case .shaping:
                return (0.25, 0.42)
            case .initiation, .release:
                return (0.30, 0.48)
            case .transition:
                return (0.34, 0.54)
            case .none:
                return (0.30, 0.48)
            }
        case .qualitySkiing, .advanced:
            switch phase {
            case .shaping:
                return (0.22, 0.38)
            case .initiation, .release:
                return (0.27, 0.44)
            case .transition:
                return (0.32, 0.50)
            case .none:
                return (0.27, 0.44)
            }
        }
    }

    static func score(hipRatio: Double, targetRange: (lower: Double, upper: Double)) -> Double {
        if hipRatio >= targetRange.lower && hipRatio <= targetRange.upper {
            return 100
        }

        if hipRatio < targetRange.lower {
            let delta = targetRange.lower - hipRatio
            return clamp(100 - delta / 0.18 * 55)
        }

        let delta = hipRatio - targetRange.upper
        return clamp(100 - delta / 0.24 * 100)
    }

    static func issue(hipRatio: Double, targetRange: (lower: Double, upper: Double)) -> String {
        if hipRatio < targetRange.lower { return "当前阶段重心过低" }
        if hipRatio > targetRange.upper { return "当前阶段重心偏高" }
        return "当前阶段重心适配"
    }

    static func confidence(
        pose: BodyPoseData,
        hipRatioConfidence: Double,
        turnFrame: TurnFrameAnalysis?
    ) -> Double {
        let visibilityConfidence: Double
        switch pose.visibility {
        case .full:
            visibilityConfidence = 1.0
        case .partial:
            visibilityConfidence = 0.75
        case .minimal:
            visibilityConfidence = 0.35
        case .none:
            visibilityConfidence = 0
        }

        let phaseConfidence = turnFrame?.confidence ?? 0.70
        return hipRatioConfidence * visibilityConfidence * phaseConfidence
    }

    static func nearestTurnFrame(to time: Double, in frames: [TurnFrameAnalysis]) -> TurnFrameAnalysis? {
        guard let nearest = frames.min(by: { abs($0.time - time) < abs($1.time - time) }),
              abs(nearest.time - time) <= nearestTurnFrameTolerance else {
            return nil
        }
        return nearest
    }

    static func dominantIssue(from frames: [CenterOfMassFrameAnalysis]) -> String? {
        var counts: [String: Int] = [:]
        for frame in frames where frame.issue != "当前阶段重心适配" {
            counts[frame.issue, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    static func label(for score: Double, confidence: Double) -> String {
        if confidence < 0.35 { return "重心数据不足" }
        if score >= 80 { return "当前阶段重心适配" }
        if score >= 65 { return "重心基本适配" }
        if score >= 50 { return "重心适配度一般" }
        return "重心阶段适配不足"
    }

}

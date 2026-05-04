import Foundation

// MARK: - 通用工具函数

/// 将值限制在 [lower, upper] 范围内
/// - Parameters:
///   - value: 输入值
///   - lower: 下限（默认 0）
///   - upper: 上限（默认 100）
/// - Returns: 限制后的值
public func clamp(_ value: Double, lower: Double = 0, upper: Double = 100) -> Double {
    min(max(value, lower), upper)
}

// MARK: - 可靠性阈值

/// 统一的分析可靠性阈值。
///
/// 低姿态、大立刃、遮挡等高级动作容易让 Vision 缺失膝/踝关键点。
/// 这类帧应该保留在原始 JSON 中，但不应用来下“走刃差/姿态差”的结论。
public enum AnalysisReliability {
    /// 低于该置信度的 PoseScore 不参与全视频评分、关键时刻和转弯阶段结论。
    public static let minimumPoseScoreConfidence = 0.30

    /// 低于该置信度的滑雪派生指标不参与“问题帧/最佳帧”判断。
    public static let minimumSkiMetricConfidence = 0.35

    /// 少于该数量的可靠帧时，不输出高光片段，避免把几帧偶然高分包装成最佳片段。
    public static let minimumHighlightFrameCount = 8
}

// MARK: - 稳定刻滑基线

/// 稳定刻滑视频中，连续高质量平台往往比逐帧均值更接近真实水平。
///
/// 某些低姿态、大倒伏刻滑会让 Vision 把膝盖/脚踝误识别成“腿直、立刃弱”，
/// 这会把整段平均分拉得过低。该基线只在条件很保守时触发：
/// - 动作稳定性高
/// - 存在持续的高分平台，而不是一两帧高光
/// - 原始均分明显低于高分平台
public struct StableCarvingBaseline {
    public let adjustedAverageScore: Double
    public let rawAverageScore: Double
    public let plateauStartTime: Double
    public let plateauEndTime: Double
    public let plateauFrameCount: Int
    public let plateauCoverage: Double

    public init(
        adjustedAverageScore: Double,
        rawAverageScore: Double,
        plateauStartTime: Double,
        plateauEndTime: Double,
        plateauFrameCount: Int,
        plateauCoverage: Double
    ) {
        self.adjustedAverageScore = adjustedAverageScore
        self.rawAverageScore = rawAverageScore
        self.plateauStartTime = plateauStartTime
        self.plateauEndTime = plateauEndTime
        self.plateauFrameCount = plateauFrameCount
        self.plateauCoverage = plateauCoverage
    }
}

/// 返回有姿态评分的帧；如果存在可靠帧，则过滤掉低置信度帧。
/// 如果没有任何可靠帧，则回退到全部有评分帧，避免完全无报告。
public func reliablePoseFrames(from frames: [DetectionResult]) -> [DetectionResult] {
    let scored = frames.filter { $0.poseScore != nil && $0.bodyPose.detected }
    let reliable = scored.filter {
        ($0.poseScore?.totalConfidence ?? 0) >= AnalysisReliability.minimumPoseScoreConfidence
    }
    return reliable.isEmpty ? scored : reliable
}

public func reliablePoseScores(from frames: [DetectionResult]) -> [PoseScore] {
    reliablePoseFrames(from: frames).compactMap(\.poseScore)
}

/// 用小腿倾斜分作为当前 2D 姿态管线里的持续立刃证据代理。
/// 返回 nil 表示没有足够置信度的数据，不应据此下结论。
public func averageEdgeEvidenceScore(from frames: [DetectionResult]) -> Double? {
    let values = reliablePoseFrames(from: frames).compactMap { frame -> (value: Double, weight: Double)? in
        guard let score = frame.poseScore,
              score.calfLeanConfidence >= AnalysisReliability.minimumPoseScoreConfidence else {
            return nil
        }
        return (score.calfLeanScore, max(0.01, score.calfLeanConfidence))
    }
    guard !values.isEmpty else { return nil }
    return weightedAverage(values)
}

public func stableCarvingBaseline(
    from frames: [DetectionResult],
    motionStability: Double
) -> StableCarvingBaseline? {
    let reliableFrames = reliablePoseFrames(from: frames)
        .sorted { $0.time < $1.time }
    guard reliableFrames.count >= 12, motionStability >= 85 else { return nil }

    let entries = reliableFrames.compactMap { frame -> (frame: DetectionResult, score: Double, weight: Double)? in
        guard let poseScore = frame.poseScore else { return nil }
        return (frame, poseScore.totalScore, max(0.01, poseScore.totalConfidence))
    }
    guard entries.count >= 12 else { return nil }

    let rawAverage = weightedAverage(entries.map { ($0.score, $0.weight) })
    let bestScore = entries.map(\.score).max() ?? 0
    let gap = bestScore - rawAverage

    // 保守触发：只有原始均分已经被打到偏低区间，且和高分平台差距明显时才校正。
    guard rawAverage < 65, bestScore >= 75, gap >= 15 else { return nil }

    let highScoreFloor = bestScore - 6
    var current: [(frame: DetectionResult, score: Double, weight: Double)] = []
    var plateaus: [[(frame: DetectionResult, score: Double, weight: Double)]] = []

    for entry in entries {
        if entry.score >= highScoreFloor {
            current.append(entry)
        } else if !current.isEmpty {
            plateaus.append(current)
            current.removeAll()
        }
    }
    if !current.isEmpty {
        plateaus.append(current)
    }

    guard let plateau = plateaus.max(by: { $0.count < $1.count }),
          plateau.count >= 5 else {
        return nil
    }

    let sampleInterval = medianSampleInterval(entries.map { $0.frame.time })
    let totalDuration = max(
        (entries.last?.frame.time ?? 0) - (entries.first?.frame.time ?? 0) + sampleInterval,
        sampleInterval
    )
    let plateauDuration = max(
        (plateau.last?.frame.time ?? 0) - (plateau.first?.frame.time ?? 0) + sampleInterval,
        sampleInterval
    )
    let coverage = plateauDuration / totalDuration
    guard coverage >= 0.18 else { return nil }

    let plateauAverage = weightedAverage(plateau.map { ($0.score, $0.weight) })
    guard plateauAverage >= 75, plateauAverage > rawAverage else { return nil }

    return StableCarvingBaseline(
        adjustedAverageScore: plateauAverage,
        rawAverageScore: rawAverage,
        plateauStartTime: plateau.first?.frame.time ?? 0,
        plateauEndTime: plateau.last?.frame.time ?? 0,
        plateauFrameCount: plateau.count,
        plateauCoverage: coverage
    )
}

private func weightedAverage(_ values: [(value: Double, weight: Double)]) -> Double {
    let totalWeight = values.map(\.weight).reduce(0, +)
    guard totalWeight > 0 else { return 0 }
    return values.map { $0.value * $0.weight }.reduce(0, +) / totalWeight
}

private func medianSampleInterval(_ times: [Double]) -> Double {
    let deltas = zip(times.dropFirst(), times).map { max($0 - $1, 0) }.filter { $0 > 0 }
    guard !deltas.isEmpty else { return 1 }
    let sorted = deltas.sorted()
    return sorted[sorted.count / 2]
}

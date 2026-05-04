import Foundation

// MARK: - 滑行阶段判定

/// 共享阶段判定逻辑，供报告和阶段化评分复用。
public struct StageClassifier {
    public init() {}

    public static func determineStage(
        averageScore: Double,
        calfScore: Double,
        kneeScore: Double,
        stabilityScore: Double
    ) -> StageLabel {
        if averageScore < 50 || averageScore == 0 { return .basicDetection }
        if averageScore < 60 { return .basicControl }
        if averageScore >= 80 { return calfScore >= 65 ? .advanced : .qualitySkiing }
        if averageScore >= 70 && calfScore >= 55 && kneeScore >= 70 { return .carvingEmerging }
        if averageScore >= 75 { return .qualitySkiing }
        if averageScore >= 70 && calfScore < 55 { return .stableSkiing }
        return .stableSkiing
    }

    public static func averageSubScores(
        from frames: [DetectionResult]
    ) -> (forwardLean: Double, kneeBend: Double, calfLean: Double, gravity: Double, symmetry: Double) {
        let scores = reliablePoseScores(from: frames)
        guard !scores.isEmpty else { return (50, 50, 50, 50, 50) }
        let weights = scores.map { max(0.01, $0.totalConfidence) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return (50, 50, 50, 50, 50) }
        return (
            forwardLean: weightedAverage(scores.map(\.forwardLeanScore), weights: weights, totalWeight: totalWeight),
            kneeBend: weightedAverage(scores.map(\.kneeBendScore), weights: weights, totalWeight: totalWeight),
            calfLean: weightedAverage(scores.map(\.calfLeanScore), weights: weights, totalWeight: totalWeight),
            gravity: weightedAverage(scores.map(\.gravityScore), weights: weights, totalWeight: totalWeight),
            symmetry: weightedAverage(scores.map(\.symmetryScore), weights: weights, totalWeight: totalWeight)
        )
    }

    private static func weightedAverage(_ values: [Double], weights: [Double], totalWeight: Double) -> Double {
        zip(values, weights).map { $0 * $1 }.reduce(0, +) / totalWeight
    }
}

import Foundation

// MARK: - 滑雪派生指标计算器

/// 从基础姿态评分推导更滑雪化的复合指标
struct SkiMetricsCalculator {

    // MARK: - 权重配置

    /// 走刃质量 = 立刃 * 0.50 + 重心 * 0.20 + 膝盖 * 0.15 + 对称性 * 0.10 + 稳定性 * 0.05
    static let edgeWeights: [(keyPath: KeyPath<PoseScore, Double>, weight: Double)] = [
        (\.calfLeanScore,    0.50),
        (\.gravityScore,     0.20),
        (\.kneeBendScore,    0.15),
        (\.symmetryScore,    0.10),
    ]

    /// 板压支撑 = 重心 * 0.45 + 膝盖 * 0.30 + 前倾 * 0.15 + 稳定性 * 0.10
    static let pressureWeights: [(KeyPath<PoseScore, Double>, Double)] = [
        (\.gravityScore,     0.45),
        (\.kneeBendScore,    0.30),
        (\.forwardLeanScore, 0.15),
    ]

    /// 前后支撑 = 前倾 * 0.60 + 重心 * 0.25 + 稳定性 * 0.15
    static let foreAftWeights: [(KeyPath<PoseScore, Double>, Double)] = [
        (\.forwardLeanScore, 0.60),
        (\.gravityScore,     0.25),
    ]

    // MARK: - 单帧计算

    static func compute(from poseScore: PoseScore, stability: Double = 50) -> SkiDerivedMetrics {
        let edge = weightedScore(poseScore, weights: edgeWeights) + stability * 0.05
        let pressure = weightedScore(poseScore, weights: pressureWeights) + stability * 0.10
        let foreAft = weightedScore(poseScore, weights: foreAftWeights) + stability * 0.15

        return SkiDerivedMetrics(
            edgeQualityScore:        clamp(edge),
            edgeQualityLabel:        edgeLabel(edge),
            pressureSupportScore:    clamp(pressure),
            pressureSupportLabel:    pressureLabel(pressure),
            foreAftSupportScore:     clamp(foreAft),
            foreAftSupportLabel:     foreAftLabel(foreAft)
        )
    }

    /// 给定 stability（来自全视频总结）时重新计算
    static func computeWithStability(_ poseScore: PoseScore, stability: Double) -> SkiDerivedMetrics {
        return compute(from: poseScore, stability: stability)
    }

    // MARK: - 全视频平均

    /// 计算全视频平均滑雪指标
    static func average(from frames: [DetectionResult], stability: Double) -> SkiDerivedMetrics {
        let valid = frames.compactMap { $0.poseScore }
        guard !valid.isEmpty else {
            return SkiDerivedMetrics(
                edgeQualityScore: 0,
                edgeQualityLabel: "无检测数据",
                pressureSupportScore: 0,
                pressureSupportLabel: "无检测数据",
                foreAftSupportScore: 0,
                foreAftSupportLabel: "无检测数据"
            )
        }

        let avgEdge = valid.map { edgeRaw($0, stability: stability) }.reduce(0, +) / Double(valid.count)
        let avgPressure = valid.map { pressureRaw($0, stability: stability) }.reduce(0, +) / Double(valid.count)
        let avgForeAft = valid.map { foreAftRaw($0, stability: stability) }.reduce(0, +) / Double(valid.count)

        return SkiDerivedMetrics(
            edgeQualityScore:        clamp(avgEdge),
            edgeQualityLabel:        edgeLabel(avgEdge),
            pressureSupportScore:    clamp(avgPressure),
            pressureSupportLabel:    pressureLabel(avgPressure),
            foreAftSupportScore:     clamp(avgForeAft),
            foreAftSupportLabel:     foreAftLabel(avgForeAft)
        )
    }

    // MARK: - 内部

    private static func weightedScore(_ s: PoseScore, weights: [(KeyPath<PoseScore, Double>, Double)]) -> Double {
        weights.reduce(0) { $0 + s[keyPath: $1.0] * $1.1 }
    }

    private static func edgeRaw(_ s: PoseScore, stability: Double) -> Double {
        weightedScore(s, weights: edgeWeights) + stability * 0.05
    }
    private static func pressureRaw(_ s: PoseScore, stability: Double) -> Double {
        weightedScore(s, weights: pressureWeights) + stability * 0.10
    }
    private static func foreAftRaw(_ s: PoseScore, stability: Double) -> Double {
        weightedScore(s, weights: foreAftWeights) + stability * 0.15
    }

    private static func clamp(_ v: Double) -> Double {
        max(0, min(100, v))
    }

    // MARK: - 标签映射

    static func edgeLabel(_ score: Double) -> String {
        if score < 40 { return "搓雪为主" }
        if score < 55 { return "有立刃尝试" }
        if score < 70 { return "刻滑雏形" }
        if score < 85 { return "走刃较稳定" }
        return "走刃优秀"
    }

    static func pressureLabel(_ score: Double) -> String {
        if score < 45 { return "支撑不够" }
        if score < 60 { return "支撑偏弱" }
        if score < 75 { return "支撑尚可" }
        if score < 90 { return "支撑扎实" }
        return "支撑优秀"
    }

    static func foreAftLabel(_ score: Double) -> String {
        if score < 50 { return "后坐倾向" }
        if score < 65 { return "前后不均衡" }
        if score < 80 { return "前后支撑尚可" }
        if score < 90 { return "前后支撑积极" }
        return "前后支撑优秀"
    }
}

import Foundation

// MARK: - 姿态评分器

/// 根据 BodyPoseData 计算各项评分、总分、等级和改进建议
///
/// 评分规则：
/// - 根据可见性等级（visibility）动态调整权重
/// - 双侧均可见（full）：使用完整权重
/// - 单侧可见（partial）：对称性权重降至 0，分配到其他项
/// - 关键点不足（minimal）：仅返回基础分
public struct PoseScorer {

    // MARK: - 权重配置

    /// 默认权重
    public static let defaultWeights = (
        forwardLean: 0.20,
        kneeBend: 0.25,
        calfLean: 0.20,
        gravity: 0.20,
        symmetry: 0.15
    )

    /// 在 partial 可见性下，对称性权重被重新分配
    /// 对称性 0.15 → 前倾 +0.05, 膝盖 +0.05, 小腿 +0.05
    public static let partialWeights = (
        forwardLean: 0.25,
        kneeBend: 0.30,
        calfLean: 0.25,
        gravity: 0.20,
        symmetry: 0.0
    )

    /// 在 minimal 可见性下，所有评分降为基础分
    public static let minimalBaseScore: Double = 40.0

    // MARK: - 理想范围

    /// 身体前倾：理想 10°~25°
    public static let leanIdealMin = 10.0
    public static let leanIdealMax = 25.0
    /// 每偏离 5° 扣 10 分
    public static let leanPenaltyPer5Deg = 10.0

    /// 膝盖弯曲：理想 100°~140°
    public static let kneeIdealMin = 100.0
    public static let kneeIdealMax = 140.0
    /// 每偏离 10° 扣 8 分
    public static let kneePenaltyPer10Deg = 8.0

    /// 小腿倾斜：0°=0分, 80°=100分（越高越好）
    public static let calfMaxScoreAngle = 80.0

    /// 重心评分
    public static let gravityScores: [String: Double] = [
        "低": 90,
        "中": 60,
        "高": 30
    ]

    /// 对称性：每偏离 5° 扣 10 分
    public static let symmetryPenaltyPer5Deg = 10.0

    // MARK: - 等级划分

    public static let levelThresholds: [(range: Range<Double>, level: String)] = [
        (85..<101, "专业"),
        (75..<85,  "高级"),
        (60..<75,  "中级"),
        (0..<60,   "初级")
    ]

    public init() {}

    // MARK: - 主入口

    /// 计算姿态评分
    /// - Parameter pose: 包含置信度的姿态数据
    /// - Returns: 评分结果，如果 `visibility == .none` 返回 nil
    public func score(pose: BodyPoseData) -> PoseScore? {
        guard pose.detected else { return nil }

        switch pose.visibility {
        case .none:
            return nil
        case .minimal:
            return minimalScore()
        case .partial:
            return computeScore(pose: pose, weights: Self.partialWeights)
        case .full:
            return computeScore(pose: pose, weights: Self.defaultWeights)
        }
    }

    // MARK: - 评分计算

    private func computeScore(pose: BodyPoseData, weights: (
        forwardLean: Double,
        kneeBend: Double,
        calfLean: Double,
        gravity: Double,
        symmetry: Double
    )) -> PoseScore {
        let forwardLeanScore = scoreForwardLean(pose)
        let kneeBendScore = scoreKneeBend(pose)
        let calfLeanScore = scoreCalfLean(pose)
        let gravityScore = scoreGravity(pose)
        let symmetryScore = scoreSymmetry(pose)

        let totalScore = forwardLeanScore * weights.forwardLean
                       + kneeBendScore * weights.kneeBend
                       + calfLeanScore * weights.calfLean
                       + gravityScore * weights.gravity
                       + symmetryScore * weights.symmetry

        let level = determineLevel(totalScore)
        let suggestions = generateSuggestions(
            forwardLean: forwardLeanScore,
            kneeBend: kneeBendScore,
            calfLean: calfLeanScore,
            gravity: gravityScore,
            symmetry: symmetryScore,
            visibility: pose.visibility
        )

        return PoseScore(
            totalScore: totalScore,
            forwardLeanScore: forwardLeanScore,
            kneeBendScore: kneeBendScore,
            calfLeanScore: calfLeanScore,
            gravityScore: gravityScore,
            symmetryScore: symmetryScore,
            level: level,
            suggestions: suggestions
        )
    }

    /// 关键点不足时的基础分
    private func minimalScore() -> PoseScore {
        return PoseScore(
            totalScore: Self.minimalBaseScore,
            forwardLeanScore: Self.minimalBaseScore,
            kneeBendScore: Self.minimalBaseScore,
            calfLeanScore: 0,
            gravityScore: Self.minimalBaseScore,
            symmetryScore: 0,
            level: "初级",
            suggestions: ["关键点识别不足，请确保全身在画面中可见"]
        )
    }

    // MARK: - 单项评分

    /// 身体前倾评分
    private func scoreForwardLean(_ pose: BodyPoseData) -> Double {
        guard let lean = pose.bodyLeanAngle else {
            // 无整体前倾角时，尝试用单侧数据
            let left = pose.leftBodyLeanAngle?.value
            let right = pose.rightBodyLeanAngle?.value
            let angles = [left, right].compactMap { $0 }
            guard !angles.isEmpty else { return 50 }
            let avg = angles.reduce(0, +) / Double(angles.count)
            return scoreAngle(avg, idealMin: Self.leanIdealMin, idealMax: Self.leanIdealMax,
                            penaltyPerUnit: Self.leanPenaltyPer5Deg, unit: 5.0)
        }
        return scoreAngle(lean.value, idealMin: Self.leanIdealMin, idealMax: Self.leanIdealMax,
                        penaltyPerUnit: Self.leanPenaltyPer5Deg, unit: 5.0)
    }

    /// 膝盖弯曲评分
    private func scoreKneeBend(_ pose: BodyPoseData) -> Double {
        let left = pose.leftKneeBendAngle?.value
        let right = pose.rightKneeBendAngle?.value
        let angles = [left, right].compactMap { $0 }
        guard !angles.isEmpty else { return 50 }
        let avg = angles.reduce(0, +) / Double(angles.count)
        return scoreAngle(avg, idealMin: Self.kneeIdealMin, idealMax: Self.kneeIdealMax,
                        penaltyPerUnit: Self.kneePenaltyPer10Deg, unit: 10.0)
    }

    /// 小腿倾斜评分（越高越好）
    private func scoreCalfLean(_ pose: BodyPoseData) -> Double {
        let left = pose.leftCalfLeanAngle?.value
        let right = pose.rightCalfLeanAngle?.value
        let angles = [left, right].compactMap { $0 }
        guard !angles.isEmpty else { return 0 }
        let avg = angles.reduce(0, +) / Double(angles.count)
        return min(avg / Self.calfMaxScoreAngle * 100, 100)
    }

    /// 重心评分
    private func scoreGravity(_ pose: BodyPoseData) -> Double {
        guard let cog = pose.centerOfGravity else { return 50 }
        return Self.gravityScores[cog.value] ?? 50
    }

    /// 对称性评分
    private func scoreSymmetry(_ pose: BodyPoseData) -> Double {
        let leftK = pose.leftKneeBendAngle?.value
        let rightK = pose.rightKneeBendAngle?.value
        let leftC = pose.leftCalfLeanAngle?.value
        let rightC = pose.rightCalfLeanAngle?.value
        let leftL = pose.leftBodyLeanAngle?.value
        let rightL = pose.rightBodyLeanAngle?.value

        var totalDiff = 0.0
        var count = 0

        if let l = leftK, let r = rightK {
            totalDiff += abs(l - r)
            count += 1
        }
        if let l = leftC, let r = rightC {
            totalDiff += abs(l - r)
            count += 1
        }
        if let l = leftL, let r = rightL {
            totalDiff += abs(l - r)
            count += 1
        }

        guard count > 0 else { return 50 }
        let avgDiff = totalDiff / Double(count)
        return max(0, 100 - (avgDiff / 5.0) * Self.symmetryPenaltyPer5Deg)
    }

    // MARK: - 辅助

    /// 通用角度评分：理想范围内满分，超出递进扣分
    private func scoreAngle(_ value: Double, idealMin: Double, idealMax: Double,
                           penaltyPerUnit: Double, unit: Double) -> Double {
        if value >= idealMin && value <= idealMax { return 100 }
        let deviation = min(abs(value - idealMin), abs(value - idealMax))
        return max(0, 100 - (deviation / unit) * penaltyPerUnit)
    }

    /// 等级评定
    private func determineLevel(_ score: Double) -> String {
        for (range, level) in Self.levelThresholds {
            if range.contains(score) { return level }
        }
        return "初级"
    }

    /// 生成改进建议
    private func generateSuggestions(
        forwardLean: Double, kneeBend: Double,
        calfLean: Double, gravity: Double,
        symmetry: Double, visibility: VisibilityLevel
    ) -> [String] {
        var suggestions: [String] = []

        if visibility == .minimal {
            suggestions.append("关键点识别不足，请确保全身在画面中可见")
            return suggestions
        }

        if forwardLean < 70 {
            suggestions.append("调整身体前倾角度至10°~25°")
        }
        if kneeBend < 70 {
            suggestions.append("膝盖应保持100°~140°的弯曲")
        }
        if calfLean < 50 {
            suggestions.append("尝试增加立刃幅度")
        }
        if gravity < 70 {
            suggestions.append("降低重心以获得更好的稳定性")
        }
        if symmetry < 70 && visibility == .full {
            suggestions.append("注意左右动作的对称性")
        }

        return suggestions
    }
}

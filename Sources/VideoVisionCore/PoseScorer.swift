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

    /// 默认权重（经验值，总计 1.0）
    ///
    /// 膝盖弯曲权重最高（0.25）：腿部弹性是滑雪所有动作的基础。
    /// 前倾、小腿、重心各 0.20：三者共同决定姿态质量。
    /// 对称性 0.15：相对次要——不对称通常是其他问题的表现而非根源。
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

    /// 各阈值和权重的来源说明：
    ///
    /// 当前评分参数基于运动生物力学的一般原则和滑雪教练的实践经验，
    /// 并非来自严格控制的实验数据。它们应被视为"合理参考范围"，
    /// 而非权威判据。不同滑雪流派、地形、速度下，理想姿态会有差异。
    ///
    /// 计划后续通过以下方式校准：
    /// - 收集专业教练的人工评分作为 ground truth
    /// - 对比分析以调整阈值和权重
    /// - 按滑雪类型（道内/野雪/公园）提供不同的参数集

    /// 身体倾斜：理想 10°~60°
    /// 来源：PSIA 技术手册中关于"athletic stance"的躯干前倾角度参考范围。
    /// 注意：当前 2D 画面无法可靠区分前后倾和横向倒伏。高级刻画中的大幅侧倾
    /// 不应被当成后坐或姿态错误，因此上限放宽到 60°。
    public static let leanIdealMin = 10.0
    public static let leanIdealMax = 60.0
    /// 每偏离 5° 扣 10 分
    public static let leanPenaltyPer5Deg = 10.0

    /// 膝盖弯曲：理想 80°~135°
    /// 来源：人工校准样本显示，高级低姿态刻滑会出现更深屈膝，不应被当成错误。
    /// 大于 140° 更接近“腿太直”，会明显降低承压和表现力，因此采用更重惩罚。
    public static let kneeIdealMin = 80.0
    public static let kneeIdealMax = 135.0
    /// 深屈膝低于理想下限时轻微扣分，直腿高于理想上限时重扣分。
    public static let deepKneePenaltyPer10Deg = 4.0
    public static let straightLegPenaltyPer10Deg = 28.0

    /// 小腿倾斜（立刃幅度）：0°=0分, 80°=100分（越高越好）
    /// 来源：滑雪教练经验——立刃角度越大，走刃质量越好。
    /// 80° 是现实中侧向立刃可达到的极限参考值。
    public static let calfMaxScoreAngle = 80.0

    /// 重心评分 —— 基于 hipRatio 连续值的线性映射
    ///
    /// hipRatio 是髋部相对高度（0~1），越小 = 重心越低 = 姿态越好。
    /// 采用分段线性映射以保持与旧三档评分的粗略一致性：
    ///   hipRatio 0    → 100 分
    ///   hipRatio 0.18 → 90 分（旧"低"档中位）
    ///   hipRatio 0.45 → 60 分（旧"中"档中位）
    ///   hipRatio 0.78 → 30 分（旧"高"档中位）
    ///   hipRatio 1.0  → 10 分（下限）
    ///
    /// 公式：score = clamp(107.5 - hipRatio × 100, 10, 100)
    public static func gravityScore(from hipRatio: Double) -> Double {
        let raw = 107.5 - hipRatio * 100.0
        return max(10, min(100, raw))
    }

    /// 对称性：每偏离 5° 扣 10 分
    public static let symmetryPenaltyPer5Deg = 10.0

    // MARK: - 等级划分

    /// 等级阈值（经验划分，供参考）
    ///
    /// 四个等级大致对应：
    /// - 初级（0-59）：滑行中频繁出现姿态问题，转弯以推雪/扫雪为主
    /// - 中级（60-74）：能稳定控速，但转弯质量主要依赖搓雪
    /// - 高级（75-84）：有走刃意识，部分弯能看到刻滑影子
    /// - 专业（85-100）：姿态稳定，立刃质量好，动作干净
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
        let forwardLeanConfidence = confidenceForwardLean(pose)
        let kneeBendConfidence = confidenceKneeBend(pose)
        let calfLeanConfidence = confidenceCalfLean(pose)
        let gravityConfidence = confidenceGravity(pose)
        let symmetryConfidence = confidenceSymmetry(pose)

        let rawTotalScore = forwardLeanScore * weights.forwardLean
                         + kneeBendScore * weights.kneeBend
                         + calfLeanScore * weights.calfLean
                         + gravityScore * weights.gravity
                         + symmetryScore * weights.symmetry
        let totalScore = applyQualityCaps(
            rawTotalScore,
            kneeBendScore: kneeBendScore,
            kneeBendConfidence: kneeBendConfidence,
            symmetryScore: symmetryScore,
            symmetryConfidence: symmetryConfidence
        )
        let totalConfidence = weightedConfidence([
            (forwardLeanConfidence, weights.forwardLean),
            (kneeBendConfidence, weights.kneeBend),
            (calfLeanConfidence, weights.calfLean),
            (gravityConfidence, weights.gravity),
            (symmetryConfidence, weights.symmetry)
        ])

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
            totalConfidence: totalConfidence,
            forwardLeanConfidence: forwardLeanConfidence,
            kneeBendConfidence: kneeBendConfidence,
            calfLeanConfidence: calfLeanConfidence,
            gravityConfidence: gravityConfidence,
            symmetryConfidence: symmetryConfidence,
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
            totalConfidence: 0.2,
            forwardLeanConfidence: 0.2,
            kneeBendConfidence: 0.2,
            calfLeanConfidence: 0,
            gravityConfidence: 0.2,
            symmetryConfidence: 0,
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

        if avg >= Self.kneeIdealMin && avg <= Self.kneeIdealMax {
            return 100
        }
        if avg < Self.kneeIdealMin {
            let deviation = Self.kneeIdealMin - avg
            return max(65, 100 - (deviation / 10.0) * Self.deepKneePenaltyPer10Deg)
        }

        let deviation = avg - Self.kneeIdealMax
        return max(20, 100 - (deviation / 10.0) * Self.straightLegPenaltyPer10Deg)
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

    /// 重心评分（连续映射）
    /// hipRatio 越小 = 重心越低越好，无数据时默认 50 分
    private func scoreGravity(_ pose: BodyPoseData) -> Double {
        guard let cog = pose.centerOfGravity else { return 50 }
        return Self.gravityScore(from: cog.value)
    }

    private func applyQualityCaps(
        _ score: Double,
        kneeBendScore: Double,
        kneeBendConfidence: Double,
        symmetryScore: Double,
        symmetryConfidence: Double
    ) -> Double {
        var capped = score
        if kneeBendScore < 60, kneeBendConfidence >= AnalysisReliability.minimumPoseScoreConfidence {
            capped = min(capped, 72)
        }
        if symmetryScore < 45, symmetryConfidence >= AnalysisReliability.minimumPoseScoreConfidence {
            capped = min(capped, 72)
        }
        return capped
    }

    /// 对称性评分（加权）
    ///
    /// 不同维度的不对称对滑行质量的影响不同：
    /// - 膝盖弯曲不对称（权重 0.5）：影响转弯质量和重心分配，最关键
    /// - 小腿倾角不对称（权重 0.3）：影响立刃一致性
    /// - 前倾不对称（权重 0.2）：影响前后平衡
    ///
    /// 缺少某维度时，剩余维度权重按比例重新分配。
    private func scoreSymmetry(_ pose: BodyPoseData) -> Double {
        let leftK = pose.leftKneeBendAngle?.value
        let rightK = pose.rightKneeBendAngle?.value
        let leftC = pose.leftCalfLeanAngle?.value
        let rightC = pose.rightCalfLeanAngle?.value
        let leftL = pose.leftBodyLeanAngle?.value
        let rightL = pose.rightBodyLeanAngle?.value

        // 各维度的原始权重
        let kneeWeight = 0.5
        let calfWeight = 0.3
        let leanWeight = 0.2

        var activeWeight = 0.0
        var weightedScore = 0.0

        if let l = leftK, let r = rightK {
            let diff = abs(l - r)
            let dimScore = max(0, 100 - (diff / 5.0) * Self.symmetryPenaltyPer5Deg)
            weightedScore += dimScore * kneeWeight
            activeWeight += kneeWeight
        }
        if let l = leftC, let r = rightC {
            let diff = abs(l - r)
            let dimScore = max(0, 100 - (diff / 5.0) * Self.symmetryPenaltyPer5Deg)
            weightedScore += dimScore * calfWeight
            activeWeight += calfWeight
        }
        if let l = leftL, let r = rightL {
            let diff = abs(l - r)
            let dimScore = max(0, 100 - (diff / 5.0) * Self.symmetryPenaltyPer5Deg)
            weightedScore += dimScore * leanWeight
            activeWeight += leanWeight
        }

        guard activeWeight > 0 else { return 50 }
        // 按实际活跃权重归一化
        return weightedScore / activeWeight
    }

    // MARK: - 置信度计算

    private func confidenceForwardLean(_ pose: BodyPoseData) -> Double {
        if let lean = pose.bodyLeanAngle {
            return lean.confidence * visibilityMultiplier(pose.visibility)
        }
        let sideConfidences = [
            pose.leftBodyLeanAngle?.confidence,
            pose.rightBodyLeanAngle?.confidence
        ].compactMap { $0 }
        guard !sideConfidences.isEmpty else { return 0 }
        let coverage = sideConfidences.count == 2 ? 0.9 : 0.65
        return average(sideConfidences) * coverage * visibilityMultiplier(pose.visibility)
    }

    private func confidenceKneeBend(_ pose: BodyPoseData) -> Double {
        bilateralConfidence([
            pose.leftKneeBendAngle?.confidence,
            pose.rightKneeBendAngle?.confidence
        ], visibility: pose.visibility)
    }

    private func confidenceCalfLean(_ pose: BodyPoseData) -> Double {
        bilateralConfidence([
            pose.leftCalfLeanAngle?.confidence,
            pose.rightCalfLeanAngle?.confidence
        ], visibility: pose.visibility)
    }

    private func confidenceGravity(_ pose: BodyPoseData) -> Double {
        guard let confidence = pose.centerOfGravity?.confidence else { return 0 }
        return confidence * visibilityMultiplier(pose.visibility)
    }

    private func confidenceSymmetry(_ pose: BodyPoseData) -> Double {
        let dimensions: [(left: MetricWithConfidence<Double>?, right: MetricWithConfidence<Double>?, weight: Double)] = [
            (pose.leftKneeBendAngle, pose.rightKneeBendAngle, 0.5),
            (pose.leftCalfLeanAngle, pose.rightCalfLeanAngle, 0.3),
            (pose.leftBodyLeanAngle, pose.rightBodyLeanAngle, 0.2)
        ]

        var weighted = 0.0
        var activeWeight = 0.0
        for dimension in dimensions {
            guard let left = dimension.left, let right = dimension.right else { continue }
            weighted += min(left.confidence, right.confidence) * dimension.weight
            activeWeight += dimension.weight
        }
        guard activeWeight > 0 else { return 0 }
        return weighted / activeWeight * visibilityMultiplier(pose.visibility)
    }

    private func bilateralConfidence(_ values: [Double?], visibility: VisibilityLevel) -> Double {
        let confidences = values.compactMap { $0 }
        guard !confidences.isEmpty else { return 0 }
        let coverage = confidences.count == 2 ? 1.0 : 0.65
        return average(confidences) * coverage * visibilityMultiplier(visibility)
    }

    // MARK: - 辅助

    /// 通用角度评分：理想范围内满分，超出递进扣分
    private func scoreAngle(_ value: Double, idealMin: Double, idealMax: Double,
                           penaltyPerUnit: Double, unit: Double) -> Double {
        if value >= idealMin && value <= idealMax { return 100 }
        let deviation = min(abs(value - idealMin), abs(value - idealMax))
        return max(0, 100 - (deviation / unit) * penaltyPerUnit)
    }

    private func visibilityMultiplier(_ visibility: VisibilityLevel) -> Double {
        switch visibility {
        case .full:
            return 1.0
        case .partial:
            return 0.75
        case .minimal:
            return 0.35
        case .none:
            return 0
        }
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
            suggestions.append("调整躯干倾斜与重心位置，避免直立或失去支撑")
        }
        if kneeBend < 70 {
            suggestions.append("避免腿过直，保持有弹性的屈膝承压")
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

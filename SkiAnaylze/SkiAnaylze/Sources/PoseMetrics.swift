import Foundation
import Vision

// MARK: - 姿态指标计算器

/// 从 Vision 人体姿态观测中提取滑雪姿态指标
///
/// 职责：
/// - 获取关键点坐标
/// - 计算角度、重心等指标
/// - 评估可见性等级和置信度
struct PoseMetricsCalculator {

    /// 关键点检测置信度阈值，低于此值视为不可见
    let pointConfidenceThreshold: VNConfidence

    init(pointConfidenceThreshold: VNConfidence = 0.3) {
        self.pointConfidenceThreshold = pointConfidenceThreshold
    }

    // MARK: - 关键点定义

    /// 姿态分析需要用到的全部关键点
    private static let requiredJoints: [VNHumanBodyPoseObservation.JointName] = [
        .leftShoulder, .rightShoulder,
        .leftHip, .rightHip,
        .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle
    ]

    // MARK: - 主入口

    /// 从 Vision 人体姿态观测计算各项指标
    /// - Parameter observation: Vision 返回的人体姿态观测
    /// - Returns: 包含置信度的 BodyPoseData
    func compute(from observation: VNHumanBodyPoseObservation) -> BodyPoseData {
        let visibleJoints = Self.requiredJoints.filter { joint in
            (try? observation.recognizedPoint(joint))?.confidence ?? 0 > pointConfidenceThreshold
        }
        let visibleCount = visibleJoints.count
        let visibility: VisibilityLevel = {
            switch visibleCount {
            case 8:     return .full
            case 4...7: return .partial
            case 1...3: return .minimal
            default:    return .none
            }
        }()

        guard let result = extractPoints(from: observation), visibleCount >= 2 else {
            return BodyPoseData(
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

        let pts = result

        // 计算各项指标
        let leftLean = computeSideLeanAngle(
            shoulder: pts.leftShoulder, hip: pts.leftHip,
            label: "左侧",
            confidenceBase: Double(visibleCount) / 8.0
        )
        let rightLean = computeSideLeanAngle(
            shoulder: pts.rightShoulder, hip: pts.rightHip,
            label: "右侧",
            confidenceBase: Double(visibleCount) / 8.0
        )

        let overallLean = computeOverallLeanAngle(
            leftShoulder: pts.leftShoulder, rightShoulder: pts.rightShoulder,
            leftHip: pts.leftHip, rightHip: pts.rightHip,
            leftLean: leftLean, rightLean: rightLean,
            totalVisible: visibleCount
        )

        let leftKnee = computeKneeBend(
            hip: pts.leftHip, knee: pts.leftKnee, ankle: pts.leftAnkle,
            label: "左膝",
            confidenceBase: Double(visibleCount) / 8.0
        )
        let rightKnee = computeKneeBend(
            hip: pts.rightHip, knee: pts.rightKnee, ankle: pts.rightAnkle,
            label: "右膝",
            confidenceBase: Double(visibleCount) / 8.0
        )

        let leftCalf = computeCalfLean(
            knee: pts.leftKnee, ankle: pts.leftAnkle,
            label: "左小腿",
            confidenceBase: Double(visibleCount) / 8.0
        )
        let rightCalf = computeCalfLean(
            knee: pts.rightKnee, ankle: pts.rightAnkle,
            label: "右小腿",
            confidenceBase: Double(visibleCount) / 8.0
        )

        let gravity = computeRelativeCenterOfGravity(
            leftShoulder: pts.leftShoulder, rightShoulder: pts.rightShoulder,
            leftHip: pts.leftHip, rightHip: pts.rightHip,
            leftAnkle: pts.leftAnkle, rightAnkle: pts.rightAnkle,
            confidenceBase: Double(visibleCount) / 8.0
        )

        return BodyPoseData(
            detected: true,
            visibility: visibility,
            bodyLeanAngle: overallLean,
            leftBodyLeanAngle: leftLean,
            rightBodyLeanAngle: rightLean,
            leftKneeBendAngle: leftKnee,
            rightKneeBendAngle: rightKnee,
            leftCalfLeanAngle: leftCalf,
            rightCalfLeanAngle: rightCalf,
            centerOfGravity: gravity
        )
    }
}

// MARK: - 关键点提取

extension PoseMetricsCalculator {
    /// 提取所有需要的关键点坐标，置信度不足的返回 nil
    struct ExtractedPoints {
        let leftShoulder: CGPoint?
        let rightShoulder: CGPoint?
        let leftHip: CGPoint?
        let rightHip: CGPoint?
        let leftKnee: CGPoint?
        let rightKnee: CGPoint?
        let leftAnkle: CGPoint?
        let rightAnkle: CGPoint?
    }

    func extractPoints(from observation: VNHumanBodyPoseObservation) -> ExtractedPoints? {
        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let recognizedPoint = try? observation.recognizedPoint(joint),
                  recognizedPoint.confidence > pointConfidenceThreshold else {
                return nil
            }
            return recognizedPoint.location
        }

        return ExtractedPoints(
            leftShoulder: point(.leftShoulder),
            rightShoulder: point(.rightShoulder),
            leftHip: point(.leftHip),
            rightHip: point(.rightHip),
            leftKnee: point(.leftKnee),
            rightKnee: point(.rightKnee),
            leftAnkle: point(.leftAnkle),
            rightAnkle: point(.rightAnkle)
        )
    }
}

// MARK: - 角度计算

extension PoseMetricsCalculator {

    /// 计算三点夹角（度）
    /// - Parameters:
    ///   - a: 第一点
    ///   - b: 顶点（角点）
    ///   - c: 第三点
    /// - Returns: 角度（度），0~180
    func angleBetween(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        let ba = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let bc = CGPoint(x: c.x - b.x, y: c.y - b.y)
        let dot = ba.x * bc.x + ba.y * bc.y
        let lenBA = sqrt(ba.x * ba.x + ba.y * ba.y)
        let lenBC = sqrt(bc.x * bc.x + bc.y * bc.y)
        guard lenBA > 0, lenBC > 0 else { return 0 }
        let cosAngle = max(-1, min(1, dot / (lenBA * lenBC)))
        return acos(cosAngle) * 180 / Double.pi
    }

    /// 计算连线与垂直方向的夹角（度）
    /// - Parameters:
    ///   - top: 上方点
    ///   - bottom: 下方点
    /// - Returns: 倾斜角度（度），0~90
    func leanAngleFromVertical(from top: CGPoint, to bottom: CGPoint) -> Double {
        let dx = bottom.x - top.x
        let dy = bottom.y - top.y
        guard dy != 0 else { return 90 }
        let angleRad = atan(abs(dx) / abs(dy))
        return angleRad * 180 / Double.pi
    }
}

// MARK: - 指标计算

extension PoseMetricsCalculator {

    // MARK: 前倾角

    /// 计算单侧前倾角
    private func computeSideLeanAngle(
        shoulder: CGPoint?, hip: CGPoint?,
        label: String, confidenceBase: Double
    ) -> MetricWithConfidence<Double>? {
        guard let s = shoulder, let h = hip else { return nil }
        let dx = s.x - h.x
        let dy = s.y - h.y
        guard dy != 0 else { return nil }
        let angleRad = atan(abs(dx) / abs(dy))
        let angle = angleRad * 180 / Double.pi
        // 单侧只需要2个点，置信度略高
        let conf = min(confidenceBase + 0.15, 1.0)
        return MetricWithConfidence(value: angle, confidence: conf)
    }

    /// 计算整体前倾角（双侧均可见时取中点连线）
    private func computeOverallLeanAngle(
        leftShoulder: CGPoint?, rightShoulder: CGPoint?,
        leftHip: CGPoint?, rightHip: CGPoint?,
        leftLean: MetricWithConfidence<Double>?,
        rightLean: MetricWithConfidence<Double>?,
        totalVisible: Int
    ) -> MetricWithConfidence<Double>? {
        // 双侧均可见 → 使用中点连线
        if let lS = leftShoulder, let rS = rightShoulder,
           let lH = leftHip, let rH = rightHip {
            let shoulderMid = CGPoint(x: (lS.x + rS.x) / 2, y: (lS.y + rS.y) / 2)
            let hipMid = CGPoint(x: (lH.x + rH.x) / 2, y: (lH.y + rH.y) / 2)
            let dx = shoulderMid.x - hipMid.x
            let dy = shoulderMid.y - hipMid.y
            if dy != 0 {
                let angleRad = atan(abs(dx) / abs(dy))
                let angle = angleRad * 180 / Double.pi
                let conf = Double(totalVisible) / 8.0
                return MetricWithConfidence(value: angle, confidence: conf)
            }
        }
        // 单侧可见 → 用已有单侧数据
        if let left = leftLean, let right = rightLean {
            let avg = (left.value + right.value) / 2
            let conf = min(left.confidence, right.confidence)
            return MetricWithConfidence(value: avg, confidence: conf)
        }
        return leftLean ?? rightLean
    }

    // MARK: 膝盖弯曲

    private func computeKneeBend(
        hip: CGPoint?, knee: CGPoint?, ankle: CGPoint?,
        label: String, confidenceBase: Double
    ) -> MetricWithConfidence<Double>? {
        guard let h = hip, let k = knee, let a = ankle else { return nil }
        let angle = angleBetween(h, k, a)
        let conf = confidenceBase
        return MetricWithConfidence(value: angle, confidence: conf)
    }

    // MARK: 小腿倾斜（立刃）

    private func computeCalfLean(
        knee: CGPoint?, ankle: CGPoint?,
        label: String, confidenceBase: Double
    ) -> MetricWithConfidence<Double>? {
        guard let k = knee, let a = ankle else { return nil }
        let angle = leanAngleFromVertical(from: k, to: a)
        let conf = confidenceBase
        return MetricWithConfidence(value: angle, confidence: conf)
    }

    // MARK: 相对重心高度

    /// 计算相对重心高度（基于人体比例，与站位远近无关）
    ///
    /// 使用公式：`(髋部中点Y - 脚踝中点Y) / (肩膀中点Y - 脚踝中点Y)`
    ///
    /// Vision 坐标系：原点左下角，Y 向上递增。
    /// 所以肩膀 Y > 髋部 Y > 脚踝 Y。
    ///
    /// 结果解释：
    /// - 值越小 → 髋部越靠近脚踝 → **重心越低**（理想滑雪姿态）
    /// - 值越大 → 髋部越靠近肩膀 → **重心越高**
    private func computeRelativeCenterOfGravity(
        leftShoulder: CGPoint?, rightShoulder: CGPoint?,
        leftHip: CGPoint?, rightHip: CGPoint?,
        leftAnkle: CGPoint?, rightAnkle: CGPoint?,
        confidenceBase: Double
    ) -> MetricWithConfidence<String>? {
        let shoulderY: Double? = {
            if let l = leftShoulder, let r = rightShoulder { return Double((l.y + r.y) / 2) }
            if let s = leftShoulder { return Double(s.y) }
            if let s = rightShoulder { return Double(s.y) }
            return nil
        }()
        let hipY: Double? = {
            if let l = leftHip, let r = rightHip { return Double((l.y + r.y) / 2) }
            if let h = leftHip { return Double(h.y) }
            if let h = rightHip { return Double(h.y) }
            return nil
        }()
        let ankleY: Double? = {
            if let l = leftAnkle, let r = rightAnkle { return Double((l.y + r.y) / 2) }
            if let a = leftAnkle { return Double(a.y) }
            if let a = rightAnkle { return Double(a.y) }
            return nil
        }()

        guard let sY = shoulderY, let hY = hipY, let aY = ankleY else {
            return nil
        }

        let bodyHeight = sY - aY
        guard bodyHeight > 0 else { return nil }

        let hipRatio = (hY - aY) / bodyHeight  // 0~1，越小重心越低

        // 相对重心等级划分
        let level: String
        if hipRatio < 0.35 {
            level = "低"
        } else if hipRatio < 0.55 {
            level = "中"
        } else {
            level = "高"
        }

        let conf = confidenceBase
        return MetricWithConfidence(value: level, confidence: conf)
    }
}

import Foundation
import Vision

// MARK: - 姿态指标计算器

/// 从 Vision 人体姿态观测中提取滑雪姿态指标
///
/// 职责：
/// - 获取关键点坐标
/// - 计算角度、重心等指标
/// - 评估可见性等级和置信度
public struct PoseMetricsCalculator {

    /// 关键点检测置信度阈值，低于此值视为不可见
    public let pointConfidenceThreshold: VNConfidence

    public init(pointConfidenceThreshold: VNConfidence = 0.3) {
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
    public func compute(from observation: VNHumanBodyPoseObservation) -> BodyPoseData {
        let visibleJoints = Self.requiredJoints.filter { joint in
            (try? observation.recognizedPoint(joint))?.confidence ?? 0 > pointConfidenceThreshold
        }
        let visibleCount = visibleJoints.count

        let visibility: VisibilityLevel = {
            if visibleCount == 8 { return .full }
            if visibleCount >= 4 { return .partial }
            if visibleCount >= 1 { return .minimal }
            return .none
        }()

        guard let pts = extractPoints(from: observation), visibleCount >= 2 else {
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

        // 计算各项指标 —— 使用实际关键点置信度
        let leftLean = computeSideLeanAngle(
            shoulder: pts.leftShoulder, hip: pts.leftHip
        )
        let rightLean = computeSideLeanAngle(
            shoulder: pts.rightShoulder, hip: pts.rightHip
        )

        let overallLean = computeOverallLeanAngle(
            leftShoulder: pts.leftShoulder, rightShoulder: pts.rightShoulder,
            leftHip: pts.leftHip, rightHip: pts.rightHip,
            leftLean: leftLean, rightLean: rightLean,
            totalVisible: visibleCount
        )

        let leftKnee = computeKneeBend(
            hip: pts.leftHip, knee: pts.leftKnee, ankle: pts.leftAnkle
        )
        let rightKnee = computeKneeBend(
            hip: pts.rightHip, knee: pts.rightKnee, ankle: pts.rightAnkle
        )

        let leftCalf = computeCalfLean(
            knee: pts.leftKnee, ankle: pts.leftAnkle
        )
        let rightCalf = computeCalfLean(
            knee: pts.rightKnee, ankle: pts.rightAnkle
        )

        let gravity = computeRelativeCenterOfGravity(
            leftShoulder: pts.leftShoulder, rightShoulder: pts.rightShoulder,
            leftHip: pts.leftHip, rightHip: pts.rightHip,
            leftAnkle: pts.leftAnkle, rightAnkle: pts.rightAnkle
        )
        let signedBodyLean = computeSignedBodyLean(
            leftShoulder: pts.leftShoulder, rightShoulder: pts.rightShoulder,
            leftHip: pts.leftHip, rightHip: pts.rightHip
        )
        let signedCalfLean = computeSignedCalfLean(
            leftKnee: pts.leftKnee, rightKnee: pts.rightKnee,
            leftAnkle: pts.leftAnkle, rightAnkle: pts.rightAnkle
        )
        let hipCenterX = computeCenterX(pts.leftHip, pts.rightHip)
        let ankleCenterX = computeCenterX(pts.leftAnkle, pts.rightAnkle)
        let bodyCenterX = computeBodyCenterX(points: pts)
        let hipCenterY = computeCenterY(pts.leftHip, pts.rightHip)
        let ankleCenterY = computeCenterY(pts.leftAnkle, pts.rightAnkle)
        let bodyCenterY = computeBodyCenterY(points: pts)
        let ankleProxyBoardAngle = computeAnkleProxyBoardAngle(
            leftAnkle: pts.leftAnkle,
            rightAnkle: pts.rightAnkle
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
            centerOfGravity: gravity,
            signedBodyLeanAngle: signedBodyLean,
            signedCalfLeanAngle: signedCalfLean,
            hipCenterX: hipCenterX,
            ankleCenterX: ankleCenterX,
            bodyCenterX: bodyCenterX,
            hipCenterY: hipCenterY,
            ankleCenterY: ankleCenterY,
            bodyCenterY: bodyCenterY,
            ankleProxyBoardAngle: ankleProxyBoardAngle,
            leftShoulderPoint: poseJointPoint(pts.leftShoulder),
            rightShoulderPoint: poseJointPoint(pts.rightShoulder),
            leftHipPoint: poseJointPoint(pts.leftHip),
            rightHipPoint: poseJointPoint(pts.rightHip),
            leftKneePoint: poseJointPoint(pts.leftKnee),
            rightKneePoint: poseJointPoint(pts.rightKnee),
            leftAnklePoint: poseJointPoint(pts.leftAnkle),
            rightAnklePoint: poseJointPoint(pts.rightAnkle)
        )
    }
}

// MARK: - 带置信度的关键点

extension PoseMetricsCalculator {
    /// 单个关键点，包含坐标和 Vision 返回的原始置信度
    public struct JointPoint {
        public let location: CGPoint
        public let confidence: VNConfidence

        public init(location: CGPoint, confidence: VNConfidence) {
            self.location = location
            self.confidence = confidence
        }
    }
}

// MARK: - 关键点提取

extension PoseMetricsCalculator {
    /// 提取所有需要的关键点，含坐标和置信度。置信度不足的返回 nil
    public struct ExtractedPoints {
        public let leftShoulder: JointPoint?
        public let rightShoulder: JointPoint?
        public let leftHip: JointPoint?
        public let rightHip: JointPoint?
        public let leftKnee: JointPoint?
        public let rightKnee: JointPoint?
        public let leftAnkle: JointPoint?
        public let rightAnkle: JointPoint?

        public init(leftShoulder: JointPoint?, rightShoulder: JointPoint?, leftHip: JointPoint?, rightHip: JointPoint?, leftKnee: JointPoint?, rightKnee: JointPoint?, leftAnkle: JointPoint?, rightAnkle: JointPoint?) {
            self.leftShoulder = leftShoulder
            self.rightShoulder = rightShoulder
            self.leftHip = leftHip
            self.rightHip = rightHip
            self.leftKnee = leftKnee
            self.rightKnee = rightKnee
            self.leftAnkle = leftAnkle
            self.rightAnkle = rightAnkle
        }
    }

    public func extractPoints(from observation: VNHumanBodyPoseObservation) -> ExtractedPoints? {
        func jointPoint(_ joint: VNHumanBodyPoseObservation.JointName) -> JointPoint? {
            guard let recognizedPoint = try? observation.recognizedPoint(joint),
                  recognizedPoint.confidence > pointConfidenceThreshold else {
                return nil
            }
            return JointPoint(location: recognizedPoint.location, confidence: recognizedPoint.confidence)
        }

        return ExtractedPoints(
            leftShoulder: jointPoint(.leftShoulder),
            rightShoulder: jointPoint(.rightShoulder),
            leftHip: jointPoint(.leftHip),
            rightHip: jointPoint(.rightHip),
            leftKnee: jointPoint(.leftKnee),
            rightKnee: jointPoint(.rightKnee),
            leftAnkle: jointPoint(.leftAnkle),
            rightAnkle: jointPoint(.rightAnkle)
        )
    }

    private func poseJointPoint(_ point: JointPoint?) -> PoseJointPoint? {
        guard let point else { return nil }
        return PoseJointPoint(
            x: point.location.x,
            y: point.location.y,
            confidence: Double(point.confidence)
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
    public func angleBetween(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
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
    public func leanAngleFromVertical(from top: CGPoint, to bottom: CGPoint) -> Double {
        let dx = bottom.x - top.x
        let dy = bottom.y - top.y
        guard dy != 0 else { return 90 }
        let angleRad = atan(abs(dx) / abs(dy))
        return angleRad * 180 / Double.pi
    }

    /// 计算连线相对垂直方向的有符号夹角。正值表示 bottom 在 top 的画面右侧。
    public func signedLeanAngleFromVertical(from top: CGPoint, to bottom: CGPoint) -> Double {
        let dx = bottom.x - top.x
        let dy = bottom.y - top.y
        guard dy != 0 else { return dx >= 0 ? 90 : -90 }
        let angleRad = atan(Double(dx) / abs(Double(dy)))
        return angleRad * 180 / Double.pi
    }
}

// MARK: - 指标计算

extension PoseMetricsCalculator {

    // MARK: 前倾角

    /// 计算单侧前倾角（肩→髋连线与垂直方向夹角）
    /// 置信度取肩、髋两点置信度的均值
    private func computeSideLeanAngle(
        shoulder: JointPoint?, hip: JointPoint?
    ) -> MetricWithConfidence<Double>? {
        guard let s = shoulder, let h = hip else { return nil }
        let dx = s.location.x - h.location.x
        let dy = s.location.y - h.location.y
        guard dy != 0 else { return nil }
        let angleRad = atan(abs(dx) / abs(dy))
        let angle = angleRad * 180 / Double.pi
        let conf = (s.confidence + h.confidence) / 2
        return MetricWithConfidence(value: angle, confidence: Double(conf))
    }

    /// 计算整体前倾角（双侧均可见时取中点连线）
    private func computeOverallLeanAngle(
        leftShoulder: JointPoint?, rightShoulder: JointPoint?,
        leftHip: JointPoint?, rightHip: JointPoint?,
        leftLean: MetricWithConfidence<Double>?,
        rightLean: MetricWithConfidence<Double>?,
        totalVisible: Int
    ) -> MetricWithConfidence<Double>? {
        // 双侧均可见 → 使用中点连线，置信度取四点均值
        if let lS = leftShoulder, let rS = rightShoulder,
           let lH = leftHip, let rH = rightHip {
            let shoulderMid = CGPoint(x: (lS.location.x + rS.location.x) / 2, y: (lS.location.y + rS.location.y) / 2)
            let hipMid = CGPoint(x: (lH.location.x + rH.location.x) / 2, y: (lH.location.y + rH.location.y) / 2)
            let dx = shoulderMid.x - hipMid.x
            let dy = shoulderMid.y - hipMid.y
            if dy != 0 {
                let angleRad = atan(abs(dx) / abs(dy))
                let angle = angleRad * 180 / Double.pi
                let conf = (lS.confidence + rS.confidence + lH.confidence + rH.confidence) / 4
                return MetricWithConfidence(value: angle, confidence: Double(conf))
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
        hip: JointPoint?, knee: JointPoint?, ankle: JointPoint?
    ) -> MetricWithConfidence<Double>? {
        guard let h = hip, let k = knee, let a = ankle else { return nil }
        let angle = angleBetween(h.location, k.location, a.location)
        let conf = min(h.confidence, k.confidence, a.confidence)
        return MetricWithConfidence(value: angle, confidence: Double(conf))
    }

    // MARK: 小腿倾斜（立刃）

    private func computeCalfLean(
        knee: JointPoint?, ankle: JointPoint?
    ) -> MetricWithConfidence<Double>? {
        guard let k = knee, let a = ankle else { return nil }
        let angle = leanAngleFromVertical(from: k.location, to: a.location)
        let conf = (k.confidence + a.confidence) / 2
        return MetricWithConfidence(value: angle, confidence: Double(conf))
    }

    // MARK: 相对重心高度

    /// 计算相对重心高度（基于人体比例，与站位远近无关）
    ///
    /// 使用公式：`(髋部中点Y - 脚踝中点Y) / (肩膀中点Y - 脚踝中点Y)`
    ///
    /// Vision 坐标系：原点左下角，Y 向上递增。
    /// 所以肩膀 Y > 髋部 Y > 脚踝 Y。
    ///
    /// 返回 hipRatio（0~1 连续值）：
    /// - 值越小 → 髋部越靠近脚踝 → **重心越低**（理想滑雪姿态）
    /// - 值越大 → 髋部越靠近肩膀 → **重心越高**
    ///
    /// 置信度取所用关键点的均值。
    private func computeRelativeCenterOfGravity(
        leftShoulder: JointPoint?, rightShoulder: JointPoint?,
        leftHip: JointPoint?, rightHip: JointPoint?,
        leftAnkle: JointPoint?, rightAnkle: JointPoint?
    ) -> MetricWithConfidence<Double>? {
        let shoulderY: Double? = {
            if let l = leftShoulder, let r = rightShoulder { return Double((l.location.y + r.location.y) / 2) }
            if let s = leftShoulder { return Double(s.location.y) }
            if let s = rightShoulder { return Double(s.location.y) }
            return nil
        }()
        let hipY: Double? = {
            if let l = leftHip, let r = rightHip { return Double((l.location.y + r.location.y) / 2) }
            if let h = leftHip { return Double(h.location.y) }
            if let h = rightHip { return Double(h.location.y) }
            return nil
        }()
        let ankleY: Double? = {
            if let l = leftAnkle, let r = rightAnkle { return Double((l.location.y + r.location.y) / 2) }
            if let a = leftAnkle { return Double(a.location.y) }
            if let a = rightAnkle { return Double(a.location.y) }
            return nil
        }()

        guard let sY = shoulderY, let hY = hipY, let aY = ankleY else { return nil }

        let bodyHeight = sY - aY
        guard bodyHeight > 0 else { return nil }

        let hipRatio = (hY - aY) / bodyHeight  // 0~1，越小重心越低

        // 置信度：取所有成功获取的关键点的平均置信度
        var confSum = 0.0
        var confCount = 0
        for jp in [leftShoulder, rightShoulder, leftHip, rightHip, leftAnkle, rightAnkle] {
            if let c = jp?.confidence { confSum += Double(c); confCount += 1 }
        }
        let conf = confCount > 0 ? confSum / Double(confCount) : 0.0

        return MetricWithConfidence(value: hipRatio, confidence: conf)
    }

    // MARK: 转弯阶段方向特征

    private func computeSignedBodyLean(
        leftShoulder: JointPoint?, rightShoulder: JointPoint?,
        leftHip: JointPoint?, rightHip: JointPoint?
    ) -> MetricWithConfidence<Double>? {
        guard let shoulder = midpoint(leftShoulder, rightShoulder),
              let hip = midpoint(leftHip, rightHip) else {
            return nil
        }
        let angle = signedLeanAngleFromVertical(from: shoulder.location, to: hip.location)
        let conf = min(shoulder.confidence, hip.confidence)
        return MetricWithConfidence(value: angle, confidence: Double(conf))
    }

    private func computeSignedCalfLean(
        leftKnee: JointPoint?, rightKnee: JointPoint?,
        leftAnkle: JointPoint?, rightAnkle: JointPoint?
    ) -> MetricWithConfidence<Double>? {
        var weightedSum = 0.0
        var totalConfidence = 0.0

        func add(knee: JointPoint?, ankle: JointPoint?) {
            guard let knee, let ankle else { return }
            let confidence = Double((knee.confidence + ankle.confidence) / 2)
            let angle = signedLeanAngleFromVertical(from: knee.location, to: ankle.location)
            weightedSum += angle * confidence
            totalConfidence += confidence
        }

        add(knee: leftKnee, ankle: leftAnkle)
        add(knee: rightKnee, ankle: rightAnkle)

        guard totalConfidence > 0 else { return nil }
        return MetricWithConfidence(value: weightedSum / totalConfidence, confidence: totalConfidence / (leftKnee != nil && rightKnee != nil ? 2.0 : 1.0))
    }

    private func computeCenterX(_ first: JointPoint?, _ second: JointPoint?) -> MetricWithConfidence<Double>? {
        guard let center = midpoint(first, second) else { return nil }
        return MetricWithConfidence(value: Double(center.location.x), confidence: Double(center.confidence))
    }

    private func computeCenterY(_ first: JointPoint?, _ second: JointPoint?) -> MetricWithConfidence<Double>? {
        guard let center = midpoint(first, second) else { return nil }
        return MetricWithConfidence(value: Double(center.location.y), confidence: Double(center.confidence))
    }

    private func computeBodyCenterX(points: ExtractedPoints) -> MetricWithConfidence<Double>? {
        let centers = [
            midpoint(points.leftShoulder, points.rightShoulder),
            midpoint(points.leftHip, points.rightHip),
            midpoint(points.leftAnkle, points.rightAnkle)
        ].compactMap { $0 }

        guard !centers.isEmpty else { return nil }
        let value = centers.map { Double($0.location.x) }.reduce(0, +) / Double(centers.count)
        let confidence = centers.map { Double($0.confidence) }.reduce(0, +) / Double(centers.count)
        return MetricWithConfidence(value: value, confidence: confidence)
    }

    private func computeBodyCenterY(points: ExtractedPoints) -> MetricWithConfidence<Double>? {
        let centers = [
            midpoint(points.leftShoulder, points.rightShoulder),
            midpoint(points.leftHip, points.rightHip),
            midpoint(points.leftAnkle, points.rightAnkle)
        ].compactMap { $0 }

        guard !centers.isEmpty else { return nil }
        let value = centers.map { Double($0.location.y) }.reduce(0, +) / Double(centers.count)
        let confidence = centers.map { Double($0.confidence) }.reduce(0, +) / Double(centers.count)
        return MetricWithConfidence(value: value, confidence: confidence)
    }

    private func computeAnkleProxyBoardAngle(
        leftAnkle: JointPoint?,
        rightAnkle: JointPoint?
    ) -> MetricWithConfidence<Double>? {
        guard let leftAnkle, let rightAnkle else { return nil }

        let dx = Double(rightAnkle.location.x - leftAnkle.location.x)
        let dy = Double(rightAnkle.location.y - leftAnkle.location.y)
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > 0.001 else { return nil }

        let angle = normalizeAngle(atan2(dy, dx) * 180 / Double.pi)
        let pointConfidence = Double((leftAnkle.confidence + rightAnkle.confidence) / 2)
        let geometryConfidence = clamp(distance * 12.0, lower: 0, upper: 1)
        return MetricWithConfidence(value: angle, confidence: pointConfidence * geometryConfidence)
    }



    private func midpoint(_ first: JointPoint?, _ second: JointPoint?) -> JointPoint? {
        if let first, let second {
            return JointPoint(
                location: CGPoint(
                    x: (first.location.x + second.location.x) / 2,
                    y: (first.location.y + second.location.y) / 2
                ),
                confidence: (first.confidence + second.confidence) / 2
            )
        }
        return first ?? second
    }
}

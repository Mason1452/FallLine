import Foundation

/// PoseSmoother
///
/// 用 1€ Filter 对整段 `[DetectionResult]` 中的姿态角度信号做时序平滑，
/// 消除 Vision 逐帧检测的抖动，再重新调用 PoseScorer 计算每帧评分。
///
/// 平滑作用于所有 `MetricWithConfidence<Double>` 的角度/坐标字段，置信度保持不变。
/// 缺失帧（value=nil）不喂入滤波器，避免 gap 破坏时序连续性。
public enum PoseSmoother {

    /// 平滑参数（滑雪场景推荐值）。
    ///
    /// 关节角度平滑度 vs 响应速度权衡：
    /// - minCutoff 越小 → 越平滑但延迟越大
    /// - beta 越大 → 快速动作时越保留细节但抖动过滤越弱
    public struct Config {
        public let angleMinCutoff: Double
        public let angleBeta: Double
        public let coordinateMinCutoff: Double
        public let coordinateBeta: Double

        public init(
            angleMinCutoff: Double = 1.2,
            angleBeta: Double = 0.02,
            coordinateMinCutoff: Double = 1.5,
            coordinateBeta: Double = 0.03
        ) {
            self.angleMinCutoff = angleMinCutoff
            self.angleBeta = angleBeta
            self.coordinateMinCutoff = coordinateMinCutoff
            self.coordinateBeta = coordinateBeta
        }

        public static let `default` = Config()
    }

    /// 对整段检测结果做时序平滑，并用平滑后的姿态重算 PoseScore。
    /// - Parameters:
    ///   - results: 原始检测结果（按 time 升序）
    ///   - scorer: 用于重新评分的 PoseScorer
    ///   - config: 滤波器参数
    /// - Returns: 与输入等长的、平滑后的检测结果
    public static func smooth(
        _ results: [DetectionResult],
        scorer: PoseScorer,
        config: Config = .default
    ) -> [DetectionResult] {
        guard results.count >= 3 else { return results }

        // 每类信号一个滤波器组。使用不同参数以匹配信号性质。
        let angleFilters = MultiOneEuroFilter { OneEuroFilter(minCutoff: config.angleMinCutoff, beta: config.angleBeta) }
        let coordFilters = MultiOneEuroFilter { OneEuroFilter(minCutoff: config.coordinateMinCutoff, beta: config.coordinateBeta) }

        return results.map { detection in
            let pose = detection.bodyPose
            guard pose.detected else { return detection }

            let t = detection.time

            let smoothed = BodyPoseData(
                detected: pose.detected,
                visibility: pose.visibility,
                bodyLeanAngle: filterMetric(pose.bodyLeanAngle, key: "bodyLean", t: t, using: angleFilters),
                leftBodyLeanAngle: filterMetric(pose.leftBodyLeanAngle, key: "leftBodyLean", t: t, using: angleFilters),
                rightBodyLeanAngle: filterMetric(pose.rightBodyLeanAngle, key: "rightBodyLean", t: t, using: angleFilters),
                leftKneeBendAngle: filterMetric(pose.leftKneeBendAngle, key: "leftKnee", t: t, using: angleFilters),
                rightKneeBendAngle: filterMetric(pose.rightKneeBendAngle, key: "rightKnee", t: t, using: angleFilters),
                leftCalfLeanAngle: filterMetric(pose.leftCalfLeanAngle, key: "leftCalf", t: t, using: angleFilters),
                rightCalfLeanAngle: filterMetric(pose.rightCalfLeanAngle, key: "rightCalf", t: t, using: angleFilters),
                centerOfGravity: filterMetric(pose.centerOfGravity, key: "cog", t: t, using: coordFilters),
                signedBodyLeanAngle: filterMetric(pose.signedBodyLeanAngle, key: "signedBodyLean", t: t, using: angleFilters),
                signedCalfLeanAngle: filterMetric(pose.signedCalfLeanAngle, key: "signedCalf", t: t, using: angleFilters),
                hipCenterX: filterMetric(pose.hipCenterX, key: "hipX", t: t, using: coordFilters),
                ankleCenterX: filterMetric(pose.ankleCenterX, key: "ankleX", t: t, using: coordFilters),
                bodyCenterX: filterMetric(pose.bodyCenterX, key: "bodyX", t: t, using: coordFilters),
                hipCenterY: filterMetric(pose.hipCenterY, key: "hipY", t: t, using: coordFilters),
                ankleCenterY: filterMetric(pose.ankleCenterY, key: "ankleY", t: t, using: coordFilters),
                bodyCenterY: filterMetric(pose.bodyCenterY, key: "bodyY", t: t, using: coordFilters),
                ankleProxyBoardAngle: filterMetric(pose.ankleProxyBoardAngle, key: "boardAngle", t: t, using: angleFilters),
                leftShoulderPoint: pose.leftShoulderPoint,
                rightShoulderPoint: pose.rightShoulderPoint,
                leftHipPoint: pose.leftHipPoint,
                rightHipPoint: pose.rightHipPoint,
                leftKneePoint: pose.leftKneePoint,
                rightKneePoint: pose.rightKneePoint,
                leftAnklePoint: pose.leftAnklePoint,
                rightAnklePoint: pose.rightAnklePoint
            )

            let newScore = scorer.score(pose: smoothed)

            return DetectionResult(
                time: detection.time,
                objects: detection.objects,
                faces: detection.faces,
                textObservations: detection.textObservations,
                sceneClassifications: detection.sceneClassifications,
                bodyPose: smoothed,
                poseScore: newScore,
                visualBoardObservation: detection.visualBoardObservation,
                skiMetrics: detection.skiMetrics,
                error: detection.error
            )
        }
    }

    // MARK: - 内部

    /// 对单个 MetricWithConfidence 做滤波，nil 值直传，置信度保持不变。
    private static func filterMetric(
        _ metric: MetricWithConfidence<Double>?,
        key: String,
        t: Double,
        using filters: MultiOneEuroFilter
    ) -> MetricWithConfidence<Double>? {
        guard let m = metric else { return nil }
        let filtered = filters.filter(m.value, key: key, timestamp: t)
        return MetricWithConfidence(value: filtered, confidence: m.confidence)
    }
}

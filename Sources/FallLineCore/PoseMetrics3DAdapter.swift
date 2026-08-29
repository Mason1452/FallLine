import Foundation
import Vision
import simd

/// PoseMetrics3DAdapter
///
/// 将 `VNHumanBodyPose3DObservation` 中的 3D 关节位置转换为角度指标，
/// 用于补强现有基于 2D 图像投影的 `PoseMetricsCalculator`。
///
/// 设计目标：3D 观测提供的是真实空间的 metric，可以消除 2D 图像的透视歧义。
/// 目前只重写膝弯角（评分权重最大且最受透视影响的维度），
/// 其他角度暂时保持 2D 值以避免全量迁移带来的阈值失配。
public enum PoseMetrics3DAdapter {

    /// 从 3D 观测计算膝弯角（大腿-小腿夹角），单位度。
    /// - Parameter observation: Vision 3D 姿态观测（macOS 14+）
    /// - Returns: (leftKneeBend, rightKneeBend)，其中值为 (angleDegrees, confidence)；不可用时为 nil
    @available(macOS 14.0, iOS 17.0, *)
    public static func kneeBendAngles(
        from observation: VNHumanBodyPose3DObservation
    ) -> (left: MetricWithConfidence<Double>?, right: MetricWithConfidence<Double>?) {
        let left = kneeBendAngle(observation, hip: .leftHip, knee: .leftKnee, ankle: .leftAnkle)
        let right = kneeBendAngle(observation, hip: .rightHip, knee: .rightKnee, ankle: .rightAnkle)
        return (left, right)
    }

    /// 将 3D 观测的信息合并到基于 2D 计算的 BodyPoseData 上，
    /// 仅重写膝弯角字段（其他字段保持不变）。
    ///
    /// 若 3D 观测不可用或关节缺失，返回原始 pose 不变。
    @available(macOS 14.0, iOS 17.0, *)
    public static func fuse(
        base2D pose: BodyPoseData,
        with observation: VNHumanBodyPose3DObservation?
    ) -> BodyPoseData {
        guard pose.detected, let obs = observation else { return pose }

        let (l, r) = kneeBendAngles(from: obs)

        return BodyPoseData(
            detected: pose.detected,
            visibility: pose.visibility,
            bodyLeanAngle: pose.bodyLeanAngle,
            leftBodyLeanAngle: pose.leftBodyLeanAngle,
            rightBodyLeanAngle: pose.rightBodyLeanAngle,
            leftKneeBendAngle: l ?? pose.leftKneeBendAngle,
            rightKneeBendAngle: r ?? pose.rightKneeBendAngle,
            leftCalfLeanAngle: pose.leftCalfLeanAngle,
            rightCalfLeanAngle: pose.rightCalfLeanAngle,
            centerOfGravity: pose.centerOfGravity,
            signedBodyLeanAngle: pose.signedBodyLeanAngle,
            signedCalfLeanAngle: pose.signedCalfLeanAngle,
            hipCenterX: pose.hipCenterX,
            ankleCenterX: pose.ankleCenterX,
            bodyCenterX: pose.bodyCenterX,
            hipCenterY: pose.hipCenterY,
            ankleCenterY: pose.ankleCenterY,
            bodyCenterY: pose.bodyCenterY,
            ankleProxyBoardAngle: pose.ankleProxyBoardAngle,
            leftShoulderPoint: pose.leftShoulderPoint,
            rightShoulderPoint: pose.rightShoulderPoint,
            leftHipPoint: pose.leftHipPoint,
            rightHipPoint: pose.rightHipPoint,
            leftKneePoint: pose.leftKneePoint,
            rightKneePoint: pose.rightKneePoint,
            leftAnklePoint: pose.leftAnklePoint,
            rightAnklePoint: pose.rightAnklePoint
        )
    }

    // MARK: - 内部：从 3 个关节计算膝弯角

    @available(macOS 14.0, iOS 17.0, *)
    private static func kneeBendAngle(
        _ observation: VNHumanBodyPose3DObservation,
        hip: VNHumanBodyPose3DObservation.JointName,
        knee: VNHumanBodyPose3DObservation.JointName,
        ankle: VNHumanBodyPose3DObservation.JointName
    ) -> MetricWithConfidence<Double>? {
        guard let hipPos = jointPosition(observation, hip),
              let kneePos = jointPosition(observation, knee),
              let anklePos = jointPosition(observation, ankle) else {
            return nil
        }

        let thigh = simd_normalize(hipPos - kneePos)
        let shank = simd_normalize(anklePos - kneePos)
        let cosTheta = simd_clamp(simd_dot(thigh, shank), -1.0, 1.0)
        let angleRad = Double(acosf(cosTheta))
        let angleDeg = angleRad * 180.0 / .pi

        // 3D 观测的关节置信度目前 Vision SDK 未公开单点 confidence，
        // 但整体检测的可靠性可以用两个次要指标之一近似——这里给一个偏保守的固定高置信，
        // 依赖上层的 2D 置信度做门槛（3D 只在 2D 也检测到的帧生效）。
        return MetricWithConfidence(value: angleDeg, confidence: 0.9)
    }

    /// 从 3D 观测的关节 4x4 变换中提取位置向量
    @available(macOS 14.0, iOS 17.0, *)
    private static func jointPosition(
        _ observation: VNHumanBodyPose3DObservation,
        _ joint: VNHumanBodyPose3DObservation.JointName
    ) -> simd_float3? {
        guard let point = try? observation.recognizedPoint(joint) else { return nil }
        let m = point.position
        return simd_float3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }
}

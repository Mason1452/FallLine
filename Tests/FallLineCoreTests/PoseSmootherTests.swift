import XCTest
@testable import FallLineCore

// MARK: - PoseSmoother 测试
//
// 2026-09-01 P0 落地：在 1€ Filter 之前对 knee/calf 关节角度做 3 帧中位数预处理，
// 抹掉孤立尖峰。以下用例覆盖预滤行为、边界处理及不影响的字段。

final class PoseSmootherTests: XCTestCase {

    // MARK: - despikeJointAngles 端到端行为

    /// 孤立尖峰：knee 序列 [100, 100, 40, 100, 100] 中的 40° 应被中位数抹回 100°
    /// （3 帧窗口 [100, 40, 100] 的中位数 = 100）。
    func test_smooth_isolatedKneeSpike_isAttenuated() {
        let raw = [100.0, 100.0, 40.0, 100.0, 100.0]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(time: Double(i) * 0.2, leftKnee: v, rightKnee: v, leftCalf: 45, rightCalf: 45)
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let leftKnees = smoothed.map { $0.bodyPose.leftKneeBendAngle?.value ?? -1 }

        XCTAssertEqual(leftKnees.count, 5)
        XCTAssertGreaterThan(leftKnees[2], 90.0,
                             "位于孤立尖峰位置的第 3 帧应被中位数抹回 ~100°，实测 \(leftKnees[2])°")
    }

    /// 连续 2 帧的真实峰值不应被误伤：knee [100, 40, 40, 100, 100] 中间两帧仍应保持低角度。
    /// （3 帧窗口 [100, 40, 40] median = 40；[40, 40, 100] median = 40）。
    func test_smooth_twoFramePeak_isPreserved() {
        let raw = [100.0, 40.0, 40.0, 100.0, 100.0]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(time: Double(i) * 0.2, leftKnee: v, rightKnee: v, leftCalf: 45, rightCalf: 45)
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let leftKnees = smoothed.map { $0.bodyPose.leftKneeBendAngle?.value ?? -1 }

        XCTAssertLessThan(leftKnees[1], 60.0,
                          "第 2 帧应保留在 40° 附近（median 会取窗口中值 40），实测 \(leftKnees[1])°")
        XCTAssertLessThan(leftKnees[2], 60.0,
                          "第 3 帧同样应保留在 40° 附近，实测 \(leftKnees[2])°")
    }

    /// 短序列 (<3 帧) 直接返回，不做任何预滤。
    func test_smooth_shortSequence_bypassesDespike() {
        let frames = [
            makeFrame(time: 0.0, leftKnee: 100, rightKnee: 100, leftCalf: 45, rightCalf: 45),
            makeFrame(time: 0.2, leftKnee: 40, rightKnee: 40, leftCalf: 45, rightCalf: 45)
        ]

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        XCTAssertEqual(smoothed.count, 2)
        XCTAssertEqual(smoothed[0].bodyPose.leftKneeBendAngle?.value ?? -1, 100, accuracy: 0.01)
        XCTAssertEqual(smoothed[1].bodyPose.leftKneeBendAngle?.value ?? -1, 40, accuracy: 0.01)
    }

    /// bodyLean 不在预滤名单里 → 应经过 1€ Filter 但不被 median 抹平。
    /// 用极端尖峰验证：如果 bodyLean 被 median 抹掉，第 3 帧值应回到 ~20°。
    /// 但实际上 1€ Filter 参数 minCutoff=1.2 允许突变通过，第 3 帧应保留较高值。
    func test_smooth_bodyLean_notDespiked() {
        let frames = (0..<5).map { i -> DetectionResult in
            let leanValue = (i == 2) ? 60.0 : 20.0
            return makeFrame(
                time: Double(i) * 0.2,
                leftKnee: 100, rightKnee: 100, leftCalf: 45, rightCalf: 45,
                bodyLean: leanValue
            )
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let leans = smoothed.map { $0.bodyPose.bodyLeanAngle?.value ?? -1 }

        // 未预滤 → 尖峰应至少残留部分（1€ 有平滑作用，但不会像 median 那样直接抹掉）
        // 判据：第 3 帧的 lean 值应显著大于第 1、5 帧的 20°（median 抹了就会 ~20°）
        XCTAssertGreaterThan(leans[2], 25.0,
                             "bodyLean 未在 despike 名单里，尖峰不应被完全抹平，实测 \(leans[2])°")
    }

    // MARK: - Helpers

    private func makeFrame(
        time: Double,
        leftKnee: Double?,
        rightKnee: Double?,
        leftCalf: Double?,
        rightCalf: Double?,
        bodyLean: Double? = 20
    ) -> DetectionResult {
        DetectionResult(
            time: time,
            objects: [],
            faces: [],
            textObservations: [],
            sceneClassifications: [],
            bodyPose: BodyPoseData(
                detected: true,
                visibility: .full,
                bodyLeanAngle: bodyLean.map { MetricWithConfidence(value: $0, confidence: 0.9) },
                leftBodyLeanAngle: nil,
                rightBodyLeanAngle: nil,
                leftKneeBendAngle: leftKnee.map { MetricWithConfidence(value: $0, confidence: 0.9) },
                rightKneeBendAngle: rightKnee.map { MetricWithConfidence(value: $0, confidence: 0.9) },
                leftCalfLeanAngle: leftCalf.map { MetricWithConfidence(value: $0, confidence: 0.9) },
                rightCalfLeanAngle: rightCalf.map { MetricWithConfidence(value: $0, confidence: 0.9) },
                centerOfGravity: nil,
                hipCenterX: MetricWithConfidence(value: 0.5, confidence: 0.9),
                ankleCenterX: MetricWithConfidence(value: 0.5, confidence: 0.9),
                bodyCenterX: MetricWithConfidence(value: 0.5, confidence: 0.9),
                hipCenterY: MetricWithConfidence(value: 0.7, confidence: 0.9),
                ankleCenterY: MetricWithConfidence(value: 0.5, confidence: 0.9),
                bodyCenterY: MetricWithConfidence(value: 0.5, confidence: 0.9),
                ankleProxyBoardAngle: nil
            ),
            poseScore: nil
        )
    }
}

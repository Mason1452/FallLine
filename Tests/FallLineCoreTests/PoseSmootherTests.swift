import XCTest
@testable import FallLineCore

// MARK: - PoseSmoother 测试
//
// 2026-09-01 P0-A 落地：在 1€ Filter 之前对 knee/calf 关节角度做 3 帧中位数预处理。
// 2026-09-03 P0b  落地：扩展 despike 覆盖 bodyLean / left/right bodyLean（3 组无符号）。
// 2026-09-01 P4-A 落地：在 despike 之后对 knee/calf 短空洞做邻域中位数插值。
// 以下用例覆盖预滤行为、边界处理、插值语义及不影响的字段。

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

    /// P0b (2026-09-03) 落地：bodyLean 已加入 despike 名单，尖峰应被 median 抹平。
    /// 用极端尖峰验证：knee=[20, 20, 60, 20, 20] 中间帧的 60° 应被回落到 ~20°。
    func test_smooth_bodyLean_isDespikedAfterP0b() {
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

        // P0b: 3 帧窗口 [20, 60, 20] 中位数 = 20 → 第 3 帧应被抹回 ~20°
        XCTAssertLessThan(leans[2], 30.0,
                          "bodyLean 已进入 P0b despike 名单，孤立尖峰应被 median 抹回 ~20°，实测 \(leans[2])°")
    }

    /// P0b: 连续 2 帧的真实 lean 峰值不应被误伤（对称于 knee 峰值保留用例）。
    /// bodyLean [20, 60, 60, 20, 20]：中间两帧仍应保留在 60° 附近。
    func test_smooth_bodyLeanTwoFramePeak_isPreserved() {
        let raw = [20.0, 60.0, 60.0, 20.0, 20.0]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(
                time: Double(i) * 0.2,
                leftKnee: 100, rightKnee: 100, leftCalf: 45, rightCalf: 45,
                bodyLean: v
            )
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let leans = smoothed.map { $0.bodyPose.bodyLeanAngle?.value ?? -1 }

        // 3 帧窗口 [20, 60, 60] median = 60；[60, 60, 20] median = 60
        // 1€ Filter 后允许有一定平滑，但应保留在 40°+ 显著高于起点 20°
        XCTAssertGreaterThan(leans[1], 40.0,
                             "第 2 帧连续峰值应保留（median 取 60），实测 \(leans[1])°")
        XCTAssertGreaterThan(leans[2], 40.0,
                             "第 3 帧连续峰值应保留（median 取 60），实测 \(leans[2])°")
    }

    /// P0b: 边界帧（首末）保留原值，这是 medianWindow 的已知折中。
    /// bodyLean [80, 20, 20, 20, 80]：首末孤立高值不会被抹掉（无 3 邻居）。
    func test_smooth_bodyLeanBoundary_preservesRawValue() {
        let raw = [80.0, 20.0, 20.0, 20.0, 80.0]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(
                time: Double(i) * 0.2,
                leftKnee: 100, rightKnee: 100, leftCalf: 45, rightCalf: 45,
                bodyLean: v
            )
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let leans = smoothed.map { $0.bodyPose.bodyLeanAngle?.value ?? -1 }

        // 首帧原值 80° 应保留（1€ 首帧 = 原值）；末帧同理
        // 若 medianWindow 覆盖了首末，会用偏置窗口抹到 ~20°；当前策略保留 80°
        XCTAssertGreaterThan(leans[0], 60.0,
                             "首帧应保留原值 ~80°（边界折中），实测 \(leans[0])°")
        XCTAssertGreaterThan(leans[4], 60.0,
                             "末帧应保留原值 ~80°（边界折中），实测 \(leans[4])°")
    }

    // MARK: - P4-A 短空洞插值

    /// 单帧 nil：knee=[100,100,nil,100,100] 中间帧应被邻居中位数 100° 补上。
    func test_impute_singleFrameGap_isFilled() {
        let raw: [Double?] = [100, 100, nil, 100, 100]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(time: Double(i) * 0.2, leftKnee: v, rightKnee: v, leftCalf: 45, rightCalf: 45)
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let leftKnee = smoothed[2].bodyPose.leftKneeBendAngle

        XCTAssertNotNil(leftKnee, "单帧 nil 应被插值恢复")
        XCTAssertEqual(leftKnee?.value ?? -1, 100, accuracy: 5.0,
                       "插值应恢复到邻域中位数 100° 附近，实测 \(leftKnee?.value ?? -1)°")
        XCTAssertLessThanOrEqual(leftKnee?.confidence ?? 1.0,
                                 AnalysisReliability.minimumPoseScoreConfidence,
                                 "插值 confidence 应 <= minimumPoseScoreConfidence，"
                                 + "让 smoothConfidenceWeight 压到 ~0.0625 避免污染 bilateralConfidence")
    }

    /// 连续 2 帧 nil：knee=[100,100,nil,nil,100,100] 两个空洞都应被补上
    /// （每个空帧窗口内至少 2 个健康邻居可用）。
    func test_impute_twoFrameGap_isFilled() {
        let raw: [Double?] = [100, 100, nil, nil, 100, 100]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(time: Double(i) * 0.2, leftKnee: v, rightKnee: v, leftCalf: 45, rightCalf: 45)
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())

        XCTAssertNotNil(smoothed[2].bodyPose.leftKneeBendAngle, "空洞第 1 帧应被补上")
        XCTAssertNotNil(smoothed[3].bodyPose.leftKneeBendAngle, "空洞第 2 帧应被补上")
    }

    /// 长空洞（连续 3 帧以上）不应被插值 —— 邻居健康数不足或全 nil。
    /// knee=[100, nil, nil, nil, nil, 100]：中间 4 帧因窗口内健康邻居 <2，不应造分。
    func test_impute_longGap_notFilled() {
        let raw: [Double?] = [100, nil, nil, nil, nil, 100]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(time: Double(i) * 0.2, leftKnee: v, rightKnee: v, leftCalf: 45, rightCalf: 45)
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())

        // 索引 2、3 距最近健康值 (0/5) 均超过 window(=2)：健康邻居数=0 → 不补
        XCTAssertNil(smoothed[2].bodyPose.leftKneeBendAngle,
                     "距最近健康帧超过窗口，不应插值")
        XCTAssertNil(smoothed[3].bodyPose.leftKneeBendAngle,
                     "距最近健康帧超过窗口，不应插值")
    }

    /// 现有健康值不被替换：所有帧都有值时输出保持连续。
    func test_impute_healthyValues_notReplaced() {
        let raw = [100.0, 95.0, 90.0, 95.0, 100.0]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(time: Double(i) * 0.2, leftKnee: v, rightKnee: v, leftCalf: 45, rightCalf: 45)
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())

        // 插值层不动，1€/median 会做轻微平滑；只需确认没有 nil / confidence 未被降低
        for (i, det) in smoothed.enumerated() {
            let k = det.bodyPose.leftKneeBendAngle
            XCTAssertNotNil(k, "第 \(i) 帧值应保留")
            XCTAssertGreaterThan(k?.confidence ?? 0, 0.5, "健康 confidence 不应被插值层降级")
        }
    }

    /// 端到端：video 4 t=17.6-18.2s 场景复现 —— 5 帧连续 calf=nil 被短窗健康邻居补上，
    /// PoseScore.calfLeanScore 应从阶跃 0 恢复为连续值。
    func test_impute_calfCollapseScenario_restoresContinuousScore() {
        // 模拟：前后各 3 帧健康（calf=45°），中间 2 帧 calf=nil。
        // 中间 2 帧仍在窗口 [i-2, i+2] 内能看到 2+ 个健康邻居，应被补上。
        let calfSeries: [Double?] = [45, 45, 45, nil, nil, 45, 45, 45]
        let frames = calfSeries.enumerated().map { (i, v) in
            makeFrame(time: Double(i) * 0.2, leftKnee: 100, rightKnee: 100, leftCalf: v, rightCalf: v)
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let scores = smoothed.compactMap { $0.poseScore?.calfLeanScore }

        XCTAssertEqual(scores.count, 8, "所有 8 帧都应产出 poseScore（含插值帧）")
        for (i, s) in scores.enumerated() {
            XCTAssertGreaterThan(s, 30.0,
                                 "第 \(i) 帧 calfLeanScore 应 >30（插值后 45° 附近映射到 ~56 分），实测 \(s)")
        }
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

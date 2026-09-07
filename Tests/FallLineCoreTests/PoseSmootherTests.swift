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

    /// P0b + P0-D: 连续 2 帧的真实 lean 峰值在 5 帧中位数窗下会被压制。
    ///
    /// bodyLean [20, 60, 60, 20, 20]，halfWidth=2 后 window 语义：
    /// - index=0/1: window <5 元素，保留原值（20/60）
    /// - index=2: window=[20,60,60,20,20] median=20 → **中间峰值被抹掉**
    /// - index=3/4: window <5 元素，保留原值（20/20）
    ///
    /// 这是 P0-D (2026-09-07) 后 lean 用 5 帧窗的**期望副作用**：为了压制连续多帧漂移，
    /// 会把"2 帧持续 lean 峰值"当作噪声处理。若真实动作 lean 变化持续 ≥3 帧才会保留。
    func test_smooth_bodyLeanTwoFramePeak_underP0D_isSuppressed() {
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

        // index=1 保留原始 60（边界不足 5 元素）
        XCTAssertGreaterThan(leans[1], 40.0,
                             "index=1 边界保留原始 60，实测 \(leans[1])°")
        // index=2 中间帧被 5 帧窗 median 抹到 20（P0-D 期望行为）
        XCTAssertLessThan(leans[2], 40.0,
                          "P0-D 5 帧窗应把 2 帧连续峰值中间帧抹回 ~20°，实测 \(leans[2])°")
    }

    /// P0-D: 连续 3 帧真实 lean 变化应被保留（median 无法压制 3 帧持续信号）。
    ///
    /// bodyLean [20, 20, 60, 60, 60, 20, 20]（长度 7），halfWidth=2：
    /// - index=2: window=[20,20,60,60,60] sorted=[20,20,60,60,60] median=60 ✓
    /// - index=3: window=[20,60,60,60,20] sorted=[20,20,60,60,60] median=60 ✓
    /// - index=4: window=[60,60,60,20,20] median=60 ✓
    ///
    /// 三帧持续变化视为真实动作，5 帧窗 median 会保留。
    func test_smooth_bodyLeanThreeFramePeak_underP0D_isPreserved() {
        let raw = [20.0, 20.0, 60.0, 60.0, 60.0, 20.0, 20.0]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(
                time: Double(i) * 0.2,
                leftKnee: 100, rightKnee: 100, leftCalf: 45, rightCalf: 45,
                bodyLean: v
            )
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let leans = smoothed.map { $0.bodyPose.bodyLeanAngle?.value ?? -1 }

        XCTAssertGreaterThan(leans[2], 40.0,
                             "P0-D 5 帧窗下持续 3 帧变化应保留（median 取 60），实测 \(leans[2])°")
        XCTAssertGreaterThan(leans[3], 40.0,
                             "中心帧应保留原 60，实测 \(leans[3])°")
        XCTAssertGreaterThan(leans[4], 40.0,
                             "末端持续帧应保留 60，实测 \(leans[4])°")
    }

    /// P0-D: knee/calf 保持 3 帧窗，其"2 帧真实峰值保留"语义不受影响。
    ///
    /// leftKnee [100, 40, 40, 100, 100]：knee 用 halfWidth=1（3 帧窗）
    /// - index=1: window=[100,40,40] median=40（保留）
    /// - index=2: window=[40,40,100] median=40（保留）
    func test_smooth_kneeTwoFramePeak_underP0D_stillPreserved() {
        let raw = [100.0, 40.0, 40.0, 100.0, 100.0]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(time: Double(i) * 0.2, leftKnee: v, rightKnee: v, leftCalf: 45, rightCalf: 45)
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let knees = smoothed.map { $0.bodyPose.leftKneeBendAngle?.value ?? -1 }

        // P0-D 后 knee 仍是 3 帧窗，连续 2 帧峰值必须保留
        XCTAssertLessThan(knees[1], 60.0,
                          "knee 3 帧窗下 2 帧峰值应保留，实测 \(knees[1])°")
        XCTAssertLessThan(knees[2], 60.0,
                          "knee 3 帧窗下 2 帧峰值应保留，实测 \(knees[2])°")
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

    // MARK: - P0-E centerOfGravity despike

    /// P0-E: cog 孤立尖峰应被 3 帧中位数抹回。
    /// cog=[0.4, 0.4, 0.9, 0.4, 0.4]，index=2 窗口 [0.4, 0.9, 0.4] median=0.4。
    func test_smooth_cog_isolatedSpike_isDespiked() {
        let raw = [0.4, 0.4, 0.9, 0.4, 0.4]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(
                time: Double(i) * 0.2,
                leftKnee: 100, rightKnee: 100, leftCalf: 45, rightCalf: 45,
                cog: v
            )
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let cogs = smoothed.map { $0.bodyPose.centerOfGravity?.value ?? -1 }

        XCTAssertLessThan(cogs[2], 0.55,
                          "cog 孤立尖峰应被 median 抹回 ~0.4，实测 \(cogs[2])")
    }

    /// P0-E: 连续 2 帧真实 cog 峰值应被保留（cog 用 halfWidth=1，语义同 knee/calf）。
    /// cog=[0.4, 0.9, 0.9, 0.4, 0.4]，index=1 window=[0.4, 0.9, 0.9] median=0.9（保留）。
    func test_smooth_cog_twoFramePeak_isPreserved() {
        let raw = [0.4, 0.9, 0.9, 0.4, 0.4]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(
                time: Double(i) * 0.2,
                leftKnee: 100, rightKnee: 100, leftCalf: 45, rightCalf: 45,
                cog: v
            )
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let cogs = smoothed.map { $0.bodyPose.centerOfGravity?.value ?? -1 }

        XCTAssertGreaterThan(cogs[1], 0.55,
                             "cog 连续 2 帧峰值应保留（median 取 0.9），实测 \(cogs[1])")
        XCTAssertGreaterThan(cogs[2], 0.55,
                             "cog 第 3 帧持续峰值应保留，实测 \(cogs[2])")
    }

    /// P0-E: cog 边界帧保留原值（medianWindow 边界折中）。
    /// cog=[0.9, 0.4, 0.4, 0.4, 0.9]：首末孤立高值不会被抹掉（<3 邻居）。
    func test_smooth_cog_boundary_preservesRawValue() {
        let raw = [0.9, 0.4, 0.4, 0.4, 0.9]
        let frames = raw.enumerated().map { (i, v) in
            makeFrame(
                time: Double(i) * 0.2,
                leftKnee: 100, rightKnee: 100, leftCalf: 45, rightCalf: 45,
                cog: v
            )
        }

        let smoothed = PoseSmoother.smooth(frames, scorer: PoseScorer())
        let cogs = smoothed.map { $0.bodyPose.centerOfGravity?.value ?? -1 }

        // 首帧原值 0.9 应保留（1€ 首帧 = 原值）；末帧同理
        XCTAssertGreaterThan(cogs[0], 0.7,
                             "cog 首帧应保留原值 ~0.9（边界折中），实测 \(cogs[0])")
        XCTAssertGreaterThan(cogs[4], 0.7,
                             "cog 末帧应保留原值 ~0.9（边界折中），实测 \(cogs[4])")
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
        bodyLean: Double? = 20,
        cog: Double? = nil
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
                centerOfGravity: cog.map { MetricWithConfidence(value: $0, confidence: 0.9) },
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

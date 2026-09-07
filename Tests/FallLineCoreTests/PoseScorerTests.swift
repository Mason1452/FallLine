import XCTest
@testable import FallLineCore

// MARK: - 评分规则测试

final class PoseScorerTests: XCTestCase {

    let scorer = PoseScorer()

    // MARK: 理想姿态 → 高分

    func test_perfectPose_fullScore() {
        let pose = BodyPoseData(
            detected: true,
            visibility: .full,
            bodyLeanAngle: MetricWithConfidence(value: 18, confidence: 0.9),  // 在 10°-25° 理想区间
            leftBodyLeanAngle: MetricWithConfidence(value: 18, confidence: 0.9),
            rightBodyLeanAngle: MetricWithConfidence(value: 18, confidence: 0.9),
            leftKneeBendAngle: MetricWithConfidence(value: 120, confidence: 0.9),  // 在 100°-140° 理想区间
            rightKneeBendAngle: MetricWithConfidence(value: 120, confidence: 0.9),
            leftCalfLeanAngle: MetricWithConfidence(value: 75, confidence: 0.9),  // 接近满分
            rightCalfLeanAngle: MetricWithConfidence(value: 75, confidence: 0.9),
            centerOfGravity: MetricWithConfidence(value: 0.15, confidence: 0.9)  // 很低的重心
        )

        let result = scorer.score(pose: pose)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.totalScore, 85)
        XCTAssertGreaterThan(result!.totalConfidence, 0.8)
        XCTAssertGreaterThan(result!.forwardLeanConfidence, 0.8)
        XCTAssertGreaterThan(result!.kneeBendConfidence, 0.8)
        XCTAssertGreaterThan(result!.calfLeanConfidence, 0.8)
        XCTAssertGreaterThan(result!.gravityConfidence, 0.8)
        XCTAssertGreaterThan(result!.symmetryConfidence, 0.8)
        XCTAssertEqual(result!.level, "专业")
    }

    // MARK: 极端偏差 → 低分

    func test_extremeDeviation_lowScore() {
        let pose = BodyPoseData(
            detected: true,
            visibility: .full,
            bodyLeanAngle: MetricWithConfidence(value: 80, confidence: 0.9),  // 严重偏离 10°-25°
            leftBodyLeanAngle: MetricWithConfidence(value: 0, confidence: 0.9),
            rightBodyLeanAngle: MetricWithConfidence(value: 80, confidence: 0.9),
            leftKneeBendAngle: MetricWithConfidence(value: 90, confidence: 0.9),
            rightKneeBendAngle: MetricWithConfidence(value: 180, confidence: 0.9),  // 严重不对称且几乎直立
            leftCalfLeanAngle: MetricWithConfidence(value: 0, confidence: 0.9),  // 几乎无立刃
            rightCalfLeanAngle: MetricWithConfidence(value: 0, confidence: 0.9),
            centerOfGravity: MetricWithConfidence(value: 1.0, confidence: 0.9)  // 极高重心
        )

        let result = scorer.score(pose: pose)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.totalScore, 50)
    }

    // MARK: 无检测

    func test_noDetection_returnsNil() {
        let pose = BodyPoseData(
            detected: false,
            visibility: .none,
            bodyLeanAngle: nil, leftBodyLeanAngle: nil, rightBodyLeanAngle: nil,
            leftKneeBendAngle: nil, rightKneeBendAngle: nil,
            leftCalfLeanAngle: nil, rightCalfLeanAngle: nil,
            centerOfGravity: nil
        )

        let result = scorer.score(pose: pose)
        XCTAssertNil(result)
    }

    // MARK: minimal 可见性

    func test_minimalVisibility_returnsBaseScore() {
        let pose = BodyPoseData(
            detected: true,
            visibility: .minimal,
            bodyLeanAngle: nil, leftBodyLeanAngle: nil, rightBodyLeanAngle: nil,
            leftKneeBendAngle: nil, rightKneeBendAngle: nil,
            leftCalfLeanAngle: nil, rightCalfLeanAngle: nil,
            centerOfGravity: nil
        )

        let result = scorer.score(pose: pose)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.totalScore, PoseScorer.minimalBaseScore)
        XCTAssertEqual(result!.level, "初级")
        XCTAssertFalse(result!.suggestions.isEmpty)
    }

    // MARK: 重力连续评分

    func test_gravityScore_lowCG() {
        let gravScore = PoseScorer.gravityScore(from: 0.10)
        XCTAssertGreaterThan(gravScore, 90)
    }

    func test_gravityScore_midCG() {
        let gravScore = PoseScorer.gravityScore(from: 0.40)
        XCTAssertGreaterThan(gravScore, 55)
        XCTAssertLessThan(gravScore, 75)
    }

    func test_gravityScore_highCG() {
        let gravScore = PoseScorer.gravityScore(from: 0.70)
        XCTAssertLessThan(gravScore, 40)
    }

    func test_gravityScore_clampedToMinimum() {
        let gravScore = PoseScorer.gravityScore(from: 1.0)
        XCTAssertEqual(gravScore, 10.0)
    }

    // MARK: 膝盖评分校准

    func test_deepCarvingStance_doesNotPenalizeKneeBend() {
        let pose = BodyPoseData(
            detected: true,
            visibility: .full,
            bodyLeanAngle: MetricWithConfidence(value: 20, confidence: 0.9),
            leftBodyLeanAngle: MetricWithConfidence(value: 20, confidence: 0.9),
            rightBodyLeanAngle: MetricWithConfidence(value: 20, confidence: 0.9),
            leftKneeBendAngle: MetricWithConfidence(value: 82, confidence: 0.9),
            rightKneeBendAngle: MetricWithConfidence(value: 88, confidence: 0.9),
            leftCalfLeanAngle: MetricWithConfidence(value: 70, confidence: 0.9),
            rightCalfLeanAngle: MetricWithConfidence(value: 70, confidence: 0.9),
            centerOfGravity: MetricWithConfidence(value: 0.25, confidence: 0.9)
        )

        let result = scorer.score(pose: pose)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.kneeBendScore, 95)
    }

    func test_straightLegStance_penalizesKneeBend() {
        let pose = BodyPoseData(
            detected: true,
            visibility: .full,
            bodyLeanAngle: MetricWithConfidence(value: 20, confidence: 0.9),
            leftBodyLeanAngle: MetricWithConfidence(value: 20, confidence: 0.9),
            rightBodyLeanAngle: MetricWithConfidence(value: 20, confidence: 0.9),
            leftKneeBendAngle: MetricWithConfidence(value: 150, confidence: 0.9),
            rightKneeBendAngle: MetricWithConfidence(value: 154, confidence: 0.9),
            leftCalfLeanAngle: MetricWithConfidence(value: 70, confidence: 0.9),
            rightCalfLeanAngle: MetricWithConfidence(value: 70, confidence: 0.9),
            centerOfGravity: MetricWithConfidence(value: 0.55, confidence: 0.9)
        )

        let result = scorer.score(pose: pose)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.kneeBendScore, 70)
    }

    // MARK: - P5-A 直腿分段平滑 (2026-09-06)
    //
    // 目标：135° 出 idealRange 后，前 5° 温和斜率（20/10°），之后 24/10° 到 clamp 20。
    // v6 t=6.80 lknee=159.4° 场景：原来 kneeBendScore=35.6，P5-A 后应回到 ~47。

    /// 140°（dev=5，落在 soft zone 末尾）：应等于 90。
    func test_p5a_140degrees_endsSoftZoneAt90() {
        let pose = makeSymPose(knee: 140)
        let score = scorer.score(pose: pose)!.kneeBendScore
        XCTAssertEqual(score, 90, accuracy: 0.5,
                       "140° dev=5 应正好走完 soft zone 到 90，实测 \(score)")
    }

    /// 145°（dev=10，进入 hard zone 5°）：应 = 90 - 5/10*24 = 78。原曲线只给 72。
    func test_p5a_145degrees_softHardCrossover() {
        let pose = makeSymPose(knee: 145)
        let score = scorer.score(pose: pose)!.kneeBendScore
        XCTAssertEqual(score, 78, accuracy: 0.5,
                       "145° hard zone 5° 应 = 78 (原 72)，实测 \(score)")
    }

    /// 158°（v6 t=6.80 场景 avg=158，原 kneeBendScore=35.6）：
    /// P5-A 应恢复到 ~47，避免触发 quality cap（<60 → ≤72）之外还提供更多缓冲。
    func test_p5a_v6Scenario_softensCollapse() {
        let pose = makeSymPose(knee: 158)
        let score = scorer.score(pose: pose)!.kneeBendScore
        // dev = 158-135 = 23, hardDev = 23-5 = 18
        // 90 - 18/10*24 = 90 - 43.2 = 46.8
        XCTAssertEqual(score, 46.8, accuracy: 0.5,
                       "v6 直腿场景 158° 应从 35.6 缓到 ~46.8 (+11.2)，实测 \(score)")
    }

    /// 165°（dev=30）：从 90 起降到 30，原曲线已 clamp 到 20。
    func test_p5a_165degrees_stillPenalized() {
        let pose = makeSymPose(knee: 165)
        let score = scorer.score(pose: pose)!.kneeBendScore
        // 90 - 25/10*24 = 30
        XCTAssertEqual(score, 30, accuracy: 0.5,
                       "165° 应 = 30 (原 clamp 20)，实测 \(score)")
    }

    /// 170°+（dev>34.17）：应触底 clamp 20，与原曲线保持"极端直腿=最低分"语义。
    func test_p5a_extremeStraightLeg_clampsAt20() {
        let pose = makeSymPose(knee: 175)
        let score = scorer.score(pose: pose)!.kneeBendScore
        XCTAssertEqual(score, 20, accuracy: 0.5,
                       "175° 应触底 clamp 20，实测 \(score)")
    }

    /// 相邻帧抖动稳健性：148° → 155° 相邻 7° 跳变的绝对分应被抬升。
    /// - 148°: 原 63.6（临近 quality cap 60 边缘）→ P5-A 70.8（+7.2，远离 cap 边缘）
    /// - 155°: 原 44.0 → P5-A 54.0（+10，避开 symmetry cap 45 边界）
    /// P5-A 主要收益：在 quality cap 敏感区抬升绝对分数，减轻单帧 collapse 影响。
    func test_p5a_neighborFrameJitter_absoluteScoresLifted() {
        let s148 = scorer.score(pose: makeSymPose(knee: 148))!.kneeBendScore
        let s155 = scorer.score(pose: makeSymPose(knee: 155))!.kneeBendScore
        XCTAssertEqual(s148, 70.8, accuracy: 0.5,
                       "148° 应从原 63.6 抬到 70.8 (+7.2)，实测 \(s148)")
        XCTAssertEqual(s155, 54, accuracy: 0.5,
                       "155° 应从原 44 抬到 54 (+10)，避开 <45 symmetry cap，实测 \(s155)")
    }

    /// 深屈膝（<80°）曲线不应被 P5-A 影响：60° 仍应走 deepKneePenalty 分支。
    func test_p5a_deepKneePath_unchanged() {
        let pose = makeSymPose(knee: 60)
        let score = scorer.score(pose: pose)!.kneeBendScore
        // 深屈膝路径：100 - 20/10*4 = 92
        XCTAssertEqual(score, 92, accuracy: 0.5,
                       "深屈膝路径不应被 P5-A 修改，60° 应 = 92，实测 \(score)")
    }

    // MARK: - P5-B knee quality cap 线性缓冲带 (2026-09-06)
    //
    // 原语义：kneeBendScore < 60 → cap = 72（悬崖）
    // P5-B：kneeBend ≤ 40 cap=72；40~60 线性 72→88；≥60 无 cap
    //
    // 构造思路：让姿态其他项接近满分（rawTotalScore ≈ 90+），从而 cap 是唯一约束。
    // 关注 totalScore 与 cap 的接触。

    /// kneeBend = 30 → 深冷冻直腿，cap 保持 72，totalScore 不超过 72。
    func test_p5b_kneeBend30_stillCappedAt72() {
        let pose = makeHighRawPose(knee: 175)  // knee 175° → kneeBend 20 (clamp)
        let result = scorer.score(pose: pose)!
        XCTAssertLessThanOrEqual(result.kneeBendScore, 40,
                                 "175° 应触底或非常低（<=40），实测 \(result.kneeBendScore)")
        XCTAssertLessThanOrEqual(result.totalScore, 72.01,
                                 "kneeBend≤40 时 cap 应仍为 72，实测 \(result.totalScore)")
    }

    /// kneeBend ≈ 40 → cap = 72（soft floor 锚点）。
    /// 158° P5-A 后 kneeBend=46.8；找一个 kneeBend≈40 的角度：dev = (90-40)/24*10+5 = 25.83° → 160.83°
    func test_p5b_kneeBend40_capsAt72() {
        let pose = makeHighRawPose(knee: 160.83)
        let result = scorer.score(pose: pose)!
        // kneeBend 应 ≈ 40
        XCTAssertEqual(result.kneeBendScore, 40, accuracy: 1.0,
                       "160.83° 应对应 kneeBend≈40，实测 \(result.kneeBendScore)")
        // cap = 72
        XCTAssertLessThanOrEqual(result.totalScore, 72.5,
                                 "kneeBend≈40 时 cap 应为 72，实测 \(result.totalScore)")
    }

    /// kneeBend = 50 → cap = 80（缓冲带中点）。
    /// dev 使 kneeBend=50: 90 - hardDev/10*24 = 50 → hardDev=16.67 → dev=21.67 → 156.67°
    func test_p5b_kneeBend50_capsAt80() {
        let pose = makeHighRawPose(knee: 156.67)
        let result = scorer.score(pose: pose)!
        XCTAssertEqual(result.kneeBendScore, 50, accuracy: 1.0,
                       "156.67° 应对应 kneeBend≈50，实测 \(result.kneeBendScore)")
        XCTAssertEqual(result.totalScore, 80, accuracy: 1.5,
                       "kneeBend≈50 时 cap 应为 80，实测 \(result.totalScore)")
    }

    /// kneeBend ≈ 59 → cap ≈ 87.2（临近悬崖）。
    /// dev 使 kneeBend=59: 90 - hardDev/10*24 = 59 → hardDev=12.92 → dev=17.92 → 152.92°
    func test_p5b_kneeBend59_capsNear87() {
        let pose = makeHighRawPose(knee: 152.92)
        let result = scorer.score(pose: pose)!
        XCTAssertEqual(result.kneeBendScore, 59, accuracy: 1.0,
                       "152.92° 应对应 kneeBend≈59，实测 \(result.kneeBendScore)")
        // cap = 72 + (59-40)/20 * 16 = 72 + 15.2 = 87.2
        XCTAssertEqual(result.totalScore, 87.2, accuracy: 1.5,
                       "kneeBend≈59 时 cap 应 ≈ 87.2，实测 \(result.totalScore)")
    }

    /// kneeBend ≥ 60 → 无 cap，totalScore 走原 rawScore。
    /// 152° → dev=17 → hardDev=12 → kneeBend = 90 - 12/10*24 = 61.2
    /// rawScore = kneeBend*0.25 + fwdLean*0.20 + calfLean*0.20 + gravity*0.20 + sym*0.15
    ///        ≈ 61.2*0.25 + 100*0.20 + 93.75*0.20 + 92.5*0.20 + 100*0.15 = 87.55
    func test_p5b_kneeBend61_noCap() {
        let pose = makeHighRawPose(knee: 152)
        let result = scorer.score(pose: pose)!
        XCTAssertGreaterThan(result.kneeBendScore, 60,
                             "152° 应对应 kneeBend > 60，实测 \(result.kneeBendScore)")
        // kneeBend > 60 时无 cap，totalScore 应 = rawScore ≈ 87.55（未被截断到 88 或以下）
        XCTAssertEqual(result.totalScore, 87.55, accuracy: 0.5,
                       "kneeBend>60 无 cap，totalScore 应 = rawScore ≈ 87.55，实测 \(result.totalScore)")
    }

    /// v6 t=6.80 场景（kneeBend=46.8）：
    /// 原来 cap=72，P5-B cap = 72 + (46.8-40)/20*16 = 72 + 5.44 = 77.44
    func test_p5b_v6TB80Scenario_capLifted() {
        let pose = makeHighRawPose(knee: 158)
        let result = scorer.score(pose: pose)!
        XCTAssertEqual(result.kneeBendScore, 46.8, accuracy: 0.5,
                       "158° 应对应 kneeBend=46.8，实测 \(result.kneeBendScore)")
        XCTAssertEqual(result.totalScore, 77.44, accuracy: 1.5,
                       "v6 t=6.80 场景 cap 应从 72 抬到 ~77.44，实测 \(result.totalScore)")
    }

    /// 相邻抖动稳健性：kneeBend 55(cap 84) → kneeBend 63(no cap)
    /// P5-A 后 155° kneeBend=54, 152° kneeBend=61.2
    /// P5-B 前：totalScore 差 = 87.18 - 72 = 15.18
    /// P5-B 后：totalScore 差应 < 8（cap 84 → 88 无 cap，rawScore ≈ 88）
    func test_p5b_neighborFrameJitter_smoothTransition() {
        let low = scorer.score(pose: makeHighRawPose(knee: 155))!  // kneeBend=54
        let high = scorer.score(pose: makeHighRawPose(knee: 152))! // kneeBend≈61
        let delta = high.totalScore - low.totalScore
        XCTAssertLessThan(delta, 8,
                          "相邻抖动 155°→152° totalScore 落差应 <8（原 >15），实测 \(delta)")
    }

    /// symmetry cap 保持原语义（不受 P5-B 影响）。
    /// 制造 symmetryScore < 45 且 kneeBend ≥ 60 的场景。
    func test_p5b_symmetryCap_unchanged() {
        let pose = BodyPoseData(
            detected: true,
            visibility: .full,
            bodyLeanAngle: MetricWithConfidence(value: 20, confidence: 0.9),
            leftBodyLeanAngle: MetricWithConfidence(value: 5, confidence: 0.9),
            rightBodyLeanAngle: MetricWithConfidence(value: 35, confidence: 0.9),
            leftKneeBendAngle: MetricWithConfidence(value: 100, confidence: 0.9),  // full score
            rightKneeBendAngle: MetricWithConfidence(value: 145, confidence: 0.9),  // 大差异 → symmetry低
            leftCalfLeanAngle: MetricWithConfidence(value: 70, confidence: 0.9),
            rightCalfLeanAngle: MetricWithConfidence(value: 30, confidence: 0.9),
            centerOfGravity: MetricWithConfidence(value: 0.3, confidence: 0.9)
        )
        let result = scorer.score(pose: pose)!
        // knee 平均 122.5 → kneeBend 100
        XCTAssertGreaterThanOrEqual(result.kneeBendScore, 60,
                                    "knee 平均在 idealRange 内应满分，实测 \(result.kneeBendScore)")
        // symmetry 应 <45
        XCTAssertLessThan(result.symmetryScore, 45,
                          "大不对称应触发 symmetry cap，实测 \(result.symmetryScore)")
        // total 应被 symmetry cap 到 72
        XCTAssertLessThanOrEqual(result.totalScore, 72.01,
                                 "symmetry<45 应 cap 到 72，实测 \(result.totalScore)")
    }

    // Helper: 构造 rawScore ≈ 88+ 的高质量姿态，仅 knee 可控。
    // 用于隔离 knee cap 效果。
    private func makeHighRawPose(knee: Double) -> BodyPoseData {
        BodyPoseData(
            detected: true,
            visibility: .full,
            bodyLeanAngle: MetricWithConfidence(value: 30, confidence: 0.9),
            leftBodyLeanAngle: MetricWithConfidence(value: 30, confidence: 0.9),
            rightBodyLeanAngle: MetricWithConfidence(value: 30, confidence: 0.9),
            leftKneeBendAngle: MetricWithConfidence(value: knee, confidence: 0.9),
            rightKneeBendAngle: MetricWithConfidence(value: knee, confidence: 0.9),
            leftCalfLeanAngle: MetricWithConfidence(value: 75, confidence: 0.9),
            rightCalfLeanAngle: MetricWithConfidence(value: 75, confidence: 0.9),
            centerOfGravity: MetricWithConfidence(value: 0.15, confidence: 0.9)
        )
    }

    // Helper：构造左右对称的姿态，只关注 knee 分数。
    private func makeSymPose(knee: Double) -> BodyPoseData {
        BodyPoseData(
            detected: true,
            visibility: .full,
            bodyLeanAngle: MetricWithConfidence(value: 20, confidence: 0.9),
            leftBodyLeanAngle: MetricWithConfidence(value: 20, confidence: 0.9),
            rightBodyLeanAngle: MetricWithConfidence(value: 20, confidence: 0.9),
            leftKneeBendAngle: MetricWithConfidence(value: knee, confidence: 0.9),
            rightKneeBendAngle: MetricWithConfidence(value: knee, confidence: 0.9),
            leftCalfLeanAngle: MetricWithConfidence(value: 70, confidence: 0.9),
            rightCalfLeanAngle: MetricWithConfidence(value: 70, confidence: 0.9),
            centerOfGravity: MetricWithConfidence(value: 0.3, confidence: 0.9)
        )
    }

    // MARK: 权重重新分配（partial 可见性）

    func test_partialVisibility_redistributesWeights() {
        // 左右不对称很大，但在 partial 模式下对称性权重应为 0
        let pose = BodyPoseData(
            detected: true,
            visibility: .partial,
            bodyLeanAngle: MetricWithConfidence(value: 18, confidence: 0.9),
            leftBodyLeanAngle: MetricWithConfidence(value: 18, confidence: 0.9),
            rightBodyLeanAngle: nil,  // 仅一侧可见
            leftKneeBendAngle: MetricWithConfidence(value: 120, confidence: 0.9),
            rightKneeBendAngle: nil,
            leftCalfLeanAngle: MetricWithConfidence(value: 75, confidence: 0.9),
            rightCalfLeanAngle: nil,
            centerOfGravity: MetricWithConfidence(value: 0.15, confidence: 0.9)
        )

        let result = scorer.score(pose: pose)
        XCTAssertNotNil(result)
        // 对称性分应为 50（默认），且不参与总分计算（权重为 0）
        XCTAssertEqual(result!.symmetryScore, 50)
        XCTAssertEqual(result!.symmetryConfidence, 0)
        XCTAssertGreaterThan(result!.forwardLeanConfidence, 0.4)
        XCTAssertGreaterThan(result!.kneeBendConfidence, 0.4)
    }
}

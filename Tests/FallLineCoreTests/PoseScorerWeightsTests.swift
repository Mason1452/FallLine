import XCTest
@testable import FallLineCore

// MARK: - PoseScorer.Weights 契约测试
// Tick 2 (2026-09-15) 守护 edge-first 权重表。见 spec：
// docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md
final class PoseScorerWeightsTests: XCTestCase {

    // MARK: 权重和

    /// defaultWeights 五维和恒等于 1.0（允许 Double 累加误差 < 1e-12）。
    func test_defaultWeights_sumToOne() {
        let sum = PoseScorer.defaultWeights.sum
        XCTAssertEqual(sum, 1.0, accuracy: 1e-12,
                       "defaultWeights 权重和必须严格 = 1.0（实测 \(sum)）")
    }

    /// partialWeights 五维和恒等于 1.0：symmetry 0.10 均分到三项后仍然收敛。
    /// symmetry 0.10 / 3 = 0.033333…，Double 累加可能引入 <1e-12 的误差，
    /// 但 [0.15 + Δ] × 3 + 0.15 = 1.0 精确成立（Δ = 0.10/3.0）。
    func test_partialWeights_sumToOne() {
        let sum = PoseScorer.partialWeights.sum
        XCTAssertEqual(sum, 1.0, accuracy: 1e-12,
                       "partialWeights 权重和必须严格 = 1.0（实测 \(sum)）")
    }

    // MARK: calfLean 主导性

    /// Tick 2 落地 spec §4.1：calfLean 是唯一走刃证据，权重必须显著大于其他四项。
    func test_defaultWeights_calfLeanIsDominant() {
        let w = PoseScorer.defaultWeights
        XCTAssertGreaterThan(w.calfLean, w.forwardLean,
                             "calfLean(\(w.calfLean)) 必须 > forwardLean(\(w.forwardLean))")
        XCTAssertGreaterThan(w.calfLean, w.kneeBend,
                             "calfLean(\(w.calfLean)) 必须 > kneeBend(\(w.kneeBend))")
        XCTAssertGreaterThan(w.calfLean, w.gravity,
                             "calfLean(\(w.calfLean)) 必须 > gravity(\(w.gravity))")
        XCTAssertGreaterThan(w.calfLean, w.symmetry,
                             "calfLean(\(w.calfLean)) 必须 > symmetry(\(w.symmetry))")
    }

    /// partial 分支下 calfLean 应保持主导（symmetry 均分不改变主导关系）。
    func test_partialWeights_calfLeanIsDominant() {
        let w = PoseScorer.partialWeights
        XCTAssertGreaterThan(w.calfLean, w.forwardLean)
        XCTAssertGreaterThan(w.calfLean, w.kneeBend)
        XCTAssertGreaterThan(w.calfLean, w.gravity)
    }

    // MARK: 精确权重锚点

    /// 冻结 defaultWeights 数值锚点：spec §4.1 的表格是评分基线，
    /// 任何数值变化都必须先更新 spec + 通过 corpus replay。
    func test_defaultWeights_anchorValues() {
        let w = PoseScorer.defaultWeights
        XCTAssertEqual(w.forwardLean, 0.15, accuracy: 1e-12)
        XCTAssertEqual(w.kneeBend,    0.25, accuracy: 1e-12)
        XCTAssertEqual(w.calfLean,    0.35, accuracy: 1e-12)
        XCTAssertEqual(w.gravity,     0.15, accuracy: 1e-12)
        XCTAssertEqual(w.symmetry,    0.10, accuracy: 1e-12)
    }

    /// 冻结 partialWeights 数值锚点。
    func test_partialWeights_anchorValues() {
        let w = PoseScorer.partialWeights
        let bump = 0.10 / 3.0
        XCTAssertEqual(w.forwardLean, 0.15 + bump, accuracy: 1e-12)
        XCTAssertEqual(w.kneeBend,    0.25 + bump, accuracy: 1e-12)
        XCTAssertEqual(w.calfLean,    0.35 + bump, accuracy: 1e-12)
        XCTAssertEqual(w.gravity,     0.15,        accuracy: 1e-12)
        XCTAssertEqual(w.symmetry,    0.0,         accuracy: 1e-12)
    }

    // MARK: 主导性行为验证（低 calf → 总分被压制）

    /// 低 calfLean（扫雪，calf=15°）即使其他项满分，总分也应显著低于阈值 75，
    /// 证明"是否走刃"由原始评分主导，无需依赖 edge cap 二次封顶。
    ///
    /// 期望（Tick 2 权重下、Tick 3 sigmoid 前的线性版本）：
    ///   forwardLean(100) × 0.15 + kneeBend(100) × 0.25 + calfLean(18.75) × 0.35
    ///   + gravity(100) × 0.15 + symmetry(100) × 0.10
    ///   = 15 + 25 + 6.5625 + 15 + 10 = 71.56
    /// 阈值放宽到 75 以在 Tick 3 sigmoid 落地后仍成立（sigmoid 会把 15° 拉低到 ~11）。
    func test_lowCalfSuppressesTotal_withoutExternalCap() {
        let pose = BodyPoseData(
            detected: true,
            visibility: .full,
            bodyLeanAngle: MetricWithConfidence(value: 18, confidence: 0.9),
            leftBodyLeanAngle: MetricWithConfidence(value: 18, confidence: 0.9),
            rightBodyLeanAngle: MetricWithConfidence(value: 18, confidence: 0.9),
            leftKneeBendAngle: MetricWithConfidence(value: 120, confidence: 0.9),
            rightKneeBendAngle: MetricWithConfidence(value: 120, confidence: 0.9),
            leftCalfLeanAngle: MetricWithConfidence(value: 15, confidence: 0.9),   // 扫雪代理
            rightCalfLeanAngle: MetricWithConfidence(value: 15, confidence: 0.9),
            centerOfGravity: MetricWithConfidence(value: 0.15, confidence: 0.9)
        )
        let result = PoseScorer().score(pose: pose)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.totalScore, 75,
                          "低 calf 场景下总分应被内嵌权重压制到 <75（实测 \(result!.totalScore)）")
    }

    /// 高 calfLean（刻滑，calf=60°）配合其他项良好，总分应进入"高级+"档。
    func test_highCalfLifts_toAdvanced() {
        let pose = BodyPoseData(
            detected: true,
            visibility: .full,
            bodyLeanAngle: MetricWithConfidence(value: 25, confidence: 0.9),
            leftBodyLeanAngle: MetricWithConfidence(value: 25, confidence: 0.9),
            rightBodyLeanAngle: MetricWithConfidence(value: 25, confidence: 0.9),
            leftKneeBendAngle: MetricWithConfidence(value: 115, confidence: 0.9),
            rightKneeBendAngle: MetricWithConfidence(value: 115, confidence: 0.9),
            leftCalfLeanAngle: MetricWithConfidence(value: 60, confidence: 0.9),   // 刻滑代理
            rightCalfLeanAngle: MetricWithConfidence(value: 60, confidence: 0.9),
            centerOfGravity: MetricWithConfidence(value: 0.20, confidence: 0.9)
        )
        let result = PoseScorer().score(pose: pose)
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.totalScore, 85,
                                    "高 calf 场景下总分应进入'专业'档（实测 \(result!.totalScore)）")
    }
}

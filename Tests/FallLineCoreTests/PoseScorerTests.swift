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

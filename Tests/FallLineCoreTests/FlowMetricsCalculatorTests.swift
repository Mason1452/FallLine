import XCTest
@testable import FallLineCore

final class FlowMetricsCalculatorTests: XCTestCase {

    let calculator = FlowMetricsCalculator()

    // MARK: - computeModulation (3-param — without poseScore, no stability thresholds)

    func testModulation_emptyState_returnsNeutral() {
        let mod = calculator.computeModulation(
            coherence: 0, stability: 0, smoothness: 100
        )
        XCTAssertEqual(mod, 1.0, accuracy: 0.001)
    }

    func testModulation_highCoherence_boostsScore() {
        let mod = calculator.computeModulation(
            coherence: 85, stability: 50, smoothness: 60
        )
        XCTAssertEqual(mod, 1.05, accuracy: 0.001)
    }

    func testModulation_lowSmoothness_penalizes() {
        let mod = calculator.computeModulation(
            coherence: 50, stability: 50, smoothness: 25
        )
        XCTAssertEqual(mod, 0.95, accuracy: 0.001)
    }

    func testModulation_allPositive_combination() {
        let mod = calculator.computeModulation(
            coherence: 85, stability: 50, smoothness: 60
        )
        // coherence > 70 → +0.05
        XCTAssertEqual(mod, 1.05, accuracy: 0.001)
    }

    func testModulation_allNegative_combination() {
        let mod = calculator.computeModulation(
            coherence: 50, stability: 50, smoothness: 25
        )
        // smoothness < 40 → -0.05
        XCTAssertEqual(mod, 0.95, accuracy: 0.001)
    }

    func testModulation_clampedToUpperBound() {
        // 3-param max: coherence boost (+0.05) = 1.05, no stability component
        let mod = calculator.computeModulation(
            coherence: 100, stability: 100, smoothness: 100
        )
        XCTAssertEqual(mod, 1.05, accuracy: 0.001)
    }

    func testModulation_clampedToLowerBound() {
        // 3-param min: smoothness penalty (-0.05) = 0.95, no stability component
        let mod = calculator.computeModulation(
            coherence: 0, stability: 0, smoothness: 0
        )
        XCTAssertEqual(mod, 0.95, accuracy: 0.001)
    }

    // MARK: - computeModulation (4-param — with poseScore, stability thresholds active)

    func testModulation_full_highCoherenceAndStabilityAndLowPose_boosts() {
        // coherence > 70 → +0.05, stability > 70 + poseScore 60 (<75) → +0.08
        let mod = calculator.computeModulation(
            coherence: 85, stability: 85, smoothness: 60, poseScore: 60
        )
        XCTAssertEqual(mod, 1.13, accuracy: 0.001)
    }

    func testModulation_full_highStabilityAndHighPose_noStabilityBoost() {
        // stability > 70 but poseScore 80 (>75) → no stability boost
        let mod = calculator.computeModulation(
            coherence: 85, stability: 85, smoothness: 60, poseScore: 80
        )
        XCTAssertEqual(mod, 1.05, accuracy: 0.001)
    }

    func testModulation_full_lowStabilityAndHighPose_penalizes() {
        // stability 20 (<30) + poseScore 80 (>75) → -0.08
        let mod = calculator.computeModulation(
            coherence: 50, stability: 20, smoothness: 60, poseScore: 80
        )
        XCTAssertEqual(mod, 0.92, accuracy: 0.001)
    }

    func testModulation_full_lowStabilityAndLowPose_noPenalty() {
        // stability 20 (<30) but poseScore 60 (<75) → no penalty (避免已低分再压低)
        let mod = calculator.computeModulation(
            coherence: 50, stability: 20, smoothness: 60, poseScore: 60
        )
        XCTAssertEqual(mod, 1.0, accuracy: 0.001)
    }

    func testModulation_full_allPositive_combined() {
        let mod = calculator.computeModulation(
            coherence: 85, stability: 85, smoothness: 60, poseScore: 60
        )
        // coherence +0.05, stability boost +0.08 → 1.13
        XCTAssertEqual(mod, 1.13, accuracy: 0.001)
    }

    func testModulation_full_allNegative_combined() {
        let mod = calculator.computeModulation(
            coherence: 50, stability: 20, smoothness: 25, poseScore: 80
        )
        // stability penalty -0.08, smoothness -0.05 → 0.87
        XCTAssertEqual(mod, 0.87, accuracy: 0.001)
    }

    // MARK: - applyModulation

    func testApplyModulation_normalCase() {
        let metrics = FlowMetrics(
            motionCoherence: 85, directionalStability: 85,
            velocitySmoothness: 60, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 70, metrics: metrics)
        // coherence 85 (>70) → +0.05, stability 85 (>70) + poseScore 70 (<75) → +0.08
        // modulation = 1.13, 70 × 1.13 = 79.1
        XCTAssertEqual(result, 79.1, accuracy: 0.01)
    }

    func testApplyModulation_emptyMetrics_returnsUnchanged() {
        let result = calculator.applyModulation(poseScore: 70, metrics: .empty)
        XCTAssertEqual(result, 70, accuracy: 0.01)
    }

    func testApplyModulation_clampsAbove100() {
        let metrics = FlowMetrics(
            motionCoherence: 100, directionalStability: 100,
            velocitySmoothness: 100, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 95, metrics: metrics)
        // coherence > 70 → +0.05, stability 100 (>70) + poseScore 95 (>75) → no boost
        // modulation = 1.05, 95 × 1.05 = 99.75
        XCTAssertEqual(result, 99.75, accuracy: 0.01)
    }

    func testApplyModulation_lowStabilityHighPose_penalized() {
        let metrics = FlowMetrics(
            motionCoherence: 0, directionalStability: 0,
            velocitySmoothness: 0, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 80, metrics: metrics)
        // coherence=0 (no boost), stability 0 (<30) + poseScore 80 (>75) → -0.08
        // smoothness 0 (<40) → -0.05, modulation = 0.87, 80 × 0.87 = 69.6
        XCTAssertEqual(result, 69.6, accuracy: 0.01)
    }

    func testApplyModulation_fewFrames_noModulation() {
        let metrics = FlowMetrics(
            motionCoherence: 100, directionalStability: 100,
            velocitySmoothness: 100, framePairsUsed: 1
        )
        let result = calculator.applyModulation(poseScore: 70, metrics: metrics)
        // framePairsUsed < 2 → no modulation
        XCTAssertEqual(result, 70, accuracy: 0.01)
    }

    // MARK: - FlowMetrics.empty

    func testEmptyFlowMetrics_hasNeutralValues() {
        XCTAssertEqual(FlowMetrics.empty.framePairsUsed, 0)
        XCTAssertEqual(FlowMetrics.empty.motionCoherence, 0)
        XCTAssertEqual(FlowMetrics.empty.directionalStability, 0)
        XCTAssertEqual(FlowMetrics.empty.velocitySmoothness, 0)
    }
}

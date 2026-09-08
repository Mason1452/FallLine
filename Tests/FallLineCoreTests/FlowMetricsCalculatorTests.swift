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
        // 3-param: coherence=0/stability=0/smoothness=0
        // 新语义（2026-09-01 flow 塌陷熔断）：smoothness=0 触发 > 0 守卫 →
        // 不再触发 -0.05 penalty，最终 modulation = 1.0
        let mod = calculator.computeModulation(
            coherence: 0, stability: 0, smoothness: 0
        )
        XCTAssertEqual(mod, 1.0, accuracy: 0.001)
    }

    // MARK: - computeModulation (4-param — P7-A 起 stability 不再参与调制，与 3-param 行为一致)

    /// P7-A (2026-09-08)：stability 调制退役。高 stability + 低 poseScore 不再触发 boost，
    /// 只剩 coherence 分支生效。
    func testModulation_full_highCoherenceAndStabilityAndLowPose_noStabilityBoostAfterP7A() {
        let mod = calculator.computeModulation(
            coherence: 85, stability: 85, smoothness: 60, poseScore: 60
        )
        // P7-A 前：coherence +0.05 + stability +0.08 = 1.13；P7-A 后：仅 coherence 1.05
        XCTAssertEqual(mod, 1.05, accuracy: 0.001)
    }

    /// P7-A 守护：同样的输入，stability 取 0 / 50 / 100 结果必须完全一致。
    func testModulation_full_stabilityValueIsIgnoredAfterP7A() {
        for stability in [0.0, 20.0, 50.0, 85.0, 100.0] {
            let mod = calculator.computeModulation(
                coherence: 50, stability: stability, smoothness: 60, poseScore: 80
            )
            XCTAssertEqual(mod, 1.0, accuracy: 0.001,
                           "stability=\(stability) 不应影响调制结果，实测 \(mod)")
        }
    }

    /// P7-A：低 stability + 高 poseScore 不再触发 penalty。
    func testModulation_full_lowStabilityAndHighPose_noPenaltyAfterP7A() {
        let mod = calculator.computeModulation(
            coherence: 50, stability: 20, smoothness: 60, poseScore: 80
        )
        // P7-A 前：stability 20 + poseScore 80 → -0.08 = 0.92；P7-A 后：1.0
        XCTAssertEqual(mod, 1.0, accuracy: 0.001)
    }

    func testModulation_full_lowStabilityAndLowPose_noPenalty() {
        let mod = calculator.computeModulation(
            coherence: 50, stability: 20, smoothness: 60, poseScore: 60
        )
        XCTAssertEqual(mod, 1.0, accuracy: 0.001)
    }

    func testModulation_full_allPositive_combined() {
        let mod = calculator.computeModulation(
            coherence: 85, stability: 85, smoothness: 60, poseScore: 60
        )
        // P7-A 后仅 coherence +0.05
        XCTAssertEqual(mod, 1.05, accuracy: 0.001)
    }

    func testModulation_full_allNegative_combined() {
        let mod = calculator.computeModulation(
            coherence: 50, stability: 20, smoothness: 25, poseScore: 80
        )
        // P7-A 后仅 smoothness -0.05（stability penalty 已退役）
        XCTAssertEqual(mod, 0.95, accuracy: 0.001)
    }

    // MARK: - applyModulation

    func testApplyModulation_normalCase() {
        let metrics = FlowMetrics(
            motionCoherence: 85, directionalStability: 85,
            velocitySmoothness: 60, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 70, metrics: metrics)
        // P7-A (2026-09-08)：stability 调制退役，只剩 coherence 85 (>70) → +0.05
        // modulation = 1.05, 70 × 1.05 = 73.5（P7-A 前 stability boost 叠加为 79.1）
        XCTAssertEqual(result, 73.5, accuracy: 0.01)
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

    func testApplyModulation_collapsedFlow_meltdownFusesModulation() {
        // 2026-09-01 flow 塌陷熔断（P2 稳定性收敛）：
        // stability=0 且 smoothness=0 视为 FlowMetricsCalculator 内部降级信号
        // （computeCircularStability 的 count>=2 门 + velocitySmoothness 空样本回落），
        // applyModulation 早退返回原始 poseScore，不再产生 -13% 的错误惩罚。
        // 24/24 corpus 命中此模式，脚本 scripts/stability_audit.py 为量化基线。
        let metrics = FlowMetrics(
            motionCoherence: 0, directionalStability: 0,
            velocitySmoothness: 0, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 80, metrics: metrics)
        XCTAssertEqual(result, 80, accuracy: 0.01)
    }

    func testApplyModulation_stabilityZeroSmoothnessNormal_penaltyGuarded() {
        // stability=0 单独出现（smoothness>0）：塌陷双 0 熔断不触发，
        // 但 stabilityPenalty 分支的 > 0 守卫仍会阻止"stability=0 且 poseScore>75 → -0.08"
        // 这条错误逻辑。coherence 也是 0，所以 modulation 稳定在 1.0。
        let metrics = FlowMetrics(
            motionCoherence: 0, directionalStability: 0,
            velocitySmoothness: 60, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 80, metrics: metrics)
        XCTAssertEqual(result, 80, accuracy: 0.01)
    }

    func testApplyModulation_smoothnessZeroStabilityNormal_penaltyGuarded() {
        // 对称情形：smoothness=0 单独出现（stability>0）时，塌陷双 0 熔断不触发，
        // smoothness penalty 的 > 0 守卫阻止"smoothness=0 → -0.05"错误逻辑。
        // stability=50 落在 [30, 70] 中间区间不触发 boost/penalty。
        let metrics = FlowMetrics(
            motionCoherence: 0, directionalStability: 50,
            velocitySmoothness: 0, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 80, metrics: metrics)
        XCTAssertEqual(result, 80, accuracy: 0.01)
    }

    func testApplyModulation_lowStabilityHighPose_noPenaltyAfterP7A() {
        // P7-A (2026-09-08)：stability penalty 分支退役。stability=15 + poseScore>75
        // 不再扣 -0.08；smoothness=25>0 仍走 penalty -0.05；净 modulation = 0.95，
        // 80 × 0.95 = 76。P7-A 前该用例为 0.87 × 80 = 69.6。
        let metrics = FlowMetrics(
            motionCoherence: 0, directionalStability: 15,
            velocitySmoothness: 25, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 80, metrics: metrics)
        XCTAssertEqual(result, 76.0, accuracy: 0.01)
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

    // MARK: - P6-A computeVelocitySmoothness (2026-09-07)

    /// P6-A: 空序列回落中性 50。
    func testComputeVelocitySmoothness_empty_returnsNeutral50() {
        XCTAssertEqual(calculator.computeVelocitySmoothness(fromChangeRates: []), 50, accuracy: 0.001)
    }

    /// P6-A: 单帧极端跳变不再拖垮整段平滑度（avg 时代 100% 塌陷为 0 的回归守护）。
    func testComputeVelocitySmoothness_singleOutlierSpike_doesNotCollapse() {
        // 诊断实录：主 corpus median ≈ 0.62，max 单帧跳变 75.2（>120×）
        let changes: [Double] = [0.55, 0.60, 0.62, 0.58, 75.2]
        let smoothness = calculator.computeVelocitySmoothness(fromChangeRates: changes)
        // median = 0.60 → linearMap([0.30, 1.20]→[100, 0]) ≈ 66.7
        XCTAssertEqual(smoothness, 66.67, accuracy: 0.01)
        // 对照：avg = 15.43，旧公式 linearMap(15.43, [0.15, 0.50]→[100, 0]) = 0（塌陷）
        XCTAssertGreaterThan(smoothness, 60, "单帧 75.2 跳变不应把平滑度拖垮，实测 \(smoothness)")
    }

    /// P6-A: 阈值锚点 — 0.30 → 100，1.20 → 0，中点 0.75 → 50。
    func testComputeVelocitySmoothness_thresholdAnchors() {
        XCTAssertEqual(calculator.computeVelocitySmoothness(fromChangeRates: [0.30]), 100, accuracy: 0.001)
        XCTAssertEqual(calculator.computeVelocitySmoothness(fromChangeRates: [1.20]), 0, accuracy: 0.001)
        XCTAssertEqual(calculator.computeVelocitySmoothness(fromChangeRates: [0.75]), 50, accuracy: 0.001)
    }

    /// P6-A: 持续高变化率（真实全程抖动）仍应得低分 — median 不是免罚金牌。
    func testComputeVelocitySmoothness_persistentJitter_stillScoresZero() {
        let changes: [Double] = [1.5, 1.6, 1.4, 1.55, 1.5]
        let smoothness = calculator.computeVelocitySmoothness(fromChangeRates: changes)
        XCTAssertEqual(smoothness, 0, accuracy: 0.001, "median 1.5 超过 1.20 上限应映射为 0，实测 \(smoothness)")
    }
}

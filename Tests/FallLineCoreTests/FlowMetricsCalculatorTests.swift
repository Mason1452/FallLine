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

    // MARK: - P6-B averageFlowWindow (2026-09-10)

    /// P6-B: 均匀场应恒等 — 窗均值 == 单点值，radius 变化不影响结果。
    func testAverageFlowWindow_uniformField_returnsIdenticalMean() {
        let field: [[(dx: Double, dy: Double)]] = Array(
            repeating: Array(repeating: (dx: 3.0, dy: -4.0), count: 20),
            count: 20
        )
        let result = calculator.averageFlowWindow(field: field, centerX: 10, centerY: 10, radius: 2)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.dx ?? 0, 3.0, accuracy: 1e-9)
        XCTAssertEqual(result?.dy ?? 0, -4.0, accuracy: 1e-9)
    }

    /// P6-B: 窗均值应能拑制单点跳变 — 25 个像素中 1 个极端值被稀释为 1/25 权重。
    /// 单点采样若命中该噪声像素，方向 / 幅值都会被彻底带偏；窗均值不受影响。
    func testAverageFlowWindow_singleOutlierSuppressed() {
        var field: [[(dx: Double, dy: Double)]] = Array(
            repeating: Array(repeating: (dx: 1.0, dy: 0.0), count: 10),
            count: 10
        )
        // 在窗中心正上方放置一个 (100, 100) 的噪声像素
        field[5][5] = (dx: 100.0, dy: 100.0)
        let result = calculator.averageFlowWindow(field: field, centerX: 5, centerY: 5, radius: 2)
        XCTAssertNotNil(result)
        // 25 个像素，24 个 (1, 0) + 1 个 (100, 100) = ((24 + 100) / 25, 100 / 25) = (4.96, 4.0)
        XCTAssertEqual(result?.dx ?? 0, (24.0 + 100.0) / 25.0, accuracy: 1e-9)
        XCTAssertEqual(result?.dy ?? 0, 100.0 / 25.0, accuracy: 1e-9)
        // 对照：单点采样命中噪声像素时 dx=100, dy=100 — 完全被单帧噪声主导
    }

    /// P6-B: 边界处 window clip — 中心在 (0,0) 时只有右下 3×3 落点，均值只统计有效格子。
    func testAverageFlowWindow_boundaryClipsToImage() {
        let field: [[(dx: Double, dy: Double)]] = [
            [(1, 0), (2, 0), (3, 0)],
            [(4, 0), (5, 0), (6, 0)],
            [(7, 0), (8, 0), (9, 0)]
        ]
        let result = calculator.averageFlowWindow(field: field, centerX: 0, centerY: 0, radius: 2)
        XCTAssertNotNil(result)
        // 从 (0,0) radius=2 但受 image 3×3 边界约束 → 落点为整张 3×3，dx 均值 = 45/9 = 5
        XCTAssertEqual(result?.dx ?? 0, 5.0, accuracy: 1e-9)
        XCTAssertEqual(result?.dy ?? 0, 0.0, accuracy: 1e-9)
    }

    /// P6-B: radius=0 回退为单点采样（保留紧急回退路径，避免 P6-B 引入回归时无法快速止血）。
    func testAverageFlowWindow_radiusZeroReturnsCenterOnly() {
        let field: [[(dx: Double, dy: Double)]] = [
            [(0, 0), (0, 0), (0, 0)],
            [(0, 0), (42, -7), (0, 0)],
            [(0, 0), (0, 0), (0, 0)]
        ]
        let result = calculator.averageFlowWindow(field: field, centerX: 1, centerY: 1, radius: 0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.dx ?? 0, 42.0, accuracy: 1e-9)
        XCTAssertEqual(result?.dy ?? 0, -7.0, accuracy: 1e-9)
    }

    /// P6-B: 越界坐标返回 nil（与 sampleFlowVectors 内嵌 sample 语义一致）。
    func testAverageFlowWindow_outOfBoundsReturnsNil() {
        let field: [[(dx: Double, dy: Double)]] = Array(
            repeating: Array(repeating: (dx: 1.0, dy: 1.0), count: 4),
            count: 4
        )
        XCTAssertNil(calculator.averageFlowWindow(field: field, centerX: -1, centerY: 0, radius: 2))
        XCTAssertNil(calculator.averageFlowWindow(field: field, centerX: 0, centerY: 4, radius: 2))
    }

    /// P6-B: init 中 radius 参数持久化到实例属性；负值 clip 到 0。
    func testInit_flowSampleRadius_persistsAndClipsNegative() {
        let defaultCalc = FlowMetricsCalculator()
        XCTAssertEqual(defaultCalc.flowSampleRadius, 3, "默认 radius 应为 3 (7×7 窗，P6-B-r3)")

        let customCalc = FlowMetricsCalculator(sampleInterval: 1.0 / 30.0, flowSampleRadius: 4)
        XCTAssertEqual(customCalc.flowSampleRadius, 4)

        let negativeCalc = FlowMetricsCalculator(sampleInterval: 1.0 / 30.0, flowSampleRadius: -1)
        XCTAssertEqual(negativeCalc.flowSampleRadius, 0, "负值应 clip 到 0（等价 radius=0 回退）")
    }

    // MARK: - P0 (2026-09-15) Flow Modulation Edge-Confidence Gating

    // MARK: 常量与兼容签名

    /// P0: 常量锚定 —— 门控阈值 0.30 与低分保护阈值 60.0 是 spec §4.3 的核心决策数值。
    /// 若这两个数字被改动，需同步更新 spec §4.3 / §5.1 / §5.3 与所有 replay 脚本。
    func testEdgeGating_thresholdConstants_matchSpec() {
        XCTAssertEqual(calculator.boardKinematicConfidenceGateThreshold, 0.30, accuracy: 1e-9,
                       "门控阈值必须 = 0.30（spec §4.3）；若调整需同步 flow_gating_replay.py")
        XCTAssertEqual(calculator.flowGateLowScoreProtectionThreshold, 60.0, accuracy: 1e-9,
                       "低分保护阈值必须 = 60.0（spec §4.3）；若调整需同步 spec §5.3 保护表")
    }

    /// P0 向后兼容：4-param `computeModulation` 内部转发 `boardKinematicConfidence=1.0`（等价无门控），
    /// 与旧 4-param 结果字节等价——保证既有 15+ 测试用例与生产调用点（VideoAnalyzer.generateSummary）不受影响。
    func testEdgeGating_4param_forwardsAsUnGated_legacyEquivalent() {
        // 覆盖 4 组典型输入：高 coherence / 低 smoothness / 双正 / 中性
        let cases: [(coh: Double, sm: Double, pose: Double)] = [
            (85, 60, 60),   // coherence boost only
            (50, 25, 80),   // smoothness penalty only
            (85, 25, 60),   // 双负
            (50, 60, 80)    // 中性
        ]
        for c in cases {
            let legacy = calculator.computeModulation(
                coherence: c.coh, stability: 50, smoothness: c.sm, poseScore: c.pose
            )
            let gated6 = calculator.computeModulation(
                coherence: c.coh, stability: 50, smoothness: c.sm, poseScore: c.pose,
                boardKinematicConfidence: 1.0
            )
            XCTAssertEqual(legacy, gated6, accuracy: 1e-9,
                           "boardC=1.0 时 4/6-param 输出必须字节等价，输入 \(c) 实测 legacy=\(legacy) gated=\(gated6)")
        }
    }

    /// P0 向后兼容：3-param `computeModulation` 同样转发无门控路径（boardC=1.0, capped=nil），行为不变。
    func testEdgeGating_3param_forwardsAsUnGated_legacyEquivalent() {
        let mod3 = calculator.computeModulation(coherence: 85, stability: 50, smoothness: 25)
        let mod6 = calculator.computeModulation(
            coherence: 85, stability: 50, smoothness: 25, poseScore: 0,
            boardKinematicConfidence: 1.0
        )
        XCTAssertEqual(mod3, mod6, accuracy: 1e-9)
        // coherence 85 > 70 → +0.05；smoothness 25 < 40 → -0.05；净 = 1.0
        XCTAssertEqual(mod3, 1.0, accuracy: 1e-9)
    }

    // MARK: 门控触发 / 未触发

    /// P0: boardC < 0.30 时上行加成被钳制到 1.0（v4 场景：coherence=98.5 但 boardC=0.157）。
    func testEdgeGating_boardCBelowThreshold_clampsUpwardBoost() {
        let mod = calculator.computeModulation(
            coherence: 98.5, stability: 50, smoothness: 60, poseScore: 80,
            boardKinematicConfidence: 0.157
        )
        // 未 gate 时 coherence>70 → +0.05 → 1.05；gate 后 min(1.05, 1.0) = 1.0
        XCTAssertEqual(mod, 1.0, accuracy: 1e-9,
                       "boardC=0.157<0.30 应把 +0.05 加成钳制到 1.0，实测 \(mod)")
    }

    /// P0: boardC ≥ 0.30 时门控不触发，上行加成正常保留（v3/v5 场景：boardC 0.552/0.510）。
    func testEdgeGating_boardCAboveThreshold_preservesBoost() {
        for boardC in [0.30, 0.510, 0.552, 0.751, 1.0] {
            let mod = calculator.computeModulation(
                coherence: 85, stability: 50, smoothness: 60, poseScore: 80,
                boardKinematicConfidence: boardC
            )
            XCTAssertEqual(mod, 1.05, accuracy: 1e-9,
                           "boardC=\(boardC)≥0.30 门控不应触发，应保留 +0.05 加成，实测 \(mod)")
        }
    }

    /// P0: 边界值 boardC=0.30 恰好 **未触发**门控（严格 `<`），阈值单调性守护。
    /// 该测试直接锁定 `<` 而非 `<=` 语义——若未来改成 `<=` 会引入不易发现的边界回归。
    func testEdgeGating_atExactThreshold_isNotGated() {
        let mod = calculator.computeModulation(
            coherence: 85, stability: 50, smoothness: 60, poseScore: 80,
            boardKinematicConfidence: 0.30
        )
        XCTAssertEqual(mod, 1.05, accuracy: 1e-9, "boardC=0.30 恰好等于阈值不触发（严格 <）")
    }

    /// P0: 门控**保留下行修正** —— boardC 低时 smoothness penalty 仍然生效。
    /// 语义：走刃证据不足时禁止加分，但不阻止塌陷降级信号扣分（保守原则，spec §3 非目标）。
    func testEdgeGating_gateOnlyBlocksUpward_preservesDownwardPenalty() {
        let mod = calculator.computeModulation(
            coherence: 50, stability: 50, smoothness: 25, poseScore: 80,
            boardKinematicConfidence: 0.20
        )
        // coherence 50 无 boost；smoothness 25<40 → -0.05；gate 触发但 min(0.95, 1.0) = 0.95
        XCTAssertEqual(mod, 0.95, accuracy: 1e-9,
                       "门控只钳制上行加成，下行 penalty 必须保留，实测 \(mod)")
    }

    /// P0: 双负叠加时门控无副作用 —— coherence 加成 + smoothness penalty 相互抵消到 1.0，
    /// gate 触发后 min(1.0, 1.0) 仍是 1.0，验证 gate 逻辑在"非严格上行"边界处的正确行为。
    func testEdgeGating_neutralModulation_gateIsNoOp() {
        let mod = calculator.computeModulation(
            coherence: 85, stability: 50, smoothness: 25, poseScore: 80,
            boardKinematicConfidence: 0.20
        )
        // +0.05 - 0.05 = 1.0；gate 触发但 min(1.0, 1.0) 无变化
        XCTAssertEqual(mod, 1.0, accuracy: 1e-9)
    }

    // MARK: 方案 (c) 低分保护

    /// P0 方案 (c)：`evidenceCappedScore < 60` 时禁用门控，保留上行加成（v1 场景）。
    /// v1 corpus：coherence=86.59, smoothness=78.82, boardC=0.239, capped=57.78 → 保护生效 → 1.05
    func testEdgeGating_lowScoreProtection_disablesGate() {
        let mod = calculator.computeModulation(
            coherence: 86.593, stability: 50, smoothness: 78.821, poseScore: 48.807,
            boardKinematicConfidence: 0.239,
            evidenceCappedScore: 57.78
        )
        XCTAssertEqual(mod, 1.05, accuracy: 1e-9,
                       "capped=57.78<60 应关闭门控，保留 +0.05 加成（v1 保护场景）")
    }

    /// P0 方案 (c)：`evidenceCappedScore ≥ 60` 时保护不触发，门控继续 kill（v4/v6 场景）。
    /// v4 corpus：capped=78.80 ≥60 → 保护关闭 → 门控 kill；v6 corpus 同理。
    func testEdgeGating_highScore_protectionInactive_gateStillKills() {
        // v4: capped=78.80
        let modV4 = calculator.computeModulation(
            coherence: 98.539, stability: 50, smoothness: 58.075, poseScore: 64.010,
            boardKinematicConfidence: 0.157,
            evidenceCappedScore: 78.80
        )
        XCTAssertEqual(modV4, 1.0, accuracy: 1e-9,
                       "v4 capped=78.80≥60 保护关闭，门控 kill +0.05 加成")

        // v6: capped=90.16
        let modV6 = calculator.computeModulation(
            coherence: 70.727, stability: 50, smoothness: 63.240, poseScore: 79.315,
            boardKinematicConfidence: 0.280,
            evidenceCappedScore: 90.16
        )
        // coherence 70.727 > 70 → +0.05；boardC 0.280<0.30；capped=90.16≥60 保护不触发；gate → 1.0
        XCTAssertEqual(modV6, 1.0, accuracy: 1e-9,
                       "v6 capped=90.16≥60 保护关闭，门控 kill +0.05 加成")
    }

    /// P0 方案 (c)：低分保护阈值恰好边界 `capped=60` **不触发保护**（严格 `<`）。
    func testEdgeGating_protectionAtExactThreshold_isInactive() {
        let mod = calculator.computeModulation(
            coherence: 85, stability: 50, smoothness: 60, poseScore: 60,
            boardKinematicConfidence: 0.20,
            evidenceCappedScore: 60.0
        )
        // capped=60 严格不 <60，保护不触发 → gate 生效 → 加成被 kill
        XCTAssertEqual(mod, 1.0, accuracy: 1e-9, "capped=60 边界值不触发保护（严格 <）")
    }

    /// P0 方案 (c)：`evidenceCappedScore=nil` 关闭低分保护路径 —— 与仅 5-param 严格门控等价。
    /// 供 4-param 与旧 `applyModulation` 转发使用；测试锁定"nil 语义 = 严格门控"契约。
    func testEdgeGating_nilCappedScore_equalsStrictGating() {
        let modNil = calculator.computeModulation(
            coherence: 85, stability: 50, smoothness: 60, poseScore: 80,
            boardKinematicConfidence: 0.20,
            evidenceCappedScore: nil
        )
        let modOmitted = calculator.computeModulation(
            coherence: 85, stability: 50, smoothness: 60, poseScore: 80,
            boardKinematicConfidence: 0.20
        )
        XCTAssertEqual(modNil, modOmitted, accuracy: 1e-9, "nil 与省略参数应完全等价")
        XCTAssertEqual(modNil, 1.0, accuracy: 1e-9, "nil 应走严格门控路径（无保护），boardC=0.20 → kill 到 1.0")
    }

    // MARK: applyModulation 新签名端到端

    /// P0 端到端：新签名 `applyModulation(poseScore:metrics:boardKinematicConfidence:evidenceCappedScore:)`
    /// 复现 v4 corpus 数值 —— capped=78.80 × gated_factor=1.0 = 78.80（spec §5 门控后综合分）。
    func testApplyModulation_endToEnd_v4Corpus_gatedToBaseScore() {
        let metrics = FlowMetrics(
            motionCoherence: 98.539, directionalStability: 50,
            velocitySmoothness: 58.075, framePairsUsed: 10
        )
        let result = calculator.applyModulation(
            poseScore: 78.80,
            metrics: metrics,
            boardKinematicConfidence: 0.157,
            evidenceCappedScore: 78.80
        )
        // v4: gate 生效，保护不触发 → factor=1.0 → 78.80 × 1.0 = 78.80
        XCTAssertEqual(result, 78.80, accuracy: 0.01,
                       "v4 端到端复现 spec §5：capped 78.80 × ×1.000 = 78.80")
    }

    /// P0 端到端：v1 低分保护复现 —— capped=57.78 × 1.05 = 60.669（spec §5.3 方案 (c) 主选值）。
    func testApplyModulation_endToEnd_v1Corpus_protectionKeepsBoost() {
        let metrics = FlowMetrics(
            motionCoherence: 86.593, directionalStability: 50,
            velocitySmoothness: 78.821, framePairsUsed: 10
        )
        let result = calculator.applyModulation(
            poseScore: 57.78,
            metrics: metrics,
            boardKinematicConfidence: 0.239,
            evidenceCappedScore: 57.78
        )
        // v1 保护：capped<60 → 保护开 → factor=1.05 → 57.78 × 1.05 = 60.669
        XCTAssertEqual(result, 60.669, accuracy: 0.01,
                       "v1 端到端复现 spec §5.3 方案 (c)：capped 57.78 × ×1.050 = 60.669")
    }

    /// P0 端到端：v6 门控生效复现 —— capped=90.16 × 1.0 = 90.16（spec §5 门控后综合分）。
    func testApplyModulation_endToEnd_v6Corpus_gatedToBaseScore() {
        let metrics = FlowMetrics(
            motionCoherence: 70.727, directionalStability: 50,
            velocitySmoothness: 63.240, framePairsUsed: 10
        )
        let result = calculator.applyModulation(
            poseScore: 90.16,
            metrics: metrics,
            boardKinematicConfidence: 0.280,
            evidenceCappedScore: 90.16
        )
        XCTAssertEqual(result, 90.16, accuracy: 0.01,
                       "v6 端到端复现 spec §5：capped 90.16 × ×1.000 = 90.16")
    }

    /// P0 端到端：framePairsUsed<2 早退兜底 —— 门控参数不影响早退路径。
    func testApplyModulation_fewFramesGuard_precedesGate() {
        let metrics = FlowMetrics(
            motionCoherence: 100, directionalStability: 100,
            velocitySmoothness: 100, framePairsUsed: 1
        )
        let result = calculator.applyModulation(
            poseScore: 78.80,
            metrics: metrics,
            boardKinematicConfidence: 0.05,   // 极低 boardC 但应先早退
            evidenceCappedScore: 78.80
        )
        XCTAssertEqual(result, 78.80, accuracy: 0.01,
                       "framePairsUsed<2 必须早退，门控参数不参与计算")
    }

    /// P0 端到端：塌陷双 0 熔断优先于门控 —— stability=0 且 smoothness=0 → 直接返回原分。
    func testApplyModulation_collapsedFlowMeltdown_precedesGate() {
        let metrics = FlowMetrics(
            motionCoherence: 90, directionalStability: 0,
            velocitySmoothness: 0, framePairsUsed: 10
        )
        let result = calculator.applyModulation(
            poseScore: 80,
            metrics: metrics,
            boardKinematicConfidence: 0.05,
            evidenceCappedScore: 80
        )
        XCTAssertEqual(result, 80, accuracy: 0.01,
                       "flow 塌陷双 0 熔断先于门控生效，返回原分")
    }

    /// P0 端到端：新签名的 clamp 上下界与旧签名一致。
    func testApplyModulation_clampBoundaries_unchanged() {
        // 极端上界：coherence 极高 + 保护开 → 1.05 × 95 = 99.75 (未超 100)
        let boostMetrics = FlowMetrics(
            motionCoherence: 100, directionalStability: 100,
            velocitySmoothness: 100, framePairsUsed: 10
        )
        let boostResult = calculator.applyModulation(
            poseScore: 95,
            metrics: boostMetrics,
            boardKinematicConfidence: 0.10,   // gate 触发
            evidenceCappedScore: 55.0         // 但保护开
        )
        // 保护关闭门控 → factor=1.05 → 95 × 1.05 = 99.75
        XCTAssertEqual(boostResult, 99.75, accuracy: 0.01)
    }

    /// P0 端到端：旧签名 `applyModulation(poseScore:metrics:)` 转发到新签名后行为字节等价。
    /// 覆盖历史测试契约：`testApplyModulation_normalCase` 期望 73.5 的行为不能被 P0 破坏。
    func testApplyModulation_legacySignature_stillReturns73_5() {
        let metrics = FlowMetrics(
            motionCoherence: 85, directionalStability: 85,
            velocitySmoothness: 60, framePairsUsed: 10
        )
        // 旧签名内部 boardC=1.0 + capped=nil → 门控不触发 → factor=1.05
        let result = calculator.applyModulation(poseScore: 70, metrics: metrics)
        XCTAssertEqual(result, 73.5, accuracy: 0.01,
                       "旧签名 P0 转发后必须与 P7-A 时代行为字节等价（73.5）")
    }
}

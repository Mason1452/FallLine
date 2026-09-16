import XCTest
@testable import FallLineCore

/// StageClassifierTests
///
/// 锁死 [StageClassifier.determineStage](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/StageClassifier.swift#L9-L22) 的分档契约。
///
/// 2026-09-15 §4.3 收紧（calibration review）：低边界 quality 准入从
/// `avg ≥ 75` 收紧为 `avg ≥ 75 且 calf ≥ 55`，防止"立刃/小腿不到位但综合
/// 虚高"的样本被贴成"高质量滑行阶段"。该 stage 仅影响报告标签与重心适配
/// 展示分（cogStageFitScore），不进入综合总分。
///
/// 明确保留：
/// - 高边界 `avg ≥ 80` 不做硬分离（GOOD_A avg85.6/calf48.5 与 MID_ACC6
///   avg83.5/calf46.8 仅差 1.7~2.1，任何硬阈值都过拟合，留待扩样本）。
/// - 不引入 symmetry 条件：刻滑功能性不对称会误伤 GOOD_A（sym≈65）。
final class StageClassifierTests: XCTestCase {

    // MARK: - 基础档

    func test_lowScores_mapToBasicTiers() {
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 0, calfScore: 10, kneeScore: 10, stabilityScore: 50),
            .basicDetection
        )
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 49.9, calfScore: 10, kneeScore: 10, stabilityScore: 50),
            .basicDetection
        )
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 55, calfScore: 10, kneeScore: 40, stabilityScore: 50),
            .basicControl
        )
    }

    // MARK: - §4.3 收紧：avg 75-80 且 calf<55 不再是 quality

    func test_avg75_lowCalf_staysStableSkiing() {
        // BAD_ACC: avg 75.3, calf 46.1 —— 教练 65 中级，edge cap 后仍不应贴 quality
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 75.3, calfScore: 46.1, kneeScore: 87.9, stabilityScore: 87.1),
            .stableSkiing
        )
        // MID_FP1: avg 76.5, calf 46.8 —— 教练明确"腿太直、没倒伏"
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 76.5, calfScore: 46.8, kneeScore: 74.0, stabilityScore: 89.4),
            .stableSkiing
        )
    }

    func test_avg75_calfAbove55_isQualitySkiing() {
        // calf 达到 55 才放行 quality；knee 不足 70 时不满足 carvingEmerging
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 76, calfScore: 55.5, kneeScore: 65, stabilityScore: 80),
            .qualitySkiing
        )
    }

    func test_avg70_calf55_knee70_isCarvingEmerging() {
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 72, calfScore: 58, kneeScore: 80, stabilityScore: 80),
            .carvingEmerging
        )
    }

    // MARK: - 高边界（保留原逻辑，不硬分离）

    func test_avg80_lowCalf_isQualitySkiing_notAdvanced() {
        // GOOD_A: avg 85.6, calf 48.5 —— 头号专业样本，必须保持 quality，不被压档
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 85.6, calfScore: 48.5, kneeScore: 97.8, stabilityScore: 70.8),
            .qualitySkiing
        )
    }

    func test_avg80_highCalf_isAdvanced() {
        // v2: avg 86.5, calf 72.7
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 86.5, calfScore: 72.7, kneeScore: 93.6, stabilityScore: 70.7),
            .advanced
        )
        // advanced 边界 calf 恰为 65
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 90, calfScore: 65, kneeScore: 90, stabilityScore: 75),
            .advanced
        )
    }

    // MARK: - 边界连续性（calf 阈值 55 / 65）

    func test_thresholdBoundaries_areStable() {
        // avg 75 区间：calf=55 放行 quality，calf=54.99 落回 stable
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 76, calfScore: 54.99, kneeScore: 80, stabilityScore: 80),
            .stableSkiing
        )
        // avg>=80：calf<65 一律 quality（不再受 55 影响）
        XCTAssertEqual(
            StageClassifier.determineStage(averageScore: 82, calfScore: 50, kneeScore: 80, stabilityScore: 80),
            .qualitySkiing
        )
    }
}

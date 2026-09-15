import XCTest
@testable import FallLineCore

/// EvidenceCapRampTests
///
/// 锁死 edge evidence cap 与 duration evidence cap 的 piecewise linear 契约。
///
/// Edge cap（Tick 4 edge-first 重构版）：[VideoAnalyzer.edgeEvidenceCapValue(for:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L479-L483)。
///
/// Tick 4 (2026-09-15) 之后的契约（同 [设计文档 §4.3](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md)）：
///  1. 单调不减：edge 升高不会让 cap 降低
///  2. 平台点：`cap(30 - ε) = 62`, `cap(42) = 100`
///  3. 过渡带中点：`cap(36) = 81`（介于 62 与 100 之间线性插值）
///  4. 边界钳位：edge < 30 均为 62；edge ≥ 42 均为 100
///  5. 连续：段与段的交接点严格连续（无 jump）
///  6. 斜率上界：全域 ≤ (100-62)/12 = 3.1667 分/edge 分
///
/// Duration cap（P2 悬崖软化，2026-09-11 落地）：[VideoAnalyzer.durationCapValue(for:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L499-L528)
/// 契约保持不变，见下半区。
final class EvidenceCapRampTests: XCTestCase {

    // MARK: - Contract 1：单调不减

    func test_monotonic_nonDecreasing_over_full_range() {
        let step = 0.25
        var x = -5.0
        var previous = VideoAnalyzer.edgeEvidenceCapValue(for: x)
        while x <= 105.0 {
            let current = VideoAnalyzer.edgeEvidenceCapValue(for: x)
            XCTAssertGreaterThanOrEqual(
                current, previous,
                "cap 非单调：cap(\(x)) = \(current) < 上一采样 \(previous)"
            )
            previous = current
            x += step
        }
    }

    // MARK: - Contract 2：平台点（阈值命中样本）

    func test_plateauValues_matchTickFourSpec() {
        // 下平台：`edge < 30` → 62
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: -1.0), 62.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 0.0), 62.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 15.94), 62.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 29.99), 62.0, accuracy: 1e-6)

        // ramp 起点 30 → 62（含）
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 30.0), 62.0, accuracy: 1e-9)

        // 上平台：`edge >= 42` → 100
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 42.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 50.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 65.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 100.0), 100.0, accuracy: 1e-9)
    }

    // MARK: - Contract 3：过渡带中点（线性插值验证）

    func test_rampMidpoints_arePreciseLinearInterpolation() {
        // ramp 段 [30, 42]，跨度 12 → cap 从 62 升到 100（跨度 38）
        // 中点 36：62 + 0.5 * 38 = 81
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 36.0), 81.0, accuracy: 1e-9)

        // 25%（x=33）：62 + 0.25 * 38 = 71.5
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 33.0), 71.5, accuracy: 1e-9)

        // 75%（x=39）：62 + 0.75 * 38 = 90.5
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 39.0), 90.5, accuracy: 1e-9)

        // 早段小步长 x=31：62 + (1/12) * 38 = 65.1667
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 31.0), 62.0 + 38.0 / 12.0, accuracy: 1e-9)

        // 晚段小步长 x=41：62 + (11/12) * 38 = 96.8333
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 41.0), 62.0 + 38.0 * 11.0 / 12.0, accuracy: 1e-9)
    }

    // MARK: - Contract 4：边界钳位

    func test_boundaryClamping_belowMinPlateau_returnsMinCap() {
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: -1.0), 62.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 0.0), 62.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 15.94), 62.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 25.0), 62.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 29.99), 62.0, accuracy: 1e-6)
    }

    func test_boundaryClamping_aboveMaxPlateau_returnsHundred() {
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 42.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 50.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 63.7), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 100.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 200.0), 100.0, accuracy: 1e-9)
    }

    // MARK: - Contract 5：corpus replay 兜底
    //
    // 数据来源：Tick 3 corpus replay 的 raw `averageEdgeEvidenceScore`。sigmoid
    // 让 edge 分整体上移，大多数样本已跨过 42 平台。旧版 [42, 50] ramp 段对现
    // 有 corpus 的“惩罚”被 Tick 4 明确豁免。

    func test_corpusReplay_matchesTickFourSpec() {
        // 高分平台样本（Tick 3 后 corpus，edge >= 42 → cap = 100）
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 65.01), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 63.70), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 60.95), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 50.06), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 45.90), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 42.47), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 42.01), 100.0, accuracy: 1e-9)

        // 极端不足兜底样本（video 1 类型：Vision 长期只识别扫雪站姿）
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 15.94), 62.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 15.81), 62.0, accuracy: 1e-9)

        // 过渡带样本探针：如果未来出现 avgEdge=35 的样本，cap 应为
        // 62 + (35-30)/12 * 38 = 62 + 15.833 = 77.833
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 35.0), 62.0 + 5.0 / 12.0 * 38.0, accuracy: 1e-6)
    }

    // MARK: - Contract 6：连续性（相邻段的边界值必须相等）

    func test_continuity_atSegmentBoundaries() {
        let epsilon = 1e-9

        // 在 30 处：左极限 = 平台 62，右极限 = linear 起点 62
        XCTAssertEqual(
            VideoAnalyzer.edgeEvidenceCapValue(for: 30.0 - epsilon),
            62.0,
            accuracy: 1e-6
        )
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 30.0), 62.0, accuracy: 1e-9)

        // 在 42 处：左极限 = linear 终点 100，右极限 = 平台 100
        XCTAssertEqual(
            VideoAnalyzer.edgeEvidenceCapValue(for: 42.0 - epsilon),
            100.0,
            accuracy: 1e-6
        )
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 42.0), 100.0, accuracy: 1e-9)
    }

    // MARK: - Contract 7：斜率上界（防止未来调参失控）

    func test_slope_isBounded() {
        // 唯一 ramp 段 [30, 42] 的理论斜率：(100 - 62) / 12 = 3.1667
        // 平台段斜率恒为 0。允许 1e-3 数值误差。
        let h = 1e-4
        let maxAllowedSlope = (100.0 - 62.0) / 12.0 + 1e-3
        let sampleStart = -1.0
        let sampleEnd = 60.0
        let step = 0.05

        var x = sampleStart
        while x <= sampleEnd {
            // 跳过段边界的“数值不可导”点，避开 h 邻域
            let atBoundary = [30.0, 42.0].contains(where: { abs(x - $0) < 2 * h })
            if !atBoundary {
                let dy = VideoAnalyzer.edgeEvidenceCapValue(for: x + h)
                    - VideoAnalyzer.edgeEvidenceCapValue(for: x - h)
                let slope = dy / (2 * h)
                XCTAssertLessThanOrEqual(
                    slope, maxAllowedSlope,
                    "斜率越界：dcap/dedge(\(x)) = \(slope) > \(maxAllowedSlope)"
                )
                XCTAssertGreaterThanOrEqual(
                    slope, -1e-3,
                    "斜率为负：dcap/dedge(\(x)) = \(slope)"
                )
            }
            x += step
        }
    }

    // MARK: - Duration Cap Contract 1：单调不减

    /// 契约：[VideoAnalyzer.durationCapValue(for:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L499-L528)
    /// 在 [0, 20] 秒范围内非严格单调不减，且平台段严格常量。
    func test_durationCap_monotonic_nonDecreasing_over_full_range() {
        let step = 0.05
        var t = -1.0
        var previous = VideoAnalyzer.durationCapValue(for: t)
        while t <= 20.0 {
            let current = VideoAnalyzer.durationCapValue(for: t)
            XCTAssertGreaterThanOrEqual(
                current, previous,
                "duration cap 非单调：cap(\(t)) = \(current) < 上一采样 \(previous)"
            )
            previous = current
            t += step
        }
    }

    // MARK: - Duration Cap Contract 2：平台点等价（与旧阶梯完全一致）

    /// 契约：所有阈值命中样本得分与旧阶梯完全一致（旧值：<5→55, <8→65, <12→78, ≥12→100）。
    func test_durationCap_plateauValues_matchStairStep() {
        let epsilon = 1e-6

        // 5s 阈值：右侧平台 55；左极限 55（<5.0 段全部为 55）
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 0.0), 55.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 4.99), 55.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 5.0 - epsilon), 55.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 5.5), 65.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 5.5 + epsilon), 65.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 6.0), 65.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 7.99), 65.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 8.0 - epsilon), 65.0, accuracy: 1e-6)

        // 8s 阈值：右侧 ramp 起点 65；ramp 终点 78
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 8.5), 78.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 11.0), 78.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 12.0 - epsilon), 78.0, accuracy: 1e-6)

        // 12s 阈值：右侧 ramp 起点 78；ramp 终点 100
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 12.5), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 16.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 100.0), 100.0, accuracy: 1e-9)
    }

    // MARK: - Duration Cap Contract 3：过渡带中点（线性插值验证）

    func test_durationCap_rampMidpoints_arePreciseLinearInterpolation() {
        // [5.0, 5.5] 中点：(55 + 65) / 2 = 60
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 5.25), 60.0, accuracy: 1e-9)

        // [8.0, 8.5] 中点：(65 + 78) / 2 = 71.5
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 8.25), 71.5, accuracy: 1e-9)

        // [12.0, 12.5] 中点：(78 + 100) / 2 = 89
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 12.25), 89.0, accuracy: 1e-9)

        // [5.0, 5.5] 25%：55 + 0.25 * 10 = 57.5
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 5.125), 57.5, accuracy: 1e-9)

        // [12.0, 12.5] 75%：78 + 0.75 * 22 = 94.5
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 12.375), 94.5, accuracy: 1e-9)
    }

    // MARK: - Duration Cap Contract 4：边界钳位

    func test_durationCap_boundaryClamping() {
        // 极端小值（含负值）钳位到最小平台
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: -1.0), 55.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 0.0), 55.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 3.0), 55.0, accuracy: 1e-9)

        // 极端大值钳位到 100
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 15.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 31.4), 100.0, accuracy: 1e-9) // 主 corpus video 6
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 200.0), 100.0, accuracy: 1e-9)
    }

    // MARK: - Duration Cap Contract 5：corpus replay 兜底

    /// 契约：主 corpus 6 份视频的时长（11.60s ~ 31.40s）全部落在 ramp 之外。
    /// 与设计文档 §5.1 一致，预期 duration ramp 对现有 corpus 零影响。
    func test_durationCap_corpusReplay_matchesDesignSpec() {
        // 全部处于 [12.5, ∞) 平台，cap = 100，与旧阶梯完全一致
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 11.60), 78.0, accuracy: 1e-9) // video 5
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 14.80), 100.0, accuracy: 1e-9) // video 4
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 16.00), 100.0, accuracy: 1e-9) // video 2
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 16.80), 100.0, accuracy: 1e-9) // video 3
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 23.40), 100.0, accuracy: 1e-9) // video 1
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 31.40), 100.0, accuracy: 1e-9) // video 6
    }

    // MARK: - Duration Cap Contract 6：连续性（相邻段的边界值必须相等）

    func test_durationCap_continuity_atSegmentBoundaries() {
        let epsilon = 1e-9

        // 5.0 处：左极限 55，右极限 = linear 起点 55
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 5.0 - epsilon), 55.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 5.0), 55.0, accuracy: 1e-9)

        // 5.5 处：左极限 = linear 终点 65，右极限 = 平台 65
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 5.5 - epsilon), 65.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 5.5), 65.0, accuracy: 1e-9)

        // 8.0 处：左极限 = 平台 65，右极限 = linear 起点 65
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 8.0 - epsilon), 65.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 8.0), 65.0, accuracy: 1e-9)

        // 8.5 处：左极限 = linear 终点 78，右极限 = 平台 78
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 8.5 - epsilon), 78.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 8.5), 78.0, accuracy: 1e-9)

        // 12.0 处：左极限 = 平台 78，右极限 = linear 起点 78
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 12.0 - epsilon), 78.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 12.0), 78.0, accuracy: 1e-9)

        // 12.5 处：左极限 = linear 终点 100，右极限 = 平台 100
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 12.5 - epsilon), 100.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.durationCapValue(for: 12.5), 100.0, accuracy: 1e-9)
    }

    // MARK: - Duration Cap Contract 7：斜率上界（防止未来调参失控）

    /// 契约：所有 ramp 段的斜率必须在 [0, 44] 分/秒范围内（[12, 12.5] 段 22/0.5 = 44 分/秒 是理论最大值）。
    func test_durationCap_slope_isBounded() {
        // 各 ramp 段的理论斜率：
        //   [5.0, 5.5]   : (65-55)/0.5 = 20 分/秒
        //   [8.0, 8.5]   : (78-65)/0.5 = 26 分/秒
        //   [12.0, 12.5] : (100-78)/0.5 = 44 分/秒 ← 全曲线最大
        // 平台段斜率恒为 0。允许 1e-3 数值误差。
        let h = 1e-5
        let maxAllowedSlope = 44.0 + 1e-3
        let sampleStart = 0.0
        let sampleEnd = 20.0
        let step = 0.01

        var t = sampleStart
        while t <= sampleEnd {
            let atBoundary = [5.0, 5.5, 8.0, 8.5, 12.0, 12.5].contains(where: { abs(t - $0) < 2 * h })
            if !atBoundary {
                let dy = VideoAnalyzer.durationCapValue(for: t + h)
                    - VideoAnalyzer.durationCapValue(for: t - h)
                let slope = dy / (2 * h)
                XCTAssertLessThanOrEqual(
                    slope, maxAllowedSlope,
                    "duration 斜率越界：dcap/dt(\(t)) = \(slope) > \(maxAllowedSlope)"
                )
                XCTAssertGreaterThanOrEqual(
                    slope, -1e-3,
                    "duration 斜率为负：dcap/dt(\(t)) = \(slope)"
                )
            }
            t += step
        }
    }
}

import XCTest
@testable import FallLineCore

/// EvidenceCapRampTests
///
/// 锁死 P2 悬崖软化的 edge evidence cap piecewise linear 契约：
/// [VideoAnalyzer.edgeEvidenceCapValue(for:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L482-L494)。
///
/// 契约来源（同 [设计文档 §4.2](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-11-evidence-cap-ramp-softening-design.md)）：
///  1. 单调不减：edge 升高不会让 cap 降低
///  2. 平台点等价：`cap(38)=65`, `cap(42)=70`, `cap(50)=100`，即阈值命中样本得分与旧阶梯完全一致
///  3. 过渡带中点：`cap(37.5)=61.5`, `cap(41)=67.5`, `cap(46)=85`
///  4. 边界钳位：edge < 37 均为 58；edge ≥ 50 均为 100
///  5. corpus replay 兜底：主 corpus 6 份的 (edge, ramp_cap) 与设计文档 §5.1 对齐
///
/// 单测策略参考：[OneEuroFilterConfidenceAwareTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/OneEuroFilterConfidenceAwareTests.swift)。
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

    // MARK: - Contract 2：平台点等价（阈值命中样本与旧阶梯完全一致）

    func test_plateauValues_matchStairStep() {
        // 阈值右侧的平台点：值必须与旧阶梯完全相等
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 38.0), 65.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 39.0), 65.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 40.0), 65.0, accuracy: 1e-9)

        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 42.0), 70.0, accuracy: 1e-9)

        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 50.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 65.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 100.0), 100.0, accuracy: 1e-9)

        // 平台平坦区（非 ramp 段）：应严格等于本段 cap
        let epsilon = 1e-6
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 37.0 - epsilon), 58.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 38.0 + epsilon), 65.0, accuracy: 1e-6)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 40.0 - epsilon), 65.0, accuracy: 1e-6)
        // 注意：42 - epsilon 处于 [40, 42] ramp 末端，≈ 70（不是旧阶梯的 65），
        //       这正是 P2 悬崖软化的设计意图（阈值内侧向下延伸的连续过渡）。
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 42.0 - epsilon), 70.0, accuracy: 1e-5)
    }

    // MARK: - Contract 3：过渡带中点（线性插值验证）

    func test_rampMidpoints_arePreciseLinearInterpolation() {
        // [37, 38] 中点：(58 + 65) / 2 = 61.5
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 37.5), 61.5, accuracy: 1e-9)

        // [40, 42] 中点：(65 + 70) / 2 = 67.5
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 41.0), 67.5, accuracy: 1e-9)

        // [42, 50] 中点：(70 + 100) / 2 = 85
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 46.0), 85.0, accuracy: 1e-9)

        // [42, 50] 早段 25%：70 + 0.25 * 30 = 77.5
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 44.0), 77.5, accuracy: 1e-9)

        // [42, 50] 晚段 75%：70 + 0.75 * 30 = 92.5
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 48.0), 92.5, accuracy: 1e-9)
    }

    // MARK: - Contract 4：边界钳位

    func test_boundaryClamping_belowMinPlateau_returnsMinCap() {
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: -1.0), 58.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 0.0), 58.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 15.94), 58.0, accuracy: 1e-9) // 主 corpus video 1/OFF
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 36.99), 58.0, accuracy: 1e-6)
    }

    func test_boundaryClamping_aboveMaxPlateau_returnsHundred() {
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 50.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 63.7), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 100.0), 100.0, accuracy: 1e-9)
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 200.0), 100.0, accuracy: 1e-9)
    }

    // MARK: - Contract 5：corpus replay 兜底
    //
    // 数据来源：主 corpus 6 份视频（OFF + ON 各 6 份）的 `averageEdgeEvidenceScore`
    // 与 P2 设计文档 §5.1 表格。当 ramp 曲线未来被再次调整时，这里的对齐值会立
    // 即报警。

    func test_corpusReplay_matchesDesignSpec() {
        // 平台样本：ramp 与 stair 完全等价 → cap = 100
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 65.01), 100.0, accuracy: 1e-9) // video 2/OFF
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 64.69), 100.0, accuracy: 1e-9) // video 2/ON
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 60.95), 100.0, accuracy: 1e-9) // video 3/OFF
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 61.48), 100.0, accuracy: 1e-9) // video 3/ON
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 63.70), 100.0, accuracy: 1e-9) // video 6/OFF
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 62.31), 100.0, accuracy: 1e-9) // video 6/ON

        // 落在 [42, 50] 悬崖区的样本
        // video 4/OFF: edge=50.06 → 已在平台，cap=100
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 50.06), 100.0, accuracy: 1e-9)

        // video 4/ON: edge=45.90 → 70 + (45.90-42)/8 * 30 = 70 + 14.625 = 84.625
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 45.90), 84.625, accuracy: 1e-6)

        // video 5/OFF: edge=42.47 → 70 + (42.47-42)/8 * 30 = 70 + 1.7625 = 71.7625
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 42.47), 71.7625, accuracy: 1e-6)

        // video 5/ON: edge=42.01 → 70 + (42.01-42)/8 * 30 = 70 + 0.0375 = 70.0375
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 42.01), 70.0375, accuracy: 1e-6)

        // 强 cap 段样本
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 15.94), 58.0, accuracy: 1e-9) // video 1/OFF
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 15.81), 58.0, accuracy: 1e-9) // video 1/ON
    }

    // MARK: - Contract 6：连续性（相邻段的边界值必须相等）

    func test_continuity_atSegmentBoundaries() {
        // 段与段的交接点必须严格连续（无 jump）
        let epsilon = 1e-9

        // 在 37 处：左极限 = 平台 58，右极限 = linear 起点 58
        XCTAssertEqual(
            VideoAnalyzer.edgeEvidenceCapValue(for: 37.0 - epsilon),
            VideoAnalyzer.edgeEvidenceCapValue(for: 37.0),
            accuracy: 1e-6
        )
        // 在 38 处：左极限 = linear 终点 65，右极限 = 平台 65
        XCTAssertEqual(
            VideoAnalyzer.edgeEvidenceCapValue(for: 38.0 - epsilon),
            65.0,
            accuracy: 1e-6
        )
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 38.0), 65.0, accuracy: 1e-9)

        // 在 40 处：左极限 = 平台 65，右极限 = linear 起点 65
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 40.0), 65.0, accuracy: 1e-9)
        XCTAssertEqual(
            VideoAnalyzer.edgeEvidenceCapValue(for: 40.0 + epsilon),
            65.0,
            accuracy: 1e-6
        )

        // 在 42 处：左极限 = linear 终点 70，右极限 = linear 起点 70
        XCTAssertEqual(
            VideoAnalyzer.edgeEvidenceCapValue(for: 42.0 - epsilon),
            70.0,
            accuracy: 1e-6
        )
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 42.0), 70.0, accuracy: 1e-9)

        // 在 50 处：左极限 = linear 终点 100，右极限 = 平台 100
        XCTAssertEqual(
            VideoAnalyzer.edgeEvidenceCapValue(for: 50.0 - epsilon),
            100.0,
            accuracy: 1e-6
        )
        XCTAssertEqual(VideoAnalyzer.edgeEvidenceCapValue(for: 50.0), 100.0, accuracy: 1e-9)
    }

    // MARK: - Contract 7：斜率上界（防止未来调参失控）

    func test_slope_isBounded() {
        // 各 ramp 段的理论斜率：
        //   [37, 38]  : (65-58)/1 = 7.0  ← 全曲线最大
        //   [40, 42]  : (70-65)/2 = 2.5
        //   [42, 50]  : (100-70)/8 = 3.75
        // 平台段斜率恒为 0。允许 1e-3 数值误差，兜住未来调参不至于失控（>7）。
        let h = 1e-4
        let maxAllowedSlope = 7.0 + 1e-3
        let sampleStart = -1.0
        let sampleEnd = 60.0
        let step = 0.05

        var x = sampleStart
        while x <= sampleEnd {
            // 跳过段边界的“数值不可导”点，避开 h 邻域
            let atBoundary = [37.0, 38.0, 40.0, 42.0, 50.0].contains(where: { abs(x - $0) < 2 * h })
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

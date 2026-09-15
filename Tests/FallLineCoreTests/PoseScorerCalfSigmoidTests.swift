import XCTest
@testable import FallLineCore

// MARK: - PoseScorer.calfLeanScore(fromAngle:) sigmoid 契约测试
// Tick 3 (2026-09-15) 守护 edge-first sigmoid 曲线，见 spec §4.2：
// docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md
//
// **c=40 微调（2026-09-15，Tick 4 corpus review 后）**：sigmoid 中点从 35 右移
// 到 40（"入门刻滑"档），锚点表和陡度断言按新曲线同步更新。
final class PoseScorerCalfSigmoidTests: XCTestCase {

    // MARK: 8 采样点锚点（spec §4.2 表 · c=40）

    private struct Anchor {
        let angle: Double
        let expected: Double
    }

    private let anchors: [Anchor] = [
        Anchor(angle:  0, expected:  1.8),   // sigmoid(-4.0) × 100 ≈ 1.799
        Anchor(angle: 10, expected:  4.7),   // sigmoid(-3.0)
        Anchor(angle: 20, expected: 11.9),   // sigmoid(-2.0)
        Anchor(angle: 30, expected: 26.9),   // sigmoid(-1.0)
        Anchor(angle: 40, expected: 50.0),   // sigmoid( 0.0) 中点
        Anchor(angle: 50, expected: 73.1),   // sigmoid(+1.0)
        Anchor(angle: 60, expected: 88.1),   // sigmoid(+2.0)
        Anchor(angle: 70, expected: 95.3),   // sigmoid(+3.0)
    ]

    func test_calfSigmoid_matchesAnchorTable() {
        for anchor in anchors {
            let actual = PoseScorer.calfLeanScore(fromAngle: anchor.angle)
            XCTAssertEqual(actual, anchor.expected, accuracy: 0.5,
                           "sigmoid(\(anchor.angle)°) 期望 ≈ \(anchor.expected)，实测 \(actual)")
        }
    }

    // MARK: 单调性

    func test_calfSigmoid_isStrictlyIncreasing() {
        var last = -Double.infinity
        for angle in stride(from: 0.0, through: 80.0, by: 1.0) {
            let score = PoseScorer.calfLeanScore(fromAngle: angle)
            XCTAssertGreaterThan(score, last,
                                 "sigmoid 必须严格单调递增：angle=\(angle) score=\(score) prev=\(last)")
            last = score
        }
    }

    // MARK: 边界与钳位

    func test_calfSigmoid_clampsToZeroForVeryNegative() {
        // 极小 angle：sigmoid 数学值虽然 >0，但业务上不应输出负分
        let score = PoseScorer.calfLeanScore(fromAngle: -1000)
        XCTAssertGreaterThanOrEqual(score, 0)
        XCTAssertLessThan(score, 1.0)
    }

    func test_calfSigmoid_clampsToHundredForVeryLarge() {
        // 极大 angle：sigmoid 渐近 100，业务上截顶到 100
        let score = PoseScorer.calfLeanScore(fromAngle: 1000)
        XCTAssertLessThanOrEqual(score, 100)
        XCTAssertGreaterThan(score, 99.0)
    }

    // MARK: 中点契约

    /// c = 40 是 sigmoid 中点，score(40) 必须严格 = 50.0
    func test_calfSigmoid_midpointIs50() {
        let score = PoseScorer.calfLeanScore(fromAngle: PoseScorer.calfSigmoidMidpoint)
        XCTAssertEqual(score, 50.0, accuracy: 1e-9,
                       "sigmoid 中点 (angle = c = \(PoseScorer.calfSigmoidMidpoint)) 必须 = 50，实测 \(score)")
    }

    // MARK: 陡度（斜率放大）

    /// spec §4.2 目标：30°–50° 段斜率显著大于旧线性 (1.25 分/°)。
    /// sigmoid k=0.10 c=40 在 [30, 50] 段的平均斜率 = (73.1 - 26.9) / 20 ≈ 2.31 分/°。
    /// 断言 [30, 50] 段总落差 ≥ 40，等价于平均斜率 ≥ 2.0 分/°（含容差）。
    func test_calfSigmoid_amplifies30to50Slope() {
        let s30 = PoseScorer.calfLeanScore(fromAngle: 30)
        let s50 = PoseScorer.calfLeanScore(fromAngle: 50)
        XCTAssertGreaterThanOrEqual(s50 - s30, 40,
                                    "30°→50° 段落差 (\(s50 - s30)) 必须 ≥ 40（平均斜率 ≥ 2.0 分/°）")
    }

    // MARK: 参数冻结

    func test_calfSigmoid_parameterAnchors() {
        XCTAssertEqual(PoseScorer.calfSigmoidSlope,    0.10, accuracy: 1e-12,
                       "sigmoid k 应固定 = 0.10")
        XCTAssertEqual(PoseScorer.calfSigmoidMidpoint, 40.0, accuracy: 1e-12,
                       "sigmoid c 应固定 = 40.0")
    }
}

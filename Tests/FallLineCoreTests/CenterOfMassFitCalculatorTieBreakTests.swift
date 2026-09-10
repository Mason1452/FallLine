import XCTest
@testable import FallLineCore

/// P9-B (2026-09-10): 守护 [CenterOfMassFitCalculator.dominantIssue] 在 `过低` vs `偏高`
/// 同频 tie 时的稳定排序。修复前采用 `Dictionary.max`，同频 tie 由 hash-order 决定，
/// 顶层 `CenterOfMassAnalysis.mainIssue` 在报告/JSON 里会跨轮抖动。
/// 优先级：偏高 > 过低。
final class CenterOfMassFitCalculatorTieBreakTests: XCTestCase {

    // MARK: - 单赢家场景（tie-break 不介入）

    func test_dominant_singleWinner_高频过低() {
        let frames = makeFrames(issues: [
            "当前阶段重心过低", "当前阶段重心过低", "当前阶段重心过低",
            "当前阶段重心偏高",
        ])
        XCTAssertEqual(
            CenterOfMassFitCalculator.dominantIssue(from: frames),
            "当前阶段重心过低",
            "过低 3 vs 偏高 1，应直接返回过低"
        )
    }

    func test_dominant_singleWinner_高频偏高() {
        let frames = makeFrames(issues: [
            "当前阶段重心偏高", "当前阶段重心偏高", "当前阶段重心偏高", "当前阶段重心偏高",
            "当前阶段重心过低",
        ])
        XCTAssertEqual(
            CenterOfMassFitCalculator.dominantIssue(from: frames),
            "当前阶段重心偏高"
        )
    }

    // MARK: - 同频 tie-break

    func test_dominant_tie_偏高优先于过低() {
        let frames = makeFrames(issues: [
            "当前阶段重心过低", "当前阶段重心过低",
            "当前阶段重心偏高", "当前阶段重心偏高",
        ])
        XCTAssertEqual(
            CenterOfMassFitCalculator.dominantIssue(from: frames),
            "当前阶段重心偏高",
            "同频时偏高应优于过低（惩罚更重、教练视角优先级更高）"
        )
    }

    func test_dominant_tie_单帧对单帧_偏高胜出() {
        let frames = makeFrames(issues: [
            "当前阶段重心过低",
            "当前阶段重心偏高",
        ])
        XCTAssertEqual(
            CenterOfMassFitCalculator.dominantIssue(from: frames),
            "当前阶段重心偏高",
            "两种 issue 各 1 帧时应回落到语义优先级"
        )
    }

    // MARK: - 边界

    func test_dominant_empty_returnsNil() {
        XCTAssertNil(CenterOfMassFitCalculator.dominantIssue(from: []))
    }

    func test_dominant_全部适配_returnsNil() {
        let frames = makeFrames(issues: [
            "当前阶段重心适配", "当前阶段重心适配", "当前阶段重心适配",
        ])
        XCTAssertNil(
            CenterOfMassFitCalculator.dominantIssue(from: frames),
            "全部帧都在目标范围内时不应有主问题"
        )
    }

    func test_dominant_适配帧不参与计数() {
        let frames = makeFrames(issues: [
            "当前阶段重心适配", "当前阶段重心适配", "当前阶段重心适配", "当前阶段重心适配",
            "当前阶段重心过低",
        ])
        XCTAssertEqual(
            CenterOfMassFitCalculator.dominantIssue(from: frames),
            "当前阶段重心过低",
            "适配帧应被过滤，唯一的过低应胜出"
        )
    }

    func test_dominant_未知字面量tie时输给已知() {
        let frames = makeFrames(issues: [
            "some_unknown_issue",
            "当前阶段重心过低",
        ])
        XCTAssertEqual(
            CenterOfMassFitCalculator.dominantIssue(from: frames),
            "当前阶段重心过低",
            "同频 tie 时未知 issue 应排在已知 issue 之后"
        )
    }

    // MARK: - 稳定性 —— 多次调用相同输入应给同一输出

    /// 通过多次不同顺序构造 frames + 上千次调用，即使 Swift Dictionary 内部 hash-seed
    /// 每进程不同，也应保证 tie-break 输出唯一稳定。
    func test_dominant_isDeterministicAcrossManyCalls() {
        let expected = "当前阶段重心偏高"
        for iteration in 0..<2000 {
            // 每轮打乱 frames 顺序，确保测试不依赖 append 顺序
            let issues = iteration.isMultiple(of: 2)
                ? ["当前阶段重心过低", "当前阶段重心偏高", "当前阶段重心过低", "当前阶段重心偏高"]
                : ["当前阶段重心偏高", "当前阶段重心过低", "当前阶段重心偏高", "当前阶段重心过低"]
            let frames = makeFrames(issues: issues)
            XCTAssertEqual(
                CenterOfMassFitCalculator.dominantIssue(from: frames),
                expected
            )
        }
    }

    // MARK: - Helpers

    private func makeFrames(issues: [String]) -> [CenterOfMassFrameAnalysis] {
        issues.enumerated().map { index, issue in
            CenterOfMassFrameAnalysis(
                time: Double(index) * 0.2,
                hipRatio: 0.5,
                targetRangeLower: 0.30,
                targetRangeUpper: 0.50,
                phase: .shaping,
                score: 100,
                confidence: 0.8,
                issue: issue
            )
        }
    }
}

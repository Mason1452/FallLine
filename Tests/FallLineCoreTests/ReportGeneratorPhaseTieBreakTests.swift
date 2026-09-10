import XCTest
@testable import FallLineCore

/// P9-A (2026-09-10): 守护 [ReportGenerator.dominantPhaseRawValue] 在 phaseDistribution
/// 同频 tie 时的稳定排序。修复前采用 `Dictionary.max`，同频 tie 由 hash-order 决定，
/// 报告文案会在 shaping ↔ release 之间无规律抖动，尤其在只有 3~5 帧的短片段。
final class ReportGeneratorPhaseTieBreakTests: XCTestCase {

    // MARK: - 单赢家场景（tie-break 不介入）

    func test_dominant_singleWinner_shapingMajority() {
        let dist: [String: Double] = [
            TurnPhase.shaping.rawValue: 0.6,
            TurnPhase.initiation.rawValue: 0.3,
            TurnPhase.release.rawValue: 0.1,
        ]
        XCTAssertEqual(
            ReportGenerator.dominantPhaseRawValue(from: dist),
            TurnPhase.shaping.rawValue,
            "严格频率最高时应直接返回 shaping"
        )
    }

    func test_dominant_singleWinner_releaseMajority() {
        let dist: [String: Double] = [
            TurnPhase.shaping.rawValue: 0.2,
            TurnPhase.release.rawValue: 0.7,
            TurnPhase.transition.rawValue: 0.1,
        ]
        XCTAssertEqual(
            ReportGenerator.dominantPhaseRawValue(from: dist),
            TurnPhase.release.rawValue
        )
    }

    // MARK: - 同频 tie-break

    func test_dominant_tie_shapingBeatsRelease() {
        let dist: [String: Double] = [
            TurnPhase.shaping.rawValue: 0.4,
            TurnPhase.release.rawValue: 0.4,
            TurnPhase.transition.rawValue: 0.2,
        ]
        XCTAssertEqual(
            ReportGenerator.dominantPhaseRawValue(from: dist),
            TurnPhase.shaping.rawValue,
            "同频时 shaping 应优于 release（弯中承压是核心）"
        )
    }

    func test_dominant_tie_initiationBeatsRelease() {
        let dist: [String: Double] = [
            TurnPhase.initiation.rawValue: 0.5,
            TurnPhase.release.rawValue: 0.5,
        ]
        XCTAssertEqual(
            ReportGenerator.dominantPhaseRawValue(from: dist),
            TurnPhase.initiation.rawValue,
            "同频时 initiation 应优于 release"
        )
    }

    func test_dominant_tie_shapingBeatsInitiation() {
        let dist: [String: Double] = [
            TurnPhase.shaping.rawValue: 0.5,
            TurnPhase.initiation.rawValue: 0.5,
        ]
        XCTAssertEqual(
            ReportGenerator.dominantPhaseRawValue(from: dist),
            TurnPhase.shaping.rawValue,
            "同频时 shaping 应优于 initiation"
        )
    }

    func test_dominant_tie_allFourPhasesEqual_returnsShaping() {
        let dist: [String: Double] = [
            TurnPhase.transition.rawValue: 0.25,
            TurnPhase.initiation.rawValue: 0.25,
            TurnPhase.shaping.rawValue: 0.25,
            TurnPhase.release.rawValue: 0.25,
        ]
        XCTAssertEqual(
            ReportGenerator.dominantPhaseRawValue(from: dist),
            TurnPhase.shaping.rawValue,
            "全部同频时应回落到语义优先级的第一位 shaping"
        )
    }

    // MARK: - 边界

    func test_dominant_emptyDistribution_returnsNil() {
        XCTAssertNil(ReportGenerator.dominantPhaseRawValue(from: [:]))
    }

    func test_dominant_unknownRawValueLosesToKnown() {
        let dist: [String: Double] = [
            "some_unknown_phase": 0.4,
            TurnPhase.release.rawValue: 0.4,
        ]
        XCTAssertEqual(
            ReportGenerator.dominantPhaseRawValue(from: dist),
            TurnPhase.release.rawValue,
            "同频 tie 时未知 rawValue 应排在已知 phase 之后"
        )
    }

    // MARK: - 稳定性 —— 多次调用相同输入应给同一输出

    /// 通过多次不同顺序构造 dict + 上千次调用，即使 Swift Dictionary 内部 hash-seed
    /// 每进程不同，也应保证 tie-break 输出唯一稳定。
    func test_dominant_isDeterministicAcrossManyCalls() {
        let expected = TurnPhase.shaping.rawValue
        for _ in 0..<2000 {
            let dist: [String: Double] = [
                TurnPhase.release.rawValue: 0.5,
                TurnPhase.shaping.rawValue: 0.5,
            ]
            XCTAssertEqual(
                ReportGenerator.dominantPhaseRawValue(from: dist),
                expected
            )
        }
    }
}

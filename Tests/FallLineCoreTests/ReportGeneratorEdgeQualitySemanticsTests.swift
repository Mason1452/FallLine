import XCTest
@testable import FallLineCore

/// P0-α (2026-09-15)：守护“edgeQuality 正式取代 sideslip 语义”的报告层契约。
///
/// Foot-Plant 诊断（scripts/footplant_diagnose.py）证伪了 sideslip 几何量：
/// 主 corpus 的板身-行进夹角带 ~40-50° 系统偏差，且与姿态派生的 edgeQuality
/// 几乎不相关。旧报告实现因此存在两类错误：
/// 1. `edgeConfidence = min(edgeQualityConfidence, boardKinematicConfidence)`，
///    几何置信度低时把真实可信的走刃质量行压成“暂不评分”；
/// 2. 据 sideslip 派生“走刃置信 / 横滑定性”，用被污染的几何量充当走刃结论。
///
/// 本契约锁定：走刃结论只由姿态派生的 edgeQuality(Confidence) 承担；
/// sideslip 降级为板身方向的原始几何诊断，不再出现“横滑角/走刃置信”等走刃语义。
/// 注意：综合分链路（flow 门控、62 分 cap）不在本次范围，仍独立消费 boardKinematicConfidence。
final class ReportGeneratorEdgeQualitySemanticsTests: XCTestCase {

    // MARK: - 核心契约：edgeConfidence 不再与几何置信度取 min

    func test_edgeRow_isReliable_whenGeometryConfidenceIsLow() {
        // edgeQualityConfidence=0.80（姿态证据充分），但几何置信度仅 0.10 且 sideslip=50。
        // 旧实现 min(0.80, 0.10)=0.10 < 0.35 → “走刃质量 暂不评分”；现必须正常给分。
        let output = makeOutput(
            edgeScore: 70,
            edgeLabel: "刻滑稳定",
            edgeConfidence: 0.80,
            boardSummary: makeBoardSummary(sideslip: 50, confidence: 0.10)
        )

        let report = ReportGenerator.generate(output: output)

        XCTAssertTrue(
            report.contains("走刃质量 70/100"),
            "姿态派生 edgeQualityConfidence 充分时，即使几何置信度极低也必须正常展示走刃质量分数"
        )
        XCTAssertFalse(
            report.contains("走刃质量 暂不评分"),
            "几何置信度不得再压制姿态派生的走刃质量判定"
        )
    }

    func test_edgeRow_isNotScored_whenEdgeQualityConfidenceIsLow_evenIfGeometryIsHigh() {
        // 反向契约：edgeQualityConfidence=0.20（姿态证据不足）时，
        // 即使几何置信度=0.90 也必须“暂不评分”——走刃行只认 edgeQualityConfidence。
        let output = makeOutput(
            edgeScore: 55,
            edgeLabel: "刻滑雏形",
            edgeConfidence: 0.20,
            boardSummary: makeBoardSummary(sideslip: 10, confidence: 0.90)
        )

        let report = ReportGenerator.generate(output: output)

        XCTAssertTrue(
            report.contains("走刃质量 暂不评分"),
            "edgeQualityConfidence 不足时走刃质量必须暂不评分，几何高置信度不得补救"
        )
        XCTAssertFalse(report.contains("走刃质量 55/100"))
    }

    // MARK: - 命名恒定：无论是否存在 sideslip 几何量，名称都是“走刃质量”

    func test_edgeName_isAlways走刃质量_whenBoardSummaryAbsent() {
        // 旧实现无 averageSideslipAngle 时命名降级为“走刃倾向”；现必须恒定“走刃质量”。
        let output = makeOutput(
            edgeScore: 72,
            edgeLabel: "刻滑稳定",
            edgeConfidence: 0.70,
            boardSummary: nil
        )

        let report = ReportGenerator.generate(output: output)

        XCTAssertTrue(report.contains("走刃质量 72/100"))
        XCTAssertFalse(report.contains("走刃倾向"))
        XCTAssertFalse(
            report.contains("板身方向（几何诊断）"),
            "无 board summary 时不应渲染几何诊断段"
        )
    }

    // MARK: - sideslip 降级：板身方向段只保留原始几何诊断，不携带走刃语义

    func test_boardSection_isRawGeometryDiagnostic_only() {
        let output = makeOutput(
            edgeScore: 70,
            edgeLabel: "刻滑稳定",
            edgeConfidence: 0.80,
            boardSummary: makeBoardSummary(sideslip: 50, confidence: 0.10)
        )

        let report = ReportGenerator.generate(output: output)

        XCTAssertTrue(report.contains("🏂 板身方向（几何诊断）"))
        XCTAssertTrue(
            report.contains("板身-行进夹角（2D 几何）50°"),
            "sideslip 仅以原始几何夹角形式保留"
        )
        XCTAssertTrue(
            report.contains("几何置信度 10/100"),
            "置信度标注为几何置信度，与走刃判定解耦"
        )
        XCTAssertTrue(
            report.contains("原始诊断，不代表走刃/搓雪"),
            "必须明确标注几何夹角不是走刃结论"
        )
        XCTAssertTrue(
            report.contains("走刃/搓雪结论以“走刃质量”为准"),
            "必须指引读者以走刃质量为走刃结论"
        )
        XCTAssertFalse(
            report.contains("走刃置信"),
            "sideslip 派生的 carvingConfidence 不得再以走刃语义出现"
        )
        XCTAssertFalse(
            report.contains("横滑角"),
            "“横滑角”命名携带错误语义，必须替换为中性几何夹角"
        )
        XCTAssertFalse(report.contains("以横滑为主"))
        XCTAssertFalse(report.contains("有走刃倾向"))
    }

    func test_boardSection_withoutSideslip_saysAngleUnavailable() {
        let output = makeOutput(
            edgeScore: 70,
            edgeLabel: "刻滑稳定",
            edgeConfidence: 0.80,
            boardSummary: makeBoardSummary(sideslip: nil, confidence: 0.50)
        )

        let report = ReportGenerator.generate(output: output)

        XCTAssertTrue(report.contains("板身方向（几何诊断）"))
        XCTAssertTrue(report.contains("暂不估计板身-行进夹角"))
        XCTAssertFalse(report.contains("横滑角"))
    }

    // MARK: - Helpers

    private func makeOutput(
        edgeScore: Double,
        edgeLabel: String,
        edgeConfidence: Double,
        boardSummary: BoardAnalysisSummary?
    ) -> AnalysisOutput {
        let summary = VideoSummary(
            averageScore: edgeScore,
            bestFrame: FrameScore(time: 0, timeString: "00:00", score: edgeScore),
            worstFrame: FrameScore(time: 0, timeString: "00:00", score: edgeScore),
            stabilityScore: 80,
            scoreConsistencyScore: 80,
            scoreStdDev: 5,
            overallLevel: "中级"
        )
        let ski = SkiDerivedMetrics(
            edgeQualityScore: edgeScore,
            edgeQualityLabel: edgeLabel,
            pressureSupportScore: 70,
            pressureSupportLabel: "支撑尚可",
            foreAftSupportScore: 70,
            foreAftSupportLabel: "前后支撑稳定",
            edgeQualityConfidence: edgeConfidence,
            pressureSupportConfidence: 0.70,
            foreAftSupportConfidence: 0.70
        )
        return AnalysisOutput(
            videoPath: "sample.mp4",
            duration: 10,
            totalFrames: 0,
            frames: [],
            summary: summary,
            skiMetrics: ski,
            keyMoments: [],
            boardAnalysis: BoardAnalysis(frames: [], summary: boardSummary)
        )
    }

    private func makeBoardSummary(sideslip: Double?, confidence: Double) -> BoardAnalysisSummary {
        BoardAnalysisSummary(
            frameCount: 20,
            averageSideslipAngle: sideslip,
            carvingConfidence: sideslip == nil ? nil : 0.2,
            confidence: confidence,
            source: .ankleProxy
        )
    }
}

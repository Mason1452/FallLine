import XCTest
@testable import FallLineCore

/// P0 (2026-09-15): 守护 [ReportGenerator.formatFlowFactorText] 在
/// Flow Modulation Edge-Confidence Gating 生效时的报告透明度文案。
/// 该测试用例是"报告端 gated==true 时是否显示 tag"的最小完备契约，
/// 与 [VideoAnalyzer.generateSummary] 中真正的门控决策形成 truth-source ↔ 展示层解耦。
final class ReportGeneratorFlowGatingTests: XCTestCase {

    // MARK: - gated == true：显示"走刃证据不足，未加成"tag

    func test_flowFactor_gated_true_appendsWarningTag() {
        let text = ReportGenerator.formatFlowFactorText(flowFactor: 1.05, gated: true)
        XCTAssertEqual(
            text,
            "×1.05（走刃证据不足，未加成）",
            "gated=true 时报告必须追加提示 tag，避免用户误读为纯加成"
        )
    }

    func test_flowFactor_gated_true_withClampedUnity_stillAppendsTag() {
        // 门控实际 kill 上行加成后，flow factor 会被 clamp 到 1.00，此时仍需 tag
        // 以帮助读者理解"为什么本次评分没有 flow 加成"。
        let text = ReportGenerator.formatFlowFactorText(flowFactor: 1.00, gated: true)
        XCTAssertEqual(text, "×1.00（走刃证据不足，未加成）")
    }

    // MARK: - gated == false：不显示 tag

    func test_flowFactor_gated_false_omitsWarningTag() {
        let text = ReportGenerator.formatFlowFactorText(flowFactor: 1.05, gated: false)
        XCTAssertEqual(
            text,
            "×1.05",
            "gated=false 时（v2/v3/v5 场景，及 v1 低分保护路径）不得显示门控标记"
        )
    }

    func test_flowFactor_gated_false_downwardModulation_stillNoTag() {
        // 光流做了下修（smoothness penalty），但没进入门控 kill 路径 → 不显示 tag
        let text = ReportGenerator.formatFlowFactorText(flowFactor: 0.95, gated: false)
        XCTAssertEqual(text, "×0.95")
    }

    // MARK: - gated == nil：不显示 tag（向后兼容 & 无光流数据）

    func test_flowFactor_gated_nil_omitsWarningTag() {
        let text = ReportGenerator.formatFlowFactorText(flowFactor: 1.00, gated: nil)
        XCTAssertEqual(
            text,
            "×1.00",
            "gated=nil 覆盖两种场景：历史归档字段缺失、无光流数据(framePairsUsed<2)。均不显示 tag。"
        )
    }

    func test_flowFactor_gated_nil_withUpwardFactor_omitsTag() {
        let text = ReportGenerator.formatFlowFactorText(flowFactor: 1.05, gated: nil)
        XCTAssertEqual(text, "×1.05")
    }

    // MARK: - 数值格式化不受 gated 影响

    func test_flowFactor_formatting_preservesTwoDecimals() {
        XCTAssertEqual(
            ReportGenerator.formatFlowFactorText(flowFactor: 1.132, gated: false),
            "×1.13",
            "flow factor 强制 2 位小数格式，与 clamp 上限 1.13 对齐"
        )
        XCTAssertEqual(
            ReportGenerator.formatFlowFactorText(flowFactor: 0.868, gated: false),
            "×0.87",
            "flow factor 强制 2 位小数格式，与 clamp 下限 0.87 对齐"
        )
    }
}

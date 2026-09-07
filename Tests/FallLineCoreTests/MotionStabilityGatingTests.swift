import XCTest
@testable import FallLineCore

/// P0-D (2026-09-07) motion stability velocity gating & lean 5-frame median 端到端验证。
///
/// - **方案 A (lean medianWindow5)**：由 [PoseSmoother](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift) 单测覆盖（`PoseSmootherTests`）
/// - **方案 B (velocity gating)**：在此测试通过合成 knee 序列在 [calculateMotionStability](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L484-L544) 端验证
///
/// 通过对比"含单帧极端异常"与"完全平稳"两组序列的 stabilityScore，
/// 证实 velocityMultiplier=3.0 门控确实屏蔽了 Vision 检测噪声。
final class MotionStabilityGatingTests: XCTestCase {

    /// 单帧极端 knee 跳变（>3× tolerance）应被 velocity 门控屏蔽，
    /// stabilityScore 不应因单帧噪声而显著下降。
    ///
    /// 构造：knee = [120, 120, 120, 120, 120, 700, 120, 120, 120, 120]（10 帧，5fps）
    ///  - 中间第 5 帧跳到 700°，帧间速度 = (700-120)/0.2 = 2900°/s（≈20× tolerance 140）
    ///  - 若无门控：saturating penalty=100 会让 knee 通道 avg_pen 显著上抬
    ///  - 有门控：>3×140=420°/s 被跳过，只留其他平稳帧
    func test_p0d_extremeKneeSpike_isGatedOut() async throws {
        let kneeSeries: [Double] = [120, 120, 120, 120, 120, 700, 120, 120, 120, 120]
        let frames = kneeSeries.enumerated().map { (i, k) in
            makeFrame(time: Double(i) * 0.2, knee: k, calf: 45)
        }

        let stabilityWithSpike = await makeAnalyzer().generateSummary(from: frames)?.stabilityScore ?? 0

        // 全平稳序列对照组
        let stableFrames = (0..<10).map { i in
            makeFrame(time: Double(i) * 0.2, knee: 120, calf: 45)
        }
        let stabilityStable = await makeAnalyzer().generateSummary(from: stableFrames)?.stabilityScore ?? 0

        // P0-D 前：一个极端 knee 跳变足以拉低整段 stabilityScore（差异 >20）
        // P0-D 后：velocity>420°/s 门控生效，spike 帧被跳过，差异应 <10
        let diff = abs(stabilityStable - stabilityWithSpike)
        XCTAssertLessThan(diff, 10.0,
                          "P0-D 门控后单帧 knee 跳变对 stabilityScore 影响应 <10 分，实测差异 \(diff)")
        XCTAssertGreaterThan(stabilityWithSpike, 85.0,
                             "有 velocity 门控时含单帧异常的 stabilityScore 仍应 >85，实测 \(stabilityWithSpike)")
    }

    /// 正常范围帧间变化（<3× tolerance）应正常参与惩罚计入，门控不误伤真实动作。
    ///
    /// 构造：knee = [120, 150, 120, 150, 120, ...]（快速抖动但每步 (150-120)/0.2 = 150°/s ≈ 1.07× tolerance）
    /// 此时 penalty 应正常累计，stabilityScore 明显低于纯平稳序列。
    func test_p0d_normalRangeJitter_stillPenalized() async throws {
        let kneeSeries: [Double] = [120, 150, 120, 150, 120, 150, 120, 150, 120, 150]
        let frames = kneeSeries.enumerated().map { (i, k) in
            makeFrame(time: Double(i) * 0.2, knee: k, calf: 45)
        }

        let stability = await makeAnalyzer().generateSummary(from: frames)?.stabilityScore ?? 0
        XCTAssertLessThan(stability, 90.0,
                          "正常范围快速抖动（速度 ≈1.07× tolerance）应被惩罚累计，stability <90，实测 \(stability)")
    }

    // MARK: - Helpers

    private func makeAnalyzer() -> VideoAnalyzer {
        VideoAnalyzer(videoURL: URL(fileURLWithPath: "/tmp/motion-stability-gating.mp4"))
    }

    private func makeFrame(time: Double, knee: Double, calf: Double) -> DetectionResult {
        DetectionResult(
            time: time,
            objects: [],
            faces: [],
            textObservations: [],
            sceneClassifications: [],
            bodyPose: BodyPoseData(
                detected: true,
                visibility: .full,
                bodyLeanAngle: MetricWithConfidence(value: 25, confidence: 0.9),
                leftBodyLeanAngle: MetricWithConfidence(value: 25, confidence: 0.9),
                rightBodyLeanAngle: MetricWithConfidence(value: 25, confidence: 0.9),
                leftKneeBendAngle: MetricWithConfidence(value: knee, confidence: 0.9),
                rightKneeBendAngle: MetricWithConfidence(value: knee, confidence: 0.9),
                leftCalfLeanAngle: MetricWithConfidence(value: calf, confidence: 0.9),
                rightCalfLeanAngle: MetricWithConfidence(value: calf, confidence: 0.9),
                centerOfGravity: MetricWithConfidence(value: 0.40, confidence: 0.9)
            ),
            poseScore: PoseScore(
                totalScore: 80,
                forwardLeanScore: 80,
                kneeBendScore: 80,
                calfLeanScore: 60,
                gravityScore: 70,
                symmetryScore: 80,
                totalConfidence: 0.9,
                forwardLeanConfidence: 0.9,
                kneeBendConfidence: 0.9,
                calfLeanConfidence: 0.9,
                gravityConfidence: 0.9,
                symmetryConfidence: 0.9,
                level: "中级",
                suggestions: []
            )
        )
    }
}

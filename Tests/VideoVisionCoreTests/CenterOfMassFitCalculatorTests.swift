import XCTest
@testable import VideoVisionCore

final class CenterOfMassFitCalculatorTests: XCTestCase {

    func test_basicControlStageAcceptsModerateCenterOfMass() {
        let frames = makeFrames(hipRatio: 0.45, totalScore: 55, calfScore: 40, kneeScore: 70)
        let analysis = CenterOfMassFitCalculator.analyze(
            frames: frames,
            summary: makeSummary(averageScore: 55),
            turnAnalysis: makeTurnAnalysis(phase: .shaping)
        )

        XCTAssertGreaterThan(analysis.cogStageFitScore, 95)
        XCTAssertEqual(analysis.mainIssue, nil)
    }

    func test_advancedShapingRequiresLowerCenterOfMassThanBasicControl() {
        let basic = CenterOfMassFitCalculator.analyze(
            frames: makeFrames(hipRatio: 0.45, totalScore: 55, calfScore: 40, kneeScore: 70),
            summary: makeSummary(averageScore: 55),
            turnAnalysis: makeTurnAnalysis(phase: .shaping)
        )
        let advanced = CenterOfMassFitCalculator.analyze(
            frames: makeFrames(hipRatio: 0.45, totalScore: 88, calfScore: 80, kneeScore: 90),
            summary: makeSummary(averageScore: 88),
            turnAnalysis: makeTurnAnalysis(phase: .shaping)
        )

        XCTAssertGreaterThan(basic.cogStageFitScore, advanced.cogStageFitScore)
        XCTAssertLessThan(advanced.cogStageFitScore, 80)
        XCTAssertEqual(advanced.mainIssue, "当前阶段重心偏高")
    }

    func test_tooHighCenterOfMassInShapingProducesMainIssue() {
        let analysis = CenterOfMassFitCalculator.analyze(
            frames: makeFrames(hipRatio: 0.75, totalScore: 72, calfScore: 45, kneeScore: 80),
            summary: makeSummary(averageScore: 72),
            turnAnalysis: makeTurnAnalysis(phase: .shaping)
        )

        XCTAssertLessThan(analysis.cogStageFitScore, 20)
        XCTAssertEqual(analysis.mainIssue, "当前阶段重心偏高")
    }

    func test_missingCenterOfMassReturnsEmptyAnalysis() {
        let frame = DetectionResult(
            time: 0,
            objects: [],
            faces: [],
            textObservations: [],
            sceneClassifications: [],
            bodyPose: BodyPoseData(
                detected: true,
                visibility: .full,
                bodyLeanAngle: nil,
                leftBodyLeanAngle: nil,
                rightBodyLeanAngle: nil,
                leftKneeBendAngle: nil,
                rightKneeBendAngle: nil,
                leftCalfLeanAngle: nil,
                rightCalfLeanAngle: nil,
                centerOfGravity: nil
            ),
            poseScore: nil
        )

        let analysis = CenterOfMassFitCalculator.analyze(
            frames: [frame],
            summary: makeSummary(averageScore: 0),
            turnAnalysis: .empty
        )

        XCTAssertEqual(analysis.frameCount, 0)
        XCTAssertEqual(analysis.cogStageFitScore, 0)
    }

    private func makeFrames(
        hipRatio: Double,
        totalScore: Double,
        calfScore: Double,
        kneeScore: Double
    ) -> [DetectionResult] {
        (0..<5).map { index in
            makeFrame(
                time: Double(index),
                hipRatio: hipRatio,
                totalScore: totalScore,
                calfScore: calfScore,
                kneeScore: kneeScore
            )
        }
    }

    private func makeFrame(
        time: Double,
        hipRatio: Double,
        totalScore: Double,
        calfScore: Double,
        kneeScore: Double
    ) -> DetectionResult {
        DetectionResult(
            time: time,
            objects: [],
            faces: [],
            textObservations: [],
            sceneClassifications: [],
            bodyPose: BodyPoseData(
                detected: true,
                visibility: .full,
                bodyLeanAngle: nil,
                leftBodyLeanAngle: nil,
                rightBodyLeanAngle: nil,
                leftKneeBendAngle: nil,
                rightKneeBendAngle: nil,
                leftCalfLeanAngle: nil,
                rightCalfLeanAngle: nil,
                centerOfGravity: MetricWithConfidence(value: hipRatio, confidence: 1)
            ),
            poseScore: PoseScore(
                totalScore: totalScore,
                forwardLeanScore: 80,
                kneeBendScore: kneeScore,
                calfLeanScore: calfScore,
                gravityScore: PoseScorer.gravityScore(from: hipRatio),
                symmetryScore: 80,
                level: "测试",
                suggestions: []
            )
        )
    }

    private func makeTurnAnalysis(phase: TurnPhase) -> TurnAnalysis {
        TurnAnalysis(
            frames: (0..<5).map { index in
                TurnFrameAnalysis(
                    time: Double(index),
                    edgeSignal: 18,
                    edgeDirection: .imageRight,
                    phase: phase,
                    confidence: 1
                )
            },
            segments: []
        )
    }

    private func makeSummary(averageScore: Double) -> VideoSummary {
        VideoSummary(
            averageScore: averageScore,
            bestFrame: FrameScore(time: 0, timeString: "00:00", score: averageScore),
            worstFrame: FrameScore(time: 0, timeString: "00:00", score: averageScore),
            stabilityScore: 70,
            scoreConsistencyScore: 90,
            scoreStdDev: 2,
            overallLevel: "测试"
        )
    }
}

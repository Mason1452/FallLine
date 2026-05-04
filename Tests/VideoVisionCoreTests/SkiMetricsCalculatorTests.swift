import XCTest
@testable import VideoVisionCore

final class SkiMetricsCalculatorTests: XCTestCase {

    func test_confidencePropagatesFromPoseScoreToSkiMetrics() {
        let poseScore = PoseScore(
            totalScore: 80,
            forwardLeanScore: 80,
            kneeBendScore: 85,
            calfLeanScore: 60,
            gravityScore: 75,
            symmetryScore: 70,
            totalConfidence: 0.8,
            forwardLeanConfidence: 0.9,
            kneeBendConfidence: 0.8,
            calfLeanConfidence: 0.4,
            gravityConfidence: 0.7,
            symmetryConfidence: 0.6,
            level: "高级",
            suggestions: []
        )

        let metrics = SkiMetricsCalculator.compute(
            from: poseScore,
            stability: 70,
            stabilityConfidence: 0.9
        )

        XCTAssertGreaterThan(metrics.edgeQualityConfidence, 0.45)
        XCTAssertLessThan(metrics.edgeQualityConfidence, metrics.foreAftSupportConfidence)
        XCTAssertGreaterThan(metrics.pressureSupportConfidence, 0.65)
        XCTAssertGreaterThan(metrics.foreAftSupportConfidence, 0.75)
    }

    func test_averageCarriesConfidence() {
        let highConfidence = makeFrame(time: 0, confidence: 0.9)
        let lowConfidence = makeFrame(time: 1, confidence: 0.3)

        let metrics = SkiMetricsCalculator.average(from: [highConfidence, lowConfidence], stability: 70)

        XCTAssertGreaterThan(metrics.pressureSupportConfidence, 0.3)
        XCTAssertLessThan(metrics.pressureSupportConfidence, 0.9)
    }

    private func makeFrame(time: Double, confidence: Double) -> DetectionResult {
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
                centerOfGravity: nil
            ),
            poseScore: PoseScore(
                totalScore: 80,
                forwardLeanScore: 80,
                kneeBendScore: 80,
                calfLeanScore: 80,
                gravityScore: 80,
                symmetryScore: 80,
                totalConfidence: confidence,
                forwardLeanConfidence: confidence,
                kneeBendConfidence: confidence,
                calfLeanConfidence: confidence,
                gravityConfidence: confidence,
                symmetryConfidence: confidence,
                level: "高级",
                suggestions: []
            )
        )
    }
}

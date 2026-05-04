import XCTest
@testable import VideoVisionCore

final class StableCarvingBaselineTests: XCTestCase {

    func test_generateSummary_usesSustainedHighPlatformForStableCarvingConflict() {
        let scores: [(score: Double, confidence: Double, count: Int)] = [
            (53.4, 0.81, 4),
            (48.0, 0.68, 7),
            (56.6, 0.60, 7),
            (53.8, 0.32, 7),
            (61.8, 0.61, 7),
            (79.1, 0.38, 10)
        ]
        let frames = makeFrames(from: scores)

        let summary = makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.averageScore ?? 0, 79.1, accuracy: 0.1)
        XCTAssertGreaterThan(summary?.stabilityScore ?? 0, 95)
    }

    func test_generateSummary_usesBestThirdInsteadOfFullAverage() {
        let scores: [(score: Double, confidence: Double, count: Int)] = [
            (50, 0.8, 12),
            (90, 0.8, 4)
        ]
        let frames = makeFrames(from: scores)

        let summary = makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.averageScore ?? 0, 76.7, accuracy: 0.1)
    }

    func test_generateSummary_capsScoreWhenReliableEvidenceIsTooSparse() {
        let frames = makeFrames(from: [
            (90, 0.8, 7)
        ])

        let summary = makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.averageScore ?? 0, 65, accuracy: 0.1)
    }

    func test_generateSummary_capsHighPostureScoreWhenEdgeEvidenceIsWeak() {
        let frames = makeFrames(score: 82, confidence: 0.8, count: 18, calfScore: 36)

        let summary = makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.averageScore ?? 0, 58, accuracy: 0.1)
    }

    private func makeAnalyzer() -> VideoAnalyzer {
        VideoAnalyzer(videoURL: URL(fileURLWithPath: "/tmp/stable-carving-test.mp4"))
    }

    private func makeFrames(from groups: [(score: Double, confidence: Double, count: Int)]) -> [DetectionResult] {
        var frames: [DetectionResult] = []
        var time = 0.0
        for group in groups {
            for _ in 0..<group.count {
                frames.append(makeFrame(time: time, score: group.score, confidence: group.confidence))
                time += 1.0
            }
        }
        return frames
    }

    private func makeFrames(score: Double, confidence: Double, count: Int, calfScore: Double) -> [DetectionResult] {
        (0..<count).map { index in
            makeFrame(
                time: Double(index),
                score: score,
                confidence: confidence,
                calfScore: calfScore
            )
        }
    }

    private func makeFrame(
        time: Double,
        score: Double,
        confidence: Double,
        calfScore: Double? = nil
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
                bodyLeanAngle: MetricWithConfidence(value: 25, confidence: 0.9),
                leftBodyLeanAngle: MetricWithConfidence(value: 25, confidence: 0.9),
                rightBodyLeanAngle: MetricWithConfidence(value: 25, confidence: 0.9),
                leftKneeBendAngle: MetricWithConfidence(value: 120, confidence: 0.9),
                rightKneeBendAngle: MetricWithConfidence(value: 120, confidence: 0.9),
                leftCalfLeanAngle: MetricWithConfidence(value: 45, confidence: 0.9),
                rightCalfLeanAngle: MetricWithConfidence(value: 45, confidence: 0.9),
                centerOfGravity: MetricWithConfidence(value: 0.40, confidence: 0.9)
            ),
            poseScore: PoseScore(
                totalScore: score,
                forwardLeanScore: 80,
                kneeBendScore: score,
                calfLeanScore: calfScore ?? score,
                gravityScore: 70,
                symmetryScore: 80,
                totalConfidence: confidence,
                forwardLeanConfidence: confidence,
                kneeBendConfidence: confidence,
                calfLeanConfidence: confidence,
                gravityConfidence: confidence,
                symmetryConfidence: confidence,
                level: "中级",
                suggestions: []
            )
        )
    }
}

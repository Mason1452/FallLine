import XCTest
@testable import FallLineCore

final class StableCarvingBaselineTests: XCTestCase {

    func test_generateSummary_usesSustainedHighPlatformForStableCarvingConflict() async throws {
        let scores: [(score: Double, confidence: Double, count: Int)] = [
            (53.4, 0.81, 4),
            (48.0, 0.68, 7),
            (56.6, 0.60, 7),
            (53.8, 0.32, 7),
            (61.8, 0.61, 7),
            (79.1, 0.38, 10)
        ]
        let frames = makeFrames(from: scores)

        let summary = await makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.averageScore ?? 0, 79.1, accuracy: 0.1)
        XCTAssertGreaterThan(summary?.stabilityScore ?? 0, 95)
    }

    func test_generateSummary_usesBestThirdInsteadOfFullAverage() async throws {
        let scores: [(score: Double, confidence: Double, count: Int)] = [
            (50, 0.8, 12),
            (90, 0.8, 4)
        ]
        let frames = makeFrames(from: scores)

        let summary = await makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.averageScore ?? 0, 76.7, accuracy: 0.1)
    }

    func test_generateSummary_capsScoreWhenReliableEvidenceIsTooSparse() async throws {
        let frames = makeFrames(from: [
            (90, 0.8, 7)
        ])

        let summary = await makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.averageScore ?? 0, 65, accuracy: 0.1)
    }

    func test_generateSummary_capsDenseFramesWhenReliableDurationIsTooShort() async throws {
        let frames = makeFrames(
            score: 90,
            confidence: 0.8,
            count: 20,
            calfScore: 90,
            timeStep: 0.2
        )

        let summary = await makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.rawPoseAverageScore ?? 0, 90, accuracy: 0.1)
        XCTAssertEqual(summary?.bestThirdAverageScore ?? 0, 90, accuracy: 0.1)
        XCTAssertEqual(summary?.evidenceCappedScore ?? 0, 55, accuracy: 0.1)
        XCTAssertEqual(summary?.averageScore ?? 0, 55, accuracy: 0.1)
        XCTAssertEqual(summary?.flowModulationFactor ?? 0, 1, accuracy: 0.001)
    }

    func test_generateSummary_capsHighPostureScoreWhenEdgeEvidenceIsWeak() async throws {
        let frames = makeFrames(score: 82, confidence: 0.8, count: 18, calfScore: 36)

        let summary = await makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.averageScore ?? 0, 58, accuracy: 0.1)
    }

    func test_generateSummary_capsHighScoreWhenBoardKinematicEvidenceIsVeryLow() async throws {
        let frames = makeFrames(
            score: 82,
            confidence: 0.8,
            count: 9,
            calfScore: 82,
            boardConfidence: 0.10
        )

        let summary = await makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.averageScore ?? 0, 62, accuracy: 0.1)
    }

    func test_generateSummary_capsHighScoreWhenBoardTravelAngleShowsSideslip() async throws {
        let frames = makeFrames(
            score: 82,
            confidence: 0.8,
            count: 12,
            calfScore: 82,
            boardConfidence: 0.9,
            boardAngle: 90
        )

        let summary = await makeAnalyzer().generateSummary(from: frames)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.averageScore ?? 0, 58, accuracy: 0.1)
    }

    private func makeAnalyzer() -> VideoAnalyzer {
        VideoAnalyzer(videoURL: URL(fileURLWithPath: "/tmp/stable-carving-test.mp4"))
    }

    private func makeFrames(
        from groups: [(score: Double, confidence: Double, count: Int)],
        timeStep: Double = 1.0
    ) -> [DetectionResult] {
        var frames: [DetectionResult] = []
        var time = 0.0
        for group in groups {
            for _ in 0..<group.count {
                frames.append(makeFrame(time: time, score: group.score, confidence: group.confidence))
                time += timeStep
            }
        }
        return frames
    }

    private func makeFrames(
        score: Double,
        confidence: Double,
        count: Int,
        calfScore: Double,
        boardConfidence: Double? = nil,
        boardAngle: Double = 0,
        timeStep: Double = 1.0
    ) -> [DetectionResult] {
        (0..<count).map { index in
            makeFrame(
                time: Double(index) * timeStep,
                score: score,
                confidence: confidence,
                calfScore: calfScore,
                boardConfidence: boardConfidence,
                boardAngle: boardAngle
            )
        }
    }

    private func makeFrame(
        time: Double,
        score: Double,
        confidence: Double,
        calfScore: Double? = nil,
        boardConfidence: Double? = nil,
        boardAngle: Double = 0
    ) -> DetectionResult {
        let centerX = 0.1 + time * 0.05
        return DetectionResult(
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
                centerOfGravity: MetricWithConfidence(value: 0.40, confidence: 0.9),
                ankleCenterX: boardConfidence.map { _ in MetricWithConfidence(value: centerX, confidence: 1) },
                bodyCenterX: boardConfidence.map { _ in MetricWithConfidence(value: centerX, confidence: 1) },
                ankleCenterY: boardConfidence.map { _ in MetricWithConfidence(value: 0.5, confidence: 1) },
                bodyCenterY: boardConfidence.map { _ in MetricWithConfidence(value: 0.5, confidence: 1) },
                ankleProxyBoardAngle: boardConfidence.map { MetricWithConfidence(value: boardAngle, confidence: $0) }
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

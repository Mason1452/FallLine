import XCTest
@testable import VideoVisionCore

final class HighlightMomentDetectorTests: XCTestCase {

    func test_detectsBestSustainedSegment() {
        let frames = makeFrames(groups: [
            (score: 55, count: 4),
            (score: 82, count: 6),
            (score: 60, count: 4)
        ])
        let summary = makeSummary(averageScore: 68, stabilityScore: 90)

        let highlights = HighlightMomentDetector.detect(from: frames, summary: summary, maxCount: 1)

        XCTAssertEqual(highlights.count, 1)
        XCTAssertEqual(highlights.first?.startTime, "00:04")
        XCTAssertEqual(highlights.first?.endTime, "00:09")
        XCTAssertGreaterThan(highlights.first?.score ?? 0, 80)
    }

    func test_doesNotTreatSingleFrameSpikeAsHighlight() {
        let frames = makeFrames(groups: [
            (score: 55, count: 5),
            (score: 95, count: 1),
            (score: 55, count: 5)
        ])
        let summary = makeSummary(averageScore: 58, stabilityScore: 90)

        let highlights = HighlightMomentDetector.detect(from: frames, summary: summary, maxCount: 1)

        XCTAssertTrue(highlights.isEmpty)
    }

    func test_requiresEnoughReliableFramesForHighlight() {
        let frames = makeFrames(groups: [
            (score: 90, count: 7)
        ])
        let summary = makeSummary(averageScore: 65, stabilityScore: 90)

        let highlights = HighlightMomentDetector.detect(from: frames, summary: summary, maxCount: 1)

        XCTAssertTrue(highlights.isEmpty)
    }

    func test_suppressesHighlightWhenOverallEdgeEvidenceIsWeak() {
        let frames = makeFrames(score: 82, count: 10, calfScore: 36)
        let summary = makeSummary(averageScore: 60, stabilityScore: 90)

        let highlights = HighlightMomentDetector.detect(from: frames, summary: summary, maxCount: 1)

        XCTAssertTrue(highlights.isEmpty)
    }

    func test_suppressesHighlightWhenBoardKinematicEvidenceIsVeryLow() {
        let frames = makeFrames(score: 82, count: 9, calfScore: 82, boardConfidence: 0.10)
        let summary = makeSummary(averageScore: 62, stabilityScore: 90)

        let highlights = HighlightMomentDetector.detect(from: frames, summary: summary, maxCount: 1)

        XCTAssertTrue(highlights.isEmpty)
    }

    func test_suppressesHighlightWhenBoardTravelAngleShowsSideslip() {
        let frames = makeFrames(score: 82, count: 12, calfScore: 82, boardConfidence: 0.9, boardAngle: 90)
        let summary = makeSummary(averageScore: 58, stabilityScore: 90)

        let highlights = HighlightMomentDetector.detect(from: frames, summary: summary, maxCount: 1)

        XCTAssertTrue(highlights.isEmpty)
    }

    private func makeFrames(groups: [(score: Double, count: Int)]) -> [DetectionResult] {
        var frames: [DetectionResult] = []
        var time = 0.0
        for group in groups {
            for _ in 0..<group.count {
                frames.append(makeFrame(time: time, score: group.score))
                time += 1.0
            }
        }
        return frames
    }

    private func makeFrames(
        score: Double,
        count: Int,
        calfScore: Double,
        boardConfidence: Double? = nil,
        boardAngle: Double = 0
    ) -> [DetectionResult] {
        (0..<count).map { index in
            makeFrame(
                time: Double(index),
                score: score,
                calfScore: calfScore,
                boardConfidence: boardConfidence,
                boardAngle: boardAngle
            )
        }
    }

    private func makeFrame(
        time: Double,
        score: Double,
        calfScore: Double? = nil,
        boardConfidence: Double? = nil,
        boardAngle: Double = 0
    ) -> DetectionResult {
        let confidence = 0.8
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
                bodyLeanAngle: MetricWithConfidence(value: 20, confidence: confidence),
                leftBodyLeanAngle: MetricWithConfidence(value: 20, confidence: confidence),
                rightBodyLeanAngle: MetricWithConfidence(value: 20, confidence: confidence),
                leftKneeBendAngle: MetricWithConfidence(value: 120, confidence: confidence),
                rightKneeBendAngle: MetricWithConfidence(value: 120, confidence: confidence),
                leftCalfLeanAngle: MetricWithConfidence(value: 45, confidence: confidence),
                rightCalfLeanAngle: MetricWithConfidence(value: 45, confidence: confidence),
                centerOfGravity: MetricWithConfidence(value: 0.35, confidence: confidence),
                ankleCenterX: boardConfidence.map { _ in MetricWithConfidence(value: centerX, confidence: 1) },
                bodyCenterX: boardConfidence.map { _ in MetricWithConfidence(value: centerX, confidence: 1) },
                ankleCenterY: boardConfidence.map { _ in MetricWithConfidence(value: 0.5, confidence: 1) },
                bodyCenterY: boardConfidence.map { _ in MetricWithConfidence(value: 0.5, confidence: 1) },
                ankleProxyBoardAngle: boardConfidence.map { MetricWithConfidence(value: boardAngle, confidence: $0) }
            ),
            poseScore: PoseScore(
                totalScore: score,
                forwardLeanScore: score,
                kneeBendScore: score,
                calfLeanScore: calfScore ?? score,
                gravityScore: score,
                symmetryScore: score,
                totalConfidence: confidence,
                forwardLeanConfidence: confidence,
                kneeBendConfidence: confidence,
                calfLeanConfidence: confidence,
                gravityConfidence: confidence,
                symmetryConfidence: confidence,
                level: "中级",
                suggestions: []
            ),
            skiMetrics: SkiDerivedMetrics(
                edgeQualityScore: score,
                edgeQualityLabel: "测试",
                pressureSupportScore: score,
                pressureSupportLabel: "测试",
                foreAftSupportScore: score,
                foreAftSupportLabel: "测试",
                edgeQualityConfidence: confidence,
                pressureSupportConfidence: confidence,
                foreAftSupportConfidence: confidence
            )
        )
    }

    private func makeSummary(averageScore: Double, stabilityScore: Double) -> VideoSummary {
        VideoSummary(
            averageScore: averageScore,
            bestFrame: FrameScore(time: 0, timeString: "00:00", score: averageScore),
            worstFrame: FrameScore(time: 0, timeString: "00:00", score: averageScore),
            stabilityScore: stabilityScore,
            scoreConsistencyScore: 80,
            scoreStdDev: 5,
            overallLevel: "中级"
        )
    }
}

import XCTest
@testable import FallLineCore

final class TurnPhaseDetectorTests: XCTestCase {

    func test_signChangeProducesTransitionAndBothDirections() {
        let analysis = TurnPhaseDetector.analyze(frames: makeFrames(signals: [-20, -18, 0, 18, 20]))

        XCTAssertTrue(analysis.frames.contains { $0.phase == .transition })
        XCTAssertTrue(analysis.frames.contains { $0.edgeDirection == .imageLeft })
        XCTAssertTrue(analysis.frames.contains { $0.edgeDirection == .imageRight })
    }

    func test_risingEdgeSignalProducesInitiation() {
        let analysis = TurnPhaseDetector.analyze(frames: makeFrames(signals: [0, 10, 18, 25, 26]))

        XCTAssertTrue(analysis.frames.contains { $0.phase == .initiation })
    }

    func test_stableHighEdgeSignalProducesShaping() {
        let analysis = TurnPhaseDetector.analyze(frames: makeFrames(signals: [20, 21, 20, 22, 21]))

        XCTAssertTrue(analysis.frames.contains { $0.phase == .shaping })
    }

    func test_fallingEdgeSignalProducesRelease() {
        let analysis = TurnPhaseDetector.analyze(frames: makeFrames(signals: [30, 26, 18, 10, 0]))

        XCTAssertTrue(analysis.frames.contains { $0.phase == .release })
    }

    func test_lessThanThreeFramesDoesNotCreateSegment() {
        let analysis = TurnPhaseDetector.analyze(frames: makeFrames(signals: [20, 21]))

        XCTAssertEqual(analysis.frames.count, 2)
        XCTAssertTrue(analysis.segments.isEmpty)
    }

    func test_neutralNoiseDoesNotCreateSegment() {
        let analysis = TurnPhaseDetector.analyze(frames: makeFrames(signals: [-3, 2, 0, 4, -2]))

        XCTAssertTrue(analysis.frames.allSatisfy { $0.edgeDirection == .neutral })
        XCTAssertTrue(analysis.segments.isEmpty)
    }

    func test_lowShapingEdgeQualityMarksMainIssue() {
        let analysis = TurnPhaseDetector.analyze(frames: makeFrames(signals: [20, 21, 20, 22, 21], edgeScore: 45))

        XCTAssertEqual(analysis.segments.first?.mainIssue, "弯中刃角保持不足")
    }

    private func makeFrames(signals: [Double], edgeScore: Double = 80) -> [DetectionResult] {
        signals.enumerated().map { index, signal in
            makeFrame(time: Double(index), signal: signal, edgeScore: edgeScore)
        }
    }

    private func makeFrame(time: Double, signal: Double, edgeScore: Double) -> DetectionResult {
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
                centerOfGravity: nil,
                signedBodyLeanAngle: nil,
                signedCalfLeanAngle: MetricWithConfidence(value: signal * 2, confidence: 1),
                hipCenterX: nil,
                ankleCenterX: nil,
                bodyCenterX: nil
            ),
            poseScore: PoseScore(
                totalScore: 80,
                forwardLeanScore: 80,
                kneeBendScore: 80,
                calfLeanScore: edgeScore,
                gravityScore: 80,
                symmetryScore: 80,
                level: "高级",
                suggestions: []
            ),
            skiMetrics: SkiDerivedMetrics(
                edgeQualityScore: edgeScore,
                edgeQualityLabel: "测试",
                pressureSupportScore: 80,
                pressureSupportLabel: "测试",
                foreAftSupportScore: 80,
                foreAftSupportLabel: "测试"
            )
        )
    }
}

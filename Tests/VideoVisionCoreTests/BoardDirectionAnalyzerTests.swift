import XCTest
@testable import VideoVisionCore

final class BoardDirectionAnalyzerTests: XCTestCase {

    func test_boardAxisAlignedWithTravelProducesLowSideslip() {
        let analysis = BoardDirectionAnalyzer.analyze(frames: [
            makeFrame(time: 0, boardAngle: 0, centerX: 0.1, centerY: 0.5),
            makeFrame(time: 1, boardAngle: 0, centerX: 0.2, centerY: 0.5),
            makeFrame(time: 2, boardAngle: 0, centerX: 0.3, centerY: 0.5)
        ])

        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 0, accuracy: 0.1)
        XCTAssertGreaterThan(analysis.summary?.carvingConfidence ?? 0, 95)
        XCTAssertEqual(analysis.frames.compactMap(\.kinematics).count, 3)
    }

    func test_boardAxisPerpendicularToTravelProducesHighSideslip() {
        let analysis = BoardDirectionAnalyzer.analyze(frames: [
            makeFrame(time: 0, boardAngle: 90, centerX: 0.1, centerY: 0.5),
            makeFrame(time: 1, boardAngle: 90, centerX: 0.2, centerY: 0.5),
            makeFrame(time: 2, boardAngle: 90, centerX: 0.3, centerY: 0.5)
        ])

        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 90, accuracy: 0.1)
        XCTAssertLessThan(analysis.summary?.carvingConfidence ?? 100, 1)
    }

    func test_stationaryCentersKeepObservationButNoKinematics() {
        let analysis = BoardDirectionAnalyzer.analyze(frames: [
            makeFrame(time: 0, boardAngle: 0, centerX: 0.2, centerY: 0.5),
            makeFrame(time: 1, boardAngle: 0, centerX: 0.2, centerY: 0.5),
            makeFrame(time: 2, boardAngle: 0, centerX: 0.2, centerY: 0.5)
        ])

        XCTAssertEqual(analysis.frames.count, 3)
        XCTAssertTrue(analysis.frames.allSatisfy { $0.kinematics == nil })
        XCTAssertNil(analysis.summary?.averageSideslipAngle)
        XCTAssertNil(analysis.summary?.carvingConfidence)
    }

    func test_missingBoardObservationReturnsEmptyAnalysis() {
        let frame = makeFrame(time: 0, boardAngle: nil, centerX: 0.2, centerY: 0.5)
        let analysis = BoardDirectionAnalyzer.analyze(frames: [frame])

        XCTAssertTrue(analysis.frames.isEmpty)
        XCTAssertNil(analysis.summary)
    }

    private func makeFrame(
        time: Double,
        boardAngle: Double?,
        centerX: Double,
        centerY: Double
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
                centerOfGravity: nil,
                hipCenterX: MetricWithConfidence(value: centerX, confidence: 1),
                ankleCenterX: MetricWithConfidence(value: centerX, confidence: 1),
                bodyCenterX: MetricWithConfidence(value: centerX, confidence: 1),
                hipCenterY: MetricWithConfidence(value: centerY + 0.2, confidence: 1),
                ankleCenterY: MetricWithConfidence(value: centerY, confidence: 1),
                bodyCenterY: MetricWithConfidence(value: centerY, confidence: 1),
                ankleProxyBoardAngle: boardAngle.map { MetricWithConfidence(value: $0, confidence: 1) }
            ),
            poseScore: nil
        )
    }
}

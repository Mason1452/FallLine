import CoreGraphics
import XCTest
@testable import FallLineCore

final class BoardVisualLineDetectorTests: XCTestCase {

    func test_detectsDarkBoardLineNearAnkles() throws {
        let image = try makeSyntheticImage(
            width: 180,
            height: 120,
            lineStart: CGPoint(x: 45, y: 60),
            lineEnd: CGPoint(x: 135, y: 60)
        )
        let pose = makePose(
            leftAnkle: PoseJointPoint(x: 0.35, y: 0.50, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.65, y: 0.50, confidence: 0.9),
            proxyAngle: 0
        )

        let observation = BoardVisualLineDetector.detect(cgImage: image, pose: pose)

        XCTAssertNotNil(observation)
        XCTAssertEqual(observation?.source, .visualCandidate)
        XCTAssertEqual(abs(observation?.axisAngle ?? 999), 0, accuracy: 8)
        XCTAssertGreaterThan(observation?.confidence ?? 0, 0.2)
    }

    func test_returnsNilWhenNoLineEvidenceExists() throws {
        let image = try makeSyntheticImage(width: 180, height: 120, lineStart: nil, lineEnd: nil)
        let pose = makePose(
            leftAnkle: PoseJointPoint(x: 0.35, y: 0.50, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.65, y: 0.50, confidence: 0.9),
            proxyAngle: 0
        )

        let observation = BoardVisualLineDetector.detect(cgImage: image, pose: pose)

        XCTAssertNil(observation)
    }

    private func makeSyntheticImage(
        width: Int,
        height: Int,
        lineStart: CGPoint?,
        lineEnd: CGPoint?
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw NSError(domain: "BoardVisualLineDetectorTests", code: 1)
        }

        context.setFillColor(CGColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let lineStart, let lineEnd {
            context.setStrokeColor(CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1))
            context.setLineWidth(7)
            context.setLineCap(.round)
            context.move(to: lineStart)
            context.addLine(to: lineEnd)
            context.strokePath()
        }

        guard let image = context.makeImage() else {
            throw NSError(domain: "BoardVisualLineDetectorTests", code: 2)
        }
        return image
    }

    private func makePose(
        leftAnkle: PoseJointPoint,
        rightAnkle: PoseJointPoint,
        proxyAngle: Double
    ) -> BodyPoseData {
        BodyPoseData(
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
            ankleCenterX: MetricWithConfidence(
                value: (leftAnkle.x + rightAnkle.x) / 2,
                confidence: min(leftAnkle.confidence, rightAnkle.confidence)
            ),
            ankleCenterY: MetricWithConfidence(
                value: (leftAnkle.y + rightAnkle.y) / 2,
                confidence: min(leftAnkle.confidence, rightAnkle.confidence)
            ),
            ankleProxyBoardAngle: MetricWithConfidence(value: proxyAngle, confidence: 0.9),
            leftAnklePoint: leftAnkle,
            rightAnklePoint: rightAnkle
        )
    }
}

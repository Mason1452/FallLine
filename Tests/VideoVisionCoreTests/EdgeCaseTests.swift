import XCTest
@testable import VideoVisionCore

// MARK: - 边界情况测试

final class EdgeCaseTests: XCTestCase {

    // MARK: JSON 编解码往返

    func test_detectionResult_codableRoundtrip() throws {
        let original = DetectionResult(
            time: 1.5,
            objects: [ObjectItem(label: "人", confidence: 0.95)],
            faces: [],
            textObservations: [],
            sceneClassifications: [],
            bodyPose: BodyPoseData(
                detected: true,
                visibility: .full,
                bodyLeanAngle: MetricWithConfidence(value: 15.0, confidence: 0.88),
                leftBodyLeanAngle: nil,
                rightBodyLeanAngle: nil,
                leftKneeBendAngle: MetricWithConfidence(value: 115.0, confidence: 0.9),
                rightKneeBendAngle: nil,
                leftCalfLeanAngle: nil,
                rightCalfLeanAngle: nil,
                centerOfGravity: MetricWithConfidence(value: 0.25, confidence: 0.85)
            ),
            poseScore: PoseScore(
                totalScore: 82,
                forwardLeanScore: 90, kneeBendScore: 85,
                calfLeanScore: 70, gravityScore: 88,
                symmetryScore: 75,
                level: "高级",
                suggestions: ["保持当前水平"]
            )
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(DetectionResult.self, from: data)

        XCTAssertEqual(decoded.time, original.time)
        XCTAssertEqual(decoded.bodyPose.centerOfGravity?.value, 0.25)
        XCTAssertEqual(decoded.poseScore?.totalScore, 82)
    }

    func test_analysisOutput_decodesWhenOptionalAnalysesMissing() throws {
        let json = """
        {
          "videoPath": "sample.mp4",
          "duration": 10.0,
          "totalFrames": 0,
          "frames": [],
          "summary": {
            "averageScore": 0,
            "bestFrame": {"time": 0, "timeString": "00:00", "score": 0},
            "worstFrame": {"time": 0, "timeString": "00:00", "score": 0},
            "stabilityScore": 0,
            "scoreConsistencyScore": 0,
            "scoreStdDev": 0,
            "overallLevel": "未检测到人体"
          },
          "skiMetrics": {
            "edgeQualityScore": 0,
            "edgeQualityLabel": "无检测数据",
            "pressureSupportScore": 0,
            "pressureSupportLabel": "无检测数据",
            "foreAftSupportScore": 0,
            "foreAftSupportLabel": "无检测数据"
          },
          "keyMoments": []
        }
        """

        let decoded = try JSONDecoder().decode(AnalysisOutput.self, from: Data(json.utf8))

        XCTAssertTrue(decoded.turnAnalysis.frames.isEmpty)
        XCTAssertTrue(decoded.turnAnalysis.segments.isEmpty)
        XCTAssertTrue(decoded.boardAnalysis.frames.isEmpty)
        XCTAssertNil(decoded.boardAnalysis.summary)
        XCTAssertEqual(decoded.centerOfMassAnalysis.frameCount, 0)
        XCTAssertEqual(decoded.centerOfMassAnalysis.cogStageFitScore, 0)
        XCTAssertTrue(decoded.highlightMoments.isEmpty)
    }

    func test_poseScoreDecodesWhenConfidenceFieldsMissing() throws {
        let json = """
        {
          "totalScore": 82,
          "forwardLeanScore": 90,
          "kneeBendScore": 85,
          "calfLeanScore": 70,
          "gravityScore": 88,
          "symmetryScore": 75,
          "level": "高级",
          "suggestions": []
        }
        """

        let decoded = try JSONDecoder().decode(PoseScore.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.totalScore, 82)
        XCTAssertEqual(decoded.totalConfidence, 0)
        XCTAssertEqual(decoded.forwardLeanConfidence, 0)
    }

    func test_skiDerivedMetricsDecodesWhenConfidenceFieldsMissing() throws {
        let json = """
        {
          "edgeQualityScore": 55,
          "edgeQualityLabel": "刻滑雏形",
          "pressureSupportScore": 70,
          "pressureSupportLabel": "支撑尚可",
          "foreAftSupportScore": 80,
          "foreAftSupportLabel": "前后支撑积极"
        }
        """

        let decoded = try JSONDecoder().decode(SkiDerivedMetrics.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.edgeQualityScore, 55)
        XCTAssertEqual(decoded.edgeQualityConfidence, 0)
        XCTAssertEqual(decoded.pressureSupportConfidence, 0)
    }

    func test_analysisOutput_turnAnalysisCodableRoundtrip() throws {
        let output = AnalysisOutput(
            videoPath: "sample.mp4",
            duration: 10,
            totalFrames: 0,
            frames: [],
            summary: VideoSummary(
                averageScore: 0,
                bestFrame: FrameScore(time: 0, timeString: "00:00", score: 0),
                worstFrame: FrameScore(time: 0, timeString: "00:00", score: 0),
                stabilityScore: 0,
                scoreConsistencyScore: 0,
                scoreStdDev: 0,
                overallLevel: "未检测到人体"
            ),
            skiMetrics: SkiDerivedMetrics(
                edgeQualityScore: 0,
                edgeQualityLabel: "无检测数据",
                pressureSupportScore: 0,
                pressureSupportLabel: "无检测数据",
                foreAftSupportScore: 0,
                foreAftSupportLabel: "无检测数据"
            ),
            keyMoments: [],
            centerOfMassAnalysis: CenterOfMassAnalysis(
                cogStageFitScore: 82,
                confidence: 0.75,
                label: "当前阶段重心适配",
                stage: StageLabel.stableSkiing.rawValue,
                frameCount: 1,
                mainIssue: nil,
                frames: [
                    CenterOfMassFrameAnalysis(
                        time: 1,
                        hipRatio: 0.42,
                        targetRangeLower: 0.34,
                        targetRangeUpper: 0.56,
                        phase: .shaping,
                        score: 82,
                        confidence: 0.75,
                        issue: "当前阶段重心适配"
                    )
                ]
            ),
            boardAnalysis: BoardAnalysis(
                frames: [
                    BoardFrameAnalysis(
                        time: 1,
                        observation: BoardObservation(
                            source: .ankleProxy,
                            axisAngle: 5,
                            centerX: 0.45,
                            centerY: 0.2,
                            confidence: 0.7
                        ),
                        kinematics: BoardKinematics(
                            boardAngle: 5,
                            travelAngle: 3,
                            sideslipAngle: 2,
                            carvingConfidence: 95,
                            confidence: 0.65
                        )
                    )
                ],
                summary: BoardAnalysisSummary(
                    frameCount: 1,
                    averageSideslipAngle: 2,
                    carvingConfidence: 95,
                    confidence: 0.65,
                    source: .ankleProxy
                )
            ),
            turnAnalysis: TurnAnalysis(
                frames: [
                    TurnFrameAnalysis(
                        time: 1,
                        edgeSignal: 18,
                        edgeDirection: .imageRight,
                        phase: .shaping,
                        confidence: 0.8
                    )
                ],
                segments: [
                    TurnSegment(
                        startTime: 1,
                        endTime: 3,
                        startTimeString: "00:01",
                        endTimeString: "00:03",
                        edgeDirection: .imageRight,
                        frameCount: 3,
                        phaseDistribution: [TurnPhase.shaping.rawValue: 1.0],
                        mainIssue: "阶段衔接基本正常"
                    )
                ]
            )
        )

        let data = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(AnalysisOutput.self, from: data)

        XCTAssertEqual(decoded.turnAnalysis.frames.first?.phase, .shaping)
        XCTAssertEqual(decoded.turnAnalysis.segments.first?.edgeDirection, .imageRight)
        XCTAssertEqual(decoded.boardAnalysis.summary?.averageSideslipAngle, 2)
        XCTAssertEqual(decoded.boardAnalysis.frames.first?.observation.source, .ankleProxy)
        XCTAssertEqual(decoded.centerOfMassAnalysis.cogStageFitScore, 82)
        XCTAssertEqual(decoded.centerOfMassAnalysis.frames.first?.phase, .shaping)
    }

    func test_bodyPoseData_codableRoundtrip() throws {
        let original = BodyPoseData(
            detected: true,
            visibility: .partial,
            bodyLeanAngle: MetricWithConfidence(value: 20.0, confidence: 0.7),
            leftBodyLeanAngle: MetricWithConfidence(value: 20.0, confidence: 0.7),
            rightBodyLeanAngle: nil,
            leftKneeBendAngle: MetricWithConfidence(value: 130.0, confidence: 0.65),
            rightKneeBendAngle: nil,
            leftCalfLeanAngle: MetricWithConfidence(value: 50.0, confidence: 0.6),
            rightCalfLeanAngle: nil,
            centerOfGravity: MetricWithConfidence(value: 0.30, confidence: 0.75),
            signedBodyLeanAngle: MetricWithConfidence(value: -12.0, confidence: 0.7),
            signedCalfLeanAngle: MetricWithConfidence(value: 18.0, confidence: 0.8),
            hipCenterX: MetricWithConfidence(value: 0.52, confidence: 0.75),
            ankleCenterX: MetricWithConfidence(value: 0.48, confidence: 0.75),
            bodyCenterX: MetricWithConfidence(value: 0.50, confidence: 0.75),
            hipCenterY: MetricWithConfidence(value: 0.38, confidence: 0.75),
            ankleCenterY: MetricWithConfidence(value: 0.12, confidence: 0.75),
            bodyCenterY: MetricWithConfidence(value: 0.30, confidence: 0.75),
            ankleProxyBoardAngle: MetricWithConfidence(value: -8.0, confidence: 0.7)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(BodyPoseData.self, from: data)

        XCTAssertEqual(decoded.detected, true)
        XCTAssertEqual(decoded.visibility, .partial)
        XCTAssertEqual(decoded.centerOfGravity?.value, 0.30)
        XCTAssertEqual(decoded.signedBodyLeanAngle?.value, -12.0)
        XCTAssertEqual(decoded.signedCalfLeanAngle?.value, 18.0)
        XCTAssertEqual(decoded.hipCenterX?.value, 0.52)
        XCTAssertEqual(decoded.ankleCenterY?.value, 0.12)
        XCTAssertEqual(decoded.ankleProxyBoardAngle?.value, -8.0)
    }

    // MARK: KeyMomentDetector 边界

    func test_keyMomentDetector_emptyFrames_returnsEmpty() {
        let moments = KeyMomentDetector.detect(from: [], duration: 0)
        XCTAssertTrue(moments.isEmpty)
    }

    func test_keyMomentDetector_singleFrame_returnsEmpty() {
        let singleFrame = DetectionResult(
            time: 0, objects: [], faces: [], textObservations: [], sceneClassifications: [],
            bodyPose: BodyPoseData(
                detected: false, visibility: .none,
                bodyLeanAngle: nil, leftBodyLeanAngle: nil, rightBodyLeanAngle: nil,
                leftKneeBendAngle: nil, rightKneeBendAngle: nil,
                leftCalfLeanAngle: nil, rightCalfLeanAngle: nil,
                centerOfGravity: nil
            ),
            poseScore: nil
        )
        let moments = KeyMomentDetector.detect(from: [singleFrame], duration: 0)
        XCTAssertTrue(moments.isEmpty)
    }

    // MARK: clamp 函数

    func test_clamp_withinRange() {
        XCTAssertEqual(clamp(50), 50)
    }

    func test_clamp_belowRange() {
        XCTAssertEqual(clamp(-10), 0)
    }

    func test_clamp_aboveRange() {
        XCTAssertEqual(clamp(150), 100)
    }

    func test_clamp_customRange() {
        XCTAssertEqual(clamp(5, lower: 10, upper: 50), 10)
    }
}

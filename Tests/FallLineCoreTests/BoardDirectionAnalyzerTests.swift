import XCTest
@testable import FallLineCore

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

    func test_thirtyDegreeSideslipIsNoLongerHighCarvingEvidence() {
        let analysis = BoardDirectionAnalyzer.analyze(frames: [
            makeFrame(time: 0, boardAngle: 30, centerX: 0.1, centerY: 0.5),
            makeFrame(time: 1, boardAngle: 30, centerX: 0.2, centerY: 0.5),
            makeFrame(time: 2, boardAngle: 30, centerX: 0.3, centerY: 0.5)
        ])

        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 30, accuracy: 0.1)
        XCTAssertEqual(analysis.summary?.carvingConfidence ?? -1, 33.3, accuracy: 0.2)
    }

    func test_fortyFiveDegreeSideslipRemovesCarvingConfidence() {
        let analysis = BoardDirectionAnalyzer.analyze(frames: [
            makeFrame(time: 0, boardAngle: 45, centerX: 0.1, centerY: 0.5),
            makeFrame(time: 1, boardAngle: 45, centerX: 0.2, centerY: 0.5),
            makeFrame(time: 2, boardAngle: 45, centerX: 0.3, centerY: 0.5)
        ])

        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 45, accuracy: 0.1)
        XCTAssertEqual(analysis.summary?.carvingConfidence ?? -1, 0, accuracy: 0.1)
    }

    func test_sparseHighSideslipDoesNotTriggerHighScoreCap() {
        let frames = [
            makeFrame(time: 0, boardAngle: 45, centerX: 0.1, centerY: 0.5),
            makeFrame(time: 1, boardAngle: 45, centerX: 0.2, centerY: 0.5)
        ]
        let analysis = BoardDirectionAnalyzer.analyze(frames: frames)

        XCTAssertEqual(analysis.frames.compactMap(\.kinematics).count, 2)
        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 45, accuracy: 0.1)
        XCTAssertNil(boardKinematicHighScoreCap(from: frames))
    }

    func test_denseButShortHighSideslipDoesNotTriggerHighScoreCap() {
        let frames = [
            makeFrame(time: 0.0, boardAngle: 45, centerX: 0.1, centerY: 0.5),
            makeFrame(time: 0.2, boardAngle: 45, centerX: 0.2, centerY: 0.5),
            makeFrame(time: 0.4, boardAngle: 45, centerX: 0.3, centerY: 0.5),
            makeFrame(time: 0.6, boardAngle: 45, centerX: 0.4, centerY: 0.5),
            makeFrame(time: 0.8, boardAngle: 45, centerX: 0.5, centerY: 0.5)
        ]
        let analysis = BoardDirectionAnalyzer.analyze(frames: frames)

        XCTAssertGreaterThanOrEqual(analysis.frames.compactMap(\.kinematics).count, 3)
        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 45, accuracy: 0.1)
        XCTAssertNil(boardKinematicHighScoreCap(from: frames))
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

    func test_keepsVisualObservationOutOfScoringWhileItIsDebugOnly() {
        let visual = BoardObservation(
            source: .visualCandidate,
            axisAngle: 0,
            centerX: 0.2,
            centerY: 0.5,
            confidence: 0.6
        )
        let analysis = BoardDirectionAnalyzer.analyze(frames: [
            makeFrame(time: 0, boardAngle: 90, centerX: 0.1, centerY: 0.5, visual: visual),
            makeFrame(time: 1, boardAngle: 90, centerX: 0.2, centerY: 0.5, visual: visual),
            makeFrame(time: 2, boardAngle: 90, centerX: 0.3, centerY: 0.5, visual: visual)
        ])

        XCTAssertEqual(analysis.summary?.source, .ankleProxy)
        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 90, accuracy: 0.1)
    }

    func test_fallsBackToAnkleProxyWhenVisualObservationIsWeak() {
        let weakVisual = BoardObservation(
            source: .visualCandidate,
            axisAngle: 0,
            centerX: 0.2,
            centerY: 0.5,
            confidence: 0.1
        )
        let analysis = BoardDirectionAnalyzer.analyze(frames: [
            makeFrame(time: 0, boardAngle: 90, centerX: 0.1, centerY: 0.5, visual: weakVisual),
            makeFrame(time: 1, boardAngle: 90, centerX: 0.2, centerY: 0.5, visual: weakVisual),
            makeFrame(time: 2, boardAngle: 90, centerX: 0.3, centerY: 0.5, visual: weakVisual)
        ])

        XCTAssertEqual(analysis.summary?.source, .ankleProxy)
        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 90, accuracy: 0.1)
    }

    // MARK: - 2026-09-08 P8-A：sideslip 派生 cap 退役

    /// P8-A：高置信度（obsCnf ≥ 0.7）+ 高 sideslip（60°）+ 长时长 → **不再触发任何 cap**
    ///
    /// 诊断证实 sideslip 测量带 ~40-50° 系统性偏差（2D 光流方向被相机运动主导），
    /// 主 corpus 6 份全部落在 42-53°（含已确认刻滑样本），cap 触发即误伤。
    /// 本用例守护退役语义：obsCnf 0.9 + sideslip 60° 也必须放行（P8-A 前此场景 cap=58）。
    func test_highConfidenceTrueSideslip_noCapAfterP8A() {
        var frames: [DetectionResult] = []
        for i in 0..<30 {
            frames.append(makeFrame(
                time: Double(i) * 0.2,
                boardAngle: 60,
                boardConfidence: 0.9,
                centerX: 0.1 + Double(i) * 0.02,
                centerY: 0.5
            ))
        }

        let analysis = BoardDirectionAnalyzer.analyze(frames: frames)
        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 60, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(analysis.summary?.confidence ?? 0, 0.7)

        XCTAssertNil(
            boardKinematicHighScoreCap(from: frames),
            "P8-A：sideslip 派生 cap 已退役，obsCnf 0.9 + sideslip 60° 不得再触发 58/70 封顶"
        )
    }

    /// P8-A 后低置信度（obsCnf < 0.7）分支保留：短片段（reliablePoseDuration < 阈值）仍走
    /// lowBoardEvidenceScoreCap=62（纯时长证据，不依赖 sideslip/travelAngle）。
    /// 此处 poseScore=nil → reliablePoseDuration=0 → 命中 62 分支。
    func test_midConfidenceShortClip_stillGetsLowEvidenceCapAfterP8A() {
        var frames: [DetectionResult] = []
        for i in 0..<30 {
            frames.append(makeFrame(
                time: Double(i) * 0.2,
                boardAngle: 60,
                boardConfidence: 0.65,
                centerX: 0.1 + Double(i) * 0.02,
                centerY: 0.5
            ))
        }

        let analysis = BoardDirectionAnalyzer.analyze(frames: frames)
        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 60, accuracy: 0.1)
        XCTAssertLessThan(analysis.summary?.confidence ?? 1, AnalysisReliability.minimumBoardKinematicConfidenceForHighScore)

        XCTAssertEqual(
            boardKinematicHighScoreCap(from: frames) ?? -1,
            AnalysisReliability.lowBoardEvidenceScoreCap,
            accuracy: 0.001,
            "P8-A 保留低置信度短片段的 62 分保守封顶（时长证据，与 sideslip 无关）"
        )
    }

    // MARK: - 2026-09-01 P3 sideslipAngle 5 帧中位数滑窗

    /// 单帧尖峰（一帧 boardAngle=90°）被前后邻居包围时，应被中位数滑窗抹平回邻居水平。
    ///
    /// 稳定性诊断显示 corpus median sideslip 帧间跳动 22°、max 28°，绝大部分来自光流 travelAngle
    /// 突变，而非真实动作变化。此用例锁定该场景下的滤波行为。
    func test_singleFrameSpikeIsAttenuatedByMedianSmoothing() {
        let frames: [DetectionResult] = [
            makeFrame(time: 0.0, boardAngle: 0, centerX: 0.1, centerY: 0.5),
            makeFrame(time: 0.2, boardAngle: 0, centerX: 0.2, centerY: 0.5),
            makeFrame(time: 0.4, boardAngle: 90, centerX: 0.3, centerY: 0.5),
            makeFrame(time: 0.6, boardAngle: 0, centerX: 0.4, centerY: 0.5),
            makeFrame(time: 0.8, boardAngle: 0, centerX: 0.5, centerY: 0.5)
        ]

        let analysis = BoardDirectionAnalyzer.analyze(frames: frames)
        let sideslipValues = analysis.frames.compactMap(\.kinematics?.sideslipAngle)
        XCTAssertEqual(sideslipValues.count, 5)

        XCTAssertEqual(sideslipValues[2], 0, accuracy: 0.5,
                       "中间帧的 90° 尖峰应被滑窗抹回 0°（前后 4 帧全 0°）")
        XCTAssertLessThan(analysis.summary?.averageSideslipAngle ?? 90, 20,
                          "整段平均 sideslip 不应被单帧尖峰主导")
    }

    /// 恒定 sideslip 序列在滑窗后应完全保持原值（等值序列的中位数=自身）。
    ///
    /// 保护"真横滑必须被 cap"的能力：滑窗不能抹掉持续存在的高 sideslip 证据。
    func test_constantSideslipUnaffectedByMedianSmoothing() {
        var frames: [DetectionResult] = []
        for i in 0..<10 {
            frames.append(makeFrame(
                time: Double(i) * 0.2,
                boardAngle: 45,
                centerX: 0.1 + Double(i) * 0.02,
                centerY: 0.5
            ))
        }
        let analysis = BoardDirectionAnalyzer.analyze(frames: frames)

        let sideslipValues = analysis.frames.compactMap(\.kinematics?.sideslipAngle)
        XCTAssertEqual(sideslipValues.count, 10)
        for value in sideslipValues {
            XCTAssertEqual(value, 45, accuracy: 0.5)
        }
        XCTAssertEqual(analysis.summary?.averageSideslipAngle ?? -1, 45, accuracy: 0.1)
    }

    /// 少于 3 帧时滑窗不触发，直接返回原值（避免边界样本被单帧主导）。
    func test_shortSequenceKeepsRawSideslip() {
        let frames = [
            makeFrame(time: 0.0, boardAngle: 30, centerX: 0.1, centerY: 0.5),
            makeFrame(time: 0.2, boardAngle: 30, centerX: 0.2, centerY: 0.5)
        ]
        let analysis = BoardDirectionAnalyzer.analyze(frames: frames)
        XCTAssertEqual(analysis.frames.compactMap(\.kinematics).count, 2)
        for kinematics in analysis.frames.compactMap(\.kinematics) {
            XCTAssertEqual(kinematics.sideslipAngle, 30, accuracy: 0.5)
        }
    }

    private func makeFrame(
        time: Double,
        boardAngle: Double?,
        boardConfidence: Double = 1,
        centerX: Double,
        centerY: Double,
        visual: BoardObservation? = nil
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
                ankleProxyBoardAngle: boardAngle.map { MetricWithConfidence(value: $0, confidence: boardConfidence) }
            ),
            poseScore: nil,
            visualBoardObservation: visual
        )
    }
}

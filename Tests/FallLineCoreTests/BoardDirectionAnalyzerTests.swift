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
        XCTAssertFalse(hasHighSideslipEvidenceForHighScore(from: frames))
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
        XCTAssertFalse(hasHighSideslipEvidenceForHighScore(from: frames))
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

    // MARK: - 2026-08-30 travelAngle 决策：阈值 0.55 → 0.7 边界回归

    /// 高置信度（obsCnf ≥ 0.7）+ 真横滑（sideslip 60°）+ 长时长（30 帧×0.2s=6s） → 仍应触发 58 分强封顶
    ///
    /// 保护"真横滑必须被 cap"这条主线，防止阈值漂移把真横滑也放过去。
    func test_highConfidenceTrueSideslipStillTriggersDominantCap() {
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

        XCTAssertEqual(
            boardKinematicHighScoreCap(from: frames) ?? -1,
            AnalysisReliability.dominantSideslipScoreCap,
            accuracy: 0.001,
            "obsCnf 0.9 且 sideslip 60° 是真横滑证据，必须触发 dominantSideslipScoreCap=58"
        )
    }

    /// 中等置信度（obsCnf 0.65，位于旧阈值 0.55 与新阈值 0.7 之间）+ 高 sideslip → 新阈值下不再走 sideslip 分支 cap
    ///
    /// 复现 corpus 里 3.json / 5.json 的场景（obsCnf 0.58~0.59 被误 cap 到 sideslip 分支）。
    /// 阈值抬到 0.7 后：obsCnf 0.65 < 0.7 走"低置信度"分支，只在短片段（<10s reliable pose）里走
    /// lowBoardEvidenceScoreCap=62；长片段直接放行。此处 poseScore=nil → reliablePoseDuration=0，
    /// 走 62 分支，**关键是不再触发 dominantSideslipScoreCap=58**（那才是 corpus 里的误 cap 类型）。
    func test_midConfidenceHighSideslipNoLongerHitsSideslipCap() {
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

        let cap = boardKinematicHighScoreCap(from: frames)
        XCTAssertNotEqual(
            cap ?? -1,
            AnalysisReliability.dominantSideslipScoreCap,
            accuracy: 0.001,
            "obsCnf 0.65 已在新阈值 0.7 之下，不允许走 sideslip 分支的 58 分强封顶"
        )
        XCTAssertNotEqual(
            cap ?? -1,
            AnalysisReliability.highSideslipScoreCap,
            accuracy: 0.001,
            "同理，也不允许走 sideslip 分支的 70 分封顶"
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

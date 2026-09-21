import XCTest
@testable import FallLineCore

final class BoardTemporalAxisAggregatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeFrame(time: Double, observation: BoardEdgeObservation?) -> DetectionResult {
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
            poseScore: nil,
            boardEdgeObservation: observation
        )
    }

    private func board(_ angle: Double) -> BoardEdgeObservation {
        BoardEdgeObservation(status: .board, axisAngle: angle)
    }

    private func fallback(
        source: BoardFallbackSource,
        angle: Double,
        confidence: Double = 0.6
    ) -> BoardEdgeObservation {
        let axis = FallbackAxis(
            source: source,
            axisAngle: angle,
            centerX: 0.5,
            centerY: 0.7,
            lengthRatio: 0.1,
            confidence: confidence,
            originalStatus: .farShot
        )
        return BoardEdgeObservation(status: .fallback, fallbackAxis: axis)
    }

    private let rejected = BoardEdgeObservation(status: .farShot)

    private func frames(from angles: [Double?]) -> [DetectionResult] {
        angles.enumerated().map { index, angle in
            let observation: BoardEdgeObservation? = angle.map { board($0) }
            return makeFrame(time: Double(index) * 0.2, observation: observation)
        }
    }

    // MARK: - 1. 全 board 稳定窗 pass + 聚合角/conf

    func test_allBoardStableWindowPasses() {
        let frames = frames(from: [30, 31, 29, 30, 32])
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: frames)

        XCTAssertEqual(metrics.evaluatedWindows, 5)
        XCTAssertEqual(metrics.stableWindows, 3)
        XCTAssertEqual(metrics.stableWindowRate, 3.0 / 5.0, accuracy: 1e-9)
        XCTAssertEqual(metrics.longestStableRunFrames, 3)
        XCTAssertEqual(metrics.longestStableRunSeconds, 0.6, accuracy: 1e-9)
        XCTAssertEqual(metrics.stableRunCount, 1)
        if let point = metrics.points.first {
            XCTAssertEqual(point.medianAngle ?? 0, 30.0, accuracy: 1e-9)
            XCTAssertEqual(point.medianConfidence ?? 0, 1.0, accuracy: 1e-9)
            XCTAssertNil(point.source)
        } else {
            XCTFail("expected pass points")
        }
    }

    // MARK: - 2. 候选不足拒绝

    func test_insufficientCandidatesRejected() {
        let frames = frames(from: [30, nil, nil, nil, nil])
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: frames)

        XCTAssertEqual(metrics.evaluatedWindows, 5)
        XCTAssertEqual(metrics.stableWindows, 0)
        XCTAssertEqual(
            metrics.rejectHist[BoardTemporalRejectReason.insufficientCandidates.rawValue], 5
        )
    }

    // MARK: - 3. IQR 边界（恰 5° pass / 超 5° reject）

    func test_iqrExactlyAtGatePasses() {
        // sorted [29,30,32,35,36]：q1=index1=30，q3=index3=35，IQR=5（末窗）
        let frames = frames(from: [29, 30, 32, 35, 36])
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: frames)
        XCTAssertEqual(metrics.points.last?.iqr ?? -1, 5.0, accuracy: 1e-9)
        XCTAssertEqual(metrics.stableWindows, 3)
    }

    func test_iqrAboveGateRejected() {
        // 末窗 sorted [29,30,32,36,37]：q1=30，q3=36，IQR=6 → reject；
        // 但早期窄窗 f2,f3 仍 pass（窗内不含 36/37）。
        let frames = frames(from: [29, 30, 32, 36, 37])
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: frames)
        XCTAssertEqual(metrics.stableWindows, 2)
        XCTAssertEqual(
            metrics.rejectHist[BoardTemporalRejectReason.unstableIQR.rawValue], 1
        )
    }

    // MARK: - 4. 混合 board/fallback 窗源多数派 + tie 取 ankle

    func test_dominantSourceAnkleWins() {
        let window: [BoardTemporalAxisAggregator.Candidate] = [
            .init(angle: 30, confidence: 1, source: nil),
            .init(angle: 30, confidence: 0.6, source: .anklePair),
            .init(angle: 31, confidence: 0.6, source: .anklePair),
            .init(angle: 29, confidence: 0.5, source: .kneePair)
        ]
        XCTAssertEqual(BoardTemporalAxisAggregator.dominantSource(window), .anklePair)
    }

    func test_dominantSourceTiePrefersAnkle() {
        let window: [BoardTemporalAxisAggregator.Candidate] = [
            .init(angle: 30, confidence: 0.6, source: .anklePair),
            .init(angle: 30, confidence: 0.5, source: .kneePair)
        ]
        XCTAssertEqual(BoardTemporalAxisAggregator.dominantSource(window), .anklePair)
    }

    func test_dominantSourceKneeOnly() {
        let window: [BoardTemporalAxisAggregator.Candidate] = [
            .init(angle: 30, confidence: 0.5, source: .kneePair)
        ]
        XCTAssertEqual(BoardTemporalAxisAggregator.dominantSource(window), .kneePair)
    }

    func test_dominantSourceBoardOnlyWindowIsNil() {
        let window: [BoardTemporalAxisAggregator.Candidate] = [
            .init(angle: 30, confidence: 1, source: nil)
        ]
        XCTAssertNil(BoardTemporalAxisAggregator.dominantSource(window))
    }

    // MARK: - fallback candidate 提取

    func test_candidateFromFallbackCarriesSyntheticAxis() {
        let candidate = BoardTemporalAxisAggregator.candidate(
            from: fallback(source: .anklePair, angle: 40, confidence: 0.55)
        )
        XCTAssertEqual(candidate?.angle ?? 0, 40, accuracy: 1e-9)
        XCTAssertEqual(candidate?.confidence ?? 0, 0.55, accuracy: 1e-9)
        XCTAssertEqual(candidate?.source, .anklePair)
    }

    func test_candidateFromRejectedStatusIsNil() {
        XCTAssertNil(BoardTemporalAxisAggregator.candidate(from: rejected))
        XCTAssertNil(BoardTemporalAxisAggregator.candidate(from: nil))
    }

    // MARK: - 5/6. fold-crossing 检测 + 有向重建 / 保守拒绝

    func test_foldCrossingWithoutDirectionConservativelyRejected() {
        // f0 单帧不折叠→insuff；f1..f4 折叠且无方向 → foldCrossing ×4
        let frames = frames(from: [10, 85, 12, 88, 11])
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: frames)

        XCTAssertEqual(metrics.stableWindows, 0)
        XCTAssertEqual(
            metrics.rejectHist[BoardTemporalRejectReason.foldCrossing.rawValue], 4
        )
        XCTAssertEqual(
            metrics.rejectHist[BoardTemporalRejectReason.insufficientCandidates.rawValue], 1
        )
        XCTAssertEqual(metrics.foldCrossingRate, 4.0 / 5.0, accuracy: 1e-9)
    }

    func test_foldCrossingWithDirectionRebuildsThenRejectedAsUnstable() {
        let frames = frames(from: [10, 85, 12, 88, 11])
        // travel ~170°：近 10° 簇重建到 ~170，近 88° 簇重建到 ~92，两簇仍分裂 → unstableIQR。
        let directions: [Double?] = [170, 170, 170, 170, 170]
        let metrics = BoardTemporalAxisAggregator.aggregate(
            frames: frames, travelDirections: directions
        )

        XCTAssertEqual(metrics.stableWindows, 0)
        XCTAssertNil(metrics.rejectHist[BoardTemporalRejectReason.foldCrossing.rawValue])
        XCTAssertEqual(
            metrics.rejectHist[BoardTemporalRejectReason.unstableIQR.rawValue], 3
        )
        XCTAssertEqual(
            metrics.rejectHist[BoardTemporalRejectReason.insufficientCandidates.rawValue], 2
        )
        XCTAssertEqual(metrics.foldCrossingRate, 0)
    }

    func test_directedAnglePicksCloserRepresentation() {
        XCTAssertEqual(
            BoardTemporalAxisAggregator.directedAngle(unsigned: 85, travel: 170),
            95, accuracy: 1e-9
        )
        XCTAssertEqual(
            BoardTemporalAxisAggregator.directedAngle(unsigned: 10, travel: 170),
            170, accuracy: 1e-9
        )
        XCTAssertEqual(
            BoardTemporalAxisAggregator.directedAngle(unsigned: 10, travel: 10),
            10, accuracy: 1e-9
        )
    }

    // MARK: - 7. 跨簇阻断 run + 帧秒换算（多段精确逻辑由 stableRuns helper 覆盖）

    func test_crossClusterBlocksRun() {
        // 3×board10（f2 pass=1）, rejected（f3 pass）, 2×board70（f4 pass）；
        // f5 窗内 3 高角 vs 2 低角，两簇分裂 IQR 大被拒 → 单 run=2（f3,f4）。
        let frames = frames(from: [10, 10, 10, nil, 70, 70])
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: frames)

        XCTAssertEqual(metrics.longestStableRunFrames, 2)
        XCTAssertEqual(metrics.longestStableRunSeconds, 0.4, accuracy: 1e-9)
        XCTAssertEqual(metrics.stableRunCount, 1)
        XCTAssertEqual(metrics.stableWindows, 2)
        XCTAssertEqual(
            metrics.rejectHist[BoardTemporalRejectReason.foldCrossing.rawValue], 2
        )
    }

    func test_stableRunsHelper() {
        XCTAssertEqual(
            BoardTemporalAxisAggregator.stableRuns(
                passFlags: [true, true, false, true, false, true, true, true]
            ),
            [3, 2, 1]
        )
        XCTAssertEqual(BoardTemporalAxisAggregator.stableRuns(passFlags: []), [])
    }

    // MARK: - 8. 片首 <W 帧边界

    func test_leadingPartialWindowUsesAvailableFrames() {
        let frames = frames(from: [30, 31])
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: frames)
        XCTAssertEqual(metrics.evaluatedWindows, 2)
        XCTAssertEqual(metrics.stableWindows, 0)
        XCTAssertEqual(
            metrics.rejectHist[BoardTemporalRejectReason.insufficientCandidates.rawValue], 2
        )
    }

    // MARK: - 9. 全拒绝帧流（无候选不崩，分母处理）

    func test_noCandidatesStream() {
        let frames = (0..<6).map { makeFrame(time: Double($0) * 0.2, observation: rejected) }
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: frames)
        XCTAssertEqual(metrics.evaluatedWindows, 0)
        XCTAssertEqual(metrics.stableWindows, 0)
        XCTAssertEqual(metrics.stableWindowRate, 0)
        XCTAssertEqual(metrics.foldCrossingRate, 0)
        XCTAssertTrue(metrics.rejectHist.isEmpty)
        XCTAssertTrue(metrics.points.isEmpty)
    }

    // MARK: - 10. 偶数元素中位数定义

    func test_evenCountMedianAveragesMiddlePair() {
        XCTAssertEqual(
            BoardTemporalAxisAggregator.median([10, 20, 30, 40]), 25, accuracy: 1e-9
        )
        XCTAssertEqual(BoardTemporalAxisAggregator.median([]), 0)
    }

    func test_iqrDefinitionMatchesSpike() {
        XCTAssertEqual(
            BoardTemporalAxisAggregator.iqr([29, 30, 32, 35, 36]), 5, accuracy: 1e-9
        )
        XCTAssertEqual(BoardTemporalAxisAggregator.iqr([30]), 0)
    }

    // MARK: - 11. 空片 / 单帧

    func test_emptyClip() {
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: [])
        XCTAssertEqual(metrics.evaluatedWindows, 0)
        XCTAssertEqual(metrics.longestStableRunFrames, 0)
        XCTAssertEqual(metrics.stableFrameCoverage, 0)
    }

    func test_singleFrame() {
        let frames = frames(from: [30])
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: frames)
        XCTAssertEqual(metrics.evaluatedWindows, 1)
        XCTAssertEqual(metrics.stableWindows, 0)
    }

    // MARK: - 12. 确定性 fuzz（同输入 2000 次聚合输出逐字段一致）

    func test_determinismFuzz() {
        let frames = frames(from: [30, 31, 29, 30, 32, 31])
        let reference = BoardTemporalAxisAggregator.aggregate(frames: frames)
        for _ in 0..<2000 {
            let rerun = BoardTemporalAxisAggregator.aggregate(frames: frames)
            XCTAssertEqual(rerun, reference)
        }
        // f0,f1 候选不足；f2..f5 pass
        XCTAssertEqual(reference.stableWindows, 4)
    }

    // MARK: - 13. JSON round-trip

    func test_jsonRoundTrip() throws {
        let frames = frames(from: [30, 31, 29, 30, 32])
        let metrics = BoardTemporalAxisAggregator.aggregate(frames: frames)
        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(BoardTrajectoryMetrics.self, from: data)
        XCTAssertEqual(decoded, metrics)
    }

    // MARK: - includeAllPoints

    func test_includeAllPointsEmitsRejectedWindows() {
        let frames = frames(from: [30, nil, nil, nil, nil])
        let metrics = BoardTemporalAxisAggregator.aggregate(
            frames: frames, includeAllPoints: true
        )
        XCTAssertEqual(metrics.points.count, 5)
        XCTAssertEqual(metrics.points.first?.windowPass, false)
        XCTAssertEqual(metrics.points.first?.rejectReason, .insufficientCandidates)
    }
}

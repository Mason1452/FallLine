import CoreGraphics
import XCTest
@testable import FallLineCore

final class BoardEdgeDetectorTests: XCTestCase {

    // MARK: - 踝点中心

    func test_ankleCenter_averagesBothAnkles() {
        let pose = makePose(
            leftAnkle: PoseJointPoint(x: 0.30, y: 0.60, confidence: 0.8),
            rightAnkle: PoseJointPoint(x: 0.50, y: 0.62, confidence: 0.9)
        )

        let center = BoardEdgeDetector.ankleCenter(from: pose, config: .standard)

        XCTAssertEqual(center?.x ?? 0, 0.40, accuracy: 1e-6)
        XCTAssertEqual(center?.y ?? 0, 0.61, accuracy: 1e-6)
        XCTAssertEqual(center?.confidence ?? 0, 0.85, accuracy: 1e-6)
    }

    func test_ankleCenter_acceptsSingleAnkle() {
        let pose = makePose(
            leftAnkle: PoseJointPoint(x: 0.40, y: 0.60, confidence: 0.6),
            rightAnkle: nil
        )

        let center = BoardEdgeDetector.ankleCenter(from: pose, config: .standard)

        XCTAssertEqual(center?.x ?? 0, 0.40, accuracy: 1e-6)
    }

    func test_ankleCenter_nilWhenConfidenceBelowGate() {
        let pose = makePose(
            leftAnkle: PoseJointPoint(x: 0.30, y: 0.60, confidence: 0.20),
            rightAnkle: PoseJointPoint(x: 0.50, y: 0.60, confidence: 0.25)
        )

        let center = BoardEdgeDetector.ankleCenter(from: pose, config: .standard)

        XCTAssertNil(center)
    }

    func test_ankleCenter_nilWhenNoAnkles() {
        let pose = makePose(leftAnkle: nil, rightAnkle: nil)

        let center = BoardEdgeDetector.ankleCenter(from: pose, config: .standard)

        XCTAssertNil(center)
    }

    // MARK: - IoU

    func test_iou_identicalRectIsOne() {
        let rect = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)
        XCTAssertEqual(BoardEdgeDetector.iou(rect, rect), 1.0, accuracy: 1e-6)
    }

    func test_iou_disjointRectIsZero() {
        let a = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
        let b = CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2)
        XCTAssertEqual(BoardEdgeDetector.iou(a, b), 0.0, accuracy: 1e-6)
    }

    func test_iou_partialOverlap() {
        let a = CGRect(x: 0, y: 0, width: 0.4, height: 0.4)
        let b = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        // 交集 0.2×0.2=0.04；并集 0.16+0.16-0.04=0.28
        XCTAssertEqual(BoardEdgeDetector.iou(a, b), 0.04 / 0.28, accuracy: 1e-6)
    }

    // MARK: - 实例归属

    func test_selectSubjectInstance_picksHighestOverlap() {
        let poseBox = CGRect(x: 0.3, y: 0.2, width: 0.25, height: 0.5)
        let far = makeInstance(index: 0, alphaCount: 5000,
                               box: CGRect(x: 0.02, y: 0.02, width: 0.1, height: 0.2))
        let owner = makeInstance(index: 1, alphaCount: 3000,
                                 box: CGRect(x: 0.31, y: 0.21, width: 0.23, height: 0.48))

        let selected = BoardEdgeDetector.selectSubjectInstance(
            [far, owner], poseBox: poseBox, config: .standard
        )

        XCTAssertEqual(selected?.index, 1)
    }

    func test_selectSubjectInstance_rejectsWhenOverlapBelowGate() {
        let poseBox = CGRect(x: 0.3, y: 0.2, width: 0.2, height: 0.4)
        let other = makeInstance(index: 0, alphaCount: 9000,
                                 box: CGRect(x: 0.75, y: 0.75, width: 0.2, height: 0.2))

        let selected = BoardEdgeDetector.selectSubjectInstance(
            [other], poseBox: poseBox, config: .standard
        )

        XCTAssertNil(selected)
    }

    func test_selectSubjectInstance_withoutPoseBoxFallsBackToLargest() {
        let small = makeInstance(index: 0, alphaCount: 100, box: .zero)
        let large = makeInstance(index: 1, alphaCount: 9000, box: .zero)

        let selected = BoardEdgeDetector.selectSubjectInstance(
            [small, large], poseBox: nil, config: .standard
        )

        XCTAssertEqual(selected?.index, 1)
    }

    // MARK: - 站姿判定

    func test_postureStatus_standingUpright() {
        let pose = makePose(
            leftShoulder: PoseJointPoint(x: 0.48, y: 0.80, confidence: 0.9),
            rightShoulder: PoseJointPoint(x: 0.52, y: 0.80, confidence: 0.9),
            leftHip: PoseJointPoint(x: 0.48, y: 0.55, confidence: 0.9),
            rightHip: PoseJointPoint(x: 0.52, y: 0.55, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.48, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.52, y: 0.30, confidence: 0.9)
        )

        XCTAssertEqual(BoardEdgeDetector.postureStatus(pose: pose, config: .standard), true)
    }

    func test_postureStatus_fallenWhenTrunkHorizontal() {
        let pose = makePose(
            leftShoulder: PoseJointPoint(x: 0.15, y: 0.50, confidence: 0.9),
            rightShoulder: PoseJointPoint(x: 0.25, y: 0.50, confidence: 0.9),
            leftHip: PoseJointPoint(x: 0.55, y: 0.50, confidence: 0.9),
            rightHip: PoseJointPoint(x: 0.65, y: 0.50, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.80, y: 0.50, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.90, y: 0.50, confidence: 0.9)
        )

        XCTAssertEqual(BoardEdgeDetector.postureStatus(pose: pose, config: .standard), false)
    }

    func test_postureStatus_sittingWhenHipNotAboveAnkle() {
        let pose = makePose(
            leftShoulder: PoseJointPoint(x: 0.48, y: 0.60, confidence: 0.9),
            rightShoulder: PoseJointPoint(x: 0.52, y: 0.60, confidence: 0.9),
            leftHip: PoseJointPoint(x: 0.48, y: 0.45, confidence: 0.9),
            rightHip: PoseJointPoint(x: 0.52, y: 0.45, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.48, y: 0.50, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.52, y: 0.50, confidence: 0.9)
        )

        XCTAssertEqual(BoardEdgeDetector.postureStatus(pose: pose, config: .standard), false)
    }

    func test_postureStatus_unknownWhenShouldersMissing() {
        let pose = makePose(
            leftShoulder: nil, rightShoulder: nil,
            leftHip: PoseJointPoint(x: 0.48, y: 0.55, confidence: 0.9),
            rightHip: PoseJointPoint(x: 0.52, y: 0.55, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.48, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.52, y: 0.30, confidence: 0.9)
        )

        XCTAssertNil(BoardEdgeDetector.postureStatus(pose: pose, config: .standard))
    }

    // MARK: - 踝下 ROI PCA

    func test_axisGeometry_horizontalStripIsBoardAxis() {
        let width = 200, height = 200
        var alpha = blankAlpha(width: width, height: height)
        // 水平细长条：y=110，x 40...159（ROI 会把两端裁到 52..<148 = 96px）
        for x in 40..<160 {
            setAlpha(&alpha, width: width, x: x, y: 110)
        }

        let geometry = BoardEdgeDetector.axisGeometry(
            alpha: alpha, width: width, height: height,
            ankleX: 0.5, ankleY: 0.60, config: .standard
        )

        XCTAssertEqual(geometry.pixelCount, 96)
        XCTAssertEqual(geometry.angle ?? 999, 0, accuracy: 5)
        XCTAssertGreaterThan(geometry.elongation, 5)
        // 96px 水平条：2·sqrt((n²−1)/12)/W ≈ 0.277
        XCTAssertEqual(geometry.lengthRatio, 0.277, accuracy: 0.02)
    }

    func test_axisGeometry_verticalStripHasHighAngle() {
        let width = 200, height = 200
        var alpha = blankAlpha(width: width, height: height)
        for y in 92..<122 {
            setAlpha(&alpha, width: width, x: 100, y: y)
        }

        let geometry = BoardEdgeDetector.axisGeometry(
            alpha: alpha, width: width, height: height,
            ankleX: 0.5, ankleY: 0.60, config: .standard
        )

        XCTAssertEqual(geometry.angle ?? -1, 90, accuracy: 5)
    }

    func test_axisGeometry_squareBlobHasLowElongation() {
        let width = 200, height = 200
        var alpha = blankAlpha(width: width, height: height)
        for y in 100..<112 {
            for x in 94..<106 {
                setAlpha(&alpha, width: width, x: x, y: y)
            }
        }

        let geometry = BoardEdgeDetector.axisGeometry(
            alpha: alpha, width: width, height: height,
            ankleX: 0.5, ankleY: 0.60, config: .standard
        )

        XCTAssertLessThan(geometry.elongation, 2.0)
    }

    func test_axisGeometry_tooFewPixelsYieldsNoAngle() {
        let width = 200, height = 200
        var alpha = blankAlpha(width: width, height: height)
        for x in 90..<105 { // 15px < minAxisPixels(30)
            setAlpha(&alpha, width: width, x: x, y: 110)
        }

        let geometry = BoardEdgeDetector.axisGeometry(
            alpha: alpha, width: width, height: height,
            ankleX: 0.5, ankleY: 0.60, config: .standard
        )

        XCTAssertNil(geometry.angle)
        XCTAssertEqual(geometry.pixelCount, 15)
    }

    func test_axisGeometry_shortStripFailsMinimumLength() {
        let width = 200, height = 200
        var alpha = blankAlpha(width: width, height: height)
        // 10 宽 × 3 高 = 30px（达到 minAxisPixels），但 lengthRatio ≈ 0.029 < 0.07
        for y in 109..<112 {
            for x in 90..<100 {
                setAlpha(&alpha, width: width, x: x, y: y)
            }
        }

        let geometry = BoardEdgeDetector.axisGeometry(
            alpha: alpha, width: width, height: height,
            ankleX: 0.5, ankleY: 0.60, config: .standard
        )

        XCTAssertEqual(geometry.angle ?? 999, 0, accuracy: 5)
        XCTAssertLessThan(geometry.lengthRatio, 0.07)
    }

    func test_axisGeometry_pixelsOutsideROIIgnored() {
        let width = 200, height = 200
        var alpha = blankAlpha(width: width, height: height)
        // ROI x ∈ [0.26,0.74] → 像素 52..<148；在 ROI 外放噪点
        for x in 0..<20 {
            setAlpha(&alpha, width: width, x: x, y: 110)
        }
        for x in 60..<140 {
            setAlpha(&alpha, width: width, x: x, y: 110)
        }

        let geometry = BoardEdgeDetector.axisGeometry(
            alpha: alpha, width: width, height: height,
            ankleX: 0.5, ankleY: 0.60, config: .standard
        )

        XCTAssertEqual(geometry.pixelCount, 80)
        XCTAssertEqual(geometry.angle ?? 999, 0, accuracy: 5)
    }

    // MARK: - 观测模型

    func test_observation_clampsNormalizedFields() {
        let observation = BoardEdgeObservation(
            status: .board,
            axisAngle: 10,
            centerX: -0.5,
            centerY: 1.8,
            lengthRatio: 2.0,
            elongation: -3,
            subjectFraction: 4,
            ankleConfidence: -1
        )

        XCTAssertEqual(observation.centerX ?? 999, 0, accuracy: 1e-6)
        XCTAssertEqual(observation.centerY ?? 999, 1, accuracy: 1e-6)
        XCTAssertEqual(observation.lengthRatio ?? 999, 1, accuracy: 1e-6)
        XCTAssertEqual(observation.elongation ?? 999, 0, accuracy: 1e-6)
        XCTAssertEqual(observation.subjectFraction ?? 999, 1, accuracy: 1e-6)
        XCTAssertEqual(observation.ankleConfidence ?? 999, 0, accuracy: 1e-6)
    }

    // MARK: - Fallback 姿态几何降级（ADR-001）

    func test_fallback_anklePairHorizontal() {
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.40, y: 0.55, confidence: 0.9),
            rightKnee: PoseJointPoint(x: 0.60, y: 0.55, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.40, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.60, y: 0.30, confidence: 0.9)
        )

        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .farShot, config: .standard
        )

        XCTAssertEqual(fallback?.source, .anklePair)
        XCTAssertEqual(fallback?.axisAngle ?? 999, 0, accuracy: 1e-6)
        XCTAssertEqual(fallback?.centerX ?? 0, 0.5, accuracy: 1e-6)
        XCTAssertEqual(fallback?.centerY ?? 0, 0.3, accuracy: 1e-6)
        XCTAssertEqual(fallback?.originalStatus, .farShot)
        // geometryConfidence = min(0.2×12, 1) = 1；confidence = 0.9
        XCTAssertEqual(fallback?.confidence ?? 0, 0.9, accuracy: 1e-6)
    }

    func test_fallback_kneePairWeakerThanAnklePair() {
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.40, y: 0.55, confidence: 0.9),
            rightKnee: PoseJointPoint(x: 0.60, y: 0.55, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.42, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.58, y: 0.30, confidence: 0.9)
        )

        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .noMask, config: .standard
        )

        // 踝间距 0.16 → geom 1 → cnf 0.9；膝间距 0.2 → geom 1 → cnf 0.9×0.6=0.54
        XCTAssertEqual(fallback?.source, .anklePair)
        XCTAssertEqual(fallback?.confidence ?? 0, 0.9, accuracy: 1e-6)
    }

    func test_fallback_prefersKneeWhenAnkleTooClose() {
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.40, y: 0.55, confidence: 0.9),
            rightKnee: PoseJointPoint(x: 0.60, y: 0.55, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.485, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.515, y: 0.30, confidence: 0.9)
        )

        // 显式还原 v2 语义（confMax + floor 0.30），验证膝对补位逻辑。
        let config = BoardEdgeConfig(
            fallbackConfidenceFloor: 0.30,
            fallbackPickStrategy: .confMax
        )
        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .farShot, config: config
        )

        // 踝间距 0.03 → geom 0.36 → cnf 0.324（合格但低）；膝对 0.54 更高
        XCTAssertEqual(fallback?.source, .kneePair)
        XCTAssertEqual(fallback?.confidence ?? 0, 0.54, accuracy: 1e-6)
    }

    func test_fallback_kneePairOnly() {
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.40, y: 0.55, confidence: 0.9),
            rightKnee: PoseJointPoint(x: 0.60, y: 0.55, confidence: 0.9),
            leftAnkle: nil,
            rightAnkle: nil
        )

        // v2 语义：confMax 允许膝对独立成为候选。
        let config = BoardEdgeConfig(
            fallbackConfidenceFloor: 0.30,
            fallbackPickStrategy: .confMax
        )
        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .ankleLowCnf, config: config
        )

        XCTAssertEqual(fallback?.source, .kneePair)
        XCTAssertEqual(fallback?.confidence ?? 0, 0.54, accuracy: 1e-6)
    }

    func test_fallback_nilWhenPairConfidenceBelowFloor() {
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.40, y: 0.55, confidence: 0.25),
            rightKnee: PoseJointPoint(x: 0.60, y: 0.55, confidence: 0.25),
            leftAnkle: PoseJointPoint(x: 0.40, y: 0.30, confidence: 0.25),
            rightAnkle: PoseJointPoint(x: 0.60, y: 0.30, confidence: 0.25)
        )

        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .farShot, config: .standard
        )

        XCTAssertNil(fallback)
    }

    func test_fallback_nilWhenBothPairsTooCloseForConfidenceFloor() {
        // 点置信 0.9；间距 0.02 → geom 0.24；踝对 cnf 0.216、膝对 0.13 均 < 0.30
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.49, y: 0.55, confidence: 0.9),
            rightKnee: PoseJointPoint(x: 0.51, y: 0.55, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.49, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.51, y: 0.30, confidence: 0.9)
        )

        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .farShot, config: .standard
        )

        XCTAssertNil(fallback)
    }

    func test_fallback_angleFoldsIntoZeroToNinety() {
        // 135° 方向（dx,dy 同幅）→ 折叠后 45°
        let pose = makePose(
            leftKnee: nil, rightKnee: nil,
            leftAnkle: PoseJointPoint(x: 0.30, y: 0.20, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.50, y: 0.40, confidence: 0.9)
        )

        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .rejectOwnership, config: .standard
        )

        XCTAssertEqual(fallback?.axisAngle ?? 0, 45, accuracy: 1e-6)
    }

    func test_fallback_confidenceJustAboveFloorPasses() {
        // point 0.9 × geom(d×12) = 0.31 → d ≈ 0.0287
        let d = 0.31 / 0.9 / 12.0
        let pose = makePose(
            leftKnee: nil, rightKnee: nil,
            leftAnkle: PoseJointPoint(x: 0.5 - d / 2, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.5 + d / 2, y: 0.30, confidence: 0.9)
        )

        // v2 语义：floor 0.30 下 0.31 恰好通过。
        let config = BoardEdgeConfig(
            fallbackConfidenceFloor: 0.30,
            fallbackPickStrategy: .confMax
        )
        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .farShot, config: config
        )

        XCTAssertEqual(fallback?.confidence ?? 0, 0.31, accuracy: 1e-9)
    }

    func test_fallback_confidenceJustBelowFloorRejected() {
        // point 0.9 × geom(d×12) = 0.29
        let d = 0.29 / 0.9 / 12.0
        let pose = makePose(
            leftKnee: nil, rightKnee: nil,
            leftAnkle: PoseJointPoint(x: 0.5 - d / 2, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.5 + d / 2, y: 0.30, confidence: 0.9)
        )

        // v2 语义：floor 0.30 下 0.29 被拒。
        let config = BoardEdgeConfig(
            fallbackConfidenceFloor: 0.30,
            fallbackPickStrategy: .confMax
        )
        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .farShot, config: config
        )

        XCTAssertNil(fallback)
    }

    func test_fallback_originalStatusPreservedPerCandidate() {
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.40, y: 0.55, confidence: 0.9),
            rightKnee: PoseJointPoint(x: 0.60, y: 0.55, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.40, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.60, y: 0.30, confidence: 0.9)
        )

        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .noAxis, config: .standard
        )

        XCTAssertEqual(fallback?.originalStatus, .noAxis)
    }

    func test_fallback_roundTripsThroughCodable() throws {
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.40, y: 0.55, confidence: 0.9),
            rightKnee: PoseJointPoint(x: 0.60, y: 0.55, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.40, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.60, y: 0.30, confidence: 0.9)
        )
        let observation = BoardEdgeObservation(
            status: .fallback,
            fallbackAxis: BoardEdgeDetector.synthesizeFallback(
                pose: pose, originalStatus: .farShot, config: .standard
            )
        )

        let encoded = try JSONEncoder().encode(observation)
        let decoded = try JSONDecoder().decode(BoardEdgeObservation.self, from: encoded)

        XCTAssertEqual(decoded.status, .fallback)
        XCTAssertEqual(decoded.fallbackAxis, observation.fallbackAxis)
        XCTAssertNil(decoded.axisAngle)
    }

    // MARK: - ADR-002：v3 默认策略（ankleOnly + floor=0.40）

    func test_defaultConfig_isAnkleOnlyWithFloor040() {
        // ADR-002 默认策略基线；防止后续误改回 v2。
        XCTAssertEqual(BoardEdgeConfig.standard.fallbackPickStrategy, .ankleOnly)
        XCTAssertEqual(BoardEdgeConfig.standard.fallbackConfidenceFloor, 0.40, accuracy: 1e-9)
    }

    func test_fallback_ankleOnlySkipsKneeEvenWhenKneeStronger() {
        // 踝对间距 0.03 → geom 0.36 → cnf 0.324（<0.40 被 floor 拒）；
        // 膝对若参与本会 cnf=0.54 高于踝，但 ankleOnly 策略下必须跳过。
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.40, y: 0.55, confidence: 0.9),
            rightKnee: PoseJointPoint(x: 0.60, y: 0.55, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.485, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.515, y: 0.30, confidence: 0.9)
        )

        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .farShot, config: .standard
        )

        // 默认策略下：膝对被跳过；踝对置信 0.324 < floor 0.40 → 全体 nil。
        XCTAssertNil(fallback)
    }

    func test_fallback_ankleOnlyReturnsAnkleWhenPassesFloor() {
        // 踝对间距 0.20 → geom 1.0 → cnf 0.9 ≥ 0.40。
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.30, y: 0.55, confidence: 0.9),
            rightKnee: PoseJointPoint(x: 0.70, y: 0.55, confidence: 0.9),
            leftAnkle: PoseJointPoint(x: 0.40, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.60, y: 0.30, confidence: 0.9)
        )

        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .farShot, config: .standard
        )

        XCTAssertEqual(fallback?.source, .anklePair)
        XCTAssertEqual(fallback?.confidence ?? 0, 0.9, accuracy: 1e-6)
    }

    func test_fallback_ankleOnlyIgnoresKneeWhenAnkleMissing() {
        // 踝缺失 + 膝对可能过 v2 floor 也不允许（ankleOnly 结构性拒绝）。
        let pose = makePose(
            leftKnee: PoseJointPoint(x: 0.30, y: 0.55, confidence: 0.95),
            rightKnee: PoseJointPoint(x: 0.70, y: 0.55, confidence: 0.95),
            leftAnkle: nil,
            rightAnkle: nil
        )

        let fallback = BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .ankleLowCnf, config: .standard
        )

        XCTAssertNil(fallback)
    }

    func test_fallback_floor040RejectsBorderlineAnklePair() {
        // point 0.9 × geom(d×12) = 0.39 → d ≈ 0.0361
        let d = 0.39 / 0.9 / 12.0
        let pose = makePose(
            leftKnee: nil, rightKnee: nil,
            leftAnkle: PoseJointPoint(x: 0.5 - d / 2, y: 0.30, confidence: 0.9),
            rightAnkle: PoseJointPoint(x: 0.5 + d / 2, y: 0.30, confidence: 0.9)
        )

        // 默认 floor=0.40 下 0.39 被拒（v2 的 floor=0.30 会通过 → 用来对照）。
        XCTAssertNil(BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .farShot, config: .standard
        ))

        let v2 = BoardEdgeConfig(
            fallbackConfidenceFloor: 0.30,
            fallbackPickStrategy: .confMax
        )
        XCTAssertNotNil(BoardEdgeDetector.synthesizeFallback(
            pose: pose, originalStatus: .farShot, config: v2
        ))
    }

    // MARK: - Helpers

    private func makeInstance(index: Int, alphaCount: Int, box: CGRect)
        -> BoardEdgeDetector.InstanceMask {
        BoardEdgeDetector.InstanceMask(index: index, data: [], alphaCount: alphaCount, box: box)
    }

    private func blankAlpha(width: Int, height: Int) -> [UInt8] {
        [UInt8](repeating: 0, count: width * height * 4)
    }

    private func setAlpha(_ alpha: inout [UInt8], width: Int, x: Int, y: Int) {
        alpha[(y * width + x) * 4 + 3] = 255
    }

    private func makePose(
        leftAnkle: PoseJointPoint?,
        rightAnkle: PoseJointPoint?
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
            leftAnklePoint: leftAnkle,
            rightAnklePoint: rightAnkle
        )
    }

    private func makePose(
        leftShoulder: PoseJointPoint?,
        rightShoulder: PoseJointPoint?,
        leftHip: PoseJointPoint?,
        rightHip: PoseJointPoint?,
        leftAnkle: PoseJointPoint?,
        rightAnkle: PoseJointPoint?
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
            leftShoulderPoint: leftShoulder,
            rightShoulderPoint: rightShoulder,
            leftHipPoint: leftHip,
            rightHipPoint: rightHip,
            leftAnklePoint: leftAnkle,
            rightAnklePoint: rightAnkle
        )
    }

    private func makePose(
        leftKnee: PoseJointPoint?,
        rightKnee: PoseJointPoint?,
        leftAnkle: PoseJointPoint?,
        rightAnkle: PoseJointPoint?
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
            leftKneePoint: leftKnee,
            rightKneePoint: rightKnee,
            leftAnklePoint: leftAnkle,
            rightAnklePoint: rightAnkle
        )
    }
}

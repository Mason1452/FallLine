import Foundation

// MARK: - 板身方向与横滑分析器

/// v1 用左右脚踝连线代理板身线条，并用画面中的中心点位移估计横滑角。
public struct BoardDirectionAnalyzer {
    public init() {}

    public static let minimumTravelDistance = 0.005
    private static let fullTravelConfidenceDistance = 0.04

    public static func analyze(frames: [DetectionResult]) -> BoardAnalysis {
        let prepared = frames.compactMap(PreparedFrame.init(frame:))
        guard !prepared.isEmpty else { return .empty }

        let analyses = prepared.indices.map { index in
            let observation = prepared[index].observation
            return BoardFrameAnalysis(
                time: prepared[index].time,
                observation: observation,
                kinematics: kinematics(at: index, in: prepared, observation: observation)
            )
        }

        return BoardAnalysis(frames: analyses, summary: summary(from: analyses))
    }
}

private extension BoardDirectionAnalyzer {
    struct PreparedFrame {
        let time: Double
        let boardAngle: Double
        let boardCenterX: Double
        let boardCenterY: Double
        let motionCenterX: Double
        let motionCenterY: Double
        let observationConfidence: Double
        let motionCenterConfidence: Double

        var observation: BoardObservation {
            BoardObservation(
                source: .ankleProxy,
                axisAngle: boardAngle,
                centerX: boardCenterX,
                centerY: boardCenterY,
                confidence: observationConfidence
            )
        }

        init?(frame: DetectionResult) {
            if let poseScore = frame.poseScore,
               poseScore.totalConfidence < AnalysisReliability.minimumPoseScoreConfidence {
                return nil
            }

            let pose = frame.bodyPose
            guard pose.detected,
                  let boardAngle = pose.ankleProxyBoardAngle,
                  let ankleX = pose.ankleCenterX,
                  let ankleY = pose.ankleCenterY else {
                return nil
            }

            let motionX = pose.bodyCenterX ?? ankleX
            let motionY = pose.bodyCenterY ?? ankleY

            self.time = frame.time
            self.boardAngle = normalizeAngle(boardAngle.value)
            self.boardCenterX = ankleX.value
            self.boardCenterY = ankleY.value
            self.motionCenterX = motionX.value
            self.motionCenterY = motionY.value
            self.observationConfidence = min(boardAngle.confidence, min(ankleX.confidence, ankleY.confidence))
            self.motionCenterConfidence = min(motionX.confidence, motionY.confidence)
        }
    }

    static func kinematics(
        at index: Int,
        in frames: [PreparedFrame],
        observation: BoardObservation
    ) -> BoardKinematics? {
        guard frames.count >= 2 else { return nil }

        let start: PreparedFrame
        let end: PreparedFrame
        if index == 0 {
            start = frames[index]
            end = frames[index + 1]
        } else if index == frames.count - 1 {
            start = frames[index - 1]
            end = frames[index]
        } else {
            start = frames[index - 1]
            end = frames[index + 1]
        }

        let dx = end.motionCenterX - start.motionCenterX
        let dy = end.motionCenterY - start.motionCenterY
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= minimumTravelDistance else { return nil }

        let travelAngle = normalizeAngle(atan2(dy, dx) * 180 / Double.pi)
        let sideslipAngle = axisAngleDifference(observation.axisAngle, travelAngle)
        let carvingConfidence = clamp(100 - sideslipAngle / 45 * 100, lower: 0, upper: 100)
        let travelConfidence = clamp(distance / fullTravelConfidenceDistance, lower: 0, upper: 1)
        let centerConfidence = min(start.motionCenterConfidence, end.motionCenterConfidence)
        let confidence = observation.confidence * travelConfidence * centerConfidence

        return BoardKinematics(
            boardAngle: observation.axisAngle,
            travelAngle: travelAngle,
            sideslipAngle: sideslipAngle,
            carvingConfidence: carvingConfidence,
            confidence: confidence
        )
    }

    static func summary(from analyses: [BoardFrameAnalysis]) -> BoardAnalysisSummary? {
        guard !analyses.isEmpty else { return nil }

        let kinematics = analyses.compactMap(\.kinematics)
        let observationConfidence = average(analyses.map(\.observation.confidence))
        guard !kinematics.isEmpty else {
            return BoardAnalysisSummary(
                frameCount: analyses.count,
                averageSideslipAngle: nil,
                carvingConfidence: nil,
                confidence: observationConfidence,
                source: .ankleProxy
            )
        }

        let sideslip = weightedAverage(kinematics.map { ($0.sideslipAngle, $0.confidence) })
            ?? average(kinematics.map(\.sideslipAngle))
        let carving = weightedAverage(kinematics.map { ($0.carvingConfidence, $0.confidence) })
            ?? average(kinematics.map(\.carvingConfidence))
        let confidence = average(kinematics.map(\.confidence))

        return BoardAnalysisSummary(
            frameCount: analyses.count,
            averageSideslipAngle: sideslip,
            carvingConfidence: carving,
            confidence: confidence,
            source: .ankleProxy
        )
    }

    static func axisAngleDifference(_ first: Double, _ second: Double) -> Double {
        let raw = abs(angleDifference(first, second))
        return raw > 90 ? 180 - raw : raw
    }

    static func angleDifference(_ first: Double, _ second: Double) -> Double {
        normalizeAngle(first - second)
    }

    static func normalizeAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized >= 180 {
            normalized -= 360
        } else if normalized < -180 {
            normalized += 360
        }
        return normalized
    }

    static func weightedAverage(_ values: [(value: Double, weight: Double)]) -> Double? {
        let weightSum = values.map { $0.weight }.reduce(0, +)
        guard weightSum > 0 else { return nil }
        return values.map { $0.value * $0.weight }.reduce(0, +) / weightSum
    }

    static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

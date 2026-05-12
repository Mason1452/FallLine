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
        let selectedObservation: BoardObservation
        let motionCenterX: Double
        let motionCenterY: Double
        let motionCenterConfidence: Double

        var observation: BoardObservation {
            selectedObservation
        }

        init?(frame: DetectionResult) {
            if let poseScore = frame.poseScore,
               poseScore.totalConfidence < AnalysisReliability.minimumPoseScoreConfidence {
                return nil
            }

            let pose = frame.bodyPose
            guard pose.detected,
                  let ankleX = pose.ankleCenterX,
                  let ankleY = pose.ankleCenterY else {
                return nil
            }

            let ankleObservation = pose.ankleProxyBoardAngle.map {
                BoardObservation(
                    source: .ankleProxy,
                    axisAngle: normalizeAngle($0.value),
                    centerX: ankleX.value,
                    centerY: ankleY.value,
                    confidence: min($0.confidence, min(ankleX.confidence, ankleY.confidence))
                )
            }
            let selectedObservation = Self.selectObservation(
                visual: frame.visualBoardObservation,
                ankle: ankleObservation
            )
            guard let selectedObservation else { return nil }

            let motionX = pose.bodyCenterX ?? ankleX
            let motionY = pose.bodyCenterY ?? ankleY

            self.time = frame.time
            self.selectedObservation = selectedObservation
            self.motionCenterX = motionX.value
            self.motionCenterY = motionY.value
            self.motionCenterConfidence = min(motionX.confidence, motionY.confidence)
        }

        static func selectObservation(
            visual: BoardObservation?,
            ankle: BoardObservation?
        ) -> BoardObservation? {
            // 图像候选线当前只作为调试层输出。真实样本显示它可能抓到雪面纹理、
            // 因此暂不参与评分/横滑计算；等人工标定稳定后再提升为主证据。
            return ankle
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
        let carvingConfidence = clamp(
            100 - sideslipAngle / AnalysisReliability.dominantSideslipAngle * 100,
            lower: 0,
            upper: 100
        )
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
        let summarySource = sourceSummary(from: analyses.map(\.observation.source))
        guard !kinematics.isEmpty else {
            return BoardAnalysisSummary(
                frameCount: analyses.count,
                averageSideslipAngle: nil,
                carvingConfidence: nil,
                confidence: observationConfidence,
                source: summarySource
            )
        }

        let sideslip = weightedAverage(kinematics.map { ($0.sideslipAngle, $0.confidence) })
        let carving = weightedAverage(kinematics.map { ($0.carvingConfidence, $0.confidence) })
        let confidence = average(kinematics.map(\.confidence))

        return BoardAnalysisSummary(
            frameCount: analyses.count,
            averageSideslipAngle: sideslip,
            carvingConfidence: carving,
            confidence: confidence,
            source: summarySource
        )
    }

    static func sourceSummary(from sources: [BoardObservationSource]) -> BoardObservationSource {
        let uniqueSources = Set(sources)
        guard uniqueSources.count != 1 else {
            return sources.first ?? .ankleProxy
        }
        return .mixed
    }

    static func axisAngleDifference(_ first: Double, _ second: Double) -> Double {
        let raw = abs(angleDifference(first, second))
        return raw > 90 ? 180 - raw : raw
    }

    static func angleDifference(_ first: Double, _ second: Double) -> Double {
        normalizeAngle(first - second)
    }

}

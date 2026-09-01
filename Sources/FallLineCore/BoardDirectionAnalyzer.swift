import Foundation

// MARK: - 板身方向与横滑分析器

/// v1 用左右脚踝连线代理板身线条，并用画面中的中心点位移估计横滑角。
public struct BoardDirectionAnalyzer {
    public init() {}

    public static let minimumTravelDistance = 0.005
    private static let fullTravelConfidenceDistance = 0.04
    private static let travelWindowHalfWidth = 3
    /// P3 sideslipAngle 中位数滑窗半宽。总窗宽 = 2 * halfWidth + 1 = 5 帧。
    /// 5fps 采样下相当于 1s 的时间窗，用于抹平 travelAngle 单帧尖峰传递到 sideslip 的抖动
    /// （corpus median 22° / max 28° 的帧间跳动主要来自光流角度突变，而非真实动作变化）。
    private static let sideslipMedianWindowHalfWidth = 2

    public static func analyze(
        frames: [DetectionResult],
        flowTravelDirections: [(time: Double, angle: Double, confidence: Double)] = []
    ) -> BoardAnalysis {
        let prepared = frames.compactMap(PreparedFrame.init(frame:))
        guard !prepared.isEmpty else { return .empty }

        let flowAngleByTime = flowTravelDirections.isEmpty
            ? nil
            : Dictionary(flowTravelDirections.map { ($0.time, (angle: $0.angle, confidence: $0.confidence)) },
                         uniquingKeysWith: { first, _ in first })

        let rawAnalyses = prepared.indices.map { index in
            let observation = prepared[index].observation
            let flowOverride = flowAngleByTime?[prepared[index].time]
            return BoardFrameAnalysis(
                time: prepared[index].time,
                observation: observation,
                kinematics: kinematics(
                    at: index,
                    in: prepared,
                    observation: observation,
                    flowTravelAngle: flowOverride?.angle,
                    flowTravelConfidence: flowOverride?.confidence
                )
            )
        }

        let smoothed = smoothSideslip(in: rawAnalyses)
        return BoardAnalysis(frames: smoothed, summary: summary(from: smoothed))
    }
}

private extension BoardDirectionAnalyzer {
    /// 对每帧的 sideslipAngle 做 5 帧中位数滑窗，并按新 sideslip 重算 carvingConfidence。
    /// travelAngle / boardAngle / confidence 保持原值，因为它们分别是输入信号和帧级诊断信号，
    /// 不应被时间维度污染。窗口内有效值不足 3 时保留原值（避免边界样本被单帧主导）。
    static func smoothSideslip(in analyses: [BoardFrameAnalysis]) -> [BoardFrameAnalysis] {
        guard analyses.count >= 3 else { return analyses }

        return analyses.indices.map { index -> BoardFrameAnalysis in
            let current = analyses[index]
            guard let currentKinematics = current.kinematics else { return current }

            let start = max(0, index - sideslipMedianWindowHalfWidth)
            let end = min(analyses.count - 1, index + sideslipMedianWindowHalfWidth)
            let windowValues = analyses[start...end].compactMap { $0.kinematics?.sideslipAngle }
            guard windowValues.count >= 3 else { return current }

            let sorted = windowValues.sorted()
            let smoothedSideslip = sorted[sorted.count / 2]
            let smoothedCarving = clamp(
                100 - smoothedSideslip / AnalysisReliability.dominantSideslipAngle * 100,
                lower: 0,
                upper: 100
            )
            let updatedKinematics = BoardKinematics(
                boardAngle: currentKinematics.boardAngle,
                travelAngle: currentKinematics.travelAngle,
                sideslipAngle: smoothedSideslip,
                carvingConfidence: smoothedCarving,
                confidence: currentKinematics.confidence
            )
            return BoardFrameAnalysis(
                time: current.time,
                observation: current.observation,
                kinematics: updatedKinematics
            )
        }
    }
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

            let motionX = pose.hipCenterX ?? ankleX
            let motionY = pose.hipCenterY ?? ankleY

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
            // 图像候选线易被雪面纹理误触发。策略：
            // 1) ankle 主线，永远作为主证据；
            // 2) 若 visual 存在且与 ankle 轴向差 ≤ arbitrationAxisTolerance，
            //    则做加权融合作为“仲裁背书”提升整体置信度；
            // 3) 若 visual 与 ankle 分歧显著（可能是雪面误检），忽略 visual。
            guard let ankle = ankle else { return nil }
            guard let visual = visual, visual.confidence > 0 else { return ankle }

            let axisDiff = BoardDirectionAnalyzer.axisAngleDifference(visual.axisAngle, ankle.axisAngle)
            guard axisDiff <= AnalysisReliability.boardVisualArbitrationTolerance else {
                return ankle
            }

            // 一致：以置信度做加权平均，得到融合观测
            let wAnkle = max(ankle.confidence, 0.001)
            let wVisual = max(visual.confidence, 0.001) * 0.5   // visual 半权，防止其未验证的偏差主导
            let wSum = wAnkle + wVisual
            let fusedAngle = normalizeAngle(
                (ankle.axisAngle * wAnkle + visual.axisAngle * wVisual) / wSum
            )
            let fusedConfidence = min(1.0, ankle.confidence + visual.confidence * 0.3)

            return BoardObservation(
                source: .mixed,
                axisAngle: fusedAngle,
                centerX: ankle.centerX,
                centerY: ankle.centerY,
                confidence: fusedConfidence
            )
        }
    }

    static func kinematics(
        at index: Int,
        in frames: [PreparedFrame],
        observation: BoardObservation,
        flowTravelAngle: Double?,
        flowTravelConfidence: Double?
    ) -> BoardKinematics? {
        let travelAngle: Double
        let travelConfidence: Double

        // 门控：仅当光流置信度足够高时才采纳光流方向；否则回退到脚踝代理位移。
        // 低置信度帧下光流角度会剧烈跳动（-4.7° ↔ 112.4°），若无脑采纳会污染 sideslipAngle
        // → carvingConfidence → boardKinematicHighScoreCap（62 分封顶）整条链路。
        let hasReliableFlow = flowTravelAngle != nil
            && (flowTravelConfidence ?? 0) >= AnalysisReliability.minimumFlowTravelConfidence

        if hasReliableFlow, let flowAngle = flowTravelAngle, let flowConf = flowTravelConfidence {
            travelAngle = flowAngle
            travelConfidence = flowConf
        } else {
            guard frames.count >= 2 else { return nil }

            let start: PreparedFrame
            let end: PreparedFrame
            let half = min(travelWindowHalfWidth, frames.count / 2)
            let startIndex = max(0, index - half)
            let endIndex = min(frames.count - 1, index + half)
            start = frames[startIndex]
            end = frames[endIndex]

            let dx = end.motionCenterX - start.motionCenterX
            let dy = end.motionCenterY - start.motionCenterY
            let distance = sqrt(dx * dx + dy * dy)
            guard distance >= minimumTravelDistance else { return nil }

            travelAngle = normalizeAngle(atan2(dy, dx) * 180 / Double.pi)
            travelConfidence = clamp(distance / fullTravelConfidenceDistance, lower: 0, upper: 1)
        }

        let sideslipAngle = axisAngleDifference(observation.axisAngle, travelAngle)
        let carvingConfidence = clamp(
            100 - sideslipAngle / AnalysisReliability.dominantSideslipAngle * 100,
            lower: 0,
            upper: 100
        )
        let centerConfidence = observation.confidence
        let confidence = centerConfidence * travelConfidence

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

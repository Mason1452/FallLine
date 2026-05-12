import Foundation

// MARK: - 单板转弯阶段检测器

/// 基于 2D 人体姿态的有符号倾斜信号，粗略识别单板压刃方向和转弯阶段。
public struct TurnPhaseDetector {
    public init() {}

    public static let neutralThreshold = 8.0
    public static let shapingThreshold = 12.0
    private static let stableDeltaThreshold = 2.5
    private static let fastBuildThreshold = 4.0
    private static let releaseDeltaThreshold = -2.0
    private static let segmentMinimumFrames = 3

    public static func analyze(frames: [DetectionResult]) -> TurnAnalysis {
        let prepared = prepareFrames(frames)
        guard !prepared.isEmpty else { return .empty }

        let smoothedSignals = prepared.indices.map { index in
            medianSignal(around: index, in: prepared)
        }
        let transitionIndices = signChangeTransitionIndices(signals: smoothedSignals)

        var analyses: [TurnFrameAnalysis] = []
        for index in prepared.indices {
            let signal = smoothedSignals[index]
            let direction = direction(for: signal)
            let phase = phase(
                at: index,
                signals: smoothedSignals,
                direction: direction,
                transitionIndices: transitionIndices
            )
            analyses.append(TurnFrameAnalysis(
                time: prepared[index].frame.time,
                edgeSignal: signal,
                edgeDirection: direction,
                phase: phase,
                confidence: prepared[index].confidence
            ))
        }

        let segments = buildSegments(prepared: prepared, analyses: analyses)
        return TurnAnalysis(frames: analyses, segments: segments)
    }
}

private extension TurnPhaseDetector {
    struct PreparedFrame {
        let frame: DetectionResult
        let rawSignal: Double
        let confidence: Double
    }

    static func prepareFrames(_ frames: [DetectionResult]) -> [PreparedFrame] {
        reliablePoseFrames(from: frames).compactMap { frame in
            guard frame.poseScore != nil, frame.bodyPose.detected else { return nil }
            let components = edgeSignalComponents(for: frame.bodyPose)
            guard components.hasSignal else { return nil }
            guard components.confidence >= AnalysisReliability.minimumPoseScoreConfidence else { return nil }
            return PreparedFrame(
                frame: frame,
                rawSignal: components.signal,
                confidence: clamp(components.confidence)
            )
        }
    }

    static func edgeSignalComponents(for pose: BodyPoseData) -> (signal: Double, confidence: Double, hasSignal: Bool) {
        var signal = 0.0
        var confidence = 0.0
        var hasSignal = false

        if let signedCalf = pose.signedCalfLeanAngle {
            signal += signedCalf.value * 0.5
            confidence += signedCalf.confidence * 0.5
            hasSignal = true
        }
        if let signedBody = pose.signedBodyLeanAngle {
            signal += signedBody.value * 0.3
            confidence += signedBody.confidence * 0.3
            hasSignal = true
        }
        if let hip = pose.hipCenterX, let ankle = pose.ankleCenterX {
            let hipOffsetSignal = (hip.value - ankle.value) * 100.0
            signal += hipOffsetSignal * 0.2
            confidence += min(hip.confidence, ankle.confidence) * 0.2
            hasSignal = true
        }

        return (signal, confidence, hasSignal)
    }

    static func medianSignal(around index: Int, in frames: [PreparedFrame]) -> Double {
        let start = max(0, index - 1)
        let end = min(frames.count - 1, index + 1)
        let values = frames[start...end].map(\.rawSignal).sorted()
        return values[values.count / 2]
    }

    static func signChangeTransitionIndices(signals: [Double]) -> Set<Int> {
        var indices = Set<Int>()
        guard signals.count >= 2 else { return indices }

        for index in 1..<signals.count {
            let previous = direction(for: signals[index - 1])
            let current = direction(for: signals[index])
            guard previous != .neutral, current != .neutral, previous != current else { continue }
            indices.insert(index - 1)
            indices.insert(index)
            if index + 1 < signals.count {
                indices.insert(index + 1)
            }
        }
        return indices
    }

    static func direction(for signal: Double) -> EdgeDirection {
        if abs(signal) < neutralThreshold { return .neutral }
        return signal > 0 ? .imageRight : .imageLeft
    }

    static func phase(
        at index: Int,
        signals: [Double],
        direction: EdgeDirection,
        transitionIndices: Set<Int>
    ) -> TurnPhase {
        guard direction != .neutral else { return .transition }
        guard !transitionIndices.contains(index) else { return .transition }

        let currentAbs = abs(signals[index])
        let previousAbs = index > 0 ? abs(signals[index - 1]) : currentAbs
        let nextAbs = index + 1 < signals.count ? abs(signals[index + 1]) : currentAbs
        let deltaFromPrevious = currentAbs - previousAbs
        let deltaToNext = nextAbs - currentAbs

        if currentAbs >= shapingThreshold, abs(deltaFromPrevious) <= stableDeltaThreshold, abs(deltaToNext) <= stableDeltaThreshold {
            return .shaping
        }
        if deltaFromPrevious >= fastBuildThreshold || deltaToNext > stableDeltaThreshold {
            return .initiation
        }
        if deltaFromPrevious <= releaseDeltaThreshold || deltaToNext < releaseDeltaThreshold {
            return .release
        }
        if currentAbs >= shapingThreshold {
            return .shaping
        }
        return .initiation
    }

    static func buildSegments(prepared: [PreparedFrame], analyses: [TurnFrameAnalysis]) -> [TurnSegment] {
        guard prepared.count == analyses.count else { return [] }

        var groups: [(direction: EdgeDirection, start: Int, end: Int)] = []
        var currentDirection: EdgeDirection?
        var currentStart = 0

        for index in analyses.indices {
            let direction = analyses[index].edgeDirection
            guard direction != .neutral, direction != .unknown else {
                if let existing = currentDirection {
                    groups.append((existing, currentStart, index - 1))
                    currentDirection = nil
                }
                continue
            }

            if currentDirection == nil {
                currentDirection = direction
                currentStart = index
            } else if currentDirection != direction {
                groups.append((currentDirection!, currentStart, index - 1))
                currentDirection = direction
                currentStart = index
            }
        }

        if let existing = currentDirection {
            groups.append((existing, currentStart, analyses.count - 1))
        }

        return groups.compactMap { group in
            let count = group.end - group.start + 1
            guard count >= segmentMinimumFrames else { return nil }
            let segmentAnalyses = Array(analyses[group.start...group.end])
            let segmentPrepared = Array(prepared[group.start...group.end])
            let phaseDistribution = distribution(for: segmentAnalyses)
            let mainIssue = issue(for: segmentAnalyses, prepared: segmentPrepared)
            let startTime = segmentAnalyses.first?.time ?? 0
            let endTime = segmentAnalyses.last?.time ?? startTime

            return TurnSegment(
                startTime: startTime,
                endTime: endTime,
                startTimeString: formatTime(startTime),
                endTimeString: formatTime(endTime),
                edgeDirection: group.direction,
                frameCount: count,
                phaseDistribution: phaseDistribution,
                mainIssue: mainIssue
            )
        }
    }

    static func distribution(for analyses: [TurnFrameAnalysis]) -> [String: Double] {
        guard !analyses.isEmpty else { return [:] }
        var counts: [String: Int] = [:]
        for analysis in analyses {
            counts[analysis.phase.rawValue, default: 0] += 1
        }
        let total = Double(analyses.count)
        return counts.mapValues { Double($0) / total }
    }

    static func issue(for analyses: [TurnFrameAnalysis], prepared: [PreparedFrame]) -> String {
        let shapingEdgeScores = zip(analyses, prepared)
            .filter { $0.0.phase == .shaping }
            .compactMap { $0.1.frame.skiMetrics?.edgeQualityScore }
        if !shapingEdgeScores.isEmpty {
            let average = shapingEdgeScores.reduce(0, +) / Double(shapingEdgeScores.count)
            if average < 55 {
                return "弯中刃角保持不足"
            }
        }

        let initiationSignals = analyses
            .filter { $0.phase == .initiation }
            .map { abs($0.edgeSignal) }
        if initiationSignals.count >= 2 {
            let build = (initiationSignals.last ?? 0) - (initiationSignals.first ?? 0)
            if build < 5 {
                return "入弯建立刃角偏晚"
            }
        }

        let releaseSignals = analyses
            .filter { $0.phase == .release }
            .map(\.edgeSignal)
        if releaseSignals.count >= 3, averageAbsDelta(releaseSignals) > 8 {
            return "出弯释放不够平顺"
        }

        return "阶段衔接基本正常"
    }

    static func averageAbsDelta(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let deltas = zip(values.dropFirst(), values).map { abs($0 - $1) }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

}

import Foundation

// MARK: - 高光时刻检测器

/// 从视频中选出用户滑得最好的连续片段，而不是单帧高分。
public struct HighlightMomentDetector {
    public init() {}

    public static func detect(
        from frames: [DetectionResult],
        summary: VideoSummary? = nil,
        maxCount: Int = 3
    ) -> [HighlightMoment] {
        let samples = reliablePoseFrames(from: frames)
            .sorted { $0.time < $1.time }
            .compactMap { frameSample(from: $0, stability: summary?.stabilityScore ?? 50) }
        guard samples.count >= AnalysisReliability.minimumHighlightFrameCount, maxCount > 0 else { return [] }

        let sampleInterval = medianSampleInterval(samples.map(\.time))
        let groups = contiguousGroups(samples, sampleInterval: sampleInterval)
        let minimumScore = minimumHighlightScore(samples: samples, summary: summary)
        let stableBaseline = summary.flatMap { stableCarvingBaseline(from: frames, motionStability: $0.stabilityScore) }
        if stableBaseline == nil, boardKinematicHighScoreCap(from: frames) != nil {
            return []
        }
        if stableBaseline == nil, (averageEdgeEvidenceScore(from: frames) ?? 0) < 42 {
            return []
        }

        var candidates: [Candidate] = []
        if let baseline = stableBaseline {
            let windowSamples = samples.filter {
                $0.time >= baseline.plateauStartTime && $0.time <= baseline.plateauEndTime
            }
            if !windowSamples.isEmpty {
                candidates.append(Candidate(
                    start: baseline.plateauStartTime,
                    end: baseline.plateauEndTime,
                    score: baseline.adjustedAverageScore,
                    confidence: average(windowSamples.map(\.confidence)),
                    rank: baseline.adjustedAverageScore + 5,
                    title: "稳定刻滑高光",
                    description: "这段连续稳定、质量最好，最能代表用户当前真实滑行水平。"
                ))
            }
        }

        for group in groups {
            candidates.append(contentsOf: windowCandidates(
                from: group,
                sampleInterval: sampleInterval,
                minimumScore: minimumScore
            ))
        }

        candidates.sort {
            if abs($0.rank - $1.rank) > 0.001 { return $0.rank > $1.rank }
            return ($0.end - $0.start) > ($1.end - $1.start)
        }

        var selected: [Candidate] = []
        for candidate in candidates {
            guard selected.allSatisfy({ !overlaps($0, candidate, padding: max(sampleInterval, 1.5)) }) else {
                continue
            }
            selected.append(candidate)
            if selected.count == maxCount { break }
        }

        selected.sort { $0.start < $1.start }
        return selected.map { candidate in
            HighlightMoment(
                startTime: formatTime(candidate.start),
                endTime: formatTime(candidate.end),
                startSeconds: candidate.start,
                endSeconds: candidate.end,
                duration: max(candidate.end - candidate.start + sampleInterval, sampleInterval),
                score: candidate.score,
                confidence: candidate.confidence,
                title: candidate.title,
                description: candidate.description
            )
        }
    }

    // MARK: - 内部模型

    private struct FrameSample {
        let time: Double
        let score: Double
        let confidence: Double
    }

    private struct Candidate {
        let start: Double
        let end: Double
        let score: Double
        let confidence: Double
        let rank: Double
        let title: String
        let description: String
    }

    // MARK: - 单帧高光分

    private static func frameSample(from frame: DetectionResult, stability: Double) -> FrameSample? {
        guard let poseScore = frame.poseScore else { return nil }

        var components: [(value: Double, weight: Double, confidence: Double)] = [
            (poseScore.totalScore, 0.60, poseScore.totalConfidence),
            (stability, 0.05, 1.0)
        ]

        if let metrics = frame.skiMetrics {
            if metrics.edgeQualityConfidence >= AnalysisReliability.minimumSkiMetricConfidence {
                components.append((metrics.edgeQualityScore, 0.15, metrics.edgeQualityConfidence))
            }
            if metrics.pressureSupportConfidence >= AnalysisReliability.minimumSkiMetricConfidence {
                components.append((metrics.pressureSupportScore, 0.12, metrics.pressureSupportConfidence))
            }
            if metrics.foreAftSupportConfidence >= AnalysisReliability.minimumSkiMetricConfidence {
                components.append((metrics.foreAftSupportScore, 0.08, metrics.foreAftSupportConfidence))
            }
        }

        let totalWeight = components.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return nil }
        let score = components.map { $0.value * $0.weight }.reduce(0, +) / totalWeight
        let confidence = components.map { $0.confidence * $0.weight }.reduce(0, +) / totalWeight

        return FrameSample(
            time: frame.time,
            score: clamp(score),
            confidence: clamp(confidence, lower: 0, upper: 1)
        )
    }

    // MARK: - 候选片段

    private static func windowCandidates(
        from samples: [FrameSample],
        sampleInterval: Double,
        minimumScore: Double
    ) -> [Candidate] {
        guard samples.count >= 3 else { return [] }

        let minWindowCount = min(samples.count, max(3, Int(ceil(4.0 / sampleInterval))))
        let maxWindowCount = min(samples.count, max(minWindowCount, Int(ceil(10.0 / sampleInterval))))
        guard minWindowCount <= maxWindowCount else { return [] }

        var candidates: [Candidate] = []
        for startIndex in samples.indices {
            for count in minWindowCount...maxWindowCount {
                let endIndex = startIndex + count - 1
                guard endIndex < samples.endIndex else { continue }
                let window = Array(samples[startIndex...endIndex])
                let score = weightedAverage(window.map { ($0.score, max(0.01, $0.confidence)) })
                guard score >= minimumScore else { continue }
                let strongFrameCoverage = Double(window.filter { $0.score >= minimumScore }.count) / Double(window.count)
                guard strongFrameCoverage >= 0.60 else { continue }

                let confidence = average(window.map(\.confidence))
                let consistency = clamp(100 - weightedStandardDeviation(
                    window.map { ($0.score, max(0.01, $0.confidence)) },
                    mean: score
                ) * 8)
                let rank = score + consistency * 0.03 + min(Double(count), 10) * 0.05

                candidates.append(Candidate(
                    start: window.first?.time ?? 0,
                    end: window.last?.time ?? 0,
                    score: score,
                    confidence: confidence,
                    rank: rank,
                    title: title(for: score),
                    description: description(for: score)
                ))
            }
        }

        return candidates
    }

    private static func contiguousGroups(_ samples: [FrameSample], sampleInterval: Double) -> [[FrameSample]] {
        guard !samples.isEmpty else { return [] }
        let maxGap = max(sampleInterval * 2.5, 2.5)
        var groups: [[FrameSample]] = []
        var current: [FrameSample] = [samples[0]]

        for sample in samples.dropFirst() {
            if sample.time - (current.last?.time ?? sample.time) <= maxGap {
                current.append(sample)
            } else {
                groups.append(current)
                current = [sample]
            }
        }
        groups.append(current)
        return groups
    }

    private static func minimumHighlightScore(samples: [FrameSample], summary: VideoSummary?) -> Double {
        let averageScore = summary?.averageScore ?? weightedAverage(samples.map { ($0.score, max(0.01, $0.confidence)) })
        if averageScore >= 70 { return 70 }
        if averageScore >= 55 { return min(70, averageScore + 4) }
        return max(50, averageScore + 4)
    }

    private static func overlaps(_ lhs: Candidate, _ rhs: Candidate, padding: Double) -> Bool {
        lhs.start <= rhs.end + padding && rhs.start <= lhs.end + padding
    }

    // MARK: - 文案

    private static func title(for score: Double) -> String {
        if score >= 85 { return "最佳刻滑片段" }
        if score >= 75 { return "稳定高质量片段" }
        return "相对最好的滑行片段"
    }

    private static func description(for score: Double) -> String {
        if score >= 85 {
            return "这段连续帧综合质量最高，可以作为用户本视频里的正面参考。"
        }
        if score >= 75 {
            return "这段姿态、支撑和稳定性组合较好，适合截出来给用户看。"
        }
        return "这是本视频中相对更好的连续片段，适合用来对比前后动作差异。"
    }

    // MARK: - 数学工具

    private static func weightedAverage(_ values: [(value: Double, weight: Double)]) -> Double {
        let totalWeight = values.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return 0 }
        return values.map { $0.value * $0.weight }.reduce(0, +) / totalWeight
    }

    private static func weightedStandardDeviation(
        _ values: [(value: Double, weight: Double)],
        mean: Double
    ) -> Double {
        let totalWeight = values.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return 0 }
        let variance = values.map { pow($0.value - mean, 2) * $0.weight }.reduce(0, +) / totalWeight
        return sqrt(variance)
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func medianSampleInterval(_ times: [Double]) -> Double {
        let deltas = zip(times.dropFirst(), times).map { max($0 - $1, 0) }.filter { $0 > 0 }
        guard !deltas.isEmpty else { return 1 }
        let sorted = deltas.sorted()
        return sorted[sorted.count / 2]
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

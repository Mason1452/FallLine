import Foundation

// MARK: - 板轴刃线时序连续性聚合器（ADR-004，§12.15，纯诊断）

/// 从全片逐帧 `BoardEdgeObservation` 聚合板轴刃线连续性时序信号（ADR-004）。
///
/// 纯函数后处理：因果前向窗 + 中位滤波 + IQR 稳定性门控；不调用 Vision、不读取评分字段，
/// 同输入跨次结果 bit-identical。
public enum BoardTemporalAxisAggregator {

    struct Candidate {
        let angle: Double
        let confidence: Double
        let source: BoardFallbackSource?
    }

    /// 对全片执行时序聚合。
    /// - Parameters:
    ///   - frames: 全片逐帧检测结果（读取 `boardEdgeObservation`）。
    ///   - travelDirections: 与 frames 对齐的行进方向角（0...360，nil = 该帧无方向信号）；
    ///     仅在折叠窗有向重建时使用。
    ///   - sampleInterval: 帧采样间隔（秒），用于 run 帧→秒换算。
    ///   - config: 板边配置（读取时序窗参数）。
    ///   - includeAllPoints: true 时 points 含全部可评估帧；默认仅含通过帧。
    public static func aggregate(
        frames: [DetectionResult],
        travelDirections: [Double?] = [],
        sampleInterval: Double = 0.2,
        config: BoardEdgeConfig = .standard,
        includeAllPoints: Bool = false
    ) -> BoardTrajectoryMetrics {
        let candidates = frames.map { candidate(from: $0.boardEdgeObservation) }
        let windowSize = config.temporalWindowSize
        let minCount = config.temporalMinCount

        var passFlags = Array(repeating: false, count: frames.count)
        var points: [BoardTemporalAxisPoint] = []
        var evaluatedWindows = 0
        var stableWindows = 0
        var rejectCounts: [BoardTemporalRejectReason: Int] = [:]

        for f in 0..<frames.count {
            let lo = max(0, f - windowSize + 1)
            let window = candidates[lo...f].compactMap { $0 }

            guard !window.isEmpty else { continue }
            evaluatedWindows += 1

            let travel = (f < travelDirections.count ? travelDirections[f] : nil)
            let angles = resolvedAngles(window: window, travel: travel, config: config)

            guard let resolved = angles else {
                rejectCounts[.foldCrossing, default: 0] += 1
                if includeAllPoints {
                    points.append(BoardTemporalAxisPoint(
                        frameIndex: f, windowPass: false, candidateCount: window.count,
                        iqr: iqr(window.map(\.angle)), rejectReason: .foldCrossing
                    ))
                }
                continue
            }

            guard window.count >= minCount else {
                rejectCounts[.insufficientCandidates, default: 0] += 1
                if includeAllPoints {
                    points.append(BoardTemporalAxisPoint(
                        frameIndex: f, windowPass: false, candidateCount: window.count,
                        iqr: iqr(resolved), rejectReason: .insufficientCandidates
                    ))
                }
                continue
            }

            let spread = iqr(resolved)
            guard spread <= config.temporalIQRGate else {
                rejectCounts[.unstableIQR, default: 0] += 1
                if includeAllPoints {
                    points.append(BoardTemporalAxisPoint(
                        frameIndex: f, windowPass: false, candidateCount: window.count,
                        iqr: spread, rejectReason: .unstableIQR
                    ))
                }
                continue
            }

            passFlags[f] = true
            stableWindows += 1
            points.append(BoardTemporalAxisPoint(
                frameIndex: f,
                windowPass: true,
                candidateCount: window.count,
                medianAngle: foldAngle(median(resolved)),
                medianConfidence: median(window.map(\.confidence)),
                iqr: spread,
                source: dominantSource(window)
            ))
        }

        let runs = stableRuns(passFlags: passFlags)
        let runSeconds = runs.map { Double($0) * sampleInterval }
        let longestRunFrames = runs.first ?? 0
        let longestRunSeconds = Double(longestRunFrames) * sampleInterval
        let stableFrameCount = passFlags.filter { $0 }.count

        let configEcho = BoardTrajectoryConfigEcho(
            windowSize: windowSize,
            minCount: minCount,
            iqrGate: config.temporalIQRGate,
            sampleInterval: sampleInterval,
            foldLowAngle: config.temporalFoldLowAngle,
            foldHighAngle: config.temporalFoldHighAngle
        )

        let orderedReasons: [BoardTemporalRejectReason] = [
            .insufficientCandidates, .unstableIQR, .foldCrossing
        ]
        var rejectHist: [String: Int] = [:]
        for reason in orderedReasons {
            if let count = rejectCounts[reason], count > 0 {
                rejectHist[reason.rawValue] = count
            }
        }

        return BoardTrajectoryMetrics(
            evaluatedWindows: evaluatedWindows,
            stableWindows: stableWindows,
            stableWindowRate: evaluatedWindows > 0
                ? Double(stableWindows) / Double(evaluatedWindows) : 0,
            longestStableRunFrames: longestRunFrames,
            longestStableRunSeconds: longestRunSeconds,
            stableRunCount: runs.count,
            stableRunMeanSeconds: runSeconds.isEmpty
                ? 0 : runSeconds.reduce(0, +) / Double(runSeconds.count),
            stableFrameCoverage: frames.isEmpty
                ? 0 : Double(stableFrameCount) / Double(frames.count),
            foldCrossingRate: evaluatedWindows > 0
                ? Double(rejectCounts[.foldCrossing] ?? 0) / Double(evaluatedWindows) : 0,
            rejectHist: rejectHist,
            configEcho: configEcho,
            points: points
        )
    }

    // MARK: - Candidate

    static func candidate(from observation: BoardEdgeObservation?) -> Candidate? {
        guard let observation else { return nil }
        switch observation.status {
        case .board:
            guard let angle = observation.axisAngle else { return nil }
            return Candidate(angle: angle, confidence: 1.0, source: nil)
        case .fallback:
            guard let axis = observation.fallbackAxis else { return nil }
            return Candidate(
                angle: axis.axisAngle,
                confidence: axis.confidence,
                source: axis.source
            )
        default:
            return nil
        }
    }

    // MARK: - Fold crossing

    /// 返回窗口角度（必要时行进方向有向重建）；折叠窗且无法重建返回 nil。
    static func resolvedAngles(
        window: [Candidate], travel: Double?, config: BoardEdgeConfig
    ) -> [Double]? {
        let raw = window.map(\.angle)
        guard let min = raw.min(), let max = raw.max(),
              min <= config.temporalFoldLowAngle,
              max >= config.temporalFoldHighAngle else {
            return raw
        }
        guard let travel else { return nil }
        return raw.map { directedAngle(unsigned: $0, travel: travel) }
    }

    /// 在有向 0...180 空间选择与行进方向更一致的表示。
    static func directedAngle(unsigned angle: Double, travel: Double) -> Double {
        let alternative = 180 - angle
        if circularDifference(alternative, travel) < circularDifference(angle, travel) {
            return alternative
        }
        return angle
    }

    static func circularDifference(_ a: Double, _ b: Double) -> Double {
        var diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff = 360 - diff }
        return diff
    }

    static func foldAngle(_ angle: Double) -> Double {
        angle > 90 ? 180 - angle : angle
    }

    // MARK: - 统计（口径与 §12.12 Python spike 对齐）

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    static func iqr(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        let q1 = sorted[Int(0.25 * Double(n - 1))]
        let q3 = sorted[Int(0.75 * Double(n - 1))]
        return q3 - q1
    }

    /// fallback 代理源多数派；tie → ankle；窗口无 fallback 候选返回 nil。
    static func dominantSource(_ window: [Candidate]) -> BoardFallbackSource? {
        var ankle = 0, knee = 0
        for candidate in window {
            switch candidate.source {
            case .anklePair?: ankle += 1
            case .kneePair?: knee += 1
            case nil: break
            }
        }
        if ankle == 0 && knee == 0 { return nil }
        return ankle >= knee ? .anklePair : .kneePair
    }

    // MARK: - Run 扫描（输出按长度降序）

    static func stableRuns(passFlags: [Bool]) -> [Int] {
        var runs: [Int] = []
        var current = 0
        for passed in passFlags {
            if passed {
                current += 1
            } else if current > 0 {
                runs.append(current)
                current = 0
            }
        }
        if current > 0 { runs.append(current) }
        return runs.sorted(by: >)
    }
}

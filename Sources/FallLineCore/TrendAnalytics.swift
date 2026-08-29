import Foundation

// MARK: - 埋点数据

/// 一次滑雪分析产生的可持久化 session 记录，作为进步曲线的基础埋点。
///
/// 只存最小必要字段；其他分维度指标（膝、腿、重心等）用 optional 以便未来扩展。
public struct SessionEntry: Codable, Equatable, Sendable {
    /// 会话结束时间（用户完成一次视频分析的时间）
    public let timestamp: Date
    /// 该次分析的总平均分（VideoSummary.averageScore）
    public let averageScore: Double
    /// 分级："初级" / "中级" / "高级" / "专业"
    public let overallLevel: String
    /// 稳定性分（可选，未来做多线图用）
    public let stabilityScore: Double?
    /// 最佳帧分数（可选）
    public let bestFrameScore: Double?

    public init(
        timestamp: Date,
        averageScore: Double,
        overallLevel: String,
        stabilityScore: Double? = nil,
        bestFrameScore: Double? = nil
    ) {
        self.timestamp = timestamp
        self.averageScore = averageScore
        self.overallLevel = overallLevel
        self.stabilityScore = stabilityScore
        self.bestFrameScore = bestFrameScore
    }
}

// MARK: - 周汇总点

/// 折线图的一个数据点：某个 ISO 周的汇总统计。
public struct WeeklySummary: Codable, Equatable, Sendable {
    /// 该周的起始日期（周一 00:00，用户所在时区）
    public let weekStart: Date
    /// 该周的会话数
    public let sessionCount: Int
    /// 该周平均分（简单算术平均）
    public let averageScore: Double
    /// 该周最高单次分
    public let bestScore: Double
    /// 该周最低单次分
    public let worstScore: Double

    public init(
        weekStart: Date,
        sessionCount: Int,
        averageScore: Double,
        bestScore: Double,
        worstScore: Double
    ) {
        self.weekStart = weekStart
        self.sessionCount = sessionCount
        self.averageScore = averageScore
        self.bestScore = bestScore
        self.worstScore = worstScore
    }
}

// MARK: - 里程碑

/// 用户达成的里程碑，用于本地通知与徽章展示。
public enum Milestone: Codable, Equatable, Sendable {
    /// 首次达成某个级别（"中级" / "高级" / "专业"）
    case firstReached(level: String)
    /// 相比上周平均分提升 N 分（N >= 3）
    case weeklyImprovement(delta: Double)
    /// 单次刷新最高分
    case newPersonalBest(score: Double)
    /// 连续活跃 N 周
    case streak(weeks: Int)

    public var displayTitle: String {
        switch self {
        case .firstReached(let level):
            return "首次达到\(level)"
        case .weeklyImprovement(let delta):
            return "比上周提升 \(String(format: "%.1f", delta)) 分"
        case .newPersonalBest(let score):
            return "刷新最高分：\(Int(score.rounded()))"
        case .streak(let weeks):
            return "连续活跃 \(weeks) 周"
        }
    }
}

// MARK: - 综合趋势报告

/// TrendAnalytics 的一次性输出：折线图、里程碑、关键统计一次拿全。
public struct TrendReport: Equatable, Sendable {
    public let weeklyPoints: [WeeklySummary]
    /// 本次新解锁的里程碑（未新增则为空）
    public let newMilestones: [Milestone]
    /// 全周期最高分
    public let personalBest: Double?
    /// 最近 7 天平均分
    public let last7DaysAverage: Double?
    /// 最近 30 天平均分
    public let last30DaysAverage: Double?
    /// 全周期最高级别
    public let highestLevelReached: String?

    public init(
        weeklyPoints: [WeeklySummary],
        newMilestones: [Milestone],
        personalBest: Double?,
        last7DaysAverage: Double?,
        last30DaysAverage: Double?,
        highestLevelReached: String?
    ) {
        self.weeklyPoints = weeklyPoints
        self.newMilestones = newMilestones
        self.personalBest = personalBest
        self.last7DaysAverage = last7DaysAverage
        self.last30DaysAverage = last30DaysAverage
        self.highestLevelReached = highestLevelReached
    }
}

// MARK: - 进步曲线分析器

/// 进步曲线分析器：给定一串按时间倒序或正序排列的 `SessionEntry`，
/// 计算周汇总折线图、里程碑与关键统计。
///
/// 纯计算，无 IO 副作用。持久化由 iOS 端 UserDefaults / File 层负责。
public struct TrendAnalytics {

    /// 判断"提升 delta 分"里程碑的最小阈值
    public static let weeklyImprovementThreshold: Double = 3.0
    /// 分级顺序，用于判断"首次达到某级别"
    public static let levelOrder: [String] = ["初级", "中级", "高级", "专业"]

    public init() {}

    /// 主入口：给定完整 session 列表 + 上一次已解锁的里程碑集合，返回综合报告。
    ///
    /// - Parameters:
    ///   - sessions: 所有历史 session（顺序不敏感，内部会按时间戳排序）
    ///   - previouslyUnlocked: 已经解锁过的里程碑（用于去重，仅返回本次新解锁的）
    ///   - calendar: 计算周边界用的日历，默认 iso8601（周一为周首日）
    ///   - now: "当前时间"，默认 Date()，测试用可注入
    public func analyze(
        sessions: [SessionEntry],
        previouslyUnlocked: Set<String> = [],
        calendar: Calendar = Self.defaultCalendar(),
        now: Date = Date()
    ) -> TrendReport {
        let sorted = sessions.sorted { $0.timestamp < $1.timestamp }

        let weekly = weeklySummaries(from: sorted, calendar: calendar)
        let personalBest = sorted.map(\.averageScore).max()
        let last7 = averageScore(within: 7 * 86400, sessions: sorted, now: now)
        let last30 = averageScore(within: 30 * 86400, sessions: sorted, now: now)
        let highestLevel = highestLevel(from: sorted)

        let allMilestones = detectMilestones(sorted: sorted, weekly: weekly)
        let newOnes = allMilestones.filter { !previouslyUnlocked.contains($0.stableKey) }

        return TrendReport(
            weeklyPoints: weekly,
            newMilestones: newOnes,
            personalBest: personalBest,
            last7DaysAverage: last7,
            last30DaysAverage: last30,
            highestLevelReached: highestLevel
        )
    }

    // MARK: - 周汇总

    /// 把按时间正序排列的 sessions 归到 ISO 周桶，产出折线图数据。
    public func weeklySummaries(
        from sorted: [SessionEntry],
        calendar: Calendar = Self.defaultCalendar()
    ) -> [WeeklySummary] {
        guard !sorted.isEmpty else { return [] }

        // 用 [weekStart: [scores]] 累积
        var buckets: [Date: [Double]] = [:]
        for session in sorted {
            let weekStart = weekStart(for: session.timestamp, calendar: calendar)
            buckets[weekStart, default: []].append(session.averageScore)
        }

        return buckets.keys.sorted().map { weekStart in
            let scores = buckets[weekStart] ?? []
            let sum = scores.reduce(0, +)
            let avg = scores.isEmpty ? 0 : sum / Double(scores.count)
            return WeeklySummary(
                weekStart: weekStart,
                sessionCount: scores.count,
                averageScore: avg,
                bestScore: scores.max() ?? 0,
                worstScore: scores.min() ?? 0
            )
        }
    }

    // MARK: - 里程碑

    /// 从时间正序的 sessions + 周汇总里检测所有可能的里程碑。
    ///
    /// 注意：这里返回"截至当前"的所有里程碑，去重交给调用方（用 stableKey）。
    public func detectMilestones(
        sorted: [SessionEntry],
        weekly: [WeeklySummary]
    ) -> [Milestone] {
        var results: [Milestone] = []

        // 1. 首次达到某级别
        var seenLevels: Set<String> = []
        for session in sorted where !seenLevels.contains(session.overallLevel) {
            seenLevels.insert(session.overallLevel)
            // 只汇报中级及以上的首次
            if Self.levelOrder.firstIndex(of: session.overallLevel) ?? 0 >= 1 {
                results.append(.firstReached(level: session.overallLevel))
            }
        }

        // 2. 单次刷新最高分（每一次超越历史最高都算里程碑）
        var runningBest: Double = -1
        for session in sorted where session.averageScore > runningBest {
            runningBest = session.averageScore
            // 首个 session 不算刷新（没有可比基线）
            if sorted.first?.timestamp != session.timestamp {
                results.append(.newPersonalBest(score: session.averageScore))
            }
        }

        // 3. 相比上周提升 N 分
        for i in 1..<weekly.count {
            let delta = weekly[i].averageScore - weekly[i - 1].averageScore
            if delta >= Self.weeklyImprovementThreshold {
                results.append(.weeklyImprovement(delta: delta))
            }
        }

        // 4. 连续活跃 N 周（≥3 才有意义）
        let streak = longestActiveWeekStreak(weekly: weekly)
        if streak >= 3 {
            results.append(.streak(weeks: streak))
        }

        return results
    }

    // MARK: - 内部工具

    /// 计算 ISO 周（周一为周首）的起始时间。
    private func weekStart(for date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // 周一
        let components = cal.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: date
        )
        return cal.date(from: components) ?? date
    }

    private func averageScore(
        within window: TimeInterval,
        sessions: [SessionEntry],
        now: Date
    ) -> Double? {
        let cutoff = now.addingTimeInterval(-window)
        let recent = sessions.filter { $0.timestamp >= cutoff }
        guard !recent.isEmpty else { return nil }
        return recent.map(\.averageScore).reduce(0, +) / Double(recent.count)
    }

    private func highestLevel(from sessions: [SessionEntry]) -> String? {
        let levels = Set(sessions.map(\.overallLevel))
        return Self.levelOrder.reversed().first { levels.contains($0) }
    }

    /// 找到 weekly 里最长的"连续有分析活动"的周数。
    /// 假设 weekly 按 weekStart 升序排列。相邻两周相差 604800 秒即视为连续。
    private func longestActiveWeekStreak(weekly: [WeeklySummary]) -> Int {
        guard !weekly.isEmpty else { return 0 }
        var maxStreak = 1
        var current = 1
        for i in 1..<weekly.count {
            let dt = weekly[i].weekStart.timeIntervalSince(weekly[i - 1].weekStart)
            // 604_800 = 7 * 86400，允许 ±6 小时抖动（时区/DST）
            if abs(dt - 604_800) <= 21_600 {
                current += 1
                maxStreak = max(maxStreak, current)
            } else {
                current = 1
            }
        }
        return maxStreak
    }

    /// 默认使用系统日历，周一为周首日
    public static func defaultCalendar() -> Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        return cal
    }
}

// MARK: - 里程碑序列化 key

extension Milestone {
    /// 用于持久化去重的稳定 key。
    /// 例如 "firstReached:高级" 或 "personalBest:87" 或 "weeklyImprovement:5"。
    public var stableKey: String {
        switch self {
        case .firstReached(let level):
            return "firstReached:\(level)"
        case .weeklyImprovement(let delta):
            // 精确到 0.5 分，避免浮点噪声导致重复解锁
            let bucket = (delta * 2).rounded() / 2
            return "weeklyImprovement:\(bucket)"
        case .newPersonalBest(let score):
            return "personalBest:\(Int(score.rounded()))"
        case .streak(let weeks):
            return "streak:\(weeks)"
        }
    }
}

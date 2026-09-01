import XCTest
@testable import FallLineCore

// MARK: - 进步曲线分析器测试
//
// 覆盖 TrendAnalytics 4 大能力：
//   1. 周汇总（weeklySummaries）- 桶分组 / 排序 / 空数据
//   2. 里程碑检测（detectMilestones）- 首次达到 / 刷新最高 / 周提升 / 连续活跃
//   3. 去重（previouslyUnlocked + stableKey）
//   4. 综合报告字段（personalBest / last7 / last30 / highestLevel / 空数据兜底）
//
// 所有测试都用 `defaultCalendar()` 的 firstWeekday=2（周一），
// 时间戳基于确定性锚点，避开 DST 时区抖动。

final class TrendAnalyticsTests: XCTestCase {

    private let analytics = TrendAnalytics()

    /// 2026-01-05 (Mon) 12:00 UTC，作为所有测试的时间锚。
    /// 该日期确定为 ISO 周一，方便验证 weekStart 归桶。
    private let anchor: Date = {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 5
        comps.hour = 12
        comps.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .iso8601).date(from: comps)!
    }()

    private func session(
        offsetDays: Double,
        score: Double,
        level: String = "初级"
    ) -> SessionEntry {
        SessionEntry(
            timestamp: anchor.addingTimeInterval(offsetDays * 86400),
            averageScore: score,
            overallLevel: level
        )
    }

    // MARK: - 1. 空数据兜底

    func test_analyze_emptySessions_returnsAllEmptyOrNil() {
        let report = analytics.analyze(sessions: [], now: anchor)

        XCTAssertTrue(report.weeklyPoints.isEmpty)
        XCTAssertTrue(report.newMilestones.isEmpty)
        XCTAssertNil(report.personalBest)
        XCTAssertNil(report.last7DaysAverage)
        XCTAssertNil(report.last30DaysAverage)
        XCTAssertNil(report.highestLevelReached)
    }

    func test_weeklySummaries_emptyInput_returnsEmptyArray() {
        XCTAssertTrue(analytics.weeklySummaries(from: []).isEmpty)
    }

    // MARK: - 2. 周汇总

    func test_weeklySummaries_singleWeek_aggregatesCorrectly() {
        // 同一周内 3 次分析，分数 60 / 80 / 70
        let sessions = [
            session(offsetDays: 0, score: 60),
            session(offsetDays: 1, score: 80),
            session(offsetDays: 2, score: 70)
        ]

        let weekly = analytics.weeklySummaries(from: sessions)

        XCTAssertEqual(weekly.count, 1, "同一周应汇聚为 1 个桶")
        let w = weekly[0]
        XCTAssertEqual(w.sessionCount, 3)
        XCTAssertEqual(w.averageScore, 70.0, accuracy: 0.001)
        XCTAssertEqual(w.bestScore, 80)
        XCTAssertEqual(w.worstScore, 60)
    }

    func test_weeklySummaries_multipleWeeks_sortedAscending() {
        // 跨 3 个日历周：0 天 / 7 天 / 14 天后
        let sessions = [
            session(offsetDays: 14, score: 75),
            session(offsetDays: 0, score: 60),
            session(offsetDays: 7, score: 68)
        ]

        let weekly = analytics.weeklySummaries(from: sessions.sorted { $0.timestamp < $1.timestamp })

        XCTAssertEqual(weekly.count, 3)
        XCTAssertLessThan(weekly[0].weekStart, weekly[1].weekStart)
        XCTAssertLessThan(weekly[1].weekStart, weekly[2].weekStart)
        XCTAssertEqual(weekly[0].averageScore, 60)
        XCTAssertEqual(weekly[1].averageScore, 68)
        XCTAssertEqual(weekly[2].averageScore, 75)
    }

    // MARK: - 3. 里程碑检测

    func test_detectMilestones_firstReached_reportsMidAndAboveOnly() {
        // 依次达到 初级 → 中级 → 高级
        let sessions = [
            session(offsetDays: 0, score: 40, level: "初级"),
            session(offsetDays: 1, score: 62, level: "中级"),
            session(offsetDays: 2, score: 82, level: "高级")
        ]
        let weekly = analytics.weeklySummaries(from: sessions)
        let milestones = analytics.detectMilestones(sorted: sessions, weekly: weekly)

        // 初级不上报，中级 + 高级各上报一次
        let firstReached = milestones.compactMap { m -> String? in
            if case .firstReached(let level) = m { return level } else { return nil }
        }
        XCTAssertEqual(firstReached, ["中级", "高级"])
        XCTAssertFalse(firstReached.contains("初级"), "初级不应触发首次达到里程碑")
    }

    func test_detectMilestones_personalBest_skipsFirstSession() {
        // 首个 session 不算刷新，之后每次超越前值算一次
        let sessions = [
            session(offsetDays: 0, score: 50),
            session(offsetDays: 1, score: 60), // 刷新 +1
            session(offsetDays: 2, score: 55), // 不刷新
            session(offsetDays: 3, score: 70)  // 刷新 +1
        ]
        let weekly = analytics.weeklySummaries(from: sessions)
        let milestones = analytics.detectMilestones(sorted: sessions, weekly: weekly)

        let bests = milestones.compactMap { m -> Double? in
            if case .newPersonalBest(let s) = m { return s } else { return nil }
        }
        XCTAssertEqual(bests, [60, 70])
    }

    func test_detectMilestones_weeklyImprovement_triggersOnDeltaThreshold() {
        // 第 1 周平均 60，第 2 周平均 65（+5 ≥ 阈值 3）
        let sessions = [
            session(offsetDays: 0, score: 60),
            session(offsetDays: 7, score: 65)
        ]
        let weekly = analytics.weeklySummaries(from: sessions)
        let milestones = analytics.detectMilestones(sorted: sessions, weekly: weekly)

        let improvements = milestones.compactMap { m -> Double? in
            if case .weeklyImprovement(let d) = m { return d } else { return nil }
        }
        XCTAssertEqual(improvements.count, 1)
        XCTAssertEqual(improvements[0], 5.0, accuracy: 0.001)
    }

    func test_detectMilestones_weeklyImprovement_belowThreshold_notFired() {
        // 第 2 周比第 1 周只提升 2 分，低于阈值 3
        let sessions = [
            session(offsetDays: 0, score: 60),
            session(offsetDays: 7, score: 62)
        ]
        let weekly = analytics.weeklySummaries(from: sessions)
        let milestones = analytics.detectMilestones(sorted: sessions, weekly: weekly)

        let hasImprovement = milestones.contains { if case .weeklyImprovement = $0 { return true }; return false }
        XCTAssertFalse(hasImprovement, "低于阈值不应触发周提升里程碑")
    }

    func test_detectMilestones_streak_requiresThreeConsecutiveWeeks() {
        // 连续 3 周活跃：offset 0 / 7 / 14
        let sessions = [
            session(offsetDays: 0, score: 60),
            session(offsetDays: 7, score: 62),
            session(offsetDays: 14, score: 64)
        ]
        let weekly = analytics.weeklySummaries(from: sessions)
        let milestones = analytics.detectMilestones(sorted: sessions, weekly: weekly)

        let streaks = milestones.compactMap { m -> Int? in
            if case .streak(let w) = m { return w } else { return nil }
        }
        XCTAssertEqual(streaks, [3])
    }

    func test_detectMilestones_singleWeek_noWeeklyImprovementNoStreakNoCrash() {
        // 覆盖 weekly.count == 1 真空区：
        // 之前只覆盖了 0（emptySessions）与 ≥2（跨周），
        // 这里补齐"多 session 但都在同一周"的边界，
        // 守护 detectMilestones L236 的 `if weekly.count >= 2` guard。
        let sessions = [
            session(offsetDays: 0, score: 60, level: "初级"),
            session(offsetDays: 1, score: 68, level: "中级"),
            session(offsetDays: 2, score: 82, level: "高级")
        ]
        let weekly = analytics.weeklySummaries(from: sessions)
        XCTAssertEqual(weekly.count, 1, "3 次 session 应汇聚到同一周")

        let milestones = analytics.detectMilestones(sorted: sessions, weekly: weekly)

        // 1. weeklyImprovement 必须为空（只有 1 周，无上周可比）
        let hasImprovement = milestones.contains {
            if case .weeklyImprovement = $0 { return true }
            return false
        }
        XCTAssertFalse(hasImprovement, "只有 1 周数据不应触发 weeklyImprovement")

        // 2. streak 必须为空（1 周 < 阈值 3）
        let hasStreak = milestones.contains {
            if case .streak = $0 { return true }
            return false
        }
        XCTAssertFalse(hasStreak, "只有 1 周数据不应触发 streak")

        // 3. firstReached 和 newPersonalBest 仍应正常上报（独立于 weekly 判定）
        let firstReached = milestones.compactMap { m -> String? in
            if case .firstReached(let level) = m { return level } else { return nil }
        }
        XCTAssertEqual(firstReached, ["中级", "高级"], "同周内的等级提升仍应正常检测")

        let bests = milestones.compactMap { m -> Double? in
            if case .newPersonalBest(let s) = m { return s } else { return nil }
        }
        XCTAssertEqual(bests, [68, 82], "同周内连续刷新最高分仍应正常检测")
    }

    func test_detectMilestones_streak_gapBreaksChain() {
        // 中间断一周（offset 0 / 7 / 21）→ 最长连续只有 2
        let sessions = [
            session(offsetDays: 0, score: 60),
            session(offsetDays: 7, score: 62),
            session(offsetDays: 21, score: 64)
        ]
        let weekly = analytics.weeklySummaries(from: sessions)
        let milestones = analytics.detectMilestones(sorted: sessions, weekly: weekly)

        let hasStreak = milestones.contains { if case .streak = $0 { return true }; return false }
        XCTAssertFalse(hasStreak, "最长连续只有 2 周，streak 不应触发（阈值 ≥3）")
    }

    // MARK: - 4. previouslyUnlocked 去重

    func test_analyze_filtersOutPreviouslyUnlockedMilestones() {
        let sessions = [
            session(offsetDays: 0, score: 40, level: "初级"),
            session(offsetDays: 1, score: 65, level: "中级"),
            session(offsetDays: 2, score: 85, level: "高级")
        ]
        // 假装"中级已经解锁过"
        let previously: Set<String> = ["firstReached:中级"]

        let report = analytics.analyze(
            sessions: sessions,
            previouslyUnlocked: previously,
            now: anchor.addingTimeInterval(3 * 86400)
        )

        let firstReachedLevels = report.newMilestones.compactMap { m -> String? in
            if case .firstReached(let level) = m { return level } else { return nil }
        }
        XCTAssertEqual(firstReachedLevels, ["高级"], "已解锁的中级里程碑应被过滤掉，只剩新的高级")
    }

    // MARK: - 5. 综合报告字段

    func test_analyze_personalBestAndLastNDays() {
        // 30 天窗口边界：now-3d / now-10d / now-40d
        let sessions = [
            session(offsetDays: -40, score: 40),
            session(offsetDays: -10, score: 70),
            session(offsetDays: -3, score: 85)
        ]
        let report = analytics.analyze(sessions: sessions, now: anchor)

        XCTAssertEqual(report.personalBest, 85)
        // last7 只包含 now-3d 一条：85
        XCTAssertEqual(report.last7DaysAverage ?? -1, 85, accuracy: 0.001)
        // last30 包含 now-10d 和 now-3d：(70+85)/2 = 77.5
        XCTAssertEqual(report.last30DaysAverage ?? -1, 77.5, accuracy: 0.001)
    }

    func test_analyze_highestLevelReached_picksTopOfHierarchy() {
        let sessions = [
            session(offsetDays: 0, score: 60, level: "中级"),
            session(offsetDays: 1, score: 88, level: "高级"),
            session(offsetDays: 2, score: 55, level: "初级")
        ]
        let report = analytics.analyze(sessions: sessions, now: anchor.addingTimeInterval(3 * 86400))
        XCTAssertEqual(report.highestLevelReached, "高级")
    }

    // MARK: - 6. stableKey 稳定性

    func test_milestoneStableKey_isDeterministicAcrossCases() {
        XCTAssertEqual(Milestone.firstReached(level: "高级").stableKey, "firstReached:高级")
        XCTAssertEqual(Milestone.streak(weeks: 5).stableKey, "streak:5")
        // personalBest 四舍五入到整数
        XCTAssertEqual(Milestone.newPersonalBest(score: 82.4).stableKey, "personalBest:82")
        XCTAssertEqual(Milestone.newPersonalBest(score: 82.6).stableKey, "personalBest:83")
        // weeklyImprovement 精确到 0.5
        XCTAssertEqual(Milestone.weeklyImprovement(delta: 5.24).stableKey, "weeklyImprovement:5.0")
        XCTAssertEqual(Milestone.weeklyImprovement(delta: 5.26).stableKey, "weeklyImprovement:5.5")
    }

    // MARK: - 7. Codable 往返

    func test_sessionEntry_codableRoundtrip() throws {
        let original = SessionEntry(
            timestamp: anchor,
            averageScore: 72.5,
            overallLevel: "中级",
            stabilityScore: 80,
            bestFrameScore: 90
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionEntry.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

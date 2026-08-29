import Foundation
import Combine
import FallLineCore

/// 进步曲线本地持久化 & 分析中枢。
///
/// 职责：
/// - 每次分析结束把 `VideoSummary` 摘要成一条 `SessionEntry` 写入 UserDefaults
/// - 保存已解锁的里程碑集合，避免重复推送
/// - 对 `VideoAnalysisManager` 暴露单一 API：`record(summary:)`
/// - 对 `TrendView` 暴露单一 API：`report()` → `TrendReport`
///
/// 采用 UserDefaults 而非文件，理由：
///   1. 数据量小（每次分析 ~200 字节，1000 次 = 200KB）
///   2. iCloud 同步天然（UserDefaults.standard 可以升级到 NSUbiquitousKeyValueStore）
///   3. 主线程读性能足够，无需 async
@MainActor
public final class TrendStore: ObservableObject {

    // MARK: - Keys

    private static let sessionsKey = "fallline.trend.sessions.v1"
    private static let unlockedMilestonesKey = "fallline.trend.unlockedMilestones.v1"

    // MARK: - State

    @Published public private(set) var sessions: [SessionEntry] = []
    @Published public private(set) var lastReport: TrendReport?

    private let defaults: UserDefaults
    private let analytics = TrendAnalytics()

    /// 已经推送过的里程碑 stableKey，避免重复解锁
    private var unlockedMilestoneKeys: Set<String> = []

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadSessions()
        loadUnlockedMilestones()
    }

    // MARK: - Public API

    /// 记录一次新的分析结果，并返回本次新解锁的里程碑（供 UI/推送使用）。
    @discardableResult
    public func record(
        timestamp: Date = Date(),
        averageScore: Double,
        overallLevel: String,
        stabilityScore: Double? = nil,
        bestFrameScore: Double? = nil
    ) -> [Milestone] {
        let entry = SessionEntry(
            timestamp: timestamp,
            averageScore: averageScore,
            overallLevel: overallLevel,
            stabilityScore: stabilityScore,
            bestFrameScore: bestFrameScore
        )
        sessions.append(entry)
        persistSessions()
        return refreshReport().newMilestones
    }

    /// 无参重算，供 TrendView.onAppear 使用。
    @discardableResult
    public func refreshReport() -> TrendReport {
        let report = analytics.analyze(
            sessions: sessions,
            previouslyUnlocked: unlockedMilestoneKeys
        )
        // 把新里程碑标记为已解锁，防止下次重复出现
        for m in report.newMilestones {
            unlockedMilestoneKeys.insert(m.stableKey)
        }
        persistUnlockedMilestones()
        lastReport = report
        return report
    }

    /// 清空所有埋点与里程碑（调试 / 用户主动重置）
    public func reset() {
        sessions = []
        unlockedMilestoneKeys = []
        defaults.removeObject(forKey: Self.sessionsKey)
        defaults.removeObject(forKey: Self.unlockedMilestonesKey)
        lastReport = nil
    }

    // MARK: - Persistence

    private func loadSessions() {
        guard let data = defaults.data(forKey: Self.sessionsKey),
              let decoded = try? JSONDecoder().decode([SessionEntry].self, from: data)
        else { return }
        sessions = decoded
    }

    private func persistSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: Self.sessionsKey)
    }

    private func loadUnlockedMilestones() {
        guard let arr = defaults.array(forKey: Self.unlockedMilestonesKey) as? [String] else { return }
        unlockedMilestoneKeys = Set(arr)
    }

    private func persistUnlockedMilestones() {
        defaults.set(Array(unlockedMilestoneKeys), forKey: Self.unlockedMilestonesKey)
    }
}

import Foundation
import UserNotifications
import FallLineCore

@MainActor
public final class TrendNotificationCenter {

    public static let shared = TrendNotificationCenter()

    private let center: UNUserNotificationCenter
    private let categoryIdentifier = "fallline.milestone"

    private static let didRequestAuthorizationKey = "fallline.trend.notification.didRequestAuthorization.v1"

    public private(set) var isAuthorized: Bool = false

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func bootstrapIfNeeded() async {
        await refreshAuthorizationStatus()
        guard !UserDefaults.standard.bool(forKey: Self.didRequestAuthorizationKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.didRequestAuthorizationKey)
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    public func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = (settings.authorizationStatus == .authorized
                        || settings.authorizationStatus == .provisional
                        || settings.authorizationStatus == .ephemeral)
    }

    public func scheduleMilestoneNotifications(_ milestones: [Milestone]) async {
        guard !milestones.isEmpty else { return }
        await refreshAuthorizationStatus()
        guard isAuthorized else { return }

        for milestone in milestones {
            await schedule(milestone: milestone)
        }
    }

    private func schedule(milestone: Milestone) async {
        let content = UNMutableNotificationContent()
        content.title = title(for: milestone)
        content.body = milestone.displayTitle
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = ["milestoneKey": milestone.stableKey]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(
            identifier: "milestone.\(milestone.stableKey)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            #if DEBUG
            print("[TrendNotificationCenter] schedule failed: \(error)")
            #endif
        }
    }

    private func title(for milestone: Milestone) -> String {
        switch milestone {
        case .firstReached:
            return "🎿 新级别达成"
        case .weeklyImprovement:
            return "📈 本周进步"
        case .newPersonalBest:
            return "🏆 刷新记录"
        case .streak:
            return "🔥 连续活跃"
        }
    }

    public func cancelAllPending() {
        center.removeAllPendingNotificationRequests()
    }
}

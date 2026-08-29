import SwiftUI

@main
struct SkiAnaylzeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // 首次启动请求本地通知权限（幂等）
                    await TrendNotificationCenter.shared.bootstrapIfNeeded()
                }
        }
    }
}

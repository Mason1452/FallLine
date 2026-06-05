import SwiftUI

/// 广告提供者协议 — 后续接入真实广告 SDK 时，创建新的遵循此协议的实现即可
protocol AdProvider {
    /// 在开屏页面底部展示的广告视图
    func makeSplashAdView() -> AnyView

    /// 广告是否就绪可展示
    var isAdReady: Bool { get }
}

/// 默认广告提供者 — 不展示任何广告内容
struct DefaultAdProvider: AdProvider {
    func makeSplashAdView() -> AnyView {
        AnyView(EmptyView())
    }

    var isAdReady: Bool { false }
}

// MARK: - 环境变量注入

private struct AdProviderKey: EnvironmentKey {
    static let defaultValue: AdProvider = DefaultAdProvider()
}

extension EnvironmentValues {
    var adProvider: AdProvider {
        get { self[AdProviderKey.self] }
        set { self[AdProviderKey.self] = newValue }
    }
}

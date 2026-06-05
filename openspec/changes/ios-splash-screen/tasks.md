## 1. 广告接口

- [x] 1.1 新建 `SkiAnaylze/SkiAnaylze/Services/AdProvider.swift`，定义 `AdProvider` 协议（提供开屏广告视图 + 广告就绪状态），实现 `DefaultAdProvider`（空视图）和 `AnyAdProvider`（类型擦除包装器）

## 2. 开屏视图

- [x] 2.1 新建 `SkiAnaylze/SkiAnaylze/Views/SplashView.swift`，实现滑雪主题开屏动画视图（背景渐变 + MountainSilhouette + CarvingTrace + GridOverlay + Logo 文字）
- [x] 2.2 实现 4 阶段动画序列：阶段 1（0.0s–0.5s）背景 + 山峰、阶段 2（0.5s–1.0s）网格 + 副标题、阶段 3（1.0s–1.5s）主标题 + 轨迹、阶段 4（1.5s–3.0s）倒计时环
- [x] 2.3 添加右上角「跳过 >」半透明胶囊按钮，点击后触发 onSkip 回调
- [x] 2.4 添加底部广告预留区域，通过环境变量获取 `AdProvider` 并渲染广告视图

## 3. 根视图与状态管理

- [x] 3.1 新建 `SkiAnaylze/SkiAnaylze/Views/RootView.swift`，实现 splash → content 状态切换（`@State showSplash`），3 秒自动切换 + 跳过按钮回调 + 0.3 秒淡入淡出过渡

## 4. 入口修改

- [x] 4.1 修改 `SkiAnaylze/SkiAnaylze/SkiAnaylzeApp.swift`，将 `WindowGroup` 中的 `ContentView()` 替换为 `RootView()`，注入 `DefaultAdProvider` 到环境变量

## 5. 验证

- [x] 5.1 在 iOS 模拟器中运行应用，验证开屏动画完整播放 3 秒后自动进入主页面
- [x] 5.2 验证点击「跳过」按钮可提前进入主页面，过渡动画为淡入淡出
- [x] 5.3 验证开屏期间的广告预留区域在默认情况下不显示内容
- [x] 5.4 验证进入主页面后所有现有功能正常（分析、历史记录）

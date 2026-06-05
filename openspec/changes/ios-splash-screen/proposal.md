## 为什么

当前应用启动后直接进入主页面，缺少品牌展示和过渡体验。新增一个符合滑雪主题的开屏页面，可以在 3 秒内展示品牌形象，同时预留广告位，为后续商业化打下基础。

## 变更内容

- **新增** RootView 作为应用根视图，管理开屏 → 主页面状态切换
- **新增** SplashView 实现滑雪主题开屏动画（山峰显现 + 刻滑轨迹绘制 + Logo 渐入）
- **新增** AdProvider 协议及默认空实现，预留广告接口
- **修改** SkiAnaylzeApp 入口，使用 RootView 替代直接显示的 ContentView
- 开屏动画 3 秒，用户可通过右上角「跳过」按钮提前进入主页面

## 能力

### 新能力

- `splash-screen`: 启动开屏页面，包含 3 秒滑雪主题动画、跳过按钮、广告预留位

### 修改的能力

（无现有能力被修改）

## 影响

- 影响文件：`SkiAnaylzeApp.swift`、新增 `RootView.swift`、`SplashView.swift`、`AdProvider.swift`
- 不影响：评分算法、分析流水线、数据持久化、现有 UI 页面
- 依赖：复用 `AppTheme.swift` 中现有视觉组件（MountainSilhouette、CarvingTrace、GridOverlay、颜色系统）

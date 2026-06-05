## 上下文

当前应用（SkiAnaylze）的入口 `SkiAnaylzeApp.swift` 直接渲染 `ContentView`，没有启动过渡页面。系统启动画面由 Xcode 自动生成（`UILaunchScreen_Generation = YES`），为纯黑色背景。

应用已有完善的 Ice Sport Technology 设计系统（`AppTheme.swift`），包含：
- 深色主题颜色系统（`fallLineNight`、`fallLineNavy`、`fallLineCyan`、`fallLineMint` 等）
- 可复用视觉组件：`MountainSilhouette` 形状、`CarvingTrace` 波形轨迹、`GridOverlay` 网格叠加
- 渐变背景 `FallLineBackground`

iOS 应用完全不包含广告相关代码，需从零设计广告接口。

## 目标 / 非目标

**目标：**
- 应用启动后展示 3 秒滑雪主题开屏动画
- 用户可通过「跳过」按钮提前结束开屏
- 预留广告接口，后续可接入任意广告 SDK，无需修改开屏页面代码
- 100% 复用现有设计系统组件，保持视觉一致性

**非目标：**
- 不实现真实广告 SDK 接入（仅预留接口和默认空实现）
- 不修改系统启动画面（Launch Screen）
- 不影响评分算法、分析流水线、数据持久化
- 不添加第三方依赖

## 决策

### 决策 1：采用 SwiftUI 视图层开屏，而非修改 Launch Screen

**选型**：在 `SkiAnaylzeApp` 中插入 `RootView` 作为根视图，管理 splash → content 状态切换。

**理由**：
- iOS Launch Screen 不支持动画和交互（只能是静态 storyboard）
- SwiftUI 层实现可以复用所有现有组件和动画能力
- 过渡流畅：开屏淡出 + 主页面淡入

**备选方案**：自定义 LaunchScreen.storyboard + 应用层开屏。被拒绝原因：增加复杂度，且系统启动画面极短（< 1s），不需要定制。

### 决策 2：动画方案 — 山峰显现 + 刻滑轨迹绘制

**选型**：分阶段动画序列，时长 3 秒：

```
0.0s ───── 0.5s ───── 1.0s ───── 1.5s ───── 2.0s ───── 3.0s
  │          │          │          │          │          │
背景渐变  网格淡入  副标题淡入  Logo缩放   倒计时环   自动进入
山峰上移  山峰持续  轨迹绘制   轨迹完成   倒计时归零  主页面
```

**理由**：
- 复用现有 `MountainSilhouette`（山峰剪影）、`CarvingTrace`（刻滑轨迹）、`GridOverlay`（网格）
- 延续 Ice Sport Technology 视觉方向
- 分阶段动画比单一循环动画更有层次感

**备选方案**：
- 雪花粒子动画：需要新建粒子系统（`CAEmitterLayer`），开发量大，且粒子动画与现有 HUD/科技风格不完全匹配
- 扫描准星动画：与 App Icon 呼应但视觉冲击力不够

### 决策 3：广告接口 — 协议导向设计

**选型**：定义 `AdProvider` 协议，通过 SwiftUI 环境变量注入。

```swift
protocol AdProvider {
    associatedtype SplashAdContent: View
    func makeSplashAdView() -> SplashAdContent
    var isAdReady: Bool { get }
}
```

使用 `AnyAdProvider` 类型擦除包装器注入环境：

```swift
struct AnyAdProvider: AdProvider {
    // 类型擦除包装
}

struct DefaultAdProvider: AdProvider {
    // 默认空实现 — 无广告展示
}
```

**理由**：
- 后续接入真实 SDK 只需新建遵循 `AdProvider` 的实现类
- 测试时可注入 mock 实现
- 不引入第三方依赖

**备选方案**：直接在 `SplashView` 中硬编码广告位。被拒绝原因：后续接入广告需要修改 `SplashView`，违反开闭原则。

### 决策 4：跳过按钮位置与样式

**选型**：右上角半透明胶囊按钮，文字「跳过 >」。

- 位置：`.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)` + `.padding(24)`
- 样式：`GlassPanel` 风格 — `.ultraThinMaterial` + 圆角胶囊
- 行为：点击后 0.3s 淡出动画过渡到 ContentView

**理由**：右上角是 iOS 跳过按钮的常见位置，用户预期一致。

## 风险 / 权衡

- **[风险] 开屏期间 VideoAnalysisManager 已初始化** → **缓解**：`ContentView` 创建时初始化 `VideoAnalysisManager`（加载历史数据），开屏期间不阻塞。如果历史数据极大（>1000 条）可能影响启动耗时，但当前用户规模下不太可能发生
- **[风险] 低端设备动画卡顿** → **缓解**：使用 SwiftUI 原生动画（`easeInOut`、`spring`），所有视觉元素为矢量 Shape，不加载图片资源
- **[权衡] 3 秒固定时长可能让部分用户觉得慢** → 提供跳过按钮作为缓解手段

## 迁移计划

无需迁移。新增功能，不修改现有行为。

部署步骤：
1. 合并代码到 main
2. 构建 iOS 应用
3. 验证启动流程：开屏动画 3 秒 → 自动进入主页面 / 点击跳过 → 进入主页面

回滚：移除 `RootView` 包装，恢复 `SkiAnaylzeApp` 直接渲染 `ContentView`。

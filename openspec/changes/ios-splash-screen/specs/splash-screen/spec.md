## ADDED Requirements

### Requirement: 应用启动时展示开屏动画

系统 SHALL 在应用启动后展示一个 3 秒的滑雪主题开屏动画，动画完成后自动进入主页面。

动画组件 SHALL 复用 AppTheme 中的 `MountainSilhouette` 形状作为山峰视觉元素，`CarvingTrace` 形状作为刻滑轨迹视觉元素，`GridOverlay` 作为背景网格视觉元素。

动画 SHALL 按以下阶段执行：
1. 0.0s–0.5s：背景渐变显现，山峰剪影从底部向上移动
2. 0.5s–1.0s：网格淡入，副标题"AI SKI MOTION COACH"淡入
3. 1.0s–1.5s："FALL LINE" 主标题缩放弹出，刻滑轨迹从左至右绘制
4. 1.5s–3.0s：冰蓝环形倒计时进度环从满到空

动画完成后，系统 SHALL 以 0.3 秒淡入淡出过渡切换到 `ContentView`。

#### Scenario: 正常启动流程

- **WHEN** 用户打开应用
- **THEN** 展示开屏动画，3 秒后自动进入主页面，过渡动画为 0.3 秒淡入淡出

#### Scenario: 动画阶段顺序

- **WHEN** 开屏页面显示
- **THEN** 动画严格按照 4 个阶段的顺序执行，不允许阶段跳跃或乱序

### Requirement: 用户可跳过开屏动画

系统 SHALL 在开屏页面右上角提供一个文字为「跳过 >」的半透明胶囊按钮。

用户点击跳过按钮或开屏动画自然完成后，系统 SHALL 执行相同的 0.3 秒淡出过渡进入 `ContentView`。

跳过按钮 SHALL 在开屏页面显示的第一帧即可交互。

#### Scenario: 用户点击跳过

- **WHEN** 用户在开屏动画播放期间点击右上角「跳过 >」按钮
- **THEN** 开屏页面以 0.3 秒淡出，然后显示主页面

#### Scenario: 动画自然结束

- **WHEN** 开屏动画完整播放 3 秒
- **THEN** 开屏页面以 0.3 秒淡出，然后显示主页面，效果与点击跳过完全一致

### Requirement: 广告接口预留

系统 SHALL 定义 `AdProvider` 协议，包含以下能力：
- 提供一个 SwiftUI 视图用于在开屏页面底部展示广告内容
- 提供一个布尔属性表示广告是否就绪

系统 SHALL 提供 `DefaultAdProvider` 作为默认实现，该实现不展示任何广告内容（空视图）。

系统 SHALL 通过 SwiftUI 环境变量机制注入 `AdProvider`，使 `SplashView` 无需硬编码广告逻辑。

#### Scenario: 默认无广告

- **WHEN** 应用使用 `DefaultAdProvider`（默认情况）
- **THEN** 开屏页面底部广告区域不显示任何内容

#### Scenario: 替换广告实现

- **WHEN** 开发者创建新的 `AdProvider` 实现并注入环境变量
- **THEN** 开屏页面底部显示新实现提供的广告内容，无需修改 `SplashView` 代码

### Requirement: RootView 管理启动状态

系统 SHALL 新增 `RootView` 作为应用的根视图，负责管理开屏页面到主页面之间的状态切换。

`RootView` SHALL 使用 `@State` 属性 `showSplash` 控制显示状态：
- 初始值为 `true`，显示 `SplashView`
- 开屏动画完成或用户点击跳过后，设置为 `false`，显示 `ContentView`

`ContentView` 在 `RootView` 中 SHALL 保持与现有逻辑完全一致，不修改其内部实现。

#### Scenario: 状态切换

- **WHEN** `showSplash` 变为 `false`
- **THEN** `RootView` 用 `ContentView` 替换 `SplashView`，过渡动画为 0.3 秒淡入淡出

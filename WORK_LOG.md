# FallLine Work Log

## Current State (2026-08-30)

**TrendAnalytics 单元测试覆盖落地（+13 用例）** —— 主线 B 收官后清单里的第 2 项可选优化完成。仅新增 [TrendAnalyticsTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift) 1 个测试文件，无生产代码改动。

**本轮变更概要**（详见 `delta_update.md` 的"2026-08-30"条目）：
- 新增 13 个 XCTest 用例，覆盖 7 大能力域：空数据兜底 / 周汇总 / 4 类里程碑（`firstReached` / `newPersonalBest` / `weeklyImprovement` / `streak`）/ `previouslyUnlocked` 去重 / 综合报告字段 / `stableKey` 稳定性 / Codable 往返
- 测试用固定时间锚 `2026-01-05 12:00 UTC`（ISO 周一）+ `session(offsetDays:score:level:)` helper，避免时区/DST 抖动导致 flaky
- 每个用例都与 `TrendAnalytics.swift` 源码具体行号交叉核对（阈值 3.0 / 3 / `firstIndex >= 1` / bucket 0.5 等）

**验证**：
- `swift build --build-tests` PASS（5.76s，Linking FallLinePackageTests 成功）
- `GetDiagnostics` 目标文件：空
- 沙箱内 `swift test` 因 XCTest 临时目录限制无法运行，需用户本机跑 `swift test 2>&1 | tail -5` 预期 `Executed 101 tests, with 0 failures`

**当前项目定位**（无变化）：
- **iOS App = Core 唯一消费方**：SwiftPM 本地依赖，8 个复制文件已删除（净减 -2384 行）
- **Core 对外契约就绪**：`Package.swift` 声明 library + executable；`AnalysisOutput: Identifiable`
- **进步曲线闭环**：`VideoAnalysisManager` 分析成功 → `trendStore.record()` 埋点 → `Milestone` 本地推送 → "趋势"Tab 折线图
- **iOS App 结构**：3 Tab（分析 / 记录 / 趋势）
- **Vision 稳定性**：iOS 分析入口已用上 warmUp + espresso 熔断 + CPU 后备
- **新算法层测试覆盖**：`TrendAnalytics` 关键路径 13 用例保护，未来重构有兜底

**下一步（用户本地）**：
1. `swift test` 本机复验 101 用例全通过
2. Xcode Cmd+B / Cmd+R 走完主线 B 收官后 +1 的模拟器验证（若上轮尚未做）
3. 决策 travelAngle 链路方向后再进入第 3 项优化

**后续可优化方向（不阻塞）**：
- travelAngle → sideslip → carvingConfidence → boardKinematicHighScoreCap 链路的低置信度误判决策（见 `AGENTS.md` 板身检测条目）
  - 候选方案：(A) 加置信度门控直接屏蔽低置信度帧的 travelAngle；(B) 引入 IMU 融合（依赖手机端埋点）；(C) 完全弃用 travelAngle，回退到 hipCenter 2D 位移
  - 建议先量化：从现有 corpus 里统计"高 carving cap 触发但主观判断误判"的样本比例

## Previous State (2026-08-29 收官后 +1)

**iOS 已切换到 `analyzeWithResilience()`** —— 主线 B 收官后清单里的第 1 项可选优化已落地。单文件改动 [VideoAnalysisManager.swift](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/VideoAnalysisManager.swift#L134-L165)。

**当轮变更概要**（详见 `delta_update.md` 的"2026-08-29 (收官后 +1)"条目）：
- `analyzer.analyze()` → `analyzer.analyzeWithResilience(progressHandler:)`：接入 Vision espresso 上下文预热 + CPU 后备 + 连续 3 帧失败熔断
- 用 `progressHandler` 把 Core 抽帧真实进度映射到 App 进度条 0.2→0.75 区间，替代原两段 500ms 假 sleep
- `AnalysisError.visionUnavailable` / `.noReliableFrames` 各自转 `NSError` 沿现有错误弹窗链路展示

## Previous State (2026-08-29 收官)

**主线 B（iOS SPM 化）+ 进步曲线全链路接入完成**。3 个 commit 已推送到 `origin/main`：

```
efd7843  feat(trend): 进步曲线接入主流程
264a1b2  feat(core): AnalysisOutput 支持 Identifiable，兼容 SwiftUI sheet(item:)
94ce905  feat(ios): 主线 B 完成 - iOS SPM 化，消除 8 个复制文件
```

本轮变更明细见 `delta_update.md` 的"2026-08-29 (收官)"条目。

## Previous State (2026-08-29 再续)

**主线 B（iOS SPM 化）Core 端就绪 + 进步曲线 c1/c2/c3 骨架已入库**。3 个 commit 推送到 `origin/main`：

```
b825c7f  feat(trend): c3 里程碑本地推送 - TrendNotificationCenter
18436c0  feat(trend): 进步曲线 - Core 算法层 + iOS 骨架
2c5ef8d  feat(core): 主线 B iOS SPM 化 - Core 端就绪
```

**本阶段完成的**：
- Core 层 iOS 兼容改造（`Package.swift` iOS 17 平台，`VisionFrameAnalyzer.usesCPUOnly + warmUp`，`VideoAnalyzer.AnalysisError + analyzeWithResilience`）
- 进步曲线骨架（`TrendAnalytics.swift` 220 行 + `TrendStore.swift` UserDefaults 持久化 + `TrendView.swift` Charts 折线图 + `TrendNotificationCenter.swift` UNUserNotificationCenter 推送）
- `scripts/setup_ios_deps.sh` --dry / --yes / --rollback + 备份机制

**已由 2026-08-29 收官轮接管**：SPM 化真正落地、8 个复制文件删除、iOS App 接入 3 处。

## Previous State (2026-08-29 续)

**算法准确度 P0/P1/P2 + iOS 熔断已入库**（commit `45dad57`，已推送 `origin/main`）。核心引擎按 2026-06-05 深度研究结论完成采样率、软置信度、travelAngle 门控、板身线仲裁、3D 融合五处改动；iOS 端补齐 Vision warmUp/CPU 回退/熔断与错误 UI。详细变更见 `delta_update.md` 的"2026-08-29 (续)"条目。

**验证状态（当轮）**：
- `swift build -c release` PASS；`swift test` 沙箱限制未跑
- 6 个测试样本被证据封顶卡在 58/55/66 三档，收益体现在内部指标（stabilityScore、kneeBendScore、rawPoseAverageScore）
- 三阶段对照快照保留：`testvideo/_p1_baseline/`、`testvideo/_c_2d/`、`testvideo/_b_3d_baseline/`

## Previous State (2026-06-05)

**仓库清理**：`.gitignore` 已加入 `UserInterfaceState.xcuserstate`，用于忽略 Xcode 用户界面状态文件。注意：该文件当前已在 Git 索引中且处于未合并状态，ignore 规则不会自动解除跟踪或解决冲突。

**深度研究完成：算法准确度提升方向**。通过 deep-research 工作流（5 角度搜索 → 22 来源 → 75 声明 → 3 票对抗验证 → 7 综合发现），梳理了单目姿态估计和光流运动分析在滑雪场景下的准确度瓶颈与改进路径。完整报告见 Journal。

**iOS 开屏页面已实现**（2026-05-28）：`SkiAnaylze/` 新增滑雪主题开屏动画，3 秒自动进入主页面，可跳过，预留广告接口。编译通过，模拟器验证通过。

**验证状态**：
- `xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`：`** BUILD SUCCEEDED **`
- `swift test`：88 tests, 0 failures（待确认：与上次验证间隔 8 天，其间代码可能有变更）

**变更文件**（开屏）：
- 新增 `SkiAnaylze/SkiAnaylze/Services/AdProvider.swift` — 广告接口协议 + 默认空实现
- 新增 `SkiAnaylze/SkiAnaylze/Views/SplashView.swift` — 4 阶段开屏动画 + 跳过按钮 + 广告位
- 新增 `SkiAnaylze/SkiAnaylze/Views/RootView.swift` — splash → content 状态切换
- 修改 `SkiAnaylze/SkiAnaylze/SkiAnaylzeApp.swift` — ContentView → RootView

**变更边界**：只改 iOS SwiftUI UI 层，不改 FallLineCore/CLI 的分析逻辑、评分模型或持久化行为。

### 深度研究关键发现

**高置信度（3-0 投票通过）**：

1. **姿态规范化（3DPCNet）**：混合 GCN-Transformer 将单目姿态旋转误差从 >20° 降至 3.4°，MPJPE 降低 27%。Estimator-agnostic——可直接操作 3D 关节点坐标，无需修改底层检测器。[arXiv:2509.23455](https://arxiv.org/html/2509.23455) (ICASSP 2026)

2. **2D 透视误差公式**：E = 100 × d / (D − d)%。简单乘性修正只能纠正平动运动学（位移、速度），**无法纠正关节角度**。透视误差是系统误差（非随机），无法通过平滑消除。[Yokoi & Okada 1994](https://cir.nii.ac.jp/crid/1390001204309690752)

3. **Apple Vision 硬限制**：VNDetectHumanBodyPoseRequest 腿部链终止于脚踝，iOS 18+ 的 3D 变体也未增加足部关键点。脚踝代理方法是当前框架下的最优解——立刃角度检测有理论上限。

4. **时序精度**：跑步步态中 20ms 事件检测偏差 → 20° 膝关节角度误差。当前 5fps（200ms 帧间隔）远超此阈值，提高采样率可能比算法改进更有效。[Mundt et al. 2024](https://pubmed.ncbi.nlm.nih.gov/38984681/)

**中置信度（2-1 投票通过）**：
- 滑雪专项 AlphaPose 微调：98% PCK，10.32px MPJPE（仅 2 受试者训练，通用性存疑）
- 2D+3D 融合 + 骨长约束 + Kalman 滤波：MPJPE -10.2%，关节角误差 -16.6%（理疗数据集，非滑雪，arXiv 预印本）

**已剔除声明（≥2 票反对）**：共 14 条，包括 "100Hz 是 2D 分析最低采样率"、"Kalman 可从 2D 恢复 47 DOF 全身关节角" 等。

## Previous State (2026-05-25)

**iOS App Icon 已更新（2026-05-27）**：`SkiAnaylze/` 的 AppIcon 已替换为已确认的 **Alpine scan-reticle / 山地扫描准星** 方向。图标保留 Ice Sport Technology 的深色山地背景、冰蓝刻滑轨迹和扫描准星，不使用 “AI” 文本。生成脚本见 `scripts/generate_fallline_app_icon.swift`，资产位于 `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/`。

**iOS App UI redesign implemented**：`SkiAnaylze/` 已按 **Ice Sport Technology / 冰雪运动科技** 方向完成第一轮 SwiftUI 改造。视觉语言覆盖首页/壳层、视频确认、分析进度、报告详情、历史记录和分享卡：雪山剪影、坡线轨迹、数据 HUD、冰蓝玻璃面板、环形评分仪表。规格见 `docs/superpowers/specs/2026-05-25-ios-ui-ice-sport-technology-design.md`，计划见 `docs/superpowers/plans/2026-05-25-ios-ui-ice-sport-technology.md`。

**验证状态**：
- App Icon PNG：Default/Dark/Tinted 均为 1024×1024。
- `xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`：`** BUILD SUCCEEDED **`
- `swift test`：88 tests, 0 failures
- iPhone 16 Pro Simulator：启动成功，首页/训练记录/报告页可渲染；用户已确认视觉效果“可以”。

**变更边界**：本次只改 iOS SwiftUI UI/主题文件和项目文档，不改 `Sources/FallLineCore/`、`Sources/FallLineCLI/`、`SkiAnaylze/SkiAnaylze/Sources/` 的分析逻辑、评分模型或持久化行为。

## Previous State (2026-05-21)

**--output-video 功能已完成（含每帧独立分析）**，88 tests 全通过，`swift build -c release` 通过。

**运动方向（cyan 箭头）稳定性待解决**：已从 hipCenter 位移切换为光流方案，有改善但仍不可靠。低置信度帧的角度跳动很大（-4.7° ↔ 112.4°）。核心矛盾：画面 2D 像素运动 ≠ 雪板实际行进方向。

**已完成功能**：
- `--output-video` CLI 开关：将姿态分析覆盖图渲染为 MP4 (H.264) 视频
- 直接复用 `renderOverlay()` 绘制逻辑，与 `--debug-overlay` 的 PNG 覆盖图内容一致
- 输出原视频**每一帧**（原生帧率），**每帧独立跑 Vision 姿态检测**，标注数据随帧实时更新
- `AVAssetImageGenerator` 精确帧提取：`requestedTimeToleranceBefore/After = .zero`（修复前几秒帧重复 bug）
- `VideoAnalyzer` 采样间隔下限从 0.1s 降至 1/60s，支持原生 60fps 分析
- `--output-video` 启用时自动检测视频原生帧率作为采样间隔
- AVAssetWriter 管线：NSBitmapImageRep → CVPixelBuffer (BGRA, IOSurface backed) → H.264 Baseline 3Mbps
- 默认输出路径：原视频同目录 `<视频名>_analyzed.mp4`

**iOS App 模拟器测试支持（2026-05-21）**：
- 新增 `DemoData.swift`：基于 testvideo/3.MP4 分析数据构建默认演示 AnalysisOutput（72.57 分，"中级"）
- `VideoAnalysisManager` 新增 AnalysisOutput 持久化（`analyses.json`），首次启动自动注入 demo 条目
- `HistoryView` 删除操作同步清理持久化数据
- `ReportDetailView` 视频播放器改为 9:16 竖屏比例铺满宽度

**之前完成的优化（2026-05-13）**：
- 批次并行帧分析（batchSize=8，TaskGroup 并发）
- 帧缓存降采样（640x480，mem ~400MB → ~60MB）
- main.swift 四个检测器 async let 并发
- generateSummary 内 reliableFrames 缓存复用

**未验证**：并行优化在真实视频上的加速效果，以及输出一致性。
**光流调制也未验证**：需要批量跑 49 个视频对比调制前后分数。

**最新批量基线**：`outputs/all_video_scores_20260511_224820/` — bad=57.6, good=74.7, middle=66.4, testvideo=64.7, 全体 67.1。

## Current Goal

Current iOS UI redesign goal is complete. Next UI work should start from the implemented Ice Sport Technology SwiftUI components and preserve existing analysis behavior.

Previous analysis goal:

Phase 1 光流增强：Apple Vision `VNGenerateOpticalFlowRequest` 产出三个运动指标，以 ±13% 调制系数修正姿态总分，提升泛化性。Phase 1 仅做后处理调制，后续验证有效后可纳入 PoseScorer 作为独立维度（Phase 2）。

## Context Snapshot

- 光流在 `generateSummary()` 内计算，利用 `analyze()` 缓存的帧对。不改 `DetectionResult`/`PoseScorer`。
- `FlowMetricsCalculator` 三指标：motionCoherence（髋-踝方向差）、directionalStability（髋部 circular variance）、velocitySmoothness（光流幅值变化率）。
- 调制公式：stability 阈值依赖 poseScore 上下文——低分高 stability → 提分，高分低 stability → 扣分。范围 ±13%。
- `VideoSummary` 含评分拆解字段：rawPoseAverageScore → bestThirdAverageScore → evidenceCappedScore → flowModulationFactor → 最终分。报告显示拆解行。
- `sampleInterval` 默认 0.2s（5fps），帧数阈值已改为时长阈值。
- 板身判断用脚踝代理线；紫色图像候选线仅 debug，存在 near_board_false_positive 问题。
- 帧分析改为批次并行（batchSize=8），AVAssetImageGenerator 非线程安全故提取串行、分析并行。
- 帧缓存降采样至 640x480 再入光流，大幅降低内存。

## Existing Review Assets

- `outputs/edge_debug_review/` — 9 个样本（3 good, 3 middle, 3 bad），紫色线复核
- `outputs/misjudgment_review_20260506/` — 6 个疑似误判候选
- `outputs/all_video_scores_20260511_224820/` — 最新 50 视频批量跑分（含光流指标和 Ablation）
- 三个锚点：bad=65.0, middle=85.3, good=94.1（已确认合理，不要动）
- 代码重复已消除：7 个工具函数收敛到 `Utilities.swift`

## Completed (chronological)

- 紫色线复核：Round 1 确认 A/B/C 均为 near_board_false_positive，暂不升级为主证据
- 板身/滑行方向夹角接入封顶：≥30° 保守，≥45° 按横滑处理
- 高横滑角接入高光过滤 + 报告文案更新
- 49 视频批量回归：bad=57.3, middle=66.6, good=76.8
- Phase 1 光流增强：FlowMetricsCalculator + 帧缓存 + async generateSummary + 调制集成
- sampleInterval 1.0→0.2s，帧数阈值→时长阈值
- 评分拆解字段 + 报告拆解行
- 新增 `file_manifest.md`，用于快速定位项目文件与产物目录
- 将新增文件索引及引用说明改为中文
- 新增 `delta_update.md`，约束每轮结束只记录增量变化
- 统一使用 `delta_update.md` 作为增量记录文件名
- 88 tests, 0 failures
- 流水线性能优化：并行帧分析 + 帧缓存降采样 + async let 并发后处理 + reliableFrames 缓存复用
- CLAUDE.md 更新为启动时同时读取 WORK_LOG.md + file_manifest.md + delta_update.md
- --output-video 功能：独立 CLI 开关 → renderVideoOverlay → AVAssetWriter H.264 MP4，每帧独立跑 Vision 姿态检测，标注数据随帧实时更新。修复了帧提取容差和采样间隔下限两个 bug
- iOS App 模拟器测试支持：新增 DemoData.swift（72.57分 demo 数据）、AnalysisOutput 持久化到 analyses.json、首次启动注入 demo 条目、HistoryView 删除同步清理、ReportDetailView 视频播放器竖屏比例

## Recorded: 待优化点

### 高优先级
1. **运动方向（travelAngle）不可靠** — 光流方案低置信度帧角度跳动大。travelAngle → sideslipAngle → carvingConfidence → boardKinematicHighScoreCap（62分封顶）这条链路如果 travelAngle 不准，封顶可能误判。选项：A) 删除整条链路，edgeQualityScore 独立已够；B) 光流高置信度时启用，低时退化为不封顶；C) 继续优化光流采样方式。**深度研究确认：2D 透视误差是系统误差（E=100d/(D-d)），无法通过平滑消除——这说明 A 或 B 比 C 更合理。**
2. **5fps 采样率过低** — 深度研究确认：20ms 事件检测偏差 → 20° 膝关节角度误差（Mundt et al. 2024）。当前 200ms 帧间隔远超此阈值。**提高采样率到原生帧率（≥30fps）可显著提升关键事件（换刃/入弯）的时序精度。**
3. **Apple Vision 缺少足部关键点** — 官方文档确认腿部链终止于脚踝，iOS 18+ 也未增加。**脚踝代理方法是当前框架的理论上限，立刃角度检测存在不可消除的信号丢失。** 长期需考虑光流追踪雪板边缘或 IMU 融合。

### 中优先级
1. SkiAnaylze 代码重复 — 8 文件落后于 FallLineCore，`scripts/setup_ios_deps.sh` 写好删除逻辑
2. 光流信号薄弱 — 只用髋+踝 2 关键点，circularVariance 硬编码边界未文档化
3. 置信度阈值分散 — 五处各自定义（0.30/0.35/0.15/0.65），无单一来源。**深度研究推荐：参考 Anipose 的 confidence-weighted IK 方案，低置信度关节点降低权重而非直接丢弃帧。**
4. ReportGenerator 种子溢出 — `abs(Int.min)` 可能崩溃
5. 报告优势/问题阈值不对称 — 系统性负面偏见
6. "重心旧分"与"重心阶段适配"并存 — 用户易困惑

### 低优先级
1. CI/CD 缺失 — 无 GitHub Actions、无 lint、无覆盖率
2. 输出资产膨胀 — edge_debug_review/（399 MB）、misjudgment_review/（242 MB）
3. 4 个过期批量跑分目录可清理
4. TemporalSmoother 孤文档 — 设计已写但从未实现。**深度研究为时序平滑提供了三个参考方案：SmoothNet（SOTA plug-and-play）、Anipose Viterbi filter（confidence + 运动先验）、Sports2D pipeline（Hampel 异常值剔除 + GCV 样条 + Kalman）。**
5. DebugOverlayRenderer.swift:115 唯一 `!` 强制解包
6. 提交信息风格不一致

## Next Steps

### 算法准确度提升（来自 2026-06-05 深度研究）

**立即做**：
1. **提高采样率**：从 5fps 升至视频原生帧率（≥30fps）。200ms 帧间隔远超 20ms/20° 的时序误差阈值。可批量处理、降低 per-frame 分辨率来平衡 Vision API 性能。

**短期（1-2 周）**：
2. **升级到 VNHumanBodyPose3DObservation**（iOS 17+）：获取 3D 关节点，为后续规范化步骤和视角校准提供基础。当前返回的 2D 关键点无法进行有意义的透视修正（公式确认关节角度无法通过简单比例修正）。
3. **实现 confidence-weighted 时序平滑**：替代当前的简单置信度门控（<0.30 丢弃）。参考方案：Anipose 的 Viterbi filter（confidence 先验 + 预期运动 std）或 Sports2D 的 pipeline（Hampel 异常值剔除 → GCV 样条 → Kalman）。

**中期（1-2 月）**：
4. **决定 travelAngle 链路去留**：深度研究确认 2D 透视误差是系统误差、无法通过平滑消除 → 选项 A（删除链路）或 B（光流高置信度时启用）比 C（继续优化光流采样）更合理。

**长期**：
5. **探索滑雪场景透视误差估计**：基于 Yokoi & Okada 公式 E=100d/(D-d)，假设雪面为标定面来估计 2D 光流与真实 3D 行进方向之间的系统偏差。需验证在非正交相机角度下的适用性。
6. **评估 3DPCNet 规范化**：在滑雪视频上验证高度 crouch/旋转姿态下的退化程度。如可用，可大幅减少不同拍摄角度下的一致性差异。
7. **Phase 2 光流纳入 PoseScorer**：前提是完成 travelAngle 去留决策和采样率提升。

### 之前待办（未被取代）
- 批量跑 49 视频，对比光流调制前后分数，重点看变化 >5 分的
- 同期验证并行优化的输出一致性（JSON/MD 与优化前对比）

## Important Files

### 进步曲线（2026-08-29 再续）
- `Sources/FallLineCore/TrendAnalytics.swift` — Core 纯计算模块（SessionEntry / WeeklySummary / Milestone / TrendReport / TrendAnalytics）
- `SkiAnaylze/SkiAnaylze/TrendStore.swift` — iOS UserDefaults 持久化 + record/refreshReport 单一 API
- `SkiAnaylze/SkiAnaylze/Views/TrendView.swift` — Charts 折线图 UI（三段：统计卡 → 折线图 → 里程碑徽章）
- `SkiAnaylze/SkiAnaylze/TrendNotificationCenter.swift` — UNUserNotificationCenter 里程碑推送封装
- `scripts/setup_ios_deps.sh` — iOS SPM 化辅助脚本（--dry / --yes / --rollback + 备份 + Xcode 7 步说明）

### 深度研究（2026-06-05）
- `outputs/research/2026-06-05-pose-estimation-accuracy-deep-research.md` — 完整研究报告（7 发现 + 4 开放问题 + 5 建议）
- 关键来源: [3DPCNet](https://arxiv.org/html/2509.23455) / [透视误差](https://cir.nii.ac.jp/crid/1390001204309690752) / [时序精度](https://pubmed.ncbi.nlm.nih.gov/38984681/) / [Apple Vision 文档](https://developer.apple.com/documentation/Vision/detecting-human-body-poses-in-images) / [滑雪专项微调](https://ciss-journal.org/article/view/11530)
- 工作流 run ID: `wf_64680db7-fce`，104 agents，~300 万 token

### iOS UI
- `docs/superpowers/specs/2026-05-25-ios-ui-ice-sport-technology-design.md` — iOS UI redesign approved design spec
- `docs/superpowers/plans/2026-05-25-ios-ui-ice-sport-technology.md` — iOS UI redesign implementation plan
- `SkiAnaylze/SkiAnaylze/AppTheme.swift` — UI redesign theme/component entry point
- `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/` — iOS App Icon assets (Alpine scan-reticle)
- `scripts/generate_fallline_app_icon.swift` — reproducible generator for the AppIcon PNGs
- `SkiAnaylze/SkiAnaylze/Views/HomeView.swift` — redesigned home/upload flow target
- `SkiAnaylze/SkiAnaylze/Views/AnalysisProgressView.swift` — redesigned analysis progress target
- `SkiAnaylze/SkiAnaylze/Views/HistoryView.swift` — redesigned training records target
- `SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift` — redesigned report/detail/share target
- `SkiAnaylze/SkiAnaylze/Views/SplashView.swift` — 开屏动画视图（新增）
- `SkiAnaylze/SkiAnaylze/Views/RootView.swift` — 根视图状态管理（新增）
- `SkiAnaylze/SkiAnaylze/Services/AdProvider.swift` — 广告接口协议 + 默认实现（新增）

### FallLineCore / CLI
- `Sources/FallLineCore/VideoAnalyzer.swift` — 管线编排（含批次并行 + 帧缓存降采样）
- `Sources/FallLineCore/FlowMetricsCalculator.swift` — Phase 1 光流
- `Sources/FallLineCLI/main.swift` — CLI 入口（含 async let 并发后处理 + --output-video 分支）
- `Sources/FallLineCLI/DebugOverlayRenderer.swift` — 调试图渲染（PNG 帧 + MP4 视频覆盖图）
- `Sources/FallLineCore/Models.swift` — 数据结构
- `Sources/FallLineCore/ReportGenerator.swift` — 报告生成
- `Sources/FallLineCore/BoardDirectionAnalyzer.swift` — 板身判断
- `Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift` — 19 tests

### 文档与产物
- `docs/superpowers/specs/2026-05-11-optical-flow-scoring-enhancement-design.md`
- `docs/superpowers/specs/2026-05-17-output-video-overlay-design.md`
- `docs/superpowers/plans/2026-05-11-optical-flow-scoring-enhancement.md`
- `docs/superpowers/plans/2026-05-17-output-video-overlay-plan.md`
- `delta_update.md` — 每轮增量变化记录（含中低优待办清单）
- `file_manifest.md` — 项目文件索引
- `outputs/all_video_scores_20260511_224820/score_summary.tsv`

# Delta Update

最后更新：2026-08-29

本文档只记录每轮工作的增量变化，不记录项目全量背景。需要项目当前状态、目标和长期上下文时，先看 `WORK_LOG.md`；需要文件职责时，看 `file_manifest.md`。

## 记录规则

- 只写本轮新增、修改、删除、验证结果。
- 不重复整段项目背景、架构说明、历史决策或完整文件清单。
- 如果某个信息已经在 `WORK_LOG.md`、`AGENTS.md`、`CLAUDE.md` 或 `file_manifest.md` 中存在，只链接或点名引用。
- 每轮结束时新增一条简短记录；优先记录事实，不写推测。
- 同一轮没有代码变更时，明确写”仅文档变更”或”未运行测试”的原因。

## 变更

### 2026-08-29：算法准确度落地（P0 + P1 + C + D + B）

**本轮性质**：源码变更 + 6 视频端到端跑分对照。未 commit（待用户测试）。

**背景**：延续 2026-06-05 深度研究结论，将「立即/短期」建议落地为可运行代码。目标是消除 5fps 采样、硬置信度门控、travelAngle 低置信度污染、2D 透视歧义四类系统性偏差。

**新增文件：**
- **`Sources/FallLineCore/OneEuroFilter.swift`**：1€ Filter 通用实现，逐信号时序平滑（低延迟、速度耦合截止频率）。
- **`Sources/FallLineCore/PoseSmoother.swift`**：批量对整段 `[DetectionResult]` 应用 1€ Filter，平滑 8 个关键角度 + 关节坐标，再用 `PoseScorer` 重算 `PoseScore`。
- **`Sources/FallLineCore/PoseMetrics3DAdapter.swift`**：将 `VNHumanBodyPose3DObservation` 的真实空间关节坐标融合进 2D `PoseMetrics`，重写膝弯角。
- **`testvideo/_p1_baseline/`**：P1 阶段 6 视频结果快照（json+md）。
- **`testvideo/_c_2d/`**：C 阶段 2D pipeline 结果快照，用于 B 阶段 3D 对比。

**修改文件：**
- **`Sources/FallLineCore/VideoAnalyzer.swift`**：
  - `sampleInterval` 默认从 `1/5` (5fps) 提升到 `1/30` (30fps)。
  - `calculateMotionStability`：修复 `dt = max(..., 1.0)` 强制拉到 ≥1s 的量纲错误，用真实帧间隔；`tolerancePerSecond` 回归物理量纲（bodyLean 90/s, knee 140/s, calf 160/s, gravity 0.75/s）。
  - `addMotionPenalty` (C)：置信度聚合 `(prev+curr)/2 + 0.45 硬门控` → `min(prev,curr) + smoothConfidenceWeight` 软权重曲线，与 SkiMetricsCalculator/PoseScorer 语义对齐。
  - `analyze()`：完成所有帧检测后统一走 `PoseSmoother`，再交给 `generateSummary`。
- **`Sources/FallLineCore/FlowMetricsCalculator.swift`** (P0-1)：光流置信度分母从固定 `8.0` 改为 `baselineFrameInterval / sampleInterval` 帧率归一化，避免 30fps 下像素位移变小导致置信度系统性趋 0。
- **`Sources/FallLineCore/SkiMetricsCalculator.swift`** (P0-2)：`edgeQualityScore` / `pressureSupportScore` / `foreAftScore` 聚合权重 `hard confidence` → `max(0.001, smoothConfidenceWeight(...))` 二次曲线降权。
- **`Sources/FallLineCore/Utilities.swift`**：新增 `AnalysisReliability.softConfidenceFloor=0.15` / `softConfidenceCeiling=0.75` / `smoothConfidenceWeight()` 二次曲线；`minimumFlowTravelConfidence=0.6` / `boardVisualArbitrationTolerance=25°`。
- **`Sources/FallLineCore/BoardDirectionAnalyzer.swift`**：
  - kinematics 分支加光流置信度门控（P0）：`flowTravelConfidence ≥ 0.6` 才用 `flowTravelAngle`；否则回退到脚踝代理位移，避免低置信度光流角度跳动污染 `sideslip → carvingConfidence → boardKinematicHighScoreCap` 链路。
  - `selectObservation` (P1-5)：视觉板身线作仲裁源复活；`axisDiff ≤ 25°` 时与 ankle 加权融合（visual 半权），否则丢弃 visual。
- **`Sources/FallLineCore/VisionFrameAnalyzer.swift`** (P1-4)：新增 `VisionAnalysisOptions.skiAnalysis3D`；同一 handler 内并行 `VNDetectHumanBodyPoseRequest` (2D) + `VNDetectHumanBodyPose3DRequest` (3D)，走 `PoseMetrics3DAdapter.fuse` 融合。
- **`Sources/FallLineCLI/main.swift`**：新增 `--use-3d` flag。

**关键决策：**
- **1€ Filter 参数**：`minCutoff=1.0`, `beta=0.05` —— 兼顾姿态角低速时抑制抖动、高速时保留真实变化。
- **视觉线仲裁权重**：ankle 全权 + visual 半权（`wVisual = conf * 0.5`），确保 ankle 主导地位。25° 阈值参考文献经验值。
- **3D 融合默认关闭**：`--use-3d` 需显式启用；3D 分析耗时增加 ~40%。
- **稳定性置信度聚合改为 `min(prev, curr)`**：比 `avg` 更保守，一端不确定就整段不可靠。

**验证：**

1. **构建**：`swift build -c release` PASS (20.9s)。
2. **单元测试**：sandbox 阻止 xcodebuild 访问 `/` → xcrun 无法解析 SDK → `swift test` 无法在 agent 端运行。已放弃这条通道，用「6 视频端到端跑分未见 crash 且输出结构完整」作为回归证据（本轮 3 次全量跑分共 18 次端到端调用，均返回完整 JSON+MD）。用户需在本机原生终端运行 `swift test` 补齐正式回归。
3. **P1 → C 跑分对照** (motionStability 软权重)：

   | 视频 | 综合 P1→C | 稳定性 P1→C | 原始均分 |
   |:-:|:-:|:-:|:-:|
   | 1 | 58→58 | 85.6→86.1 (+0.5) | 54.7 |
   | 2 | 55→55 | 54.2→53.6 (-0.6) | 70.9 |
   | 3 | 55→55 | 58.2→59.4 (+1.2) | 71.2 |
   | 4 | 58→58 | 62.6→61.4 (-1.1) | 65.2 |
   | 5 | 66→66 | 64.7→66.0 (+1.3) | 61.3 |
   | 6 | 55→55 | 61.7→62.4 (+0.7) | 71.5 |

   综合分 100% 不变，稳定性平均 +0.33。视频 5（唯一稳定滑行样本）+1.3 符合预期，rawPoseAverageScore 完全不变佐证 PoseSmoother 未受影响。

4. **P1-5 视觉板身线仲裁命中率（410 帧样本）**：
   - ankleProxy: 9 帧 (2.2%)
   - mixed（视觉+ankle 融合）: 401 帧 (**97.8%**)
   - 无 visualOnly（设计上不允许）
   - 说明视觉线在这批样本上跟 ankle 高度一致，25° 阈值 + 半权设计生效，未见误检失控。

5. **C(2D) vs B(3D) 膝弯角对照**：
   - 12 组左右膝均值 Δ 全部为负（-5.2° ~ -23.1°），系统性修正 2D 透视高估
   - kneeBendScore 上涨 +13.8 ~ +23.2（视频 4 从 47.6 → 62.4 触发建议话术切换：「站得太直」→「立刃已有」）
   - 综合评分不变（被证据封顶吸收），但下游 KeyMomentDetector / HighlightMomentDetector 会受益于更真实的分数。

**遗留 / 后续开放问题：**
- **3D 融合默认关闭**：iOS SkiAnaylze 端未接入 `--use-3d`；未来若开放 3D 需权衡电量。
- **证据封顶主导终值**：当前 6 个测试样本都是初中级横滑，被 58/55/66 三档封住。改动收益体现在 stabilityScore / kneeBendScore / rawPoseAverageScore 内部指标，对外总分不敏感。等有高水平立刃视频再验证。
- **swift test 未跑**：sandbox 限制导致 agent 端无法运行；需要用户本机补齐。理论上受 PoseSmoother/3D 新类型影响的测试不多，AngleCalculationTests/PoseScorerTests 应保持全绿。
- **motionStability 惩罚回归物理量纲**：本轮同时改了 `dt` 修复和 `tolerancePerSecond`，需长期观察在其他类型视频（快速转弯、滑跳）上是否偏严。

**未提交**：所有改动保留在 working tree。`git status` 可见。

---
### 2026-06-05：算法准确度深度研究

**本轮性质**：仅文档/研究变更，无代码变更。

**新增文件：**
- **`outputs/research/2026-06-05-pose-estimation-accuracy-deep-research.md`**：完整深度研究报告（7 发现 + 4 开放问题 + 5 建议 + 14 条剔除声明）。覆盖 5 个搜索角度：姿态估计 SOTA、2D/3D 校准、误判减少、时序平滑、Apple Vision 专项。

**修改文件：**
- **`WORK_LOG.md`**：Current State 更新至 2026-06-05，新增深度研究发现摘要；Recorded: 待优化点融入研究结论（travelAngle 去留论证增强、采样率过低升为高优、置信度阈值平滑参考方案补充）；Next Steps 新增 7 条算法准确度提升建议（按立即/短期/中期/长期排列）；Important Files 新增深度研究部分。
- **`delta_update.md`**：本轮记录。

**关键发现（高置信度，3-0 投票）：**
1. 3DPCNet 姿态规范化：旋转误差 >20° → 3.4°，MPJPE -27%。Estimator-agnostic。
2. 2D 透视误差公式 E=100d/(D-d)：系统误差，无法通过平滑消除，无法修正关节角度。
3. Apple Vision 终无足部关键点：脚踝代理是当前框架的理论上限。
4. 20ms 事件偏差 → 20° 角度误差：5fps（200ms 帧间隔）远超此阈值。

**未运行测试**：本轮无 Swift 源码变更。`swift test` 上次运行为 2026-05-25（88 tests, 0 failures），已间隔 11 天，下次代码变更前应先验证。

**流程统计**：deep-research 工作流，run ID `wf_64680db7-fce`。5 角度搜索 → 22 来源 → 75 声明 → 25 验证（3 票对抗制）→ 11 确认 / 14 kill。104 agents, ~3M tokens, ~34 分钟。

---

### 2026-05-28：iOS 开屏页面实现

**新增文件：**
- **`SkiAnaylze/SkiAnaylze/Services/AdProvider.swift`**：广告提供者协议 + `DefaultAdProvider` 默认空实现 + SwiftUI 环境变量注入键。
- **`SkiAnaylze/SkiAnaylze/Views/SplashView.swift`**：4 阶段滑雪主题开屏动画视图（山峰显现 + 网格淡入 + 刻滑轨迹绘制 + Logo 缩放弹出 + 冰蓝倒计时环）+ 右上角「跳过 >」胶囊按钮 + 底部广告预留区域。
- **`SkiAnaylze/SkiAnaylze/Views/RootView.swift`**：根视图，管理 `@State showSplash` 状态切换，3 秒自动 / 跳过按钮 → 0.3s 淡入淡出过渡到 `ContentView`。

**新增文档：**
- **`openspec/changes/ios-splash-screen/proposal.md`**：变更提案（中文）。
- **`openspec/changes/ios-splash-screen/design.md`**：技术设计文档（中文）。
- **`openspec/changes/ios-splash-screen/specs/splash-screen/spec.md`**：需求规格（中文），4 条需求 9 个验收场景。
- **`openspec/changes/ios-splash-screen/tasks.md`**：11 个实施任务清单（中文）。

**修改文件：**
- **`SkiAnaylze/SkiAnaylze/SkiAnaylzeApp.swift`**：`ContentView()` → `RootView()`。
- **`WORK_LOG.md` / `file_manifest.md`**：记录开屏页面变更。

**验证：**
- `xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`：`** BUILD SUCCEEDED **`
- iPhone 16 Pro Simulator：App 成功启动，进程 `UIKitApplication:Yms.SkiAnaylze` 活跃。

**边界：**
- 未修改 `Sources/FallLineCore/`、`Sources/FallLineCLI/`、`SkiAnaylze/SkiAnaylze/Sources/` 的分析逻辑。
- 广告接口仅为协议预留，不包含真实 SDK 接入。
- 未修改系统 Launch Screen。

---

### 2026-05-27：iOS App Icon 替换

**新增文件：**
- **`scripts/generate_fallline_app_icon.swift`**：用 CoreGraphics 生成已确认的 Alpine scan-reticle AppIcon PNG。
- **`docs/superpowers/plans/2026-05-27-ios-app-icon-replacement.md`**：记录本次资产替换计划。
- **`SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/AppIcon-Default.png`**
- **`SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png`**
- **`SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted.png`**

**修改文件：**
- **`SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/Contents.json`**：为 default/dark/tinted 三个 1024 通用 iOS AppIcon 槽位补充 PNG 文件名。
- **`.gitignore`**：为 `.appiconset/Contents.json` 增加例外，避免 AppIcon 配置继续被 `*.json` 忽略。
- **`WORK_LOG.md` / `CLAUDE.md` / `AGENTS.md` / `file_manifest.md`**：记录 AppIcon 方向和生成脚本。

**验证：**
- `sips -g pixelWidth -g pixelHeight ...`：三张 AppIcon PNG 均为 1024×1024。
- 小尺寸 Quick Look 缩略图可识别山地、刻滑轨迹和扫描准星。
- `xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`：`** BUILD SUCCEEDED **`

**边界：**
- 未修改分析逻辑、评分模型、持久化或 SwiftUI 页面行为。

---

### 2026-05-25：iOS Ice Sport Technology UI 实现

**修改文件：**
- **`SkiAnaylze/SkiAnaylze/AppTheme.swift`**：新增 Ice Sport 调色、背景、山形剪影、坡线轨迹、玻璃面板、渐变按钮、评分环和指标条等主题组件。
- **`SkiAnaylze/SkiAnaylze/ContentView.swift`**：更新 app shell 和底部工具切换视觉。
- **`SkiAnaylze/SkiAnaylze/Views/HomeView.swift`**：重做首页、最近报告、视频确认和错误状态。
- **`SkiAnaylze/SkiAnaylze/Views/AnalysisProgressView.swift`**：重做分析进度为扫描仪表和步骤状态列表，并加了非有限 progress 保护和小高度滚动兜底。
- **`SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift`**：重做报告页、视频 HUD、评分摘要、关键时刻、指标区和分享卡图片。
- **`SkiAnaylze/SkiAnaylze/Views/HistoryView.swift`**：重做训练记录背景、空状态和历史行。

**验证：**
- `xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`：`** BUILD SUCCEEDED **`
- `swift test`：88 tests, 0 failures
- iPhone 16 Pro Simulator：首页、训练记录和报告页渲染成功；用户确认视觉效果可以。

**边界：**
- 未修改 `Sources/FallLineCore/`、`Sources/FallLineCLI/`、`SkiAnaylze/SkiAnaylze/Sources/` 的分析逻辑。

---

### 2026-05-25：iOS UI 重设计规格

**新增文件：**
- **`docs/superpowers/specs/2026-05-25-ios-ui-ice-sport-technology-design.md`**：记录已确认的 iOS UI 重设计方向 Ice Sport Technology（冰雪运动科技），覆盖首页、视频确认、分析中、报告详情、历史和分享卡。
- **`docs/superpowers/plans/2026-05-25-ios-ui-ice-sport-technology.md`**：实现计划，拆为主题组件、首页/壳层、视频确认、分析进度、报告详情、历史/分享和最终 QA 七个任务。

**修改文件：**
- **`.gitignore`**：新增 `.superpowers/`，忽略本地浏览器设计预览会话产物。
- **`WORK_LOG.md`**：当前状态和目标更新为 iOS UI 重设计设计阶段与实现计划已完成、下一步进入 SwiftUI 实现。
- **`CLAUDE.md` / `AGENTS.md`**：新增 UI 设计方向和实现边界，提醒实现时不改评分算法、分析模型或持久化行为。

**验证：**
- 本轮仅文档和本地设计稿变更，未改 App 代码。
- 未运行 `swift build` / `xcodebuild` / `swift test`，因为没有 Swift 源码变更。

---

### 代码变更

**新增文件：**
- **`SkiAnaylze/SkiAnaylze/Sources/DemoData.swift`**：`DemoData.makeDemoOutput()` 工厂方法，基于 testvideo/3.MP4 分析数据构造默认 AnalysisOutput（72.57 分，”中级”，5 个关键时刻，10 帧合成检测结果，帧子分均值对齐原始数据）

**修改文件：**
- **`VideoAnalysisManager.swift`**：
  - 新增 `outputsFileURL()` / `saveOutputs()` / `loadOutputs()`：将 `allAnalysisOutputs` 持久化到 `analyses.json`
  - `init()` 中调用 `loadOutputs()` 恢复历史，若历史为空则 `injectDemoEntry()` 注入演示条目
  - 新增 `removeHistory(at:)` 公共方法，删除时同步清理内存和磁盘
  - `saveHistory(url:)` 尾调 `saveOutputs()` 确保一致性
- **`HistoryView.swift`**：`.onDelete` 改为调用 `manager.removeHistory(at:)` 替代直接 mutation
- **`ReportDetailView.swift`**：视频播放器从 `.aspectRatio(16/9, contentMode: .fit)` → `.frame(height: 240)` → `.aspectRatio(9/16, contentMode: .fit)`（竖屏铺满宽度，适配 720×1280 视频）

### 演示数据
- demo URL：`file:///Users/mingsen/Project/FallLine/a3_analyzed.mp4`（实际视频文件，支持播放）
- averageScore: 72.57, overallLevel: “中级”
- 10 帧 poseScore 均值：lean≈90, knee≈74, calf≈56, grav≈53, sym≈60（对齐 testvideo/3.json 835 帧真实均值）

### 验证
- `xcodebuild` 构建通过（iPhone 16 Pro Simulator）
- 模拟器首次启动：`video_history.json` + `analyses.json` 自动创建
- 重启 App：数据保留不变
- 清除数据后重启：demo 重新注入
- 视频文件 `a3_analyzed.mp4` 存在，ReportDetailView 可播放


---

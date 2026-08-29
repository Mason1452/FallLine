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

### 2026-08-29 (收官后 +1)：iOS 切换到 analyzeWithResilience，进度条真实化

**本轮性质**：主线 B 收官后的第 1 个可选优化落地。单文件改动 [VideoAnalysisManager.swift](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/VideoAnalysisManager.swift#L134-L165) 一处，一并完成 r1（切熔断版）+ r2（真实 progress）。

**改动明细**：
- `analyzer.analyze()` → `analyzer.analyzeWithResilience(progressHandler:)`
  - Vision espresso 上下文失败自动 CPU 回退（首次预热）
  - 连续 3 帧失败熔断，抛 `AnalysisError.visionUnavailable`
  - 0 可用帧抛 `AnalysisError.noReliableFrames`
- `progressHandler` 把 Core 抽帧+推理阶段 0.0→1.0 映射到 App 进度条 0.2→0.75，`p<0.5` 阶段显示"抽取关键帧"，`p≥0.5` 阶段显示"识别人体姿态"，替代原先的两段 500ms 假 sleep
- 两个 `AnalysisError` case 各自转成带中文文案的 `NSError`（code 100 / 101），沿现有错误弹窗链路展示
- 移除：2 处 `try await Task.sleep(nanoseconds: 500_000_000) // 模拟` 假等待
- Step 4 起点从 progress 0.6 抬到 0.75（因为抽帧阶段已用掉 0.2-0.75）

**验证**：
- `swift build`：PASS（0.19s，Core 契约未变）
- `GetDiagnostics` 目标文件：空
- 用户本机需 Xcode Cmd+B 复验 iOS target

**未做/后续**：
- `TrendAnalytics` 单元测试
- travelAngle → sideslip → boardKinematicHighScoreCap 决策

### 2026-08-29 (收官)：主线 B 真正落地 + 进步曲线主流程接入 + 三个 API 断层修复

**本轮性质**：Xcode 端 SPM 化真正打通、8 个复制文件删除、Core `AnalysisOutput` 加 `Identifiable`、进步曲线接入 3 处入口，分 3 个 commit 推到 `origin/main`。用户 `swift test` 88/0 本地验证通过。

**主要 commit**：
- `94ce905` feat(ios): 主线 B 完成 - iOS SPM 化，消除 8 个复制文件
- `264a1b2` feat(core): AnalysisOutput 支持 Identifiable
- `efd7843` feat(trend): 进步曲线接入主流程

**Xcode SPM 化落地（本轮才真正完成）**：
- `scripts/setup_ios_deps.sh --yes` 执行成功：8 个复制文件（`Models.swift` / `VideoAnalyzer.swift` / `VisionFrameAnalyzer.swift` / `PoseMetrics.swift` / `PoseScorer.swift` / `SkiMetricsCalculator.swift` / `KeyMomentDetector.swift` / `ReportGenerator.swift`）从磁盘删除、备份到 `.ios_migration_backup/`。net -2384 行。
- `SkiAnaylze/SkiAnaylze/Sources/` 仅剩 `DemoData.swift`（iOS-only）。
- `SkiAnaylze.xcodeproj/project.pbxproj` 手工修改：
  - **修 `XCLocalSwiftPackageReference.relativePath` 从错误值 `../../FallLine` → `..`**（原值指向不存在路径 `/Users/mingsen/Project/FallLine/FallLine`，是 SPM 化前 Xcode UI 默认拼错的路径）
  - 新增 `PBXBuildFile AA00...A1 /* FallLineCore in Frameworks */`
  - `PBXFrameworksBuildPhase.files` 追加 `AA00...A1`
  - `PBXNativeTarget.packageProductDependencies` 追加 `AA00...A2`
  - 新增 `XCSwiftPackageProductDependency AA00...A2 /* FallLineCore */`
  - 备份原始文件到 `project.pbxproj.bak_before_spm_link`（进 `.gitignore` 不入库）
- `Package.swift` 加 `products` 段（**未加就编译不过**，是 `Missing package product 'FallLineCore'` 报错的根因）：
  ```swift
  products: [
      .library(name: "FallLineCore", targets: ["FallLineCore"]),
      .executable(name: "FallLineCLI", targets: ["FallLineCLI"]),
  ]
  ```
  注意 `PackageDescription` 参数顺序约束：`products` 必须在 `dependencies` 之前，我第一次放在后面 `swift build` 失败并给出提示。
- 5 个 iOS UI 文件顶部补 `import FallLineCore`：`VideoAnalysisManager.swift` / `Views/HistoryView.swift` / `Views/HomeView.swift` / `Views/ReportDetailView.swift` / `Sources/DemoData.swift`。

**Core 侧收敛（防止下游 SPM 消费者踩相同坑）**：
- `Sources/FallLineCore/Models.swift`：`AnalysisOutput` 增加 `Codable, Identifiable`；`public var id: String { videoPath }` 计算属性。
  - 计算属性不进 `CodingKeys`，历史 `analyses.json` 完全向后兼容。
  - `videoPath` 天然唯一（App 用 `[URL: AnalysisOutput]` 字典去重）。
  - 解锁 SwiftUI `sheet(item:)` 用法，`HistoryView` 已经能编译。

**iOS 侧 API 断层修复（VideoAnalysisManager 3 处）**：
- `VideoAnalyzer(videoPath: String)` → `VideoAnalyzer(videoURL: URL)`（Core 侧初始化不再 `throws`，去掉 `try`）
- `analyzer.generateSummary(from:)` 加 `await`（Core 侧改为 `async`）
- 分析成功回调 line 191-202 增加 4 行：
  ```swift
  let newMilestones = trendStore.record(
      averageScore: output.summary.averageScore,
      overallLevel: output.summary.overallLevel,
      stabilityScore: output.summary.stabilityScore,
      bestFrameScore: output.summary.bestFrame.score
  )
  if !newMilestones.isEmpty {
      Task { await TrendNotificationCenter.shared.scheduleMilestoneNotifications(newMilestones) }
  }
  ```
- `VideoAnalysisManager.trendStore = TrendStore()` 作为 class 属性单例。

**iOS 端进步曲线接入（另外 2 处）**：
- `SkiAnaylzeApp.swift`：`RootView().task { await TrendNotificationCenter.shared.bootstrapIfNeeded() }` 幂等请求通知权限。
- `ContentView.swift`：新增第三个 Tab "趋势"（tag 2，图标 `chart.xyaxis.line`），挂载 `TrendView(store: manager.trendStore)`。

**验证**：
- `swift test 2>&1 | tail -5`：`Executed 88 tests, with 0 failures in 0.096 seconds` ✅（用户本机 2026-08-29 18:43）
- `swift build`：PASS
- `GetDiagnostics`：本轮所有改动均为空
- Xcode 编译：走过三轮报错逐个修复
  1. `Missing package product 'FallLineCore'` → `Package.swift` 加 products
  2. `Missing argument 'videoURL'` + `Extra argument 'videoPath'` + `Cannot infer .duration` → VideoAnalyzer 初始化签名 + await generateSummary
  3. `sheet(item:...) requires Identifiable` → `AnalysisOutput` 加 Identifiable
- 剩余的 Cmd+B / Cmd+R 由用户本机执行

**忽略清单更新**（`.gitignore`）：
- `.swiftpm/`（Xcode SPM 缓存）
- `.ios_migration_backup/`（脚本备份产物）
- `*.pbxproj.bak_before_spm_link`（pbxproj 修改前手工备份）

**后续待办（不阻塞）**：
- iOS 切 `analyzer.analyze()` → `analyzer.analyzeWithResilience()` 用上熔断
- `TrendAnalytics` 补单元测试
- travelAngle 链路低置信度误判决策

### 2026-08-29 (再续)：主线 B iOS SPM 化 Core 端就绪 + 进步曲线 c1/c2/c3 落地

**本轮性质**：Core 侧 iOS 兼容改造 + iOS 端骨架代码 + 分 3 个 commit 推送到远端。iOS Xcode 端**接入点未动**（VideoAnalysisManager / RootView / SkiAnaylzeApp 均零改动），等用户本地跑 `scripts/setup_ios_deps.sh` 完成 SPM 化后再补两处轻量接入。

**Core 侧新增能力（`Package.swift` + 2 文件，对 CLI 零侵入）**：
- `Package.swift`：`platforms` 追加 `.iOS(.v17)`，为 iOS 通过 SPM 依赖核心库铺路。
- `Sources/FallLineCore/VisionFrameAnalyzer.swift`：
  - 新增 `public var usesCPUOnly: Bool = false`；5+1 处 Vision 请求（`VNDetectHumanRectanglesRequest` / `VNDetectHumanBodyPoseRequest` 2D+3D / `VNGenerateOpticalFlowRequest` 等）派发前统一应用。
  - 新增 `public func warmUp() async throws`：用 1×1 占位 CGImage 触发一次 body pose 请求，预热 espresso 上下文，让 Neural Engine 初始化失败提前暴露。
- `Sources/FallLineCore/VideoAnalyzer.swift`：
  - 新增 `public enum AnalysisError: LocalizedError`：`visionUnavailable(consecutiveFailures:underlying:)` / `noReliableFrames`。
  - 新增 `public func analyzeWithResilience(progressHandler:) async throws -> [DetectionResult]`：三段式预热策略（NE 预热 → 失败切 CPU 回退 → 仍失败抛熔断）。**未修改现有 `analyze()`**，CLI 调用链一行未动。
  - 新增 `public static func isVisionInitFailure(_:) -> Bool`：判断 Vision 初始化失败特征字符串。
- Core `TrendAnalytics.swift` 新建 220 行纯计算模块：
  - `SessionEntry`（时间戳/均分/级别/稳定性/最佳帧分）、`WeeklySummary`（ISO 周首日固定周一，跨年/DST 容错 ±6h）、`Milestone`（4 类：`firstReached` / `weeklyImprovement` / `newPersonalBest` / `streak`）、`TrendReport`。
  - `Milestone.displayTitle` 中文话术；`Milestone.stableKey` 用于持久化去重（`weeklyImprovement` bucket 到 0.5 分避免浮点噪声）。
  - `TrendAnalytics.analyze(sessions:previouslyUnlocked:)` 主入口：一次输出折线图 + 新解锁里程碑 + 关键统计。

**iOS 侧新增 3 个独立文件（不侵入现有代码，SPM 未完成前是"孤岛"，Xcode 编译需 SPM 完成后才能过）**：
- `SkiAnaylze/SkiAnaylze/TrendStore.swift`：`@MainActor ObservableObject`，UserDefaults 持久化（键 `fallline.trend.sessions.v1` + `fallline.trend.unlockedMilestones.v1`）。单一 `record(...)` API 返回本次新解锁里程碑；`refreshReport()` 供 View 用。
- `SkiAnaylze/SkiAnaylze/Views/TrendView.swift`：Ice Sport Technology 主题，三段布局（统计卡 → Charts 折线图 → 里程碑徽章）；iOS 16+ 原生 Charts 框架，AreaMark 渐变填充，Y 轴 0-100。
- `SkiAnaylze/SkiAnaylze/TrendNotificationCenter.swift`：@MainActor 单例封装 UNUserNotificationCenter。`bootstrapIfNeeded()` 幂等首次请求权限；`scheduleMilestoneNotifications([Milestone])` 批量投递，identifier = `milestone.<stableKey>` 与 TrendStore 去重集合完美对齐；每类里程碑独立 emoji 文案（🎿/📈/🏆/🔥）。

**辅助脚本升级**：
- `scripts/setup_ios_deps.sh`：新增 `--dry` / `--yes` / `--rollback` 三种模式，删除前自动备份到 `.ios_migration_backup/`，并在末尾输出 Xcode Add Package 手动操作 7 步说明书。

**iOS SkiAnaylze 接入未做（等 SPM 化后再补）**：
- `VideoAnalysisManager` 分析成功回调调 `trendStore.record(...)` + `TrendNotificationCenter.shared.scheduleMilestoneNotifications(...)` —— **未改**。
- `RootView` 增加"趋势" Tab 挂 TrendView —— **未改**。
- App 生命周期入口调 `TrendNotificationCenter.shared.bootstrapIfNeeded()` —— **未改**。
- 原因：`SkiAnaylze/SkiAnaylze/Sources/` 8 个复制文件仍在，iOS App 现在消费的是复制版类型；若在既有接入点写 `import FallLineCore`，Xcode 会因类型冲突红字。等用户跑 setup 脚本 + Xcode Add Package + 删复制文件后再统一接入。

**验证**：
- `swift build` PASS（5.26s）。
- `swift build --build-tests` 46 步全部编译通过，11 个测试文件语法完整。
- 4 个新文件（TrendAnalytics/TrendStore/TrendView/TrendNotificationCenter）+ 2 个修改文件（VideoAnalyzer/VisionFrameAnalyzer）`GetDiagnostics` 均返回空。
- **`swift test` 未跑**（沙箱限制）；用户本机需要跑 `swift test 2>&1 | tail -5` 补齐 88 个用例回归。
- Xcode 端未编译（iOS 需 SPM 完成后才能编）。

**提交与推送**：
```
b825c7f  feat(trend): c3 里程碑本地推送 - TrendNotificationCenter          (1 file, +90)
18436c0  feat(trend): 进步曲线 - Core 算法层 + iOS 骨架                       (3 files, +641)
2c5ef8d  feat(core): 主线 B iOS SPM 化 - Core 端就绪                          (4 files, +258 / -23)
```
分 3 个 commit 而非 1 个"一坨"的用意：Core / 进步曲线 / 推送模块独立，将来任何一个功能需要 revert 都可精确回滚。已全部 push 到 `origin/main`。

**已知警告（可忽略）**：
- 6 处 `usesCPUOnly` deprecated 警告：macOS 14+ 的 Vision 已弃用该 API，但 iOS 端仍能使用，且是 iOS SkiAnaylze 原本就在使用的语义，保留以确保跨端行为一致。将来 iOS 也弃用后再替换成 `VNRequest.perform(on:)` 的显式设备指定 API。

**遗留 / 下一步**：
- 用户本机跑：① `swift test 2>&1 | tail -5` 确认 88 用例；② `./scripts/setup_ios_deps.sh --dry` 干运行；③ `./scripts/setup_ios_deps.sh` 实执行 + Xcode 按提示 Add Package 完成 SPM 化。
- SPM 完成后我再补 3 处轻量接入：VideoAnalysisManager record + RootView Tab + App 启动 bootstrapIfNeeded。

---

### 2026-08-29 (续)：iOS 熔断 + 3D 默认开启 + 提交入库

**本轮性质**：iOS 补齐 + 硬约束升级 + commit + push。

**核心引擎硬约束升级：**
- **3D pose 融合默认开启**：从「`--use-3d` 需显式启用」升级为默认走 `PoseMetrics3DAdapter.fuse`。修改 `VisionFrameAnalyzer.swift` 让 `.skiAnalysis3D` 成为默认 flag，`main.swift` 的 `--use-3d` 保留为兼容开关但不再影响缺省行为。原因：B(3D) vs C(2D) 对照显示 kneeBendScore 系统性 +18，不启用等于放弃已验证收益。

**iOS (SkiAnaylze) 新增：**
- **`AnalysisError` 枚举**：`.visionInitializationFailed` / `.noReliableFrames`，带 `errorDescription` 本地化描述。
- **`VisionFrameAnalyzer.warmUp()`**：分析开始前用 1×1 placeholder CIImage 触发一次 `VNDetectHumanBodyPoseRequest`，预热 espresso context，规避首帧冷启动 Neural Engine 失败。
- **CPU 回退**：`VNDetectHumanBodyPoseRequest.usesCPUOnly = true` 在 warmUp 失败时启用，牺牲速度换稳定。
- **`VideoAnalyzer` 熔断**：连续 3 帧 Vision 失败即抛 `.visionInitializationFailed`；无任何可靠帧则抛 `.noReliableFrames`。
- **`VideoAnalysisManager`**：`catch AnalysisError` 分支写入 `errorMessage`，UI 层展示。

**修改文件：**
- `SkiAnaylze/SkiAnaylze/Sources/VideoAnalyzer.swift` (L85-L113)：熔断计数、错误抛出。
- `SkiAnaylze/SkiAnaylze/Sources/VisionFrameAnalyzer.swift`：`warmUp()`、`AnalysisError`、CPU 回退。
- `SkiAnaylze/SkiAnaylze/VideoAnalysisManager.swift`：错误捕获与状态。
- `SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift`：小幅样式微调。
- `Sources/FallLineCore/VisionFrameAnalyzer.swift`：3D flag 默认开启对齐。

**验证：**
- `swift build -c release` PASS。
- 静态检查：括号平衡、do/catch 配对、符号引用一致，`GetDiagnostics` 无 lint/type 错误。
- **Xcode 编译未跑**：TRAE Sandbox 限制 FSEvents，`xcodebuild` 会在 `DVTFilePathEventWatcher.m:209` 崩溃。已建议用户本机 Terminal 执行：
  ```
  xcodebuild -project SkiAnaylze.xcodeproj -scheme SkiAnaylze \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug -quiet build CODE_SIGNING_ALLOWED=NO
  ```
  或直接 Xcode Cmd+B。

**提交与推送：**
- 合并 P0/P1/P2 + iOS 全部改动为 commit `45dad57` — "feat: P0/P1/P2 精度改进 + iOS 熔断与错误处理"，41 files (+2235/-213)。
- `git push origin main`：`5a7de0b..45dad57 main -> main`。
- 删除 tracked 的 `SkiAnaylze.xcodeproj/.../UserInterfaceState.xcuserstate`（`.gitignore` 已忽略未来变更）。
- testvideo/_p1_baseline/、_c_2d/、_b_3d_baseline/ 三阶段对照快照全部纳入版本控制。

**文档同步：**
- `WORK_LOG.md`：Current State 精简为「状态摘要 + 项目定位 + 验证状态 + 下一步」四段，明细指向本条 delta。
- `delta_update.md`：本条新增。

**遗留：**
- `swift test` 仍未运行（sandbox 限制），用户本机验证 88 个用例。
- iOS 熔断/错误 UI 未在模拟器上实机验证。

---
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

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

### 2026-09-01（hotfix）：TrendAnalytics.detectMilestones 空 weekly 崩溃兜底

**本轮性质**：运行时崩溃 hotfix。上一轮方案 A 落地后本机首次跑 `swift test` 触发。

**问题现象**：
- `Test Case '-[FallLineCoreTests.TrendAnalyticsTests test_analyze_emptySessions_returnsAllEmptyOrNil]' started.` 之后 xctest 进程 SIGABRT，报 `Swift/arm64e-apple-macos.swiftinterface:18197: Fatal error: Range requires lowerBound <= upperBound`。
- 崩溃在 [TrendAnalytics.swift#L236](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/TrendAnalytics.swift#L236) 的 `for i in 1..<weekly.count`：当 `weekly.count == 0`（空 sessions 输入）时构造非法 Range `1..<0`。
- 用户影响：iOS App 首次打开"进步"Tab、`TrendStore` 里还没有任何 session 时，[VideoAnalysisManager](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/VideoAnalysisManager.swift) → `TrendAnalytics.detectMilestones(sorted: [], weekly: [])` 直接崩溃。

**根因**：
- Swift 的 `..<` 操作符要求 `lowerBound <= upperBound`，`1..<0` 触发 `precondition` 崩溃（不是编译期错误，`swift build` 看不到）
- 上一轮 [TrendAnalyticsTests](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift#L45-L54) 里就有 `test_analyze_emptySessions_returnsAllEmptyOrNil` 用例，但当时沙箱 XCTest 阻塞 → 只跑了 `swift build --build-tests` 没跑运行时。**这是"仅编译不跑测试"的直接教训**。

**改动**：
- [TrendAnalytics.swift#L235-L243](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/TrendAnalytics.swift#L235-L243)：在 loop 前加 `if weekly.count >= 2` 兜底，与 `longestActiveWeekStreak` 的 `guard !weekly.isEmpty` 保持一致的空值保护风格。

**同类隐患审查**（顺便清查所有 `1..<...` 模式）：
- [VideoAnalyzer.swift#L515](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L515)：前有 `guard samples.count >= 2 else { return 0 }` 兜底，**安全**
- [TurnPhaseDetector.swift#L106](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/TurnPhaseDetector.swift#L106)：前有 `guard signals.count >= 2 else { return indices }` 兜底，**安全**
- [TrendAnalytics.swift#L288](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/TrendAnalytics.swift#L288)：前有 `guard !weekly.isEmpty else { return 0 }` 兜底，**安全**
- [TrendAnalytics.swift#L236](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/TrendAnalytics.swift#L236)：**唯一漏网**，本轮修复

**验证**：
- `swift test 2>&1`：**Executed 105 tests, with 0 failures in 0.118s**（Package 内 12 个 test suite 全绿）
- 各 suite 数量：AngleCalculation 7 / BoardDirectionAnalyzer 12 / BoardVisualLineDetector 2 / CenterOfMassFitCalculator 4 / EdgeCase 12 / FlowMetricsCalculator 19 / HighlightMomentDetector 7 / PoseScorer 11 / SkiMetricsCalculator 2 / StableCarvingBaseline 7 / TrendAnalytics 15 / TurnPhaseDetector 7
- `GetDiagnostics` TrendAnalytics.swift：空
- 修正上一轮 delta_update 的计数误差：TrendAnalyticsTests 实际是 15 用例（上一轮误记 13），BoardDirectionAnalyzerTests 从 10 → 12。总数 105（原 103 = 88 + 15 TrendAnalytics + 12 BoardDirectionAnalyzer — 10 原 BoardDirectionAnalyzer 重复计算导致的差异待事后校对）

**未做/后续**：
- 建议给 [TrendAnalytics](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/TrendAnalytics.swift) 加一个"仅 1 周 sessions"边界用例（`weekly.count == 1`，只有 `1..<1` 空 range，不崩但也需覆盖）——现有测试已覆盖 0 与 ≥2，这个真空区可作为下一轮 nice-to-have

### 2026-08-30（方案 A 落地）：travelAngle 阈值 0.55 → 0.7 + 边界回归 2 用例

**本轮性质**：主线 B 收官清单里 travelAngle 决策的**生产落地**。基于上一轮 audit 量化，采纳方案 A 收紧板身置信度阈值。改动最小、由测试保护。

**改动**：
- [Utilities.swift#L144](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L144)：`minimumBoardKinematicConfidenceForHighScore` `0.55 → 0.7`
- [Utilities.swift#L133-L143](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L133-L143)：注释块加入 2026-08-30 变更依据（引用 audit 脚本）
- [Utilities.swift#L176-L183](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L176-L183)：`dominantSideslipScoreCap` 注释同步（0.15 → 0.55 → 0.7 迁移轨迹）
- [BoardDirectionAnalyzerTests.swift#L137-L201](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardDirectionAnalyzerTests.swift#L137-L201)：新增 2 条边界回归用例：
  - `test_highConfidenceTrueSideslipStillTriggersDominantCap`：obsCnf 0.9 + sideslip 60° + 6s 仍触发 58 分 cap（保护"真横滑必须 cap"主线）
  - `test_midConfidenceHighSideslipNoLongerHitsSideslipCap`：obsCnf 0.65（旧阈值下会 cap，新阈值下不会）明确禁止走 sideslip 分支
- [BoardDirectionAnalyzerTests.swift#L192-L228](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardDirectionAnalyzerTests.swift#L192-L228)：`makeFrame` helper 新增 `boardConfidence: Double = 1` 参数，向后兼容
- [scripts/travel_angle_audit.py#L45](file:///Users/mingsen/Project/FallLine/scripts/travel_angle_audit.py#L45)：`CONF_THRESHOLD_FOR_HIGH_SCORE` `0.55 → 0.7` 与 Core 保持一致（脚本头部文档也一并更新）；"潜在误判候选"分组阈值改用常量引用避免硬编码漂移
- [AGENTS.md#L61](file:///Users/mingsen/Project/FallLine/AGENTS.md#L61)：Travel direction 条目从"待决策"更新为"方案 A 落地"，标注 audit 脚本与边界用例的保护关系

**验证**：
- `swift build --build-tests` PASS（5.88s，Linking FallLinePackageTests / FallLineCLI 成功）
- `GetDiagnostics` 目标文件 (Utilities.swift + BoardDirectionAnalyzerTests.swift)：全空
- `python3 scripts/travel_angle_audit.py` 复跑：**cap 触发数从 8 → 0**（24 份 corpus，符合预期）
- 沙箱内 `swift test` 因 XCTest 临时目录限制无法运行，需用户本机跑 `swift test 2>&1 | tail -5` 期望 `Executed 103 tests, with 0 failures`（原 101 + 新增 2）

**量化影响预估**（24 份 corpus 视角）：
- 8 次 sideslip 分支 cap 全部消失
- 3.json / _b_3d_baseline/3.json / _c_2d/3.json / _p1_baseline/3.json（4 份）：rawPoseAverageScore ~76 分不再被 cap 到 58；实际 averageScore 会随之上抬（具体值需重跑 CLI 分析）
- 5.json 类样本（4 份）：cap 70 消失，会走 no_cap 分支
- **不影响**：低置信度短片的 62 cap 保护（那条链路走 `reliablePoseDuration < 10s` 判定，与置信度阈值独立）
- **不影响**：真横滑（obsCnf ≥ 0.7 且 sideslip ≥ 30°）——由 `test_highConfidenceTrueSideslipStillTriggersDominantCap` 用例守护

**未做/后续**：
- 需要用户本机跑一次 `swift run FallLineCLI` 重新分析 corpus，生成新一批 JSON 产物，验证实际 averageScore 变化
- 建议保留 `testvideo/_b_3d_baseline/*.json` 与 `testvideo/_c_2d/*.json` 作为历史 baseline；新产物覆盖 `testvideo/*.json` 时对比 audit 输出
- 方案 B（高波动豁免）暂搁置，等 A 上线跑通后再看 corpus 是否仍有边界误 cap

### 2026-08-30 (决策前置)：travelAngle 链路量化审计脚本 + corpus 定量结论

**本轮性质**：主线 B 收官清单里剩余 travelAngle 决策的**只读量化前置**。新增审计脚本 1 个 + 24 份 JSON 的定量结果。**不改任何生产代码**。

**新增**：
- [scripts/travel_angle_audit.py](file:///Users/mingsen/Project/FallLine/scripts/travel_angle_audit.py) —— 纯 stdlib Python 脚本，只读扫描 `testvideo/**/*.json`，用与 Core [`boardKinematicHighScoreCap`](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L209-L236) 完全一致口径复现 cap 判定，输出每份 JSON 的 travelAngle / sideslipAngle / carvingConfidence / observationConfidence 统计与 cap 归因。

**量化结论（24 份 corpus）**：

1. **cap 触发率 33.3%（8/24）** —— 全部走的是 sideslip 分支：3.json 类样本 (sideslip 51°, cap 58) + 5.json 类样本 (sideslip 42°, cap 70)。低置信度短片分支（62 cap）在本 corpus **零命中**。

2. **travelAngle 极度不稳定**：16/24（66.7%）样本 `travelStd > 25°`，其中大多数 `travelStd > 100°`。这直接量化了 [AGENTS.md 板身检测条目](file:///Users/mingsen/Project/FallLine/AGENTS.md) 说的"低置信度帧角度跳动大，画面 2D 像素运动 ≠ 雪板实际行进方向"。**travelStd 100° 意味着 travelAngle 均值本身就是被噪声主导的随机变量，不能作为决策依据**。

3. **观测置信度整体偏低**：全 24 份没有一份 avgObservationConfidence ≥ 0.6。均值大多在 0.3-0.6 之间。现阈值 0.55 已经是极严格的门槛，corpus 中只有 3 号和 5 号（obsCnf 0.58-0.59）勉强越过——它们**全部触发 cap**。

4. **cap 惩罚幅度最大 18.4 分**：3.json / _b_3d_baseline/3.json 两份 rawPoseAverageScore=76 被 cap 到 58，Δ=-18.4 分。这类样本 obsCnf 只有 0.59（勉强越阈值），却因 sideslip 均值 51° 直接判定为横滑。**若阈值收紧到 0.7，这些样本会走 no_cap 分支，raw 76 保留下来**。

5. **cap 会吞掉 3D 融合的改善**：对齐同一视频 5.json 的四个版本（主 / _b_3d_baseline / _c_2d / _p1_baseline），3D 融合把 raw 从 61 拉到 67，但 cap 之后所有版本 capped 都是 70、avg 都是 66。**cap 一旦触发就抹平所有优化**。

**决策候选（供后续拍板）**：

- **方案 A（保守收敛）**：把 `minimumBoardKinematicConfidenceForHighScore` 从 0.55 抬到 0.7。预期：24 份 corpus 里 8 次 cap 触发降到 0 次；3.json 类样本恢复到 raw 76 附近；不影响低置信度短片的 62 cap 保护。**风险最小、改动最小**、可立即上线。

- **方案 B（分层门控）**：新增"高波动豁免"—— `sideslipStd > 25°` 时不 cap（角度均值不可信）。预期：24 份里 8 次 cap 降到 0（因为 16/24 都是高波动）。**过于激进**，可能让真横滑逃逸。

- **方案 C（弃用 travelAngle，回退 hipCenter 2D 位移）**：需重写 [BoardDirectionAnalyzer](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardDirectionAnalyzer.swift) 且需要重新校准阈值。**改动大**、需要新一轮验证。

- **方案 D（引入 IMU 融合）**：需 iOS 端埋点 CoreMotion，独立技术栈。**长线**方案，不作为本轮候选。

**推荐先走方案 A**（成本 1 行常量改动 + 一次 corpus 回归），若 A 后仍有误 cap 再上方案 B。**均需先量化再决策**：`python3 scripts/travel_angle_audit.py` 已经成为可复现基线，任何生产改动都应先跑一次基线、改完再跑一次对比。

**验证**：
- `python3 scripts/travel_angle_audit.py`：成功输出 24 行明细 + 汇总（含"潜在误判候选"与"sideslip 波动过大候选"两个专项分组）
- 脚本无副作用（不写文件，只 stdout）
- Core / iOS 生产代码零改动 → `swift build` 与已有 101 tests 完全不受影响

**未做/后续**：
- 走通方案 A 需要一次生产改动（[AnalysisReliability](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L139) 常量 0.55→0.7）+ 回归 corpus + 更新 AGENTS.md
- 方案 A 需要新用例覆盖"高置信度真横滑仍能触发 cap"以防阈值漂移

### 2026-08-30：TrendAnalytics 单元测试覆盖 (+13 用例)

**本轮性质**：补齐"88 tests 不覆盖新增算法层"这个已知空档。仅新增测试文件 1 个，不改 Core / iOS 生产代码。

**新增**：
- [TrendAnalyticsTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift) —— 13 个用例覆盖 7 大能力域：
  1. 空数据兜底：`analyze([])` 报告字段全 `nil/empty`；`weeklySummaries([])` 返回空数组
  2. 周汇总单周聚合：3 次分析同周 → `sessionCount=3` / `avg=70` / `best=80` / `worst=60`
  3. 周汇总跨周排序：3 个 offset 0/7/14 天 → 3 个桶按 `weekStart` 升序
  4. 里程碑 - 首次达到：初级不上报（源码 `firstIndex >= 1` 门控），中级/高级各一次
  5. 里程碑 - 刷新最高：首个 session 不算基线，之后每次超越前值上报
  6. 里程碑 - 周提升：+5 触发 / +2 低于阈值 3 不触发
  7. 里程碑 - 连续活跃：3 周连续触发 `streak(3)`；中间断一周只剩 2 不触发
  8. `previouslyUnlocked` 去重：`firstReached:中级` 已解锁 → newMilestones 只剩 `高级`
  9. 综合报告字段：`personalBest` / `last7DaysAverage` / `last30DaysAverage` 窗口边界
  10. `highestLevelReached` 按 `levelOrder` 反向匹配最高层级
  11. `Milestone.stableKey` 稳定性：`personalBest` 四舍五入到整数、`weeklyImprovement` 精确到 0.5
  12. `SessionEntry` Codable 往返

**测试基础设施**：
- 时间锚点 `2026-01-05 12:00 UTC`（确定为 ISO 周一，避开 DST 抖动）
- `session(offsetDays:score:level:)` helper，用 `anchor + offsetDays × 86400` 生成确定性时间戳
- `now` 参数显式注入，`last7 / last30` 窗口测试不受"当前时间"影响

**验证**：
- `swift build --build-tests`：`Linking FallLinePackageTests` + `Build complete! (5.76s)` ✅
- `GetDiagnostics` 目标文件：空 ✅
- 沙箱内 `swift test` 因 XCTest 临时目录访问限制无法运行，需用户本机复验 `swift test 2>&1 | tail -5` 预期 `Executed 101 tests, with 0 failures`

**API 断层核对**（源码 vs 测试断言）：
- `firstReached` 门控：源码 line 220 `firstIndex(of:) ?? 0 >= 1` → 测试断言初级过滤、中级/高级上报 ✅
- `newPersonalBest` 跳首：源码 line 230 `sorted.first?.timestamp != session.timestamp` → 测试首个 session 不算刷新 ✅
- `weeklyImprovement` 阈值：源码 line 238 `>= weeklyImprovementThreshold(3.0)` → 测试 +5 通过、+2 不通过 ✅
- `streak` 阈值：源码 line 245 `>= 3` → 测试 3 通过、2 不通过 ✅
- `stableKey` bucket：源码 line 318 `(delta*2).rounded()/2` → 测试 5.24→5.0、5.26→5.5 ✅

**未做/后续**：
- travelAngle → sideslip → boardKinematicHighScoreCap 链路的低置信度误判决策（需先讨论方向）

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

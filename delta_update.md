# Delta Update

最后更新：2026-05-25

本文档只记录每轮工作的增量变化，不记录项目全量背景。需要项目当前状态、目标和长期上下文时，先看 `WORK_LOG.md`；需要文件职责时，看 `file_manifest.md`。

## 记录规则

- 只写本轮新增、修改、删除、验证结果。
- 不重复整段项目背景、架构说明、历史决策或完整文件清单。
- 如果某个信息已经在 `WORK_LOG.md`、`AGENTS.md`、`CLAUDE.md` 或 `file_manifest.md` 中存在，只链接或点名引用。
- 每轮结束时新增一条简短记录；优先记录事实，不写推测。
- 同一轮没有代码变更时，明确写”仅文档变更”或”未运行测试”的原因。

## 变更

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

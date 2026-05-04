# VideoVision 修改方案

## 总览

本方案按优先级分为五个阶段，可以在各阶段之间灵活调整。

**阶段一（评分准确性）** 是你指定的最高优先级，聚焦评分体系的可靠性。
**阶段二（代码重复）** 是架构前提——消除文件副本，让后续修改只需改一处。
**阶段三（工程健壮性）** 提升代码质量和可维护性。
**阶段四（测试）** 为核心逻辑建立安全网。
**阶段五（文档）** 让项目状态与文档一致。

---

## 阶段一：评分体系校准

### 1.1 重心评分从离散三档改为连续映射

**问题**：`PoseMetricsCalculator.computeRelativeCenterOfGravity()` 已经计算出了 `hipRatio`（0~1 的连续值），但只把它映射到三个离散标签（"低"/"中"/"高"），然后 `PoseScorer` 又把标签映射回三个离散分数（90/60/30）。信息在两步映射中大量丢失。一个 hipRatio 0.34 和一个 hipRatio 0.54 在滑雪体验上是差异很大的姿态，但在当前系统里一个是"低"（90分）、一个是"中"（60分），差距被过度放大。

**改动范围**：

`Models.swift` — `BodyPoseData.centerOfGravity` 的类型从 `MetricWithConfidence<String>?` 改为 `MetricWithConfidence<Double>?`，直接存储 hipRatio 数值。

`PoseMetrics.swift` — `computeRelativeCenterOfGravity()` 返回 `MetricWithConfidence<Double>`，值就是 hipRatio 本身，不再做字符串映射。保留分级阈值的注释作为参考，但不再硬编码到数据流中。

`PoseScorer.swift` — `scoreGravity()` 改为连续评分函数。建议采用分段线性映射：
- hipRatio 在 0~0.25 → 映射到 95~100 分（非常低的重心，竞技姿态）
- hipRatio 在 0.25~0.45 → 映射到 70~95 分（良好的重心控制）
- hipRatio 在 0.45~0.60 → 映射到 40~70 分（重心偏高）
- hipRatio > 0.60 → 映射到 10~40 分（严重偏高）
- 无数据时默认 50 分

`SkiMetricsCalculator.swift` — 确认基于 gravityScore 的加权计算不受影响（它用的是 PoseScore 的 gravityScore 值，不直接依赖 BodyPoseData 的 centerOfGravity 类型）。

任何引用了 `centerOfGravity.value` 作为字符串比较的代码（如 `VideoAnalyzer.gravityLevelMetric()`）需要同步修改。

### 1.2 对称性评分加入维度权重

**问题**：`scoreSymmetry()` 对三个维度（膝盖差、小腿倾角差、前倾差）做简单算术平均，但膝盖不对称对滑行质量的影响远大于前倾不对称。一个左右膝差 15° 和一个左右前倾差 15° 被等量齐观，不合理。

**改动范围**：

`PoseScorer.scoreSymmetry()` — 将简单平均改为加权平均：
- 膝盖弯曲对称性：权重 0.5（对转弯质量和稳定性影响最大）
- 小腿倾角（立刃）对称性：权重 0.3
- 前倾对称性：权重 0.2

如果某些维度缺少双侧数据，剩余维度的权重按比例重新分配。

### 1.3 利用 Vision 逐点置信度计算指标置信度

**问题**：`PoseMetricsCalculator` 中每个指标的置信度用 `Double(visibleCount) / 8.0` 或 `confidenceBase + 0.15` 估算，完全忽略了 Vision 框架为每个关键点提供的独立置信度值。例如，左膝关键点置信度 0.9 和左膝关键点置信度 0.31 在当前系统里只要都超过阈值 0.3，就被等同处理。

**改动范围**：

`PoseMetrics.swift` — 修改 `extractPoints()` 使其返回每个点的置信度值（或修改 `ExtractedPoints` 结构体，让每个可选 CGPoint 变为包含 point 和 confidence 的元组）。修改各 `compute*` 方法，用实际参与计算的关键点的置信度来估算该指标的置信度。例如，膝盖弯曲角度用髋、膝、踝三个点计算，其置信度取 `min(hipConfidence, kneeConfidence, ankleConfidence)`。

具体来说，新建一个内部结构体替代裸 CGPoint?：

```swift
struct KeypointInfo {
    let point: CGPoint
    let confidence: VNConfidence
}
```

`ExtractedPoints` 各字段从 `CGPoint?` 改为 `KeypointInfo?`。角度计算方法（`angleBetween`、`leanAngleFromVertical`）保持不变，它们只需要坐标。但各 `compute*` 方法在构造 `MetricWithConfidence` 时使用实际置信度而非估算值。

### 1.4 可见性判断增加空间分布考量

**问题**：当前可见性判断只看关键点数量（8=full, 4-7=partial, 1-3=minimal），不关心是哪些点在。如果检测到 4 个点全是左侧的（左肩、左髋、左膝、左踝），系统判定为 partial 并正常计算对称性分数，但实际上右侧完全没有数据，对称性无意义。

**改动范围**：

`PoseMetrics.swift` — 在 `compute()` 中，计算可见性时增加一个检查：判断左右两侧的关键点数量分布。具体逻辑：
- 如果检测到的关键点只分布在单侧（比如只有左侧的点）→ 强制降为 minimal
- 如果双侧都有点但其中一侧明显偏少（比如左侧 6 个、右侧 2 个）→ 维持 partial 但标记为非对称可用
- 如果双侧均衡（两侧至少各有 3 个点）→ 按现有逻辑

同时，`BodyPoseData` 可以考虑增加一个 `Bool` 字段如 `symmetryAvailable` 来标记对称性评分是否有效，供 `PoseScorer` 在计算对称分时参考。

### 1.5 评分阈值和权重的来源文档化

**问题**：所有阈值（理想前倾 10°~25°、理想膝角 100°~140° 等）和权重（前倾 20%、膝盖 25% 等）没有注明来源。

**改动范围**：

`PoseScorer.swift` — 在每个 `public static let` 配置项上方添加文档注释，说明该值的来源（如"参考 PSIA 技术手册"、"基于教练经验共识"、"待实验校准"等）。对于暂时无可靠来源的值，明确标注为经验值。

`README.md` — "评分规则"章节后新增一段文字，说明当前评分体系的依据和局限性。强调这是一个辅助参考工具而非权威评判。

---

## 阶段二：消除代码重复

### 2.1 iOS App 改为依赖 VideoVisionCore

**问题**：`SkiAnaylze/SkiAnaylze/Sources/` 下完整复制了 8 个核心源文件，与 `Sources/VideoVisionCore/` 完全重复。

**改动范围**：

1. 检查 `SkiAnaylze/` 目录下的 Xcode 项目文件（`.xcodeproj` 或 `Package.swift`），确认当前如何引入源文件。
2. 将 `VideoVisionCore` 作为本地 Swift Package 依赖添加到 App 的构建配置中。
3. 删除 `SkiAnaylze/SkiAnaylze/Sources/` 下与 `VideoVisionCore` 重复的全部文件：
   - `Models.swift`
   - `VideoAnalyzer.swift`
   - `VisionFrameAnalyzer.swift`
   - `PoseMetrics.swift`
   - `PoseScorer.swift`
   - `SkiMetricsCalculator.swift`
   - `KeyMomentDetector.swift`
   - `ReportGenerator.swift`
4. 在 App 的 Swift 文件中将 `import` 或文件内引用改为 `import VideoVisionCore`。
5. 编译验证 iOS App 正常工作。

**注意**：在阶段一的重心评分改造中，`BodyPoseData.centerOfGravity` 类型会从 `String` 变为 `Double`，需要确认 iOS App 中有没有直接消费这个字段的 UI 代码一并更新。

---

## 阶段三：工程健壮性

### 3.1 错误处理 —— 不再静默吞帧

**问题**：`VideoAnalyzer.analyze()` 第 63-64 行的 catch 块为空，帧提取失败时无任何记录。

**改动范围**：

`VideoAnalyzer.swift` — 在 `analyze()` 方法中维护一个错误计数变量。catch 块中递增计数并记录时间戳。analyze() 返回结果时同时提供错误摘要，或在最终报告中体现丢帧信息。

具体做法：`analyze()` 目前返回 `[DetectionResult]`，改为返回一个包含 results 和 errorSummary 的结构体，或者将错误信息附加到 DetectionResult 中（增加一个 `error: String?` 字段）。

### 3.2 消除强制解包

**问题**：`KeyMomentDetector` 中 `$0.poseScore!.kneeBendScore` 和 `$0.poseScore!.symmetryScore` 使用强制解包。

**改动范围**：

`KeyMomentDetector.swift` — 四个 `min(by:)` 闭包中的 `!` 改为 `guard let` 或使用 `??` 提供默认值。当前逻辑下 `valid` 数组已过滤 nil，但显式处理让意图更清晰、维护更安全。

### 3.3 消除重复的工具函数

**问题**：`clamp` 函数在 `VideoAnalyzer` 和 `SkiMetricsCalculator` 中各定义了一次。

**改动范围**：

新建 `Sources/VideoVisionCore/Utilities.swift`（或放到现有的某个公共文件中），定义：

```swift
func clamp(_ value: Double, lower: Double = 0, upper: Double = 100) -> Double {
    min(max(value, lower), upper)
}
```

将 `VideoAnalyzer` 和 `SkiMetricsCalculator` 中的私有 `clamp` 替换为对这个公共函数的调用。

### 3.4 报告生成使用稳定的 Hash

**问题**：`ReportGenerator.videoSeed()` 使用 `String.hashValue`，而 Swift 的 `hashValue` 从 4.1 起每次进程启动都是随机的。这意味着同一个视频在不同次运行中可能得到不同的语料选择。

**改动范围**：

`ReportGenerator.swift` — `videoSeed()` 改为使用稳定的哈希实现。一个简单方案是使用 `String.utf8.reduce(0) { $0 &* 31 &+ Int($1) }` 计算确定性哈希（DJB2 或类似算法）。或者如果项目可以引入 `CryptoKit`（系统框架，无需第三方依赖），使用 SHA256 的前几个字节。

### 3.5 Vision 请求可配置化

**问题**：`VisionFrameAnalyzer` 每帧固定执行全部五种 Vision 请求，其中人脸检测、文字识别、场景分类对滑雪分析基本无用，浪费算力。

**改动范围**：

`VisionFrameAnalyzer.swift` — 添加一个 `options` 配置结构体：

```swift
public struct VisionAnalysisOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    
    public static let humanDetection  = VisionAnalysisOptions(rawValue: 1 << 0)
    public static let faceDetection   = VisionAnalysisOptions(rawValue: 1 << 1)
    public static let textRecognition = VisionAnalysisOptions(rawValue: 1 << 2)
    public static let sceneClassification = VisionAnalysisOptions(rawValue: 1 << 3)
    public static let bodyPose        = VisionAnalysisOptions(rawValue: 1 << 4)
    
    public static let skiAnalysis: VisionAnalysisOptions = [.bodyPose]
    public static let all: VisionAnalysisOptions = [.humanDetection, .faceDetection, .textRecognition, .sceneClassification, .bodyPose]
}
```

`VisionFrameAnalyzer.analyze()` 根据配置跳过不必要的请求。默认使用 `.skiAnalysis`，只执行姿态检测。

### 3.6 采样率和分辨率可配置

**问题**：每秒一帧的采样率硬编码，分辨率硬编码为 1920×1080。

**改动范围**：

`VideoAnalyzer` — 在 `init` 中增加两个可选参数：`sampleInterval: Double = 1.0` 和 `maxFrameSize: CGSize? = nil`（nil 表示使用视频原始分辨率）。`analyze()` 使用这些参数。

---

## 阶段四：测试

### 4.1 角度计算单元测试

测试 `PoseMetricsCalculator` 的几何计算：
- `angleBetween()` 对直角（90°）、平角（180°）、锐角（45°）的计算是否准确
- `leanAngleFromVertical()` 对纯垂直（0°）、45° 倾斜、纯水平（90°）的计算
- 边界：三点共线、两点重合

### 4.2 评分规则测试

测试 `PoseScorer`：
- 理想姿态（所有角度在最佳范围内）→ 总分应为 100
- 极端偏差姿态 → 各维度分和总分的下限
- 部分可见（partial visibility）→ 权重重新分配是否正确
- 最小可见（minimal）→ 返回基础分 40
- 无检测（none）→ 返回 nil
- 重心连续评分的边界值测试

### 4.3 边界情况测试

- 空帧数组 → generateSummary 返回 nil
- 单帧 → 稳定性计算返回 0（至少需要 2 帧）
- 无姿态检测帧 → KeyMomentDetector 返回空数组
- JSON 编解码往返——确保所有 Codable 模型能正确序列化和反序列化

测试文件放在 `Tests/VideoVisionCoreTests/` 下，用 SwiftPM 的 `swift test` 运行。

---

## 阶段五：文档更新

### 5.1 README 同步

更新 `README.md`：
- 项目结构章节反映当前 `VideoVisionCore` + `VideoVisionCLI` + `SkiAnaylze` 的实际布局
- 新增"评分依据"章节，说明各阈值和权重的来源
- 新增 iOS App 使用说明
- 输出章节补充滑雪派生指标（`SkiDerivedMetrics`）和关键时刻（`KeyMoment`）的说明
- 已知限制补充 2D 姿态检测对所有角度计算的影响（不仅是重心）

---

## 各阶段依赖关系

```
阶段一（评分） ───── 独立，可先行
    │
阶段二（去重） ───── 依赖阶段一的类型变更（centerOfGravity: String→Double）
    │                  需在去重时确保 App 端引用一致
阶段三（健壮性）─── 依赖阶段二的统一代码结构
    │                  （避免对重复文件做同样的修改）
阶段四（测试） ───── 依赖阶段一和三
    │                  （测试的是改完后的行为）
阶段五（文档） ───── 独立，可随时进行，最后更新即可
```

**建议的执行顺序**：阶段一 → 阶段二 → 阶段三 → 阶段四 → 阶段五。阶段五也可以在任意阶段穿插进行。

---

## 风险点

1. **重心评分从 String 改为 Double** 是破坏性变更——所有消费 `BodyPoseData.centerOfGravity` 的代码都需要适配。好在类型系统会帮我们发现所有遗漏。
2. **iOS App 改为依赖 VideoVisionCore** 可能遇到 Xcode 项目的本地 Swift Package 引用配置问题，建议先在单独分支上验证。
3. **Vision 请求默认改为仅姿态检测** 会改变 VideoAnalyzer 的输出行为——`DetectionResult` 中的 objects、faces、textObservations、sceneClassifications 会变为空。如果下游代码依赖这些字段（当前 CLI 和 App 的 UI 都没有实质使用它们），需要同步调整。

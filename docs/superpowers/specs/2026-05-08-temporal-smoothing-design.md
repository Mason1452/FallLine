# TemporalSmoother — 时序平滑模块设计

## 背景

VideoVision 使用 Apple Vision 框架的 `VNDetectHumanBodyPoseRequest` 逐帧分析滑雪姿态。用户反馈从侧后方跟拍的视频中，Vision 返回的关键点置信度普遍偏低，导致以下问题：

- 单帧关键点位置噪声较大，角度计算不稳定
- 置信度过低时帧被 `reliablePoseFrames` 过滤，损失有效数据
- 转弯阶段检测（TurnPhaseDetector）基于有符号倾斜信号，单帧噪声影响弯型分段

根本原因：Vision 的人体姿态模型以正面姿态训练为主，侧后方跟拍和非标准滑雪蹲姿不在其最优检测范围内。

## 设计方案

### 架构变更

在 `VideoAnalyzer.analyze()` 逐帧检测完成后、post-processing 之前插入 `TemporalSmoother` 模块：

```
逐帧分析（VisionFrameAnalyzer → PoseMetrics → PoseScorer）
  → [新增] TemporalSmoother（3帧滑动窗口中值滤波）
  → SkiMetricsCalculator
  → BoardDirectionAnalyzer
  → TurnPhaseDetector
  → CenterOfMassFitCalculator
  → KeyMomentDetector
  → ReportGenerator
```

### TemporalSmoother 模块

**新文件：** `Sources/VideoVisionCore/TemporalSmoother.swift`

```swift
public struct TemporalSmoother {
    public let windowSize: Int = 3

    public func smooth(frames: [DetectionResult]) -> [DetectionResult]
}
```

**输入：** 全视频的 `[DetectionResult]` 数组（已包含 BodyPoseData 和 PoseScore）

**输出：** 同样长度的 `[DetectionResult]` 数组，其中 BodyPoseData 和 PoseScore 用平滑后的值替换。

**处理逻辑：**

对每一帧 `i`：

1. 如果 `frames[i].bodyPose.detected == false`，跳过该帧，原样保留
2. 从相邻帧 `[i-1, i, i+1]` 中筛选出有效（detected == true）的帧
3. 如果有效帧不足 2 帧，跳过平滑，原样保留
4. 对 8 个关键点（左右肩/髋/膝/踝）的每个 `JointPoint`，取窗口内对应关节位置的 **中值**（分别对 `location.x`、`location.y`、`confidence` 做中值滤波）
5. 用平滑后的关键点，重新调用 `PoseMetricsCalculator.compute(from:)` 生成新的 `BodyPoseData`
6. 用新的 `BodyPoseData` 重新调用 `PoseScorer.score(pose:)` 生成新的 `PoseScore`
7. 替换原帧的 `bodyPose` 和 `poseScore`

**帧边界处理：**

- 第 0 帧：窗口为 `[0, 1]`
- 第 1 帧至倒数第 2 帧：窗口为 `[i-1, i, i+1]`
- 最后一帧：窗口为 `[n-2, n-1]`

### 置信度模型

最终置信度 = `medianConfidence × (1 + consistencyBoost)`

- `medianConfidence`：窗口内 confidence 的中值
- `consistencyBoost`：窗口内三帧关节位置标准差越小，boost 越高
  - `consistencyBoost = clamp(0.20 - stddev × 5, 0, 0.20)`
  - 因子 5 将归一化坐标的标准差映射到 boost 值（如 stddev=0.02 → boost=0.10）
  - 最多 boost 20%，最少 boost 0%

如果平滑后的置信度低于原始单帧置信度，取两者中较高者。

### VideoAnalyzer 集成

在 `VideoAnalyzer` 中新增参数和逻辑：

```swift
public init(
    videoURL: URL,
    pointConfidenceThreshold: VNConfidence = 0.3,
    sampleInterval: Double = 0.2,
    maxFrameSize: CGSize? = CGSize(width: 1920, height: 1080),
    visionOptions: VisionAnalysisOptions = .skiAnalysis,
    enableSmoothing: Bool = true  // 默认开启
)
```

在 `analyze()` 方法 return 之前，如果 `enableSmoothing == true`，调用 `TemporalSmoother.smooth(frames:)`。

`main.swift` 无改动（默认开启）。

### 边界情况

| 场景 | 处理 |
|---|---|
| 视频只有 1-2 帧 | 有效帧不足，跳过平滑，原样返回 |
| 中间某一帧无人检测 | 该帧不参与相邻帧的窗口，窗口缩小 |
| 连续多帧无人检测 | 逐帧处理，每个窗口独立判断 |
| 平滑后置信度反而低于原始 | 取原始和平滑中置信度较高的那个 |
| 所有帧都检测失败 | `smooth()` 直接返回原数组 |
| 窗口内所有帧的关键点一致 | 平滑结果与原始结果一致，无副作用 |

### 测试

**新文件：** `Tests/VideoVisionCoreTests/TemporalSmootherTests.swift`

测试策略：

1. **噪声抑制测试**：构造 5 帧序列，中间帧的关键点坐标添加模拟噪声。验证平滑后角度变化小于原始角度变化。
2. **单帧保留测试**：输入 1 帧，验证原样返回，不崩溃。
3. **缺失帧跳过测试**：输入序列中包含无检测帧，验证窗口正确收缩，不报错。

## 不变的部分

以下逻辑全部不变：
- `PoseMetricsCalculator` 的角度计算和提取逻辑
- `PoseScorer` 的评分阈值和权重
- `AnalysisReliability` 的置信度阈值（0.30/0.35）
- `reliablePoseFrames` 过滤逻辑
- 所有 post-processing 模块（SkiMetricsCalculator, BoardDirectionAnalyzer, TurnPhaseDetector, CenterOfMassFitCalculator, KeyMomentDetector, ReportGenerator）
- JSON 输出格式和字段

## 效果预期

- 有效帧比例提升：低置信度帧经过平滑后置信度提升 10-20%
- 角度稳定性：帧间角度跳动降低 30-50%
- 转弯阶段分段：边缘信号更平滑，减少误判的 phase transition
- 对已有的高分视频（高置信度帧）影响极小，平滑前后结果基本一致

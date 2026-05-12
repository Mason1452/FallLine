# Optical Flow Scoring Enhancement — Design Spec

**Date:** 2026-05-11
**Status:** Approved
**Author:** Mason (User) + Claude (Assistant)

## Problem Statement

当前评分系统基于 Apple Vision 2D 人体姿态检测，存在泛化性差的问题：

1. **特定滑法失准**：固定理想范围（膝盖 80-135°、倾斜 10-60°）对所有滑法一刀切，但不同滑法（刻滑 vs 小弯 vs 蘑菇）的"好姿态"本身就不同
2. **新视频不可预测**：在已校准锚点上分数合理，但新视频（不同的拍摄角度、雪况、光线）经常出现不合理的高低分
3. **2D 投影歧义**：2D 画面无法区分前倾和侧倾，拍摄角度一变，同一个动作的投影完全不同

## Root Cause

评分系统只看「静态姿态几何」，不看「运动模式」。运动模式（上下身分离、方向稳定性、动作流畅度）对不同拍摄角度和滑法天然更鲁棒——例如膝盖弯曲伸展的节奏在侧面和正面视角下虽然形态不同，但节律一致。

## Solution

引入 Apple Vision 的光流（Optical Flow）作为姿态评分的补充信号。光流检测 `VNGenerateOpticalFlowRequest` 已在 Apple Vision 框架中可用，不需要引入外部依赖。

### 版本策略

**Phase 1（本 spec）**：光流作为后处理质量调制器。光流指标不参与逐帧评分，在 `generateSummary()` 阶段作为总分调制因子，修正姿态评分的系统性偏差。改动最小，风险最低，可快速验证光流信号是否有效。

**Phase 2（后续，效果验证后）**：将光流指标正式纳入 `PoseScorer` 作为独立评分维度（从 5 维扩展到 7-8 维），赋予固定权重参与逐帧评分。

## Architecture

### Pipeline Overview

```
VideoAnalyzer.analyze()
  └─ 逐帧: VisionFrameAnalyzer → PoseMetricsCalculator → PoseScorer → DetectionResult
       └─ 新增: 缓存 (CGImage, BodyPoseData) 帧对

VideoAnalyzer.generateSummary()
  ├─ 现有: 聚合评分 → applyEvidenceCaps → rawTotalScore
  ├─ 新增: FlowMetricsCalculator.compute(from: cachedFrames)
  └─ 新增: applyFlowModulation(rawTotalScore, flowMetrics) → finalScore
```

### Design Principles

- **不修改逐帧循环**：`DetectionResult`、`PoseScorer`、`VisionFrameAnalyzer` 结构不变
- **光流是调制因子，不是独立分数**：调制范围 ±13%，保证光流是"修正"而非"主导"
- **降级容错**：光流计算失败时返回调制系数 1.0，不影响现有评分
- **帧缓存仅在内存**：不持久化，不增加磁盘开销

## Optical Flow Metrics

### Metric 1: Motion Coherence (运动一致性)

测量髋部与脚踝光流方向的差异，反映上下身分离程度。

- **计算**：取 root/hip 关键点光流方向 vs 脚踝关键点光流方向，计算夹角
- **映射**：
  - 夹角 ≤ 15° → 100 分（高度分离，典型刻滑特征）
  - 夹角 ≥ 60° → 0 分（无分离）
- **调制**：coherence > 70 → 调制系数 +0.05
- **不惩罚低值**：低一致性不扣分，因为不是所有滑法都需要上下身分离

### Metric 2: Directional Stability (方向稳定性)

测量髋部运动方向的帧间一致性。

- **计算**：连续帧髋部光流方向的 circular variance
- **映射**：
  - variance < 0.15 → 100 分（方向高度一致，典型走刃）
  - variance > 0.5 → 0 分（方向漂移，典型搓雪）
- **调制**：stability > 70 且姿态总分 < 75 → 调制系数 +0.08（拍摄角度可能低估了实际质量）
- **调制**：stability < 30 且姿态总分 > 75 → 调制系数 -0.08（静态好姿态但运动不稳定）

### Metric 3: Velocity Smoothness (速度平滑度)

光流幅值（运动速度）的帧间变化率。

- **计算**：相邻帧光流幅值的变化率
- **映射**：
  - 变化率 < 15% → 100 分（运动流畅）
  - 变化率 > 50% → 0 分（运动突变）
- **调制**：smoothness < 40 → 调制系数 -0.05（动作不流畅降低信心）
- **不提升**：平滑度高不做提升（好是应该的）

### Modulation Formula

```
modulation = 1.0
if coherence > 70:                    modulation += 0.05
if stability > 70 && poseScore < 75:  modulation += 0.08
if stability < 30 && poseScore > 75:  modulation -= 0.08
if smoothness < 40:                   modulation -= 0.05

finalScore = clamp(rawScore × modulation, 0, 100)
```

调制范围：0.87 ~ 1.13

阈值和幅度为初始经验值。批量回归 49 个视频后可根据实际效果校准。

## Implementation

### New File: `FlowMetricsCalculator.swift`

```swift
public struct FlowMetricsCalculator {
    /// Compute all three flow metrics from cached frame pairs
    public func compute(from framePairs: [(CGImage, BodyPoseData)]) -> FlowMetrics
    
    /// Apply flow modulation to raw pose score
    public func applyModulation(poseScore: Double, metrics: FlowMetrics) -> Double
}

public struct FlowMetrics {
    public let motionCoherence: Double      // 0-100
    public let directionalStability: Double // 0-100
    public let velocitySmoothness: Double   // 0-100
    public let modulationFactor: Double     // 0.87-1.13
    public let framePairsUsed: Int          // how many frame pairs contributed
}
```

### Modified: `VideoAnalyzer.swift`

**Frame caching** — in `analyze()`, alongside result collection:
```swift
private var frameCache: [(CGImage, BodyPoseData)] = []
// After each successful pose detection:
if bodyPose.detected && bodyPose.visibility != .none {
    frameCache.append((cgImage, bodyPose))
}
```

**Flow computation** — new method:
```swift
private func computeFlowMetrics() -> FlowMetrics {
    guard frameCache.count >= 2 else {
        return FlowMetrics(motionCoherence: 0, directionalStability: 0,
                          velocitySmoothness: 0, modulationFactor: 1.0,
                          framePairsUsed: 0)
    }
    let calculator = FlowMetricsCalculator()
    let framePairs = stride(from: 0, to: frameCache.count - 1, by: 1).compactMap { i in
        // pair consecutive frames
        (frameCache[i].0, frameCache[i].1, frameCache[i+1].0, frameCache[i+1].1)
    }
    return calculator.compute(from: framePairs)
}
```

**Integration in `generateSummary()`** — after computing `avg`:
```swift
let flowMetrics = computeFlowMetrics()
let flowModulatedScore = FlowMetricsCalculator()
    .applyModulation(poseScore: avg, metrics: flowMetrics)
// flowModulatedScore is used for final VideoSummary.averageScore
```

### Modified: `Models.swift`

`VideoSummary` 新增可选字段：
```swift
public let flowMotionCoherence: Double?
public let flowDirectionalStability: Double?
public let flowVelocitySmoothness: Double?
```

### Modified: `ReportGenerator.swift`

在报告技术细节区展示光流指标（不影响主报告结构）。

### New Tests: `FlowMetricsCalculatorTests.swift`

测试覆盖：
- 正常帧对 → 三个指标在有效范围内
- 空帧对 → 返回默认值、调制系数 1.0
- 单帧对 → 无法计算 sequential metrics，降级处理
- 调制边界 → 验证 clamp 到 0-100

## Edge Cases

| Scenario | Handling |
|----------|----------|
| 有效帧对 < 3 | 调制系数 = 1.0，跳过光流 |
| 关键点置信度 < 0.3 | 该帧对光流采样降权或跳过 |
| 单帧光流请求失败 | 不影响其他帧对，降级使用剩余帧对 |
| 调制后总分 > 100 | clamp 到 100 |
| 调制后总分 < 0 | clamp 到 0 |
| 全视频无可信姿态帧 | 不执行光流分析，调制系数 = 1.0 |

## Memory Consideration

- 1080p CGImage per frame: ~8MB
- 60 sec video × 5fps = 300 frames → ~2.4GB peak
- Only cache frames with successful pose detection (visibility ≥ .minimal)
- Not persisted to disk, freed after `generateSummary()` returns
- Future optimization: if memory becomes an issue, subsample to every 3rd frame for flow analysis

## Rollout

1. Implement `FlowMetricsCalculator` + tests
2. Integrate into `VideoAnalyzer`
3. Extend `VideoSummary` model and `ReportGenerator`
4. Run existing 65 tests — must all pass (no regression)
5. Batch run on all 49 videos
6. Compare flow-modulated scores vs original scores in `score_summary.tsv`
7. Manually review videos where modulation changed score by > 5 points
8. Calibrate modulation thresholds if necessary
9. If Phase 1 results are positive, plan Phase 2 (flow as scoring dimension)

## File Change Summary

| File | Change |
|------|--------|
| `Sources/VideoVisionCore/FlowMetricsCalculator.swift` | **New** |
| `Sources/VideoVisionCore/VideoAnalyzer.swift` | Frame cache + computeFlowMetrics + modulation call |
| `Sources/VideoVisionCore/Models.swift` | 3 optional fields in VideoSummary |
| `Sources/VideoVisionCore/ReportGenerator.swift` | Display flow metrics in tech section |
| `Tests/VideoVisionCoreTests/FlowMetricsCalculatorTests.swift` | **New** |

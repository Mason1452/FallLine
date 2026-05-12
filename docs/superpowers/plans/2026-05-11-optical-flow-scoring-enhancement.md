# Optical Flow Scoring Enhancement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optical flow as a post-processing quality modulator to the ski posture scoring pipeline, improving generalization across camera angles and skiing styles without changing per-frame pose analysis.

**Architecture:** Phase 1 — flow metrics computed after pose analysis in `generateSummary()`, acting as a ±13% modulation on the final score. New `FlowMetricsCalculator` handles flow computation and metric derivation; `VideoAnalyzer` caches frame images during `analyze()` and calls flow computation before returning `VideoSummary`.

**Tech Stack:** Swift + Apple Vision (`VNGenerateOpticalFlowRequest`), macOS 14+, no external dependencies.

---

### File Structure

| File | Role |
|------|------|
| `Sources/FallLineCore/FlowMetricsCalculator.swift` | **New** — Flow computation, 3-metric derivation, modulation formula |
| `Sources/FallLineCore/VideoAnalyzer.swift` | Frame cache during analyze(), computeFlowMetrics(), modulation in generateSummary() |
| `Sources/FallLineCore/Models.swift` | 3 optional flow fields in VideoSummary |
| `Sources/FallLineCore/ReportGenerator.swift` | Display flow metrics in tech section of report |
| `Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift` | **New** — Unit tests for metrics and modulation |

---

### Task 1: FlowMetrics data model + modulation formula

**Files:**
- Create: `Sources/FallLineCore/FlowMetricsCalculator.swift`

- [ ] **Step 1: Create the file with FlowMetrics struct and FlowMetricsCalculator skeleton**

```swift
import Foundation
import Vision
import CoreImage

// MARK: - 光流指标

/// 从光流分析中提取的三个质量指标，用于调制姿态评分。
/// 调制系数不在本结构体中存储——它依赖 poseScore 上下文，在 applyModulation 中动态计算。
public struct FlowMetrics {
    /// 运动一致性 0-100：髋部与脚踝光流方向差异，高值 = 上下身分离好
    public let motionCoherence: Double
    /// 方向稳定性 0-100：髋部运动方向帧间一致性，高值 = 走刃特征明显
    public let directionalStability: Double
    /// 速度平滑度 0-100：光流幅值变化率，高值 = 动作流畅
    public let velocitySmoothness: Double
    /// 参与计算的有效帧对数
    public let framePairsUsed: Int

    public init(
        motionCoherence: Double,
        directionalStability: Double,
        velocitySmoothness: Double,
        framePairsUsed: Int
    ) {
        self.motionCoherence = motionCoherence
        self.directionalStability = directionalStability
        self.velocitySmoothness = velocitySmoothness
        self.framePairsUsed = framePairsUsed
    }

    /// 空结果 — 无可用的光流数据时使用
    public static let empty = FlowMetrics(
        motionCoherence: 0,
        directionalStability: 0,
        velocitySmoothness: 0,
        framePairsUsed: 0
    )
}

// MARK: - 光流指标计算器

/// 从帧对序列计算光流质量指标，并将指标转化为姿态评分的调制系数。
///
/// 三个指标：
/// - motionCoherence: 髋部 vs 脚踝光流方向夹角 → 上下身分离度
/// - directionalStability: 髋部光流方向的 circular variance → 走刃/搓雪区分
/// - velocitySmoothness: 光流幅值变化率 → 动作流畅度
///
/// 调制范围 ±13%。
public struct FlowMetricsCalculator {

    // MARK: - 配置常量

    /// 光流采样时的关键点置信度最低要求
    public let minPointConfidence: Float = 0.3

    /// 调制参数
    public let coherenceBoostThreshold: Double = 70.0
    public let coherenceBoostAmount: Double = 0.05
    public let stabilityBoostThreshold: Double = 70.0
    public let stabilityBoostAmount: Double = 0.08
    public let stabilityPenaltyThreshold: Double = 30.0
    public let stabilityPenaltyAmount: Double = 0.08
    public let smoothnessPenaltyThreshold: Double = 40.0
    public let smoothnessPenaltyAmount: Double = 0.05
    /// 方向稳定性调制仅在姿态分低于此阈值时提升（避免已高分因拍摄角度被低估）
    public let stabilityBoostScoreCap: Double = 75.0
    /// 方向稳定性调制仅在姿态分高于此阈值时扣减（避免已低分再被压低）
    public let stabilityPenaltyScoreFloor: Double = 75.0

    public init() {}

    // MARK: - 主入口

    /// 计算光流指标并返回 FlowMetrics
    /// - Parameter framePairs: 连续帧对数组，每项为 (前帧图像, 前帧姿态, 后帧图像, 后帧姿态)
    /// - Returns: FlowMetrics，如果帧对不足返回 .empty
    public func compute(
        from framePairs: [(prevImage: CGImage, prevPose: BodyPoseData, nextImage: CGImage, nextPose: BodyPoseData)]
    ) async -> FlowMetrics {
        guard framePairs.count >= 2 else { return .empty }

        var coherenceSamples: [Double] = []
        var hipFlowDirections: [Double] = []
        var velocityChanges: [Double] = []
        var previousVelocity: Double? = nil

        for pair in framePairs {
            guard let flowVectors = await sampleFlowVectors(
                prevImage: pair.prevImage,
                nextImage: pair.nextImage,
                prevPose: pair.prevPose,
                nextPose: pair.nextPose
            ) else {
                continue
            }

            // 运动一致性：髋部 vs 脚踝方向差异
            let hipDir = atan2(flowVectors.hip.dy, flowVectors.hip.dx)
            let ankleDir = atan2(flowVectors.ankle.dy, flowVectors.ankle.dx)
            let dirDiff = abs(angleDifferenceDegrees(hipDir, ankleDir))
            let coherence = linearMap(dirDiff, inMin: 15, inMax: 60, outMin: 100, outMax: 0)
            coherenceSamples.append(coherence)

            // 髋部方向
            hipFlowDirections.append(hipDir)

            // 速度平滑度
            let velocity = sqrt(flowVectors.hip.dx * flowVectors.hip.dx + flowVectors.hip.dy * flowVectors.hip.dy)
            if let prev = previousVelocity {
                let changeRate = prev > 0 ? abs(velocity - prev) / prev : 0
                velocityChanges.append(changeRate)
            }
            previousVelocity = velocity
        }

        guard !coherenceSamples.isEmpty else { return .empty }

        let motionCoherence = clamp(coherenceSamples.reduce(0, +) / Double(coherenceSamples.count), lower: 0, upper: 100)
        let directionalStability = computeCircularStability(hipFlowDirections)
        let velocitySmoothness: Double
        if velocityChanges.isEmpty {
            velocitySmoothness = 50
        } else {
            let avgChange = velocityChanges.reduce(0, +) / Double(velocityChanges.count)
            velocitySmoothness = linearMap(avgChange, inMin: 0.15, inMax: 0.50, outMin: 100, outMax: 0)
        }

        return FlowMetrics(
            motionCoherence: motionCoherence,
            directionalStability: directionalStability,
            velocitySmoothness: velocitySmoothness,
            framePairsUsed: framePairs.count
        )
    }

    // MARK: - 调制公式

    /// 应用光流调制到原始姿态评分。
    /// 内部调用带 poseScore 上下文的 computeModulation，确保稳定性阈值判断正确。
    public func applyModulation(poseScore: Double, metrics: FlowMetrics) -> Double {
        guard metrics.framePairsUsed >= 2 else { return poseScore }
        let factor = computeModulation(
            coherence: metrics.motionCoherence,
            stability: metrics.directionalStability,
            smoothness: metrics.velocitySmoothness,
            poseScore: poseScore
        )
        return clamp(poseScore * factor, lower: 0, upper: 100)
    }

    /// 根据三个光流指标计算调制系数（不含稳定性阈值——稳定性依赖 poseScore 上下文）。
    /// 供基础测试使用；生产环境使用带 poseScore 的重载版本。
    public func computeModulation(
        coherence: Double,
        stability: Double,
        smoothness: Double
    ) -> Double {
        var modulation = 1.0
        if coherence > coherenceBoostThreshold {
            modulation += coherenceBoostAmount
        }
        if smoothness < smoothnessPenaltyThreshold {
            modulation -= smoothnessPenaltyAmount
        }
        return clamp(modulation, lower: 0.87, upper: 1.13)
    }

    /// 带姿态分上下文的完整调制系数（生产环境使用此版本）。
    /// stability 阈值仅在 poseScore 满足条件时触发 boost/penalty。
    public func computeModulation(
        coherence: Double,
        stability: Double,
        smoothness: Double,
        poseScore: Double
    ) -> Double {
        var modulation = 1.0
        if coherence > coherenceBoostThreshold {
            modulation += coherenceBoostAmount
        }
        if stability > stabilityBoostThreshold && poseScore < stabilityBoostScoreCap {
            modulation += stabilityBoostAmount
        }
        if stability < stabilityPenaltyThreshold && poseScore > stabilityPenaltyScoreFloor {
            modulation -= stabilityPenaltyAmount
        }
        if smoothness < smoothnessPenaltyThreshold {
            modulation -= smoothnessPenaltyAmount
        }
        return clamp(modulation, lower: 0.87, upper: 1.13)
    }

    // MARK: - 光流采样

    /// 帧对光流关键点采样结果
    private struct FlowSample {
        let hip: (dx: Double, dy: Double)
        let ankle: (dx: Double, dy: Double)
    }

    /// 在帧对之间运行 VNGenerateOpticalFlowRequest 并在关键点位置采样光流向量
    private func sampleFlowVectors(
        prevImage: CGImage,
        nextImage: CGImage,
        prevPose: BodyPoseData,
        nextPose: BodyPoseData
    ) async -> FlowSample? {
        // 检查关键点置信度
        guard let prevHipX = prevPose.hipCenterX, prevHipX.confidence >= minPointConfidence,
              let prevHipY = prevPose.hipCenterY, prevHipY.confidence >= minPointConfidence,
              let prevAnkleX = prevPose.ankleCenterX, prevAnkleX.confidence >= minPointConfidence,
              let prevAnkleY = prevPose.ankleCenterY, prevAnkleY.confidence >= minPointConfidence else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNGenerateOpticalFlowRequest(targetedCGImage: nextImage, options: [:])
            let handler = VNImageRequestHandler(cgImage: prevImage, options: [:])

            do {
                try handler.perform([request])
                guard let result = request.results?.first as? VNPixelBufferObservation else {
                    continuation.resume(returning: nil)
                    return
                }

                let buffer = result.pixelBuffer
                let width = CVPixelBufferGetWidth(buffer)
                let height = CVPixelBufferGetHeight(buffer)

                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

                guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
                    continuation.resume(returning: nil)
                    return
                }

                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                // 光流像素格式为 two-component float32: (dx, dy)
                let floatPtr = baseAddress.assumingMemoryBound(to: Float.self)
                let floatsPerRow = bytesPerRow / MemoryLayout<Float>.stride

                func sample(atX x: Double, y: Double) -> (dx: Double, dy: Double)? {
                    let px = Int(x * Double(width))
                    let py = Int(y * Double(height))
                    guard px >= 0, px < width, py >= 0, py < height else { return nil }
                    let offset = py * floatsPerRow + px * 2
                    return (Double(floatPtr[offset]), Double(floatPtr[offset + 1]))
                }

                guard let hipFlow = sample(atX: prevHipX.value, y: prevHipY.value),
                      let ankleFlow = sample(atX: prevAnkleX.value, y: prevAnkleY.value) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: FlowSample(hip: hipFlow, ankle: ankleFlow))
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - 数学工具

    /// 计算角度的 circular variance（0=完全一致, 1=完全随机）
    private func computeCircularStability(_ directions: [Double]) -> Double {
        guard directions.count >= 2 else { return 0 }
        var sumSin = 0.0
        var sumCos = 0.0
        for dir in directions {
            sumSin += sin(dir)
            sumCos += cos(dir)
        }
        let meanSin = sumSin / Double(directions.count)
        let meanCos = sumCos / Double(directions.count)
        let r = sqrt(meanSin * meanSin + meanCos * meanCos) // mean resultant length
        let variance = 1.0 - r // circular variance
        return linearMap(variance, inMin: 0.15, inMax: 0.50, outMin: 100, outMax: 0)
    }

    /// 两角度差（degrees）
    private func angleDifferenceDegrees(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b)
        let pi = Double.pi
        if diff > pi {
            return (2 * pi - diff) * 180.0 / pi
        }
        return diff * 180.0 / pi
    }
}
```

- [ ] **Step 2: Verify the file compiles**

```bash
swift build -c release 2>&1 | tail -5
```

Expected: Build succeeds (the file won't be linked yet since it's not referenced, but parsing should pass).

- [ ] **Step 3: Commit**

```bash
git add Sources/FallLineCore/FlowMetricsCalculator.swift
git commit -m "feat: add FlowMetricsCalculator with flow metrics model and modulation formula"
```

---

### Task 2: Unit tests for FlowMetricsCalculator

**Files:**
- Create: `Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift`

- [ ] **Step 1: Write the test file**

```swift
import XCTest
@testable import FallLineCore

final class FlowMetricsCalculatorTests: XCTestCase {

    let calculator = FlowMetricsCalculator()

    // MARK: - computeModulation (pure function tests)

    func testModulation_emptyState_returnsNeutral() {
        let mod = calculator.computeModulation(
            coherence: 0, stability: 0, smoothness: 100
        )
        XCTAssertEqual(mod, 1.0, accuracy: 0.001)
    }

    func testModulation_highCoherence_boostsScore() {
        let mod = calculator.computeModulation(
            coherence: 85, stability: 50, smoothness: 60
        )
        XCTAssertEqual(mod, 1.05, accuracy: 0.001)
    }

    func testModulation_full_highCoherenceAndStabilityAndLowPose_boosts() {
        // 4-param version: coherence > 70 → +0.05, stability > 70 + poseScore 60 (<75) → +0.08
        let mod = calculator.computeModulation(
            coherence: 85, stability: 85, smoothness: 60, poseScore: 60
        )
        XCTAssertEqual(mod, 1.13, accuracy: 0.001)
    }

    func testModulation_full_highStabilityAndHighPose_noStabilityBoost() {
        // stability > 70 but poseScore 80 (>75) → no stability boost
        let mod = calculator.computeModulation(
            coherence: 85, stability: 85, smoothness: 60, poseScore: 80
        )
        XCTAssertEqual(mod, 1.05, accuracy: 0.001)
    }

    func testModulation_full_lowStabilityAndHighPose_penalizes() {
        // stability 20 (<30) + poseScore 80 (>75) → -0.08, smoothness 60 (>40) → no penalty
        let mod = calculator.computeModulation(
            coherence: 50, stability: 20, smoothness: 60, poseScore: 80
        )
        XCTAssertEqual(mod, 0.92, accuracy: 0.001)
    }

    func testModulation_full_lowStabilityAndLowPose_noPenalty() {
        // stability 20 (<30) but poseScore 60 (<75) → no penalty (避免已低分再压低)
        let mod = calculator.computeModulation(
            coherence: 50, stability: 20, smoothness: 60, poseScore: 60
        )
        XCTAssertEqual(mod, 1.0, accuracy: 0.001)
    }

    func testModulation_lowSmoothness_penalizes() {
        let mod = calculator.computeModulation(
            coherence: 50, stability: 50, smoothness: 25
        )
        XCTAssertEqual(mod, 0.95, accuracy: 0.001)
    }

    func testModulation_allPositive_combination() {
        let mod = calculator.computeModulation(
            coherence: 85, stability: 50, smoothness: 60
        )
        // coherence > 70 → +0.05
        XCTAssertEqual(mod, 1.05, accuracy: 0.001)
    }

    func testModulation_allNegative_combination() {
        let mod = calculator.computeModulation(
            coherence: 50, stability: 50, smoothness: 25
        )
        // smoothness < 40 → -0.05
        XCTAssertEqual(mod, 0.95, accuracy: 0.001)
    }

    func testModulation_clampedToUpperBound() {
        let mod = calculator.computeModulation(
            coherence: 100, stability: 100, smoothness: 100, poseScore: 50
        )
        XCTAssertEqual(mod, 1.13, accuracy: 0.001)
    }

    func testModulation_clampedToLowerBound() {
        let mod = calculator.computeModulation(
            coherence: 0, stability: 0, smoothness: 0, poseScore: 100
        )
        XCTAssertEqual(mod, 0.87, accuracy: 0.001)
    }

    // MARK: - applyModulation

    func testApplyModulation_normalCase() {
        let metrics = FlowMetrics(
            motionCoherence: 85, directionalStability: 85,
            velocitySmoothness: 60, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 70, metrics: metrics)
        // coherence 85 (>70) → +0.05, stability 85 (>70) + poseScore 70 (<75) → +0.08
        // modulation = 1.13, 70 × 1.13 = 79.1
        XCTAssertEqual(result, 79.1, accuracy: 0.01)
    }

    func testApplyModulation_emptyMetrics_returnsUnchanged() {
        let result = calculator.applyModulation(poseScore: 70, metrics: .empty)
        XCTAssertEqual(result, 70, accuracy: 0.01)
    }

    func testApplyModulation_clampsAbove100() {
        let metrics = FlowMetrics(
            motionCoherence: 100, directionalStability: 100,
            velocitySmoothness: 100, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 95, metrics: metrics)
        // coherence > 70 → +0.05, stability 100 (>70) + poseScore 95 (>75) → no boost
        // modulation = 1.05, 95 × 1.05 = 99.75
        XCTAssertEqual(result, 99.75, accuracy: 0.01)
    }

    func testApplyModulation_clampsBelow0() {
        let metrics = FlowMetrics(
            motionCoherence: 0, directionalStability: 0,
            velocitySmoothness: 0, framePairsUsed: 10
        )
        let result = calculator.applyModulation(poseScore: 3, metrics: metrics)
        // coherence=0 (no boost), stability 0 (<30) + poseScore 3 (<75, no penalty)
        // smoothness 0 (<40) → -0.05, modulation = 0.95, 3 × 0.95 = 2.85
        XCTAssertEqual(result, 2.85, accuracy: 0.01)
    }

    // MARK: - FlowMetrics.empty

    func testEmptyFlowMetrics_hasNeutralValues() {
        XCTAssertEqual(FlowMetrics.empty.framePairsUsed, 0)
        XCTAssertEqual(FlowMetrics.empty.motionCoherence, 0)
        XCTAssertEqual(FlowMetrics.empty.directionalStability, 0)
        XCTAssertEqual(FlowMetrics.empty.velocitySmoothness, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (FlowMetricsCalculator not in test target yet)**

```bash
swift test --filter FlowMetricsCalculatorTests 2>&1 | tail -5
```

Expected: Build failure or 0 tests — because the test file references `FlowMetricsCalculator` which exists in the source directory but the tests may not link against it yet. If it builds, tests should pass.

- [ ] **Step 3: Verify tests pass**

```bash
swift test --filter FlowMetricsCalculatorTests 2>&1 | tail -10
```

Expected: All 15 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift
git commit -m "test: add FlowMetricsCalculator unit tests for modulation formula and edge cases"
```

---

### Task 3: Extend VideoSummary in Models.swift

**Files:**
- Modify: `Sources/FallLineCore/Models.swift:703-729`

- [ ] **Step 1: Add optional flow fields to VideoSummary**

Open `Sources/FallLineCore/Models.swift` and find `public struct VideoSummary: Codable {` around line 703. Add three new fields after `overallLevel`:

```swift
// In VideoSummary struct, after:
//     public let overallLevel: String
// Add:
    /// 光流运动一致性 0-100（Phase 1 实验指标）
    public let flowMotionCoherence: Double?
    /// 光流方向稳定性 0-100（Phase 1 实验指标）
    public let flowDirectionalStability: Double?
    /// 光流速度平滑度 0-100（Phase 1 实验指标）
    public let flowVelocitySmoothness: Double?

// In VideoSummary.init, add default-nil parameters after overallLevel:
        flowMotionCoherence: Double? = nil,
        flowDirectionalStability: Double? = nil,
        flowVelocitySmoothness: Double? = nil

// In init body, assign:
        self.flowMotionCoherence = flowMotionCoherence
        self.flowDirectionalStability = flowDirectionalStability
        self.flowVelocitySmoothness = flowVelocitySmoothness
```

The full updated struct should be:

```swift
public struct VideoSummary: Codable {
    public let averageScore: Double
    public let bestFrame: FrameScore
    public let worstFrame: FrameScore
    public let stabilityScore: Double
    public let scoreConsistencyScore: Double
    public let scoreStdDev: Double
    public let overallLevel: String
    public let flowMotionCoherence: Double?
    public let flowDirectionalStability: Double?
    public let flowVelocitySmoothness: Double?

    public init(
        averageScore: Double,
        bestFrame: FrameScore,
        worstFrame: FrameScore,
        stabilityScore: Double,
        scoreConsistencyScore: Double,
        scoreStdDev: Double,
        overallLevel: String,
        flowMotionCoherence: Double? = nil,
        flowDirectionalStability: Double? = nil,
        flowVelocitySmoothness: Double? = nil
    ) {
        self.averageScore = averageScore
        self.bestFrame = bestFrame
        self.worstFrame = worstFrame
        self.stabilityScore = stabilityScore
        self.scoreConsistencyScore = scoreConsistencyScore
        self.scoreStdDev = scoreStdDev
        self.overallLevel = overallLevel
        self.flowMotionCoherence = flowMotionCoherence
        self.flowDirectionalStability = flowDirectionalStability
        self.flowVelocitySmoothness = flowVelocitySmoothness
    }
}
```

Note: Since fields have defaults (`nil`), existing callers won't break.

- [ ] **Step 2: Verify code compiles**

```bash
swift build -c release 2>&1 | tail -5
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/FallLineCore/Models.swift
git commit -m "feat: add optional optical flow metrics fields to VideoSummary"
```

---

### Task 4: Integrate frame cache and flow computation in VideoAnalyzer

**Files:**
- Modify: `Sources/FallLineCore/VideoAnalyzer.swift`

- [ ] **Step 1: Add frame cache property**

At the top of the `VideoAnalyzer` class, after the existing properties (around line 24), add:

```swift
/// 光流分析用帧缓存（仅缓存姿态检测成功的帧）
private var frameCache: [(image: CGImage, pose: BodyPoseData)] = []
```

- [ ] **Step 2: Populate frame cache in analyze()**

In the `analyze()` method, find the successful frame analysis branch (the `do` block around line 76-79). After `results.append(result)`, add:

```swift
// 缓存姿态成功的帧用于后续光流分析
if result.bodyPose.detected && result.bodyPose.visibility != .none {
    frameCache.append((cgImage, result.bodyPose))
}
```

The updated `do` block in `analyze()` should look like:

```swift
do {
    let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
    let result = try await analyzeFrame(cgImage: cgImage, at: time)
    results.append(result)
    // 缓存姿态成功的帧用于后续光流分析
    if result.bodyPose.detected && result.bodyPose.visibility != .none {
        frameCache.append((cgImage, result.bodyPose))
    }
} catch {
```

- [ ] **Step 3: Add computeFlowMetrics method**

After the existing `calculateMotionStability` method (around line 386), add:

```swift
// MARK: - 光流指标计算

/// 基于缓存的帧对计算光流指标
private func computeFlowMetrics() async -> FlowMetrics {
    guard frameCache.count >= 2 else { return .empty }

    let calculator = FlowMetricsCalculator()

    // 构建连续帧对
    var pairs: [(prevImage: CGImage, prevPose: BodyPoseData, nextImage: CGImage, nextPose: BodyPoseData)] = []
    for i in 0..<(frameCache.count - 1) {
        pairs.append((
            prevImage: frameCache[i].image,
            prevPose: frameCache[i].pose,
            nextImage: frameCache[i + 1].image,
            nextPose: frameCache[i + 1].pose
        ))
    }

    return await calculator.compute(from: pairs)
}
```

- [ ] **Step 4: Integrate flow modulation in generateSummary()**

Method signature: change `generateSummary(from:)` to `async`:

```swift
public func generateSummary(from results: [DetectionResult]) async -> VideoSummary? {
```

In the method body, **replace** the `avg` computation block (where `avg` is set from `applyEvidenceCaps`) and the `overallLevel` + `return VideoSummary(...)` block with:

```swift
        let avg = applyEvidenceCaps(
            score: boardCappedAverage,
            reliableFrameCount: scoreEntries.count
        )

        // 光流调制
        let flowMetrics = await computeFlowMetrics()
        let modulatedScore = FlowMetricsCalculator().applyModulation(
            poseScore: avg,
            metrics: flowMetrics
        )

        // 找最佳/最差帧（仍基于原始姿态分，光流不改变帧级判断）
        var best = (time: 0.0, score: -1.0)
        var worst = (time: 0.0, score: 101.0)

        for entry in scoreEntries {
            if entry.score > best.score { best = (entry.time, entry.score) }
            if entry.score < worst.score { worst = (entry.time, entry.score) }
        }

        let overallLevel: String = {
            switch modulatedScore {
            case 85...100: return "专业"
            case 75..<85:  return "高级"
            case 60..<75:  return "中级"
            default:       return "初级"
            }
        }()

        return VideoSummary(
            averageScore: modulatedScore,
            bestFrame: FrameScore(
                time: best.time,
                timeString: formatTime(seconds: best.time),
                score: best.score
            ),
            worstFrame: FrameScore(
                time: worst.time,
                timeString: formatTime(seconds: worst.time),
                score: worst.score
            ),
            stabilityScore: stabilityScore,
            scoreConsistencyScore: scoreConsistencyScore,
            scoreStdDev: std,
            overallLevel: overallLevel,
            flowMotionCoherence: flowMetrics.framePairsUsed >= 2 ? flowMetrics.motionCoherence : nil,
            flowDirectionalStability: flowMetrics.framePairsUsed >= 2 ? flowMetrics.directionalStability : nil,
            flowVelocitySmoothness: flowMetrics.framePairsUsed >= 2 ? flowMetrics.velocitySmoothness : nil
        )
```

This replaces the entire section from the `let avg = applyEvidenceCaps(...)` line through the `return VideoSummary(...)` statement. The existing best/worst search and `overallLevel` computation that came before are removed — they're now in this single block with `modulatedScore`.

- [ ] **Step 5: Verify compilation**

```bash
swift build -c release 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/FallLineCore/VideoAnalyzer.swift
git commit -m "feat: integrate optical flow frame cache and modulation into VideoAnalyzer"
```

---

### Task 5: Update CLI main.swift for async generateSummary

**Files:**
- Modify: `Sources/FallLineCLI/main.swift:73`

- [ ] **Step 1: Add await to generateSummary call**

Find line 73:
```swift
let summary = analyzer.generateSummary(from: results)
```

Change to:
```swift
let summary = await analyzer.generateSummary(from: results)
```

- [ ] **Step 2: Update the fallback VideoSummary to include new fields (optional with defaults, no change needed)**

The fallback at line 74-82 uses the old init with positional args. Since new fields have defaults (`nil`), this code compiles unchanged.

- [ ] **Step 3: Verify compilation**

```bash
swift build -c release 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/FallLineCLI/main.swift
git commit -m "fix: add await to generateSummary call for async flow computation"
```

---

### Task 6: Display flow metrics in report

**Files:**
- Modify: `Sources/FallLineCore/ReportGenerator.swift`

- [ ] **Step 1: Add flow metrics to ReportContext**

Open `ReportGenerator.swift`. In the `ReportContext` struct (around line 6), add three fields after `stableCarvingBaseline`:

```swift
public let flowMotionCoherence: Double?
public let flowDirectionalStability: Double?
public let flowVelocitySmoothness: Double?
```

Update `ReportContext.init` to include these parameters with defaults:

```swift
flowMotionCoherence: Double? = nil,
flowDirectionalStability: Double? = nil,
flowVelocitySmoothness: Double? = nil
```

And in the init body:
```swift
self.flowMotionCoherence = flowMotionCoherence
self.flowDirectionalStability = flowDirectionalStability
self.flowVelocitySmoothness = flowVelocitySmoothness
```

- [ ] **Step 2: Pass flow metrics from buildContext to ReportContext**

In the `buildContext` method (around line 506), find the `return ReportContext(...)` statement. Add flow fields:

```swift
return ReportContext(
    avgScore: s.averageScore,
    // ... existing fields ...
    stableCarvingBaseline: stableBaseline,
    flowMotionCoherence: s.flowMotionCoherence,
    flowDirectionalStability: s.flowDirectionalStability,
    flowVelocitySmoothness: s.flowVelocitySmoothness
)
```

- [ ] **Step 3: Add flow metrics section after debug scores in the report**

In `ReportGenerator.swift`, find the `"  🔎 原始姿态指标（调试参考）"` section (around line 443-449). After the `lines.append("")` that follows the debug score lines (line 449), insert the flow metrics block:

```swift
        // 光流运动指标（Phase 1 实验，有数据时展示）
        if let coherence = ctx.flowMotionCoherence,
           let dirStability = ctx.flowDirectionalStability,
           let smoothness = ctx.flowVelocitySmoothness {
            lines.append("  🌊 光流运动指标（实验性）")
            lines.append("  | 运动一致性: \(String(format: "%.0f", coherence)) | 方向稳定性: \(String(format: "%.0f", dirStability)) | 速度平滑度: \(String(format: "%.0f", smoothness)) |")
            lines.append("  | >70 分离明显 | >70 走刃特征 | <40 动作不稳定 |")
            lines.append("")
        }
```

Insert this after the `lines.append("")` that follows the `makeScoreLine` calls (after line 449) and before the `"  🔍 关键时刻"` section.

- [ ] **Step 4: Verify compilation**

```bash
swift build -c release 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/FallLineCore/ReportGenerator.swift
git commit -m "feat: display optical flow metrics in report tech section"
```

---

### Task 7: Run all existing tests — regression check

**Files:** None

- [ ] **Step 1: Run full test suite**

```bash
swift test 2>&1 | tail -5
```

Expected: All existing 65 tests pass plus the new FlowMetricsCalculatorTests (15 tests) → 80 tests, 0 failures.

- [ ] **Step 2: If any existing tests fail, diagnose and fix before proceeding**

Check `swift test 2>&1 | grep "failed"` for details.

---

### Task 8: Batch run on all 49 videos and compare scores

**Files:** None

- [ ] **Step 1: Batch run CLI on all videos**

```bash
# Create output directory
mkdir -p outputs/flow_modulation_test_20260511

# Run on all videos (adjust video/ directory path as needed)
for group in bad good middle root; do
  for video in video/$group/*.{MP4,MOV,mp4,mov}; do
    [ -f "$video" ] || continue
    echo "Processing: $video"
    swift run FallLineCLI "$video" --json > "outputs/flow_modulation_test_20260511/$(basename "$video").json" 2>/dev/null
  done
done
```

- [ ] **Step 2: Extract scores and compare with baseline**

Write a comparison script or manually inspect a few key videos:

```bash
# Extract modulated scores from the new JSON outputs
for f in outputs/flow_modulation_test_20260511/*.json; do
  name=$(basename "$f" .json)
  score=$(python3 -c "import json; d=json.load(open('$f')); print(d['summary']['averageScore'])" 2>/dev/null)
  coherence=$(python3 -c "import json; d=json.load(open('$f')); print(d['summary'].get('flowMotionCoherence', 'N/A'))" 2>/dev/null)
  echo "$name $score coherence=$coherence"
done
```

- [ ] **Step 3: Compare against baseline scores**

Compare against `outputs/all_video_scores_20260506_150537/score_summary.tsv`. Flag videos where modulation changed score by > 5 points for manual review.

- [ ] **Step 4: Commit batch run results (TSV summary only)**

```bash
git add outputs/flow_modulation_test_20260511/score_comparison.tsv
git commit -m "results: add flow modulation batch run score comparison"
```

---

### Task 9: Manual review of significant changes

- [ ] **Step 1: Identify videos with > 5 point change**

From the comparison TSV, list videos where |new_score - old_score| > 5.

- [ ] **Step 2: For each flagged video, manually review**

Watch the video, check whether the modulated score is more reasonable than the original. Document findings.

- [ ] **Step 3: If all reviewed changes are improvements, proceed. If any are worse, adjust modulation parameters.**

Parameters to tune in `FlowMetricsCalculator`:
- `coherenceBoostThreshold` (default 70)
- `stabilityBoostThreshold` (default 70)
- `stabilityPenaltyThreshold` (default 30)
- `smoothnessPenaltyThreshold` (default 40)
- Individual boost/penalty amounts

---

### Task 10: Clean up and final commit

- [ ] **Step 1: Verify final state**

```bash
git diff --stat
swift test 2>&1 | tail -3
```

Expected: Clean diff (only intentional changes), all tests pass.

- [ ] **Step 2: Final commit**

```bash
git add -A
git commit -m "feat(Phase 1): optical flow post-processing modulation for score generalization

- FlowMetricsCalculator: 3-metric flow analysis (coherence, stability, smoothness)
- VideoAnalyzer: frame cache during analyze(), async flow computation in generateSummary()
- VideoSummary: optional flow metric fields
- ReportGenerator: flow metrics display in tech section
- Tests: 15 unit tests for modulation formula and edge cases"
```

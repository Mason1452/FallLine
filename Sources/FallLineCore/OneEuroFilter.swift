import Foundation

/// 1€ Filter（One-Euro Filter）
///
/// 由 Casiez, Roussel & Vogel (2012) 提出，用于低延迟人机交互的实时信号平滑。
/// 相较普通 EMA 滤波，1€ Filter 在慢速运动时用低截止频率强平滑（抖动最小），
/// 在快速运动时自适应提高截止频率（保留响应速度），从而同时兼顾抖动抑制与延迟。
///
/// 参考：https://cristal.univ-lille.fr/~casiez/1euro/
///
/// 使用方式：为每个独立信号维度创建单独实例（不同信号不共享状态）。
public final class OneEuroFilter {

    // MARK: - 参数

    /// 最小截止频率 fc_min（Hz）。速度趋近 0 时使用此值，越低越平滑。
    public let minCutoff: Double

    /// 速度耦合系数 β。速度越大，等效截止频率越高（响应越快）。
    public let beta: Double

    /// 用于估算速度信号本身的低通截止频率
    public let dCutoff: Double

    // MARK: - 状态

    private var lastRawValue: Double?
    private var lastFilteredValue: Double?
    private var lastRawDerivative: Double?
    private var lastFilteredDerivative: Double?
    private var lastTimestamp: Double?

    // MARK: - 初始化

    /// - Parameters:
    ///   - minCutoff: 静止时的截止频率，滑雪关节角度推荐 0.8–2.0 Hz
    ///   - beta: 快速运动时的响应速度系数，推荐 0.005–0.05
    ///   - dCutoff: 速度信号自身的截止频率，推荐 1.0
    public init(minCutoff: Double = 1.2, beta: Double = 0.01, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    /// 重置滤波器状态，用于多个独立序列复用同一实例的场景
    public func reset() {
        lastRawValue = nil
        lastFilteredValue = nil
        lastRawDerivative = nil
        lastFilteredDerivative = nil
        lastTimestamp = nil
    }

    // MARK: - 主入口

    /// 对单个时间点的采样值滤波。
    /// - Parameters:
    ///   - value: 原始信号值
    ///   - timestamp: 时间（秒）
    /// - Returns: 滤波后的值
    public func filter(value: Double, timestamp: Double) -> Double {
        return filter(value: value, timestamp: timestamp, weight: 1.0)
    }

    /// Confidence-aware 滤波入口（方案 α，2026-09-11 落地）。
    ///
    /// 让低置信度样本对滤波器状态的影响按 `weight ∈ [0, 1]` 降级：
    /// - `weight = 1.0` → 与不带 weight 的旧路径**字节等价**（`OneEuroFilterConfidenceAwareTests` 锁死）
    /// - `weight = 0.0`（非首帧）→ 输出 = `lastFilteredValue`，滤波器状态**完全不更新**
    ///   （lastRaw/lastFiltered/derivative 保持不动），等价于"丢弃这一帧"
    /// - `weight ∈ (0, 1)` → 把 α 缩放为 `weight × α`；状态按 weight 凸组合更新
    ///   → 输出永远在 [prevFiltered, value] 之间（fuzz 断言）
    ///
    /// **首帧**：任何 weight 都退回旧初始化路径。首帧没有 prevFiltered，
    /// 无论选择"丢弃"还是"接受"都是主观决定，选择保守的"接受"以避免整段序列
    /// 因首帧低置信度被延迟启动。
    ///
    /// 设计动机：当前 PoseSmoother 在 `smoothConfidenceWeight` 下游做 confidence-weighted
    /// 聚合（softFloor 0.15 / softCeiling 0.75 二次曲线），但滤波层平等吸收所有样本。
    /// Corpus 审计（scripts/confidence_smoothing_audit.py）显示 5/6 视频有 36-44% 帧
    /// 落在 0.30-0.75 段，且视频 2/3/4/5/6 都存在 ≥15 帧连续 conf<0.30 段，1€ Filter
    /// 状态会被这些段拽偏。此 overload 让滤波层的信任度与聚合层对齐。
    ///
    /// - Parameters:
    ///   - value: 原始信号值
    ///   - timestamp: 时间（秒）
    ///   - weight: [0, 1] 区间的置信度权重。默认 1.0 保持向后兼容。
    /// - Returns: 滤波后的值
    public func filter(value: Double, timestamp: Double, weight: Double) -> Double {
        let clampedWeight = min(1.0, max(0.0, weight))

        guard let prevTime = lastTimestamp,
              let prevFiltered = lastFilteredValue else {
            // 首帧：不滤波，仅初始化状态（保持与旧行为完全一致）
            lastTimestamp = timestamp
            lastRawValue = value
            lastFilteredValue = value
            lastRawDerivative = 0
            lastFilteredDerivative = 0
            return value
        }

        // weight = 0：状态完全不更新，直接返回 prevFiltered
        // （lastRaw/lastFiltered/derivative/timestamp 全部保持）
        if clampedWeight <= 0 {
            return prevFiltered
        }

        let dt = max(timestamp - prevTime, 1.0 / 240.0)

        // Step 1: 估算原始速度（数值微分）
        let rawDerivative = (value - (lastRawValue ?? value)) / dt

        // Step 2: 低通滤波速度（用 dCutoff）
        let dAlpha = smoothingFactor(cutoff: dCutoff, dt: dt)
        let filteredDerivative = dAlpha * rawDerivative + (1 - dAlpha) * (lastFilteredDerivative ?? rawDerivative)

        // Step 3: 根据速度动态调整信号的截止频率
        let adaptiveCutoff = minCutoff + beta * abs(filteredDerivative)
        let baseAlpha = smoothingFactor(cutoff: adaptiveCutoff, dt: dt)

        // Step 4: 低通滤波信号
        // 关键差异：把 weight 直接乘到 α 上。weight=1 → alpha=baseAlpha（等价旧路径）；
        // weight=0 → alpha=0，filtered=prevFiltered。中间值 → filtered 在
        // [prevFiltered, value] 的凸组合上，靠近 prevFiltered 的程度与 weight 线性挂钩。
        let alpha = clampedWeight * baseAlpha
        let filtered = alpha * value + (1 - alpha) * prevFiltered

        // Step 5: 状态更新
        // - clampedWeight = 1：状态直接跳到新值（等价旧路径）
        // - clampedWeight = 0：上文已 early return，不会到这里
        // - clampedWeight ∈ (0, 1)：状态按 weight 凸组合更新，避免低置信度样本主导
        //   raw/filtered derivative（否则相当于把 weight 从"输出降权"退化为
        //   "状态延迟污染"，等下一次 weight=1 时仍会被拽偏）。
        let prevRaw = lastRawValue ?? value
        let prevRawDeriv = lastRawDerivative ?? 0
        let prevFilteredDeriv = lastFilteredDerivative ?? 0

        lastRawValue = clampedWeight * value + (1 - clampedWeight) * prevRaw
        lastFilteredValue = filtered
        lastRawDerivative = clampedWeight * rawDerivative + (1 - clampedWeight) * prevRawDeriv
        lastFilteredDerivative = clampedWeight * filteredDerivative + (1 - clampedWeight) * prevFilteredDeriv
        lastTimestamp = timestamp

        return filtered
    }

    /// 便捷方法：对整段时序做批量滤波
    /// - Parameter samples: (value, timestamp) 数组
    /// - Returns: 与输入长度相同的滤波序列
    public func filterSeries(_ samples: [(value: Double, timestamp: Double)]) -> [Double] {
        reset()
        return samples.map { filter(value: $0.value, timestamp: $0.timestamp) }
    }

    // MARK: - 内部

    /// 一阶低通滤波系数：α = 1 / (1 + τ/dt)，其中 τ = 1 / (2π·fc)
    private func smoothingFactor(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}

// MARK: - 多信号批量滤波辅助

/// 对多路信号（如 8 个关节角度）批量维护 1€ Filter 组，并支持按时间轴逐帧输入
public final class MultiOneEuroFilter {

    private var filters: [String: OneEuroFilter] = [:]
    private let makeFilter: () -> OneEuroFilter

    public init(makeFilter: @escaping () -> OneEuroFilter = { OneEuroFilter() }) {
        self.makeFilter = makeFilter
    }

    /// 对键 key 对应的信号做滤波，若首次遇见自动创建滤波器
    public func filter(_ value: Double, key: String, timestamp: Double) -> Double {
        return filter(value, key: key, timestamp: timestamp, weight: 1.0)
    }

    /// Confidence-aware overload：把 `weight ∈ [0, 1]` 转发给底层 [OneEuroFilter.filter](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/OneEuroFilter.swift#L89-L146)。
    /// weight=1.0 与旧方法字节等价。
    public func filter(_ value: Double, key: String, timestamp: Double, weight: Double) -> Double {
        if filters[key] == nil {
            filters[key] = makeFilter()
        }
        return filters[key]!.filter(value: value, timestamp: timestamp, weight: weight)
    }

    /// 可选辅助：过滤 nil 保持传播（None 时不喂入滤波器，避免破坏时序）
    public func filterOptional(_ value: Double?, key: String, timestamp: Double) -> Double? {
        guard let v = value else { return nil }
        return filter(v, key: key, timestamp: timestamp)
    }

    public func reset() {
        filters.removeAll(keepingCapacity: true)
    }
}

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
        guard let prevTime = lastTimestamp,
              let prevFiltered = lastFilteredValue else {
            // 首帧：不滤波，仅初始化状态
            lastTimestamp = timestamp
            lastRawValue = value
            lastFilteredValue = value
            lastRawDerivative = 0
            lastFilteredDerivative = 0
            return value
        }

        let dt = max(timestamp - prevTime, 1.0 / 240.0)

        // Step 1: 估算原始速度（数值微分）
        let rawDerivative = (value - (lastRawValue ?? value)) / dt

        // Step 2: 低通滤波速度（用 dCutoff）
        let dAlpha = smoothingFactor(cutoff: dCutoff, dt: dt)
        let filteredDerivative = dAlpha * rawDerivative + (1 - dAlpha) * (lastFilteredDerivative ?? rawDerivative)

        // Step 3: 根据速度动态调整信号的截止频率
        let adaptiveCutoff = minCutoff + beta * abs(filteredDerivative)
        let alpha = smoothingFactor(cutoff: adaptiveCutoff, dt: dt)

        // Step 4: 低通滤波信号
        let filtered = alpha * value + (1 - alpha) * prevFiltered

        // Step 5: 更新状态
        lastRawValue = value
        lastFilteredValue = filtered
        lastRawDerivative = rawDerivative
        lastFilteredDerivative = filteredDerivative
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
        if filters[key] == nil {
            filters[key] = makeFilter()
        }
        return filters[key]!.filter(value: value, timestamp: timestamp)
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

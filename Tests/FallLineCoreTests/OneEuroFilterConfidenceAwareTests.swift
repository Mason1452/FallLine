import XCTest
@testable import FallLineCore

/// OneEuroFilterConfidenceAwareTests
///
/// 锁死方案 α（confidence-aware 平滑）的 4 条契约。这些测试即使方案后续调参
/// 也**必须保持通过**，否则说明 confidence-aware overload 的核心不变量被破坏。
///
/// 契约来源：
///  1. `OneEuroFilter.filter(value:timestamp:weight:1.0)` 与 `filter(value:timestamp:)` 字节等价
///  2. `weight = 0`（非首帧）→ 输出 = prevFiltered，滤波器状态完全不更新
///  3. 单调性：`weight` 越小，滤波结果越靠近 prevFiltered
///  4. Fuzz：随机序列 + 随机 weight ∈ [0, 1]，输出永远在 [prevFiltered, value] 闭区间
///
/// 相关设计文档：[OneEuroFilter.filter(value:timestamp:weight:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/OneEuroFilter.swift#L89-L146)。
final class OneEuroFilterConfidenceAwareTests: XCTestCase {

    // MARK: - Contract 1：weight = 1.0 与旧路径完全等价

    /// 一条固定序列，用 weight=1.0 与不带 weight 的老方法对比，逐帧输出必须完全一致。
    /// 覆盖：首帧初始化、稳态低通、变化点自适应截止频率。
    func test_weight1_isByteEquivalentToLegacy() {
        let series: [(value: Double, timestamp: Double)] = [
            (100.0, 0.0),
            (102.0, 0.1),
            (105.0, 0.2),
            (110.0, 0.3),
            (150.0, 0.4), // 大跳变，测自适应截止频率
            (152.0, 0.5),
            (149.0, 0.6),
            (150.0, 0.7),
        ]

        let legacy = OneEuroFilter(minCutoff: 1.2, beta: 0.02)
        let aware  = OneEuroFilter(minCutoff: 1.2, beta: 0.02)

        for s in series {
            let a = legacy.filter(value: s.value, timestamp: s.timestamp)
            let b = aware.filter(value: s.value, timestamp: s.timestamp, weight: 1.0)
            XCTAssertEqual(a, b, accuracy: 1e-12,
                           "weight=1.0 必须与旧 filter 字节等价：value=\(s.value) t=\(s.timestamp) legacy=\(a) aware=\(b)")
        }
    }

    // MARK: - Contract 2：weight = 0 → 输出锁死 prevFiltered，状态不更新

    /// 先用 weight=1 建立状态；再喂一个 weight=0 的样本：
    /// - 输出必须等于 prevFiltered
    /// - 接下来用 weight=1 喂一个相同的样本，结果必须与"没经过 weight=0 帧"的对照组一致
    func test_weight0_holdsOutputAndFreezesState() {
        let filter = OneEuroFilter(minCutoff: 1.2, beta: 0.02)
        let control = OneEuroFilter(minCutoff: 1.2, beta: 0.02)

        // 建立稳态
        _ = filter.filter(value: 100.0, timestamp: 0.0, weight: 1.0)
        let prevFiltered = filter.filter(value: 105.0, timestamp: 0.1, weight: 1.0)

        _ = control.filter(value: 100.0, timestamp: 0.0, weight: 1.0)
        _ = control.filter(value: 105.0, timestamp: 0.1, weight: 1.0)

        // weight=0：注入一个巨大离群值，输出必须锁死
        let out = filter.filter(value: 9_999.0, timestamp: 0.2, weight: 0.0)
        XCTAssertEqual(out, prevFiltered, accuracy: 1e-12,
                       "weight=0 应把巨大离群值完全抵消，输出=prevFiltered")

        // 再喂一个正常样本；对照组直接喂同一个样本（跳过 t=0.2）
        // 状态应被冻结 → 两者输出**必须**一致（除了时间跳一帧）
        let awareNext = filter.filter(value: 108.0, timestamp: 0.3, weight: 1.0)
        // 对照组：跳过 0.2s 的巨大离群，直接从 0.1s 跳到 0.3s
        let ctlNext = control.filter(value: 108.0, timestamp: 0.3, weight: 1.0)

        XCTAssertEqual(awareNext, ctlNext, accuracy: 1e-9,
                       "weight=0 后的状态应等价于'该帧不存在'（时间跳过）")
    }

    // MARK: - Contract 3：weight 单调性

    /// 从同一 prevFiltered 出发，同一 value + 同一 timestamp，
    /// weight 越小 → 滤波结果越靠近 prevFiltered（每次用新 filter，避免状态耦合）。
    func test_weightMonotonicity_smallerWeightMovesLessTowardsValue() {
        let value = 200.0

        func runWithWeight(_ w: Double) -> (out: Double, prev: Double) {
            let f = OneEuroFilter(minCutoff: 1.2, beta: 0.02)
            _ = f.filter(value: 100.0, timestamp: 0.0, weight: 1.0)
            let prev = f.filter(value: 100.0, timestamp: 0.1, weight: 1.0) // ≈ 100
            let out = f.filter(value: value, timestamp: 0.2, weight: w)
            return (out, prev)
        }

        let w10 = runWithWeight(1.0)
        let w05 = runWithWeight(0.5)
        let w02 = runWithWeight(0.2)
        let w00 = runWithWeight(0.0)

        // prev 都相同，用 w=1.0 的 prev 作参考
        let prev = w10.prev

        // value=200 > prev≈100 → 输出应严格递减（w 越小越贴近 prev）
        XCTAssertGreaterThan(w10.out, w05.out, "w=1.0 应比 w=0.5 更靠近 value")
        XCTAssertGreaterThan(w05.out, w02.out, "w=0.5 应比 w=0.2 更靠近 value")
        XCTAssertGreaterThan(w02.out, w00.out, "w=0.2 应比 w=0.0 更靠近 value")

        XCTAssertEqual(w00.out, prev, accuracy: 1e-12,
                       "w=0.0 时输出必须等于 prevFiltered")

        // 所有输出必须在 [prev, value] 闭区间内
        for (label, o) in [("w=1.0", w10.out), ("w=0.5", w05.out),
                           ("w=0.2", w02.out), ("w=0.0", w00.out)] {
            XCTAssertGreaterThanOrEqual(o, prev - 1e-9, "\(label) 越出下界")
            XCTAssertLessThanOrEqual(o, value + 1e-9, "\(label) 越出上界")
        }
    }

    // MARK: - Contract 4：Fuzz — 输出永远在 [min, max](prev, value) 闭区间

    /// 用固定 seed 的伪随机源生成 500 步序列 + 随机 weight ∈ [0, 1]，
    /// 每一步输出必须落在 min(prevFiltered, value) ~ max(prevFiltered, value) 之间。
    /// 这是 confidence-aware overload 的核心不变量：它只能减弱对 value 的追随，
    /// 不能"反向超出"或"越过 value"（那会引入伪信号）。
    func test_fuzz_outputAlwaysWithinPrevAndValueBounds() {
        // 简易 LCG，避免依赖 Swift 版本对 Random 语义的差异
        var seed: UInt64 = 0xDEAD_BEEF_CAFE_1234
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 32) / Double(UInt32.max)
        }

        let filter = OneEuroFilter(minCutoff: 1.2, beta: 0.02)

        // 首帧初始化
        var t = 0.0
        _ = filter.filter(value: 100.0, timestamp: t, weight: 1.0)
        var prevOut = 100.0

        for step in 0..<500 {
            t += 0.033 + next() * 0.02 // 抖动的 dt
            let value = 50.0 + next() * 200.0
            let weight = next()

            let out = filter.filter(value: value, timestamp: t, weight: weight)

            let lo = min(prevOut, value)
            let hi = max(prevOut, value)
            XCTAssertGreaterThanOrEqual(
                out, lo - 1e-9,
                "step=\(step) value=\(value) prevOut=\(prevOut) weight=\(weight) 越出下界 out=\(out)")
            XCTAssertLessThanOrEqual(
                out, hi + 1e-9,
                "step=\(step) value=\(value) prevOut=\(prevOut) weight=\(weight) 越出上界 out=\(out)")

            prevOut = out
        }
    }

    // MARK: - Contract 5：非法 weight 的钳位

    /// weight 超出 [0, 1] 时应被静默钳位（避免上游忘记预处理导致的运行时崩溃）。
    func test_weightOutsideUnitInterval_isClamped() {
        let f1 = OneEuroFilter(minCutoff: 1.2, beta: 0.02)
        let f2 = OneEuroFilter(minCutoff: 1.2, beta: 0.02)
        _ = f1.filter(value: 100.0, timestamp: 0.0, weight: 1.0)
        _ = f2.filter(value: 100.0, timestamp: 0.0, weight: 1.0)
        let a = f1.filter(value: 200.0, timestamp: 0.1, weight: -0.5)  // 应视为 0
        let b = f2.filter(value: 200.0, timestamp: 0.1, weight: 0.0)
        XCTAssertEqual(a, b, accuracy: 1e-12, "weight=-0.5 应被钳位到 0")

        let f3 = OneEuroFilter(minCutoff: 1.2, beta: 0.02)
        let f4 = OneEuroFilter(minCutoff: 1.2, beta: 0.02)
        _ = f3.filter(value: 100.0, timestamp: 0.0, weight: 1.0)
        _ = f4.filter(value: 100.0, timestamp: 0.0, weight: 1.0)
        let c = f3.filter(value: 200.0, timestamp: 0.1, weight: 2.5)   // 应视为 1
        let d = f4.filter(value: 200.0, timestamp: 0.1, weight: 1.0)
        XCTAssertEqual(c, d, accuracy: 1e-12, "weight=2.5 应被钳位到 1")
    }

    // MARK: - Contract 6：PoseSmoother.Config.useConfidenceAwareFiltering 默认 on（α 翻默认后契约）

    /// α 已于 2026-09-11 翻默认 on（见 [PoseSmoother.Config](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift#L15-L52)），
    /// 历史行为仍可通过 `FALLLINE_CONFIDENCE_AWARE=0/false/off/no` 强制关闭（见
    /// [VideoAnalyzer.smoothingConfig](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L257-L261)）。
    /// 本契约锁死 PoseSmoother 默认值必须为 true，避免默认被无意翻回 off。
    func test_poseSmootherConfig_defaultKeepsLegacyBehavior() {
        XCTAssertTrue(PoseSmoother.Config.default.useConfidenceAwareFiltering,
                      "PoseSmoother.Config 默认必须 confidence-aware on（α 已翻默认 on）")
    }
}

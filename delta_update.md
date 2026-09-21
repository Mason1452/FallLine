# Delta Update

最后更新：2026-09-20

本文档只记录每轮工作的增量变化，不记录项目全量背景。需要项目当前状态、目标和长期上下文时，先看 `WORK_LOG.md`；需要文件职责时，看 `file_manifest.md`。

## 记录规则

- 只写本轮新增、修改、删除、验证结果。
- 不重复整段项目背景、架构说明、历史决策或完整文件清单。
- 如果某个信息已经在 `WORK_LOG.md`、`AGENTS.md`、`CLAUDE.md` 或 `file_manifest.md` 中存在，只链接或点名引用。
- 每轮结束时新增一条简短记录；优先记录事实，不写推测。
- 同一轮没有代码变更时，明确写”仅文档变更”或”未运行测试”的原因。

## 变更

### 2026-09-21（候选 F 决策标准锁定：IoU≥0.65 / 推理≤20ms / farShot 恢复率≥50% 三条硬门槛）

**本轮性质**：候选 F 已被 Gate-G2 NO-GO 激活，用户正式锁定 §12.14 决策标准中的三条硬门槛。仅 spec + 脚本变更，无生产代码改动、未跑测试。

**变更**
- spec §12.14「决策标准」：去掉"先声明、spike 前不动"，加锁定状态引用块——**① 分割 IoU≥0.65；② CoreML M1 Pro 单帧推理≤20ms；④ farShot 桶恢复率≥50%**，三条须同时满足，任一 FAIL 即候选 F 失败，不再放宽数字；第 3/5/6 条（板轴准入精度/bit 确定性/人力）仍待确认。
- [board_edge_coreml_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_coreml_spike.py)：新增 `LOCKED_NOTE`，`DECISION_CRITERIA` 第 1/2/4 条标【已锁定】，`--check-plan` 打印锁定提示并把状态从 "Design only" 更新为 "已激活，待模型选型 + GT 标注预算"。
- 验证：`py_compile` 过 + `--check-plan` 输出正确。

**当前口径（同日更新）**：
- 模型选型**搁置——等用户自行测试后再决定**，spec §12.14 维持"spike 前不 pin"；
- GT 规模**锁定 100 帧最小集**（spec §12.14 GT 方案已更新，≈0.83 人时、含 QA ≈1–1.5 人时），用于先验证 IoU≥0.65，临界再补标 200–300。实际选帧 / 标注启动待用户指示。

### 2026-09-21（方向 C 时序聚合 S4·刃线/轨迹检测 Phase 2：44 片实测 Gate-G2 **NO-GO**，方向反转，激活候选 F）

**本轮性质**：执行 §12.15.2 阶段 **S4**——release 构建 + 44 片 `--board-edge` 重跑 + Gate-G2 margin/LOOCV/景别残差裁决。生产代码零改动（仅扩 audit 脚本 + 新增一次性驱动脚本）。

**产物**
- release 构建过（14.66s，仅既有 `usesCPUOnly` deprecation 警告）；
- 44/44 重跑成功（`outputs/board_edge_p2/trajectory_json/*.json`，全部含 `summary.boardTrajectory`），驱动脚本 `_run_trajectory_44.py` + 日志 `trajectory_44.log`；
- 扩展 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) 新增 `--trajectory` 模式（5 时序特征 + farShotFrac，1D margin + 全样本 acc + LOOCV + 景别相关/去趋势残差核对，双口径 high-vs-low 主裁决 + 低端 11 片对照）；裁决日志 [gate_g2_trajectory_44.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g2_trajectory_44.log)。

**核心结果（mean stableWindowRate）**：high=0.384 / mid=0.328 / low=**0.405**。主口径 high(21) vs low(10) 最强时序特征 margin=−0.13σ、LOOCV=45.2%、专业误伤 11；低端 11 片对照同向反转（−1.03σ）。最强单一信号为 farShotFrac（0.75σ/71%）仍不达标。**margin≥1.5σ、LOOCV≥90%、专业零误伤三条全 FAIL → NO-GO。**

**机理（逐片核对，非 bug / 非景别假相关）**：推坡直滑板轴恒定朝坡下 → PCA 主轴天然稳（多 low 片 board% 50–75%、swr 0.55–0.83）；刻滑连续换弯 → 板轴转动更易 IQR>5° 被拒。"轴方向不变"与"沿弧线走刃"弱负相关，根因同 P7-A/P8-A「2D 方向不携带质量信息」与 §10.2 相机补偿假 margin——2D 几何天花板。去 farShot 后残差 margin≈0（0.08σ），排除景别伪信号；foldCrossingRate 全片 0，真实换弯大转角被 `unstableIQR` 吃掉。

**处置**：`boardTrajectory` + 聚合器保留纯诊断（不进评分/cap/report）；**激活候选 F（§12.14 CoreML 板边分割）**——44 片上方向 A/B、相机补偿 C、时序 D 三次撞穿 2D 天花板后唯一剩余视觉路径；Gate-G1 v3 FAIL 结论与门槛不动。spec §12.15.3 与 §12.4 检查表已回写。

### 2026-09-21（方向 C 时序聚合 S3·刃线/轨迹检测 Phase 2：24 条聚合器单测落地，314/314 全绿）

**本轮性质**：执行 §12.15.2 阶段 **S3**——新增聚合器单元测试，覆盖 §12.15.2 清单全部 14 项并补若干边界。生产代码零改动。

**新增测试**：[BoardTemporalAxisAggregatorTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardTemporalAxisAggregatorTests.swift)（24 个 test）。
- 全 board 稳定窗 pass + 聚合角 / conf / source（board 窗 source=nil）；
- 候选不足（insufficientCandidates）；IQR 恰 5° pass / 6° reject（早期窄窗仍 pass 的边界效应显式断言）；
- 源多数派 ankle 胜 / tie 取 ankle / knee only / 纯 board 窗 source=nil；
- candidate 提取：fallback 携带合成轴 angle·conf·source；rejected / nil → nil；
- fold-crossing：无方向保守拒绝（foldCrossing）+ 有方向重建后两簇仍分裂 → unstableIQR；directedAngle 三分支；
- 跨簇阻断 run（混合 [10,70] 窗判 foldCrossing，run 缩短）+ stableRuns helper（多段降序 / 空数组）；
- 片首 <W 帧、全拒绝帧流（0 可评估窗不崩）、偶数中位（中间两值均）、IQR 分位定义、空片 / 单帧；
- 确定性：同输入 2000 次聚合逐字段相等；JSON round-trip；includeAllPoints 输出被拒窗。

**验证**
- `/usr/bin/xcrun swift test` **314/314 通过（0.330s，0 failures）**＝290 基线 + 24 新增；
- GetDiagnostics 零诊断；
- 中途 2 处 FAIL 均为我手算 run / fold 口径偏差（非生产 bug），修正测试期望值后全绿——过程也交叉验证了聚合器行为符合 §12.15 设计。

**写测试时确认 / 强化的语义（值得留痕，供 S4 关注）**
1. **混合簇窗一律保守拒绝**：如 [10,70] 同窗，即便轴可能在弯形过渡中平滑转动，当前规则也判 foldCrossing / unstable；因此**弯形快速切换区可能被少计**。这是 ADR-004 已列风险，S4 必须量化 foldCrossingRate，刻滑样本若 >10% 需先补有向重建；
2. **早期窄窗边界效应**：片首不足 W 帧时只要候选数 ≥minCount(3) 前不可能 pass（因为 minCount=3 而前 2 窗最多 2 候选），属预期；
3. IQR 用索引分位 `sorted[Int(0.25·(n-1))]` / `Int(0.75·(n-1))`，n=5 → index1/index3，与 §12.12 spike 一致。

**下一步（S4）**：`swift build -c release` → `--board-edge` 对 44 片重跑（新 JSON 含 boardTrajectory）；扩展 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) 读 stableWindowRate / longestStableRunSeconds / stableFrameCoverage / foldCrossingRate，出 Gate-G2 margin + LOOCV + 景别残差核对；结果回流 outputs/board_edge_p2/。

### 2026-09-21（方向 C 时序聚合 S2·刃线/轨迹检测 Phase 2：generateSummary 接线完成，290/290 全绿）

**本轮性质**：执行 §12.15.2 阶段 **S2**——把 S1 的纯函数聚合器接入 `generateSummary()` 后处理。逐帧 `DetectionResult` / 评分 / cap / flow / report 零改动，复用 `--board-edge` 开关。

**接线变更（仅 [VideoAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L464-L479) 一处）**
- 在 [computeFlowMetrics()](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L405) 之后（此时 `cachedTravelDirections` 已由光流遍历填充）、return 之前，构造 `boardTrajectory`：
  - `guard enableBoardEdge else { return nil }`——默认关路径 summary.boardTrajectory 为 nil；
  - 把稀疏 `cachedTravelDirections`（按 time/angle/confidence）建成 `[time: angle]` 字典（`uniquingKeysWith` 取首个，与 [BoardDirectionAnalyzer](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardDirectionAnalyzer.swift#L24-L27) 口径一致），再对**全量 results** 按精确时间戳 `results.map { directionByTime[$0.time] }` 对齐成 `[Double?]`；
  - 调用 `BoardTemporalAxisAggregator.aggregate(frames:travelDirections:sampleInterval:config:)`，挂到 VideoSummary `boardTrajectory`；
  - 无匹配方向帧为 nil，折叠窗在缺方向信号时保守拒绝（ADR-004 语义）。
- VideoSummary 构造补 `boardTrajectory:` 实参；无其他调用方 / 报告 / CLI 参数改动。

**验证**
- `/usr/bin/xcrun swift build` Build complete（1.45s 增量）；
- `/usr/bin/xcrun swift test` **290/290 通过（0.208s，0 failures）**；
- GetDiagnostics 零诊断；
- 评分零污染确认：聚合器只读 `boardEdgeObservation`，不写任何评分字段；默认关路径完全不执行聚合。

**下一步（S3）**：新增 `BoardTemporalAxisAggregatorTests` ≥14 条（§12.15.2 清单：全 board 稳定窗 / 候选不足 / IQR 边界 / 源多数派 tie / fold-crossing 重建与保守拒绝 / run 扫描 / 片首边界 / 空片单帧 / 偶数中位 / 2000 次确定性 fuzz / JSON round-trip / 默认关 nil）。之后 S4 release 44 片 + Gate-G2 margin/LOOCV + 景别残差核对。

### 2026-09-21（方向 C 时序聚合 S1·刃线/轨迹检测 Phase 2：Models + 聚合器核心落地，不接线，swift build 通过）

**本轮性质**：执行 §12.15.2 阶段 **S1**——新增时序聚合所需模型类型与纯函数聚合器核心，**不接线、不改任何调用方**。下一阶段 S2 才在 `generateSummary()` 后处理接线。

**Sources 变更**
- [Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift) 新增 4 个类型（紧随 `BoardEdgeObservation`）：
  - `BoardTemporalRejectReason`（insufficientCandidates / unstableIQR / foldCrossing）；
  - `BoardTemporalAxisPoint`（帧对齐窗口产物：windowPass / candidateCount / medianAngle / medianConfidence / iqr / source / rejectReason，带值域钳制）；
  - `BoardTrajectoryConfigEcho`（windowSize / minCount / iqrGate / sampleInterval / foldLow·HighAngle，JSON 自解释）；
  - `BoardTrajectoryMetrics`（片级：stableWindowRate / longestStableRunFrames·Seconds / stableRunCount / stableRunMeanSeconds / stableFrameCoverage / foldCrossingRate / rejectHist / configEcho / points）；
  - `VideoSummary` 新增可选字段 **`boardTrajectory: BoardTrajectoryMetrics?`**（init 默认 nil，后向兼容）。
- [BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift) `BoardEdgeConfig` 补 5 个时序参数：`temporalWindowSize=5` / `temporalMinCount=3` / `temporalIQRGate=5.0` / `temporalFoldLowAngle=20` / `temporalFoldHighAngle=70`（init 带下限保护）。
- 新增 [BoardTemporalAxisAggregator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardTemporalAxisAggregator.swift)（约 220 行，纯函数）：
  - candidate 提取：`board` → 直接证据 conf=1.0；`fallback` → fallbackAxis 的 angle/conf/source；其余状态无候选；
  - 因果前向窗 `[f-W+1..f]`（W=5，1s）；通过 = 候选数 ≥3 且 IQR ≤5°；
  - **fold-crossing**：窗内 min≤20 且 max≥70 判跨折叠，优先用与 frames 对齐的 `travelDirections` 在 0…180 有向空间选与行进方向更一致的表示（环形差）；无方向信号保守拒绝并计 foldCrossingRate；
  - median（偶数取中间两值均）/ IQR 口径与 §12.12 Python spike 对齐；源多数派 tie→ankle；run 扫描输出按长度降序；
  - rejectHist 按固定语义顺序（insufficient→unstable→fold）构造，规避 Dictionary 无序（确定性规约）；
  - `points` 默认仅含通过帧，`includeAllPoints=true` 含全量可评估帧。

**验证**
- `/usr/bin/xcrun swift build` **Build complete（5.99s）**；GetDiagnostics 零诊断；
- **未跑 `swift test`**：S1 无行为变更（聚合器无调用方，VideoSummary 新参数默认 nil），测试留到 S2 接线后连同新增单测一起跑；
- 评分零污染：不读取 / 不修改任何评分字段，不调用 Vision，预期性能开销 O(W·F) 算术 ≈0%（待 S4 实测）。

**下一步（S2）**：在 [VideoAnalyzer.generateSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L371) 仅当 `enableBoardEdge` 时调用聚合器（行进方向传 flow travel angles），挂到 summary `boardTrajectory`；逐帧 `DetectionResult` / 评分 / flow / report 零改动。

### 2026-09-21（方向 C 时序累积重定位·刃线/轨迹检测 Phase 2：ADR-004 + 生产级 spike 计划，仅文档变更）

**本轮性质**：用户在 §12.13 v3 FAIL 的三条路径中选择"按候选 D 执行"，起草方向 C（时序累积）的正式 ADR 与生产级 spike 计划。**本轮零代码 / 零测试变更**，仅 spec + WORK_LOG + delta_update。

**核心产出**：[spec §12.15](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L829)（ADR-004 + 四阶段 spike 计划）。
- **编号**：ADR-001 v2（§12.9）、ADR-002 v3（§12.13）、**ADR-003 保留给候选 F**（§12.14）；本节 = **ADR-004**。
- **定位翻转（本轮核心决策）**：时序累积从"Gate-G1 覆盖率手段"（§12.12 已 NO-GO、§12.13 v3 双 FAIL）改为"**Gate-G2 刃线连续性质量信号**"。IQR 稳定性门的 pass/fail 序列 + 连续 pass 段长 = Gate-G2 §6 第 3 条点名的"连续弧 / 刃线证据"；§12.12 的"覆盖率代价"在 Gate-G2 语境下即被测物理量本身。Gate-G1 v3 门槛 / FAIL 结论**不回改、不再松绑**。
- **聚合器**：新增纯函数 `BoardTemporalAxisAggregator`（新文件），从全片 `boardEdgeObservation`（board→axisAngle / fallback→fallbackAxis）做因果前向窗 **W=5（1s）+ minCount=3 + IQR≤5°**；显式处理 PCA unsigned 0–90° 的 fold-crossing（方向信号可重建有向角，不可用则保守拒绝）。
- **片级度量 → summary 新可选字段 `boardTrajectory`（`BoardTrajectoryMetrics`）**：stableWindowRate / longestStableRunFrames·Seconds / stableRunCount·MeanSeconds / stableFrameCoverage / foldCrossingRate / rejectHist / configEcho / points。
- **spike 计划**：S1 Models + 聚合器（不接线）→ S2 `generateSummary()` 后处理接线（逐帧 / 评分 / flow / report 零改动，复用 `--board-edge`）→ S3 ≥14 条单测（290 基线）→ S4 release 44 片重跑 + 扩展 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) 读 boardTrajectory 出 margin/LOOCV + 景别混淆残差核对。
- **验收**：GO = margin≥1.5σ + LOOCV≥90% + 方向正确 + 景别残差通过 + 专业档零误伤 + bit-identical + 性能≈0%；NO-GO → 字段留诊断 + 激活候选 F（ADR-003）；熔断 = 关 `enableBoardEdge`。

**风险留痕**：机位 / 景别混淆（§10.2 相机补偿 2.0σ 假 margin 教训，最高危，S4 残差核对）；foldCrossingRate 在刻滑样本 >10% 需先补有向重建；Gate-G2 证据密度 ~31% 需如实标注。

**文档回写**：spec §12.15（新节）+ [§12.4 检查表](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L423)（新增 ADR-004 条 [x] + 时序特征条更新）+ 首行状态；[WORK_LOG Current State](file:///Users/mingsen/Project/FallLine/WORK_LOG.md#L3) 换新（v3 实测降 Previous，并在旧路径块标注实际 ADR-004 用途与路径 3 预想不同）。

**遗留 / 未验证**：未跑 `swift test`（无 Sources 变更）；下一步待确认进入 S1（Models + `BoardTemporalAxisAggregator.swift`，不改调用方）。

### 2026-09-20（E v3 44 片 8364 帧实测·刃线/轨迹检测 Phase 2：Gate-G1 v3 双门槛结构性 FAIL，无代码变更）

**本轮性质**：候选 E 落地闭环的最后一步——用 v3 版探针脚本对 [§4.4](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L44) 44 片全部重跑，验证 ADR-002 v3 双口径判定。**本轮零代码变更**，仅 CLI 执行 + 结果回流 + spec/WORK_LOG/delta_update 三份文档同步。

**执行明细**
- release binary：[.build/release/FallLineCLI](file:///Users/mingsen/Project/FallLine/.build/release/FallLineCLI)（含 ADR-002 默认 `fallbackPickStrategy = .ankleOnly` + `fallbackConfidenceFloor = 0.40`，本轮增量 `swift build -c release` 12.8s 通过）；
- 入口：[scripts/board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py) 44 片 × 3 CLI = 132 次运行；
- 输出回流：[outputs/board_edge_p2/gate_g1_probe_v3.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe_v3.log)（原始 tee 日志）+ [outputs/board_edge_p2/gate_g1_probe_v3_summary.json](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe_v3_summary.json)（结构化摘要 + 关键洞察 + 三条判定路径）。

**实测数字**
- 总账：44 片 / **8364 帧** / board **1638** / effV2 = effV3 = **2582**（v3 生产默认 `floor 0.40` 未额外剔除任何 fallback 帧——现有 fallback 帧 confidence 全部 ≥0.40，v2/v3 差异只在 pick 策略 `ankleOnly vs confMax`）。
- **Gate-G1 v3 主判定（ADR-002）**：
  - **v3-B**：片级 effCov≥25% 占比 **26/44 = 59.1%** vs 门槛 ≥60% → **FAIL**（差 0.9pp / **1 片**）；
  - **v3-A**：帧加权可用性（cap 60%）**30.64** vs 门槛 ≥40 → **FAIL**（差 9.36pp）；
  - **v3 总判定：FAIL**（A/B 二选一）。
- **Gate-G1 v2 对照**：v2-A 22/44 = 50.0% FAIL、v2-B 30.64 FAIL；v2-B 与 v3-A 帧加权数字一致（同 cap 60%），差异只在 v2-A/v3-B 的片级 cov 阈值（30% → 25%）。
- **确定性**：8364/8364 帧 bit-identical → **PASS**（v3 默认参数未引入任何非确定性）。
- **性能**：avg = 1.049（+4.9%）/ median = 1.050 / max = 1.079，远低于 ≤1.30 头部预算 → **PASS**。

**关键洞察**
1. **v3-B 只差 1 片**（22.1%~24.8% 桶 7 片：BND_HI3 22.1 / CAND_M05 21.7 / BND2_H2 22.5 / CAND_G05 23.2 / BND2_LB 23.2 / BND2_H1 23.5 / BND_L3 24.8），任一片被抬到 ≥25% 即可 PASS，属"极临界" FAIL；
2. **v3-A 结构性差 9pp**：帧加权 30.64 vs 40，光靠 pick 策略 / floor 微调难以补齐；
3. **effV2 = effV3 完全等值**：确认 `floor 0.30 → 0.40` 在当前 fallback 分布下不产生剔除，v3 相对 v2 的收益全在 pick 策略换来的精度天花板（GT 小闸门语义），而非 floor 换来的覆盖率数字；
4. **9 片 effV3 < 20% 结构性远景 / 低置信桶**（BND_L1 0 / BND2_L4 7.4 / BND_L2 7.6 / CAND_M09 7.7 / BND2_L2 8.5 / CAND_M01 9.0 / BND2_H3 12.5 / CAND_G07 15.4 / CAND_M08 17.8 / BND_HI2 19.7）：光靠 ankleOnly + floor 无法拉起，需要候选 F CoreML 分割才能翻身。

**文档回写**
- [spec §12.13](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L751) 尾追加"v3 44 片 8364 帧实测（2026-09-20，本 spec 首份 ADR-002 全量数字）"小节：执行入口、总账、v3-A/v3-B 判定表、v2 对照、确定性 & 性能、5 条关键洞察、3 条判定路径。
- [spec §12.4](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L421) 检查表把"候选 E 44 片 v3 重跑"从 `[ ]` 勾成 `[x]`，一句话结论 + 结构化摘要 JSON 引用。
- [spec 首行状态](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L5) 追加"v3 44 片实测（§12.13 尾）：双 FAIL + bit/perf PASS + 三条判定路径待拍板"。
- [WORK_LOG Current State](file:///Users/mingsen/Project/FallLine/WORK_LOG.md#L3) 换新为"v3 44 片实测 → 双门槛结构性 FAIL，三条判定路径待拍板"，旧 E+F 并行 Current 降级 Previous。

**下一步（等用户拍板）**
1. **激活 §12.14 候选 F CoreML spike**：跳出 2D 姿态几何天花板，正式启动 ADR-003 撰写 + `CoreMLBackend` 实现（[scripts/board_edge_coreml_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_coreml_spike.py) 骨架已就绪）；
2. **保留 v3 定义不动，走 Gate-G2 直判**：让 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py)（LOOCV + 1.5σ margin）直接承担"低覆盖率下的可分性证明"；
3. **追加 ADR-004**：显式承认"Gate-G1 v3 FAIL + 走 Gate-G2 直判"路径，把 Gate-G1 判定的必要性从"硬闸门"降级为"可用性观察"。

**遗留 / 未验证**
- 未跑 `swift test`（本轮零代码变更，v3 单测已在上一轮 290/290 通过）；
- v3 差 1 片的"极临界"性质可能诱导"再下调 v3-B 到 24%"的诱惑——ADR-002 §12.13 已明确记录"不推荐降门槛倒推"，本轮 §12.13 尾"判定路径"小节再次点名规避。

### 2026-09-20（E+F 并行·刃线/轨迹检测 Phase 2：候选 E ADR-002 落地 + 候选 F 设计骨架，评分零污染）

**本轮性质**：闭环 §12.12 尾段结论——候选 D NO-GO 后，Phase 2 主体前置候选缩到 E / F 二选一，本轮**并行推进两者**：候选 E 走完 spec ADR-002 → 探针脚本 v3 → 生产默认接线 → 单测的完整闭环；候选 F 落设计骨架不投模型二进制。**Sources 变更集中在 fallback 默认参数**（评分零污染，`boardEdgeObservation` 仍是纯诊断字段，Models 消费方零改动）。

**候选 E（Gate-G1 v3 门槛松绑）**

1. **spec §12.13 落 ADR-002（Accepted）**：Gate-G1 从"覆盖率闸门"翻转为"精度优先的可用性闸门"；fallback 链路收敛到 `ankleOnly + floor 0.40 + W=5 + IQR≤5°`；v3 门槛二选一——v3-A 帧加权可用性 ≥40%（保持）或 v3-B 片级 effCov ≥25% 占比 ≥60%（从 v2-B 30/60 下调）。答辩记录：§12.10 v2 双微差 + §12.11 GT 三策略 FAIL + §12.12 时序累积 NO-GO 三轮连续 FAIL；§6 Gate-G1 v3 条已同步。
2. **生产接线**：[BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift) 新增 `BoardFallbackPickStrategy` 枚举（`.confMax` 保留 v2 语义、`.ankleOnly` 是 v3 默认）；[BoardEdgeConfig](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L19-L100) 默认 `fallbackConfidenceFloor: 0.30 → 0.40`、`fallbackPickStrategy: .ankleOnly`；`synthesizeFallback` 按 `switch config.fallbackPickStrategy` 决定膝对是否参与，其余逻辑不变。生产帧级 `boardEdgeObservation` **不叠加时序聚合**（W=5/IQR≤5° 只在离线 [board_edge_fallback_temporal_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_fallback_temporal_spike.py) 复算）。
3. **探针脚本 v3 升级**：[board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py) 引入 `FALLBACK_CONFIDENCE_FLOOR_V3=0.40` / `GATE_G1_V3_CLIP_COV=25.0` / `GATE_G1_V3_CLIP_RATIO=0.60` / `GATE_G1_V3_WEIGHTED=40.0` / `GATE_G1_V3_WEIGHTED_CAP=60.0`；v3-A/B 双口径判定，保留 v2 对照；`summarize` 输出 v2/v3 两组数字。
4. **单测（e4）**：[BoardEdgeDetectorTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardEdgeDetectorTests.swift) 修复因默认策略变更失效的 5 个 v2 用例（显式传入 `confMax + floor 0.30` 还原语义：`test_fallback_prefersKneeWhenAnkleTooClose` / `test_fallback_kneePairOnly` / `test_fallback_confidenceJustAboveFloorPasses` / `test_fallback_confidenceJustBelowFloorRejected` / 相关 nil 边界）；新增 4 条 ADR-002 用例——
    - `test_defaultConfig_isAnkleOnlyWithFloor040`：默认基线锁定，防止误改回 v2。
    - `test_fallback_ankleOnlySkipsKneeEvenWhenKneeStronger`：踝间距 0.03 → cnf 0.324 < floor 0.40 被拒，膝对若参与本可 0.54 通过但 ankleOnly 结构性跳过 → 全体 nil。
    - `test_fallback_ankleOnlyIgnoresKneeWhenAnkleMissing`：踝缺失 + 膝对独立即使过 v2 floor 也拒（ankleOnly 结构性）。
    - `test_fallback_floor040RejectsBorderlineAnklePair`：cnf 0.39 < floor 0.40 被拒，同 pose 在 v2 (`confMax + floor 0.30`) 通过做对照。
    - `swift test` 全量 **290/290 通过**（Phase 1+ADR-001 基线 285 + 本轮 +5：4 条 ADR-002 + 1 条 v2/v3 边界拆分）。

**候选 F（CoreML 板边分割 spike）Design only**

- **spec §12.14 落设计骨架**：4 模型对比表（DeepLabV3+ MobileNetV2 / U-Net tiny / SAM2 tiny / YOLOv8-seg nano）、初选 YOLOv8-seg nano 或 DeepLabV3+；GT 标注方案（100–300 帧板身像素级 mask，~4 人时含 QA）；6 条决策标准（IoU ≥0.65、CoreML M1 Pro ≤20ms/frame、GT 准入 ≥90%、farShot 恢复率 ≥50%、bit-identical、总人力 ≤20 人时）；成本 vs 收益预算（收益上限 effCov 50–60%、下限持平 fallback）；决策路径（v3+Gate-G2 通过 → 降级 Phase 3+；v3 通过 Gate-G2 失败 → 升 P0）。
- **新增骨架脚本 [scripts/board_edge_coreml_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_coreml_spike.py)**（约 260 行，纯 stdlib）：`SegmentationBackend` 抽象接口 + `NoopBackend` 占位实现；三条命令行入口——`--check-plan` 打印 §12.14 决策标准与决策路径、`--list-clips` 与 v3 探针共用 44 片 CLIPS（校对通过）、无参跑打印占位说明 + Noop 报告 JSON；`--model` / `--gt` / `--report` 参数留位但未实现，`--model` 明确以退出码 2 拒绝，防止误启动；`compare_against_fallback` 骨架挂 `fallback_gt_cache.json` 对齐 TODO(ADR-003)。**不引入模型二进制、不改 [Package.swift](file:///Users/mingsen/Project/FallLine/Package.swift)、不新增依赖**；`py_compile` 通过。
- **不动**：本轮不启动训练、不新建 `outputs/board_edge_p2/coreml_spike/` 目录，等 ADR-003 生效后另起。

**文档回写（本轮四文件）**

- spec §12.13（ADR-002 完整骨架）+ §12.14（候选 F 骨架）+ §12.4 检查表新增候选 E 单测条 + 首行状态标记 E 已落 F 骨架。
- WORK_LOG Current State 换新（E+F 并行）+ 旧 Current 降级到 Previous。
- delta_update 新条目（本条）。
- Package/CLAUDE/AGENTS/file_manifest 不改。

**验证**

- `swift test` 全量 **290/290 通过**；因默认策略变更失效的 v2 单测已通过显式配置还原语义。
- Sources 变更：[BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift) 新增枚举 + 4 处默认参数；`boardEdgeObservation` 仍不参评分（评分零污染原则守住）。
- 探针脚本 `py_compile` 通过；44 片 v3 实测数字暂不在本轮跑（探针 script 已就绪，等 CLI 8364 帧）。

**遗留问题**

- 候选 E 44 片 v3 实测判定表（v3-A / v3-B 具体数字）未跑，等用户决定是否投入 25 分钟 CLI 重跑。
- Gate-G2 可分性判定与候选 F spike 启动均阻塞在 v3 实测数字上。

### 2026-09-20（尾段·刃线/轨迹检测 Phase 2：候选 D 时序累积离线 spike NO-GO，评分零改动）

**本轮性质**：闭环 §12.11 下一步「候选 D 方向 C 时序累积」——在不改生产代码的前提下，通过纯 Python 离线 spike 验证「前向 W 帧滑窗 + 中位滤波 + IQR 稳定性门控」能否同时把准入精度顶到 90% 且守住 Gate-G1 v2 覆盖率门槛。**零生产代码变更**（仅新增脚本 + spec §12.12 / §12.4 检查表 / 首行状态 + WORK_LOG）。

**新增脚本 [board_edge_fallback_temporal_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_fallback_temporal_spike.py)**（约 220 行，纯 stdlib）：
- 复用 §12.11 `fallback_gt_cache.json`（不重跑 CLI）；引入 §12.11 `pick_confmax / pick_ankle_preferred / pick_ankle_only` 三策略。
- 聚合器规则：非 `{board,rejectPosture,disabled}` 帧上，窗口 = [f-W+1..f] 前向候选（`pick.confidence ≥ floor`）；通过条件 = 候选数 ≥ ⌈W/2⌉ 且 IQR(angles) ≤ 阈值；聚合角 = 中位、conf = 中位、源 = 多数派。
- GT 评估：对 board 帧 f，用前一 W 帧候选（不含 f 自身）聚合，通过则与真 `ba` 比误差——模拟"如果这帧走 fallback"。
- W=1 baseline 与 §12.11 单帧数字逐位一致（confMax 145/86.9%、ankleOnly 133/87.2%）——脚本口径自校准。
- `py_compile` 通过；单跑 44 片 81 组合仅耗时 ~1 秒（纯内存计算）。

**扫描空间**：3 策略 × 3 floor (0.30/0.35/0.40) × 3 窗 (1/5/7) × 3 IQR (5°/8°/∞) = **81 组合**；结果日志 [fallback_temporal_spike.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/fallback_temporal_spike.log)（.gitignore，96 行）。

**关键结果**（选中 6 行；其余在日志）：

| 策略 | floor | W | IQR | GT 命中 | 中位 | 准入 ≤12° | effCov | v2-A | v2-B | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|
| confMax | 0.30 | 1 | – | 145 | 3.98° | 86.9% | 35.51% | 56.8% | 34.91 | baseline（= §12.11） |
| **ankleOnly** | **0.35** | **5** | **5°** | 57 | 3.78° | **91.2%** ✅ | 26.90% | 40.9% | 26.76 | **GT 最强 / v2 差** |
| confMax | 0.35 | 5 | 5° | 55 | 3.38° | 90.9% ✅ | 26.96% | 40.9% | 26.82 | GT 过 / v2 差 |
| ankleOnly | 0.40 | 1 | – | 110 | 3.32° | 90.0% ✅ | 30.87% | 50.0% | 30.64 | GT 过 / v2 差（无时序） |
| ankleOnly | 0.40 | 5 | 5° | 53 | 3.78° | 90.6% ✅ | 25.72% | 38.6% | 25.58 | GT 过 / v2 差 |
| ankleOnly | 0.35 | 5 | ∞ | 69 | 4.99° | 87.0% ❌ | 27.97% | 43.2% | 27.83 | 关 IQR → 准入回落 |

- **无一组合同时过 GT (≤12° 中位 & ≥90%) 与 v2 (v2-A ≥60% 或 v2-B ≥40)**。
- **时序聚合机理有效**（准入 87.2% → 91.2%），但 IQR 门本身把 60% 候选帧剔了；effCov 从 35% 掉到 25–27%，v2 双门槛更远。
- W=7 全线劣于 W=5（更严 → 更少 GT）。
- 短片风险 = 0：W=1/5/7 三档下 0/44 片帧数 < W，最短片 55 帧 > 7。失败原因不是"短片没窗口"，是**几何精度天花板 vs Gate-G1 v2 40/60 门槛的结构性矛盾**。

**结论**：候选 D 单独 **NO-GO**。Phase 2 主体前置候选缩到 E / F 二选一（详见 spec §12.12）：

- **候选 E**（Gate-G1 v3 门槛松绑）：以 `ankleOnly + floor 0.40 + W=5 + IQR≤5°` 通过；需在 §6 落 ADR-002 v3-A ≥40% / v3-B ≥25，答辩"覆盖率不再是主指标"。
- **候选 F**（CoreML 板边分割 spike）：另起视觉信号，跳出 2D 姿态几何天花板；投入产出未知。

不再建议：候选 D 独立推进、fallback 规则再迭代（§12.11 已扫尽，本轮又证时序聚合触到同一天花板）。

**验证**：本轮零 Sources / 生产代码变更（仅 scripts 新增 1 文件 + docs 3 文件更新）；`py_compile scripts/board_edge_fallback_temporal_spike.py` 通过；`swift test` 未跑（无 Sources 变更，Phase 1+ADR-001 285 通过基线不变）。

**遗留问题**：等用户在 §6 决策候选 E vs F 后进 Phase 2 主体。

### 2026-09-20（下半段·刃线/轨迹检测 Phase 2：fallback GT 精度小闸门收官，结构性 FAIL，评分零改动）

**本轮性质**：闭环 §12.10 下一步①——全 44 片 8364 帧 × 三 pick 策略 × 八 floor GT 小闸门跑通，验证 [synthesizeFallback](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L232-L300) 是否达到 spec §12.9 规定的准入精度门槛。**零生产代码变更**（仅脚本升级 + spec §12.11 + WORK_LOG）。

**脚本变更**：[board_edge_fallback_gt_gate.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_fallback_gt_gate.py) 大改：
- 从 bodyPose 关键点 Python 精确复现 synthesizeFallback 并与生产 JSON `fallbackAxis` 逐位交叉验证（1332/1332 OK，无坐标差异）；
- 引入 JSON 缓存（[fallback_gt_cache.json](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/fallback_gt_cache.json)，按视频+binary mtime/size 失效，`--refresh` 强刷）——首跑 CLI ~25 分钟，后续 policy/floor 组合切换 0 CLI 重跑；
- 三 pick 策略并列评估：`confMax`（生产现状）/ `anklePreferred`（踝 conf≥0.40 优先）/ `ankleOnly`（丢弃膝对）；
- 修复初版两个逻辑问题：① 双重计数（board 帧也计 fallback 候选导致 effCov 150%），改为只在生产会走降级的 status 集合外统计；② 主口径应为「实际选中轴」而非只看踝对。
- `py_compile` 通过；单片冒烟 BND2_L1（76 帧 board 57 / fb 3）交叉验证 OK。

**44 片 × 三策略结果**（板帧 pick↔真实 board 角配对；参照 GT；日志 [fallback_gt_gate_44.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/fallback_gt_gate_44.log)，.gitignore）：

| 策略 | 选踝/选膝 | 中位 | 准入 ≤12° | 小闸门 | v2-A / v2-B（floor 0.30） |
|---|---|---|---|---|---|
| confMax（生产）| 1354 / 215 | **3.75°** PASS | **85.1%** FAIL | FAIL | 56.8% / 34.91 |
| anklePreferred | 1170 / 399 | 4.00° PASS | 82.9% FAIL | FAIL | 50.0% / 31.34 |
| ankleOnly（三者最优）| 1438 / 0 | **3.53°** PASS | **87.2%** FAIL | FAIL | 56.8% / 34.50 |

- **①中位误差三策略全 PASS，②准入精度三策略全 FAIL**（最好 87.2%，差 90% 门槛 2.8pp）。
- 分源精度（confMax）：选踝 89.9% vs **选膝 55.3%**——弯中双膝内扣 5–15° 系统性偏差，膝对是准入拖累主力。
- floor 扫描（confMax）**精度-覆盖率强负相关**：floor 0.30 准入 92.2%（GT 单项过）但 v2 双差；floor 0.40 准入 94.4% 但 v2-A/B 崩到 50%/30.7；floor 0.70 准入 98.2% 但 v2-B 只有 22。**无 floor+pick 组合可同时过关**。

**结论**：ADR-001 定义的 fallback 链路在当前 §4.4 corpus 与 pair floor=0.30 组合下**不能通过 Gate-G1 v2 小闸门**——不是脚本 bug、不是策略选择错误，是 2D 踝对作为板轴代理的**几何精度天花板**（低置信踝点位置误差 → 角度尾部）。本轮 3 策略 × 8 floor = 24 组合已扫尽这类空间。

**遗留 / 下一步**（三选一，等确认，[spec §12.11 尾](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L649)）：① **候选 D 方向 C 时序累积**（连续 ≥5 帧稳定轴 + 中位滤波），风险是 §4.4 短片窗口缺样；② **候选 E Gate-G1 v3 口径松绑**（v3-A ≥50% / v3-B ≥30，落 ADR-002），需先答辩「覆盖率不再是主指标」；③ **候选 F CoreML 板边分割 spike**（ADR-001 Consequences 已列备选）。三条互斥，决策后再进 Phase 2 主体。

**验证**：`swift test` 未跑（无 Sources 变更，上轮 285 通过基线不变）；`py_compile` 通过。

### 2026-09-20（刃线/轨迹检测 Phase 2：方向 A 落地——fallbackAxis 实现 + 全 44 片 v2 度量，评分零改动）

**本轮性质**：ADR-001 ①–④ 前半实现闭环：fallback 合成链路、overlay、脚本升级，44 片（8364 帧）单轮 audit + 三轮探针度量。评分 / PoseSmoother 语义 / iOS 零改动。

**生产代码变更**：
- [Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L621-L662)：新增 `BoardFallbackSource{anklePair,kneePair}`、`FallbackAxis`（7 字段，init clamp），`BoardEdgeStatus` 加 `.fallback`，`BoardEdgeObservation` 加 optional `fallbackAxis`（默认 nil，旧 JSON 兼容）。
- [BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift)：抽出 `primaryDetection()`；`detect()` 按状态分派（board/rejectPosture 直通，其余在 `enableFallback` 下尝试合成，成功置 `.fallback` 并透传 subjectFraction/ankleConfidence）；`synthesizeFallback`/`fallbackAxis` 纯函数（踝对权重 1.0 / 膝对 0.6 取高者；点 cnf→间距→合成 cnf 三级门控；角度与 PCA 同口径折叠 0…90）；`BoardEdgeConfig` 加 5 个 fallback 参数，enableFallback 默认 true。
- [DebugOverlayRenderer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/DebugOverlayRenderer.swift#L359-L399)：board 青轴 / fallback 黄轴。

**脚本变更**：[board_edge_reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py) 与 [board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py) 升级 fallback 口径。探针首跑 44 片数据全产出但 summarize 残留旧常量 `GATE_G1_COVERAGE` 报 NameError——已修复（不影响数据）；并修正帧加权 cap 误用 30%（片级门槛）→ 按 spec §6 权威口径 cap=60%，新增 `GATE_G1_V2_WEIGHTED_CAP=60`。两脚本 py_compile 通过；从日志解析复算汇总，未重跑 CLI。

**44 片度量结果**（产物 `outputs/board_edge_p2/reason_audit_44_v2.log`、`gate_g1_probe_44_v2_summary.txt`，.gitignore；详见 [spec §12.10](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L586)）：
- raw board **19.58%**（与 v1 逐位一致，证重构无污染）；effective（board+fb≥0.30）**35.51%**——救回 1332 帧（+15.93pp），originalStatus 回流 farShot 902（67.7%）/ noMask 150 / rejectBlob 116；ankleLowCnf 仅回流 6（踝中心失败时踝对天然不可用，符合 ADR 预期）。
- **Gate-G1 v2 微差 FAIL**：v2-A 片级 effCov≥30% 占比 **25/44=56.8%**（门槛 60%，差 2 片）；v2-B 帧加权可用性 **34.90**（门槛 40，差 5.1）。当前为 GT 精度小闸门之前的乐观上界。压线片 CAND_G05 29.5% / BND2_TOP 29.2%。
- 确定性 **8364/8364 bit-identical PASS**（含 fallbackAxis 全字段）；性能 avg **+4.51%** / median +4.31% / max +7.56% **PASS**（门槛 ≤30%）。

**验证**：`swift test` 全量 **285 通过**（BoardEdgeDetectorTests 新增 11 例：双源选择、floor 上下边界、角度折叠、Codable）；`swift build -c release` 通过。

**遗留 / 下一步**（等确认）：① fallback GT 精度小闸门（同帧 board vs fallback 角度：中位误差 ≤12°、准入精度 ≥90%），据此校准 floor；② GT 后重判 v2-A/B，仍 FAIL 按 ADR-001 回 §6 重评（方向 C 时序累积 / CoreML），不放宽门槛；③ Gate-G1 过才进 Gate-G2 可分性。

### 2026-09-19（刃线/轨迹检测 Phase 2：ADR-001 Accepted + fallbackAxis 降级链路设计定稿，仅文档）

**本轮性质**：方向 A 设计闭环——Gate-G1 门槛 v2 决策 + fallbackAxis 实现规格。**零 Sources / 零脚本变更**，仅 spec + WORK_LOG + 本文件；未跑 build/test。

**spec 变更（[2026-09-18-board-edge-trajectory-detection-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md)）**：
- [§6 验收闸门](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L208)：Gate-G1 拆为 v1（历史，全帧≥60%，结构性 FAIL）与 **v2（现行）**：有效帧 = board + fallback（confidence≥floor）；片级可用性二选一（effectiveCov≥30% 片占比≥60% 或帧加权可用性≥40%）；确定性/性能条款沿用。
- [§12.9 新增](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L481)：ADR-001 全文（Status/Context/Decision/Consequences）+ 几何勘误 + fallbackAxis 实现规格六节（触发流程、双源代理与置信度公式、GT 精度小闸门、数据模型与 Codable 兼容论证、探针/overlay 同步、实施顺序）。
- [§12.4 检查表](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L393)：勾上"候选池回填（44 片）"与"ADR + fallbackAxis 定稿"；覆盖率项更新为 v1 FAIL / 待 A 实现后按 v2 重测。

**关键设计决策**：
- **几何勘误**：原"踝-膝矢量合成板轴"不成立——踝-膝是小腿方向（对应立刃角）。板长轴一阶代理 = **双踝连线**（复用 [computeAnkleProxyBoardAngle](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseMetrics.swift#L468-L483) 口径），二阶弱代理 = **双膝连线**（源权重 0.6）。
- **置信度** = 关节对点置信度均值 × min(归一间距×12, 1) × 源权重；floor 初值 0.30（点对/合成双 floor），属待 GT 校准值；不合格保留原始拒绝 status。
- **触发集**：不搞状态白名单——除 `board / rejectPosture / disabled` 外所有拒绝状态统一尝试，由关键点 + 间距门控自然裁决（含 rejectOwnership：mask 属他人但姿态属本人）。
- **模型**：新增 `FallbackAxis`（source/axisAngle/center/lengthRatio/confidence/originalStatus）+ `BoardEdgeStatus.fallback`；`BoardEdgeObservation.fallbackAxis` optional + init 默认 nil；不做跨帧平滑（留方向 C）；`enableFallback` 配置开关随 `--board-edge` 生效，不加新 flag。
- **放水防护**：fallback 进 Gate-G1 v2 统计前须过 GT 精度小闸门（中位角度误差 ≤12°、准入精度 ≥90%、bit-identical）；若远景帧几何门控大面积拒绝导致 v2 仍不达标，不继续放宽，回 §6 重评。

**遗留 / 下一步**（等确认开工）：① Models + `synthesizeFallback` 纯函数 + 单测；② Detector 接线；③ overlay 黄轴；④ GT 小闸门 → 校准 floor → 全 44 片 v2 度量；⑤ 文档回写。全程不跑评分联动。

### 2026-09-19（刃线/轨迹检测 Phase 2：Batch 3 档位回填闭环 + 全 44 片分档 audit，证伪"只改门槛"）

**本轮性质**：Phase 2 扩边界集收尾——19 张接触表逐张判档并回填 [Batch 3 表](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md#L153)，边界集 25 → **44 片全部有教练档位**；同步两脚本 group 后全量重跑 reason audit。**未改任何生产代码**（19 行标注 + 脚本 CLIPS/文案 + 三份文档）。

**Batch 3 回填结果（19 片）**：
- 档位分布：**专业 10**（G01–G08 + M03 + M05）/ **高质量 1**（M10，连续走刃但非竞技级折叠）/ **中级偏上 5**（M02/M04/M06/M08/B01）/ **中级 1**（M07）/ **初级 2**（M01/M09）；确认稳定刻滑 11 片。
- 高端密度虚高被证实但不极端：教练专业 10/19 vs 算法专业带 12/19。典型错档：B01 算法 75 实为中级纠错片（踮脚尖/前刃不稳、片中摔倒）、M09 算法 61 实为初级放板（bestThird 抬高）、M01 calf 6.7 全集最低坐实初级；M08 藏王粉雪高站姿算法 81 实为中级偏上（粉雪非刻滑）。

**脚本同步**：[gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py) / [reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py) CLIPS 中 19 片 `tbd` 全部替换为实际 group（high=专业/高质量刻滑、mid=中级/中级偏上、low=初级），头部注释 / 分档标题同步更新。

**全 44 片 reason audit（8364 帧，`outputs/board_edge_p2/reason_audit_44.log`，.gitignore）**：
- board **1638/8364 = 19.58%**——第三次独立复现 ~20%（25 片 19.56% → 19 片 19.61% → 44 片 19.58%），60% 门槛结构性不可达一锤定音。
- 分档：high（21 片/4721 帧）board18% / farShot38% / ankleLowCnf25% / noMask9%；mid（13 片/1927 帧）board26%（最高）/ farShot23% / ankleLowCnf23% / rejectVertical+rejectLength 各 8%；low（10 片/1716 帧）board16% / farShot35% / ankleLowCnf27% / rejectOwnership6%。

**关键新负结论（spec §12.8）**：§12.6 方向 B 两个重定义门槛在 44 片上同样 FAIL——
- "片级 cov≥30% 占比 ≥60%"：实测 **12/44 = 27.3%**（旧 25 片 28%，扩集无改善）；
- "加权可用性 Σmin(cov,60%)·f/F ≥40%"：实测 **19.4%**（因片 cov 均远低于 60%，数学上退化为普通覆盖率）；
- 分档 ≥30% 片数 high 3/21、mid 5/13、low 4/10。
- **"只改统计口径"证伪 → 方向 A 降级链路（ankleProxy 几何合成 fallbackAxis，不新增模型推理，覆盖 farShot/ankleLowCnf/noMask 合计 64.4% 拒绝帧）成为 Gate-G1 v2 唯一前置**；A 落地重跑后再定 B 阈值，时序方向 C 并行。

**验证**：2 个 py 脚本 `py_compile` 通过；本轮零 Sources 变更，release binary 不变、未跑 `swift test`（Phase 1 274 通过基线不变）。

**遗留 / 下一步**（等确认）：① spec §6 落 ADR + `BoardEdgeObservation.fallbackAxis` Codable 后向兼容设计；② 实现方向 A 几何合成，重跑 44 片 audit 验证片级覆盖率；③ A 通过后定方向 B 阈值，进时序特征 + Gate-G2。

### 2026-09-18（刃线/轨迹检测 Phase 2 扩边界集：§4.4 第三批 19 片算法列 + Gate-G1 预跑）

**本轮性质**：Phase 2 扩边界集——把起步 1 的 19 片接触表候选池（good 8 / middle 10 / bad 1）一次性纳入 [calibration_anchors.md §4.4 Batch 3](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md#L153)。**未改任何生产代码**（新脚本 + 文档 + 探针 CLIPS）。教练档位/刻滑两列留空，待看接触表回填。

**新增 [scripts/board_edge_batch3_extract.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_batch3_extract.py)**（约 200 行，纯 stdlib）：
- 19 片跑当前 release **基线** CLI（不开 `--board-edge`），提取综合分 / edgeQuality(conf) / pressure / calf / knee / sideslip / carvingCnf / 时长，直接吐 Markdown 表行。
- calf/knee 加权口径对齐 [StageClassifier.averageSubScores](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/StageClassifier.swift#L24-L39)：只取可靠姿态帧、按 `totalConfidence` 加权。旧片校验：knee 与既有标注精确复现，calf 有 ~1.5 的旧缓存版本微漂（综合分 92 精确对齐）；CAND_G07=86 / edge60.8 / calf48.2 与 GOOD_A 锚点一致，佐证口径对齐。
- 产物：`outputs/board_edge_p2/batch3_extract.log` + `batch3_json/<alias>.json`（均 .gitignore）。

**探针/审计脚本扩样**（CLIPS 25 → 44 片）：[board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py) / [board_edge_reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py) 各加 19 片 `group="tbd"`；audit 分档聚合从写死 high/mid/low 改为按实际 group 动态排序，tbd 单列不混桶。回填档位后把 tbd 改成实际 group 即可重跑，覆盖率数字本身不随档位变。

**第三批 Gate-G1 reason 预跑**（spec §12.7，4218 帧，`outputs/board_edge_p2/batch3_reason_audit.log`）：
- **board 覆盖率 827/4218 = 19.61%，与旧 25 片的 19.56%（811/4146）几乎逐位相同**——两个独立候选池同得 ~20%，坐实 Gate-G1 v1 的 60% 门槛结构性不可达、非抽样偶然，再次支撑 §12.6 方向 B/A（门槛重定义 + 降级链路）。
- reason 分布：farShot **37.22%** / ankleLowCnf **22.12%** / noMask **7.56%**（较旧池 4.51% 上升为第三大项，CAND_G02 单片 59.2% 前景分割失败）/ rejectLength 4.84% / rejectPosture 3.65% / rejectBlob 2.28% / rejectOwnership 1.85% / **rejectVertical 仅 0.71%**（旧池 4.80%，二度证伪放宽 45° 夹角门控）/ noAxis 0.17%。
- 每片主导路径：farShot 9 片（M02 86% 最高）、ankleLowCnf 6 片（M01 60% 最高）、noMask 3 片（G02/G01/M06）。片级高覆盖：M06 56% / G06 48% / M10 44% / B01 41% / M04 35% / G03 30%。

**算法列初步观察（不作档位依据）**：弱先验分与当前 release 偏差大（G02 72→93、M01 67→55 calf 仅 6.7、M05 74→93）；12/19 落专业带、calf≥48 达 14 片，候选池偏高姿态质量——回填时需重点核对"姿态好 ≠ 专业刻滑"，防 Gate-G2 高端密度虚高。

**验证**：release build 通过；3 个 py 脚本 `py_compile` 通过；本轮零 Sources 变更，未跑 `swift test`（Phase 1 274 通过基线不变）。

**2026-09-19 补：Batch 3 数据只读核对（无文件改动）**——教练回填前对 19 片原始 JSON 做独立重算（未复用提取脚本逻辑，避免同 bug 同源）：
- **19 片 × 9 列全部匹配**：综合分 / edge / edgeConf / pressure / calf / knee / sideslip / carvingCnf / 时长，与 [Batch 3 表格](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md#L157)逐格一致；calf/knee 独立重算严格走 [reliablePoseFrames](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L272-L278)（`poseScore≠nil && bodyPose.detected` + `totalConfidence≥0.30`，空则回退，权重 `max(0.01, cnf)`）与 [averageSubScores](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/StageClassifier.swift#L24-L39) 口径。
- 核对过程中的 DIFF 系**校验脚本自身量纲错误**（误把 JSON 已为百分数的 `carvingConfidence` 再 ×100，得 1755），修正后全对；**表格数据无需改动**。
- 结构完整性：19 JSON 齐全、`totalFrames` 与 frames 数组长度全一致；有效抽帧帧率全部 ≈5.00fps（5.00–5.06）；reason 十状态求和 4218 与总帧精确闭合。
- 评分勾稽：最终分均可由 `evidenceCappedScore × flowModulation` 复现（如 M06 78×1.05→82、M01 52.1×1.05→55），无矛盾。
- **判档注意点**：bestThird 虚高在本批同样明显（M01 raw44.7→best1/3 52.1、M07 raw51.7→62.3）；M01 可靠姿态帧仅 37%（全池最低，calf6.7 稳定性弱）；M04=72/M06=78/M07=62 触发证据 cap；本批 flow 仅 +5% 加成、无惩罚（10 片 ×1.05）。

**遗留 / 下一步**：等教练看 `outputs/board_edge_p2/contact_sheets/<alias>.jpg` 回填 §4.4 第三批档位/刻滑 → 同步两脚本 group → 44 片重跑 Gate-G1 三合一 + 分档 reason audit（方向 B 片级口径）→ 回写 §12.7 / WORK_LOG / delta_update。

### 2026-09-18（刃线/轨迹检测 Phase 2 起步 3：Gate-G1 reason audit 翻转下一步方向）

**本轮性质**：紧接 Phase 2 起步 2（Gate-G1 三合一探针）向前推一格——落地 reason 分布 audit 脚本，对 §4.4 全 25 片跑通并**证伪 §12.5 结尾提出的"放宽板轴几何门控"路线**。**未改任何生产代码**，仅新增 audit 脚本 + 更新 spec / WORK_LOG / delta_update。

**新增脚本 [scripts/board_edge_reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py)**（约 210 行，纯 stdlib）：
- 单轮 CLI（`--board-edge`），从 JSON 逐帧解析 `boardEdgeObservation.status`，按 [`BoardEdgeStatus`](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L594-L617) 11 枚举（board / farShot / rejectVertical / rejectLength / rejectBlob / rejectOwnership / rejectPosture / ankleLowCnf / noAxis / noMask / disabled）做分片直方图。
- 聚合层：全集总账 + 分档位（high/mid/low）对比 + 每片最大拒绝路径 + Top-5 拒绝路径。
- 不做 bit-identical / 耗时对比（§12.5 已 PASS，不重复验证）；支持 `ONLY=<alias>,...` 单片过滤、`-n <k>` 前 k 片抽样。

**25 片全量结果**（4146 帧）：
- **Top-5 拒绝路径**：`farShot` **29.76%**（1234 帧）/ `ankleLowCnf` **27.59%**（1144 帧）/ `rejectLength` 5.79%（240）/ `rejectVertical` **4.80%**（199）/ `noMask` 4.51%（187）。其余 `rejectBlob` 3.59% / `rejectOwnership` 3.09% / `rejectPosture` 1.11% / `noAxis` 0.17%。
- **分档位**：
    - high 桶 2106 帧：board 15% / farShot **42%** / ankleLowCnf **28%** / noMask 7%（远拍专业滑手，人体像素占比与踝点稳定性双吃亏）
    - mid 桶 1079 帧：board 24% / ankleLowCnf **28%** / rejectVertical **14%** / rejectLength **10%**（BND_M2 独家 rejectVertical 25% + rejectLength 16%）
    - low 桶 961 帧：board 25% / farShot **27%** / ankleLowCnf **25%** / rejectOwnership 7%（雪场群拍背景他人板）
- **每片最大拒绝路径归类**：`ankleLowCnf` 主导 **12 片**（近半，BND_L1 66% / BND_M3 65% / BND2_L4 63% / BND2_LB 57% / BND_HI2 57% / BND_L2 53% / BND_M1 48% / BND2_H2 47% / BND2_H1 39% / BND_L3 34% / BND2_L3 34% / BND2_TOP 28% / BND2_L1 21%）；`farShot` 主导 **7 片**（BND_HI1 74% / BND2_L6 63% / BND_HI3 62% / BND2_H3 58% / BND2_H0 40% / BND2_H4 34% / BND2_GM 31%）；`rejectOwnership` 主导 2 片（BND2_L2 37% / BND2_L5 29%）；`rejectVertical` 主导仅 1 片（BND_M2 25%，全集唯一）；`noMask`/`rejectBlob` 各 1 片；1 片纯 board。

**方向翻转（关键结论）**：
- §12.5 结尾曾提出"放宽 `farShot=0.02→0.01` / `rejectVertical=45°→55°` / 或重定义门槛"三条候选，本轮 audit **证伪前两条**：即使把 `farShot`(29.8%) + `rejectVertical`(4.8%) 完全砍掉，理论覆盖率上限只到 **54%**（19.6% + 34.6%），仍够不到 60% 门槛；而 **`ankleLowCnf` 27.6%** 是完全独立的踝点定位问题，与板轴几何门控无关。
- 放宽 `farShot / rejectVertical` 不但收益 <5% 完成 Gate-G1 覆盖率闭环，还会**引入远景假阳/雪杖误识**（Phase 0 §10.4 已经做过决策，rejectVertical 拦下的正是雪杖/裤腿/竖直他人）。

**Phase 2 主体方向重定义**（§12.6，评分零改动）：
1. **优先方向 A：降级链路** — `status ∈ {ankleLowCnf, farShot, noMask}` 时，`BoardEdgeDetector` 用踝-膝矢量 + 髋高度先验合成 `boardEdgeObservation.fallbackAxis`（复用 [`BoardObservationSource.ankleProxy`](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L555-L557)）。**不新增模型推理，性能开销可忽略**；Gate-G1 覆盖率按 `status ∈ {board, fallbackAxis}` 重新度量。
2. **优先方向 B：Gate-G1 覆盖率门槛重定义** — 从"全帧口径 ≥60%" 改为"每片可用性 = min(cov%, 60%)，加权平均 ≥40%" 或"片级 cov% ≥30% 的样本比例 ≥60%"（当前 §4.4 25 片中 cov% ≥30% 的样本 7/25 = 28%）。此路是纯统计约定，需在 §6 明确 ADR。
3. **辅助方向 C：Phase 2 时序特征以"连续 board 片段"为输入** — 要求视频存在"连续 ≥5 帧板轴稳定"窗口（1 秒 @ 5fps），BND2_L1(75%) / BND2_LM(57%) / BND2_L3(50%) / BND_M4(38%) / BND2_L5(39%) 5 片已具备。

**产物**：[outputs/board_edge_p2/reason_audit.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/reason_audit.log)（`.gitignore` 已排除，`outputs/board_edge_p2/*.log` 规则命中）。

**spec 更新**（[2026-09-18-board-edge-trajectory-detection-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md)）：
- §12.4 前置检查表新增 `[x] Phase 2 起步 3：Gate-G1 reason 分布 audit 完成` 与"覆盖率一行"更新链接指向 §12.6（原指向 §12.5 已废弃）。
- 新增 §12.6 "Gate-G1 reason 分布 audit（2026-09-18，§4.4 全 25 片，4146 帧）"：脚本描述 + Top-5 拒绝路径 + 分档位对比 + 每片最大拒绝归类 + 方向翻转分析 + Phase 2 三方向重定义 + 不建议方向 + spec §6 决策要求。
- §12.5 "Gate-G1 结论"补一句：`覆盖率被压低的主因初步猜测已被 §12.6 部分证伪`；"下一步"改为"由 §12.6 已完成第 1 项"。

**验证**：
- 3 片验证（BND_L1 + BND2_LB + BND2_L1）：小样本 top-reject 全是 `ankleLowCnf` 66% / 57% / 21%，与全量结论一致，格式 & 聚合逻辑正确。
- 全量 25 片单轮，与 §12.5 三轮的 board 帧数总账完全对齐（811 帧），说明单轮 audit 与三轮探针在覆盖率维度上等价。
- 本轮零 Sources 变更，`swift build` / `swift test` 未跑（release binary 复用 §12.5 build，Phase 1 274 通过基线不变）。

**下一步（未开始，等确认）**：
1. **spec §6 补 ADR "Gate-G1 覆盖率不是唯一门槛"**：把优先方向 A + B 组合作为 Gate-G1 v2 定义，v1 门槛 60% 降级为"理想覆盖率"仅供参考、不作为准入闸门；此 ADR 未落地前不动 [`BoardEdgeConfig.standard`](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift) 阈值。
2. 起草 `BoardEdgeObservation.fallbackAxis` Codable 后向兼容改造（新增字段，评分零改动）。
3. 教练判档 §12.2 优先次序 9 片 → §4.4 扩到 ≥34 → 重跑 §12.5 + §12.6 探针，验证降级链路 A 是否能把覆盖率推到 v2 门槛。

---

### 2026-09-18（刃线/轨迹检测 Phase 2 起步 2：Gate-G1 三合一探针跑通 25 片，两 PASS 一 FAIL）

**本轮性质**：紧接 Phase 2 起步 1（接触表落地）向前推一格——落地 Gate-G1 三合一探针脚本，对 §4.4 全 25 片跑通并输出**确定性/性能双 PASS、覆盖率 FAIL** 的负结论。**未改任何生产代码**，仅新增探针脚本 + 更新 spec / WORK_LOG / delta_update。

**新增脚本 [scripts/board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py)**（约 210 行）：
- 每片 CLI 三轮：`--board-edge` × 2 + 基线 × 1；从 JSON `detections[*].boardEdgeObservation` 逐帧提取 status/reason，三合一同帧算：
    ①**覆盖率** = `status=board` 帧数 / 总帧数（Gate-G1 门槛 ≥60%）；
    ②**确定性** = 两轮 `--board-edge` 逐帧 `board_flag / axis_angle_deg / axis_length_norm / confidence / near_body_shape / obs_confidence / reason` 全字段 bit-identical；
    ③**性能** = `--board-edge` 均耗时 / 基线耗时（Gate-G1 门槛 ≤30%）。
- CLIPS 25 片映射 §4.4：BND2_* 12 片 + BND_HI1-3 / BND_M1-4 / BND_L1-3 10 片；BND_HI1-3 首版误定位到 `video/good/` 已改为 `video/middle/`。
- 支持 `ONLY=<alias>,<alias>,...` 单片过滤、`-n <k>` 前 k 片抽样；调用 `/Users/mingsen/Project/FallLine/.build/release/FallLineCLI` release 二进制。
- 直接以 `/usr/bin/python3 scripts/board_edge_gate_g1_probe.py` 运行，纯 stdlib（无第三方依赖）。

**25 片全量结果**：
- **覆盖率**：全帧口径 **811/4146 = 19.56%** → FAIL（远低于 60%）；片级 ≥60% 仅 1/25：BND2_L1 = 75%，其次 BND2_LM 57% / BND2_L3 50%。
- **确定性**：**4146/4146 = 100%** bit-identical → PASS（跨两轮 `--board-edge` 逐字段完全一致）。
- **性能**：`--board-edge` 开对总耗时 **avg +5.9% / median +5.2% / max +19.7%** → PASS（远低于 30%）。
- 单片分布（cov% ↓，前 10）：BND2_L1 75% / BND2_LM 57% / BND2_L3 50% / BND2_L5 38.7% / BND_M4 37.7% / BND_M2 32.3% / BND2_H4 31.6% / BND_M1 28.9% / BND_M3 23.2% / BND2_H0 22.0%。
- 最差 5：BND_L1 0.0%（金色夕阳远景，与 [outputs/edge_spike/](file:///Users/mingsen/Project/FallLine/outputs/edge_spike) 一致，诚实拒绝）、BND2_L4 1.9% / BND2_L2 2.3% / BND_HI3 2.3% / BND2_H3 4.5%。

**Gate-G1 结论**：**确定性 & 性能达到 Phase 2 主体准入水位；覆盖率不达标属"门控阈值层面的负结论"，不是可靠性问题**。BND2_L1 75% / BND2_LM 57% 证明门控在近景初级/中级雏形上稳定；`--board-edge` 观测器状态机纯函数化 + 只在 Vision 结果后回调、不进入评分链路，确定性 100% 与性能 +5.9% 均达到 Phase 2 主体门槛（§11 Phase 1 "默认关、纯诊断"承诺兑现）；覆盖率主要被 `farShot` + `rejectVertical` 拒，扩集含大量长片 & 远景，正是需要 Phase 2 时序特征补齐的场景。

**产物**：[outputs/board_edge_p2/gate_g1_probe.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe.log)（`.gitignore` 已排除，25 片探针日志 + 3 片 BND_HI 补跑日志）。

**spec 更新**（[2026-09-18-board-edge-trajectory-detection-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md)）：
- §12.4 前置检查表勾选：`[x] Phase 2 起步 2：Gate-G1 探针脚本落地并全量跑 25 片` / `[x] 跨次 bit-identical (25 片 4146/4146 帧)` / `[x] 耗时 ≤+30% (avg +5.9%)`；覆盖率一行标注 FAIL + 下一步建议。
- 新增 §12.5 "Gate-G1 三合一探针实测（2026-09-18，§4.4 全 25 片）"：脚本描述 + 总账 + 单片分布 + 结论 + 下一步（① reason 分布 audit ② 结合 §12.2 优先次序回流 9 片教练判档 → §4.4 扩到 ≥34 ③ 或按"每片可用性 = min(cov%, 60%)"重定义 Gate-G1 门槛，须在 spec §6 决策）。

**验证**：
- `swift build -c release` 通过（15.46s，仅 usesCPUOnly deprecation warning 与 Phase 1 一致）。
- 3 片验证脚本（BND_L1 远景 + BND2_LB 近景 + BND2_H1 专业）：cov=0/103 + 32/181 + 24/166，格式 & 计算逻辑正确，后续全量结果自洽。
- 全量 25 片 + BND_HI1-3 补跑一次，共 28 片；bit-identical 全通过，无脚本自身 flakiness。
- 本轮零 Sources 变更，`swift test` 未跑（Phase 1 274 通过基线不变）。

**下一步（未开始，等确认）**：
1. `--board-edge` 结果 reason 分布 audit：对 4146 帧按 `farShot` / `rejectVertical` / `axisTooShort` / `elongTooLow` / `noMask` / `rejectPosture` / `rejectOwnership` / `ankleLowCnf` 分片做直方图，量化最大拒绝路径（脚本可复用 gate_g1_probe.py 已有的 JSON 解析）。
2. 教练判档 §12.2 优先次序 9 片 → §4.4 扩到 ≥34 → 重跑 §12.5 探针，验证覆盖率 ≥60% 是否**在扩集口径下可达**。
3. 或改按"每片可用性 = min(cov%, 60%)"重定义 Gate-G1 门槛（须在 spec §6 决策并附证据）。
4. 覆盖率闭环后进 Phase 2 主体（时序特征 + Gate-G2）。

---

### 2026-09-18（刃线/轨迹检测 Phase 2 起步 1：19 片候选池接触表已生成）

**本轮性质**：紧接 Phase 2 起步（候选池盘点）向前推一格——把 spec §12.3 里"待落地"的接触表脚本实现并对全部 19 片候选池跑通。**未改任何生产代码**，仅新增脚本 + 更新 spec / WORK_LOG / delta_update。

**新增脚本 [scripts/p2_candidate_contact_sheets.swift](file:///Users/mingsen/Project/FallLine/scripts/p2_candidate_contact_sheets.swift)**（约 260 行）：
- 沿用 [p0_board_axis_dense_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_board_axis_dense_spike.swift) 的检测链——AVAssetImageGenerator 精确抽帧（`frac=0.08~0.92`，10 均匀点）→ Vision `bodyPose` 求踝均值 → `foregroundInstanceMask` 抠人体 → 踝下 ROI（x±0.24 / y[anky-0.16, anky-0.01]）PCA 主轴。门控口径与生产 `BoardEdgeConfig.standard` 对齐（`minCnf=0.30 / minSubj=0.02 / maxAng=45° / minLen=0.07 / maxLen=0.55 / minElong=2.0`）。
- 产物布局：每片一张 5×2 拼图 JPG（1524×1214 左右），每帧 300×533，绘 ROI 黄框 + 板轴（board=绿 / rejected=红）+ 三行状态文本（`#tap t=Xs [verdict] / cnf/subj / ang/e/L`），顶栏一行 `alias hint=… (score=…) board=X/10  farShot=Y  ankleLowCnf=Z`。写入 [outputs/board_edge_p2/contact_sheets/](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/contact_sheets)（`.gitignore` 已排除）。
- 支持 `ONLY=<alias>,<alias>,...` CLI 过滤单片重跑，纯 Swift（`AVFoundation + Vision + AppKit + CoreImage`），无 ffmpeg / Python 依赖。
- 直接以 `/usr/bin/xcrun swift scripts/p2_candidate_contact_sheets.swift` 运行；本项目工作目录无 `swift` 于 PATH 时用该绝对路径。

**运行结果（19 片全跑通，`verdict==board` / 10 抽帧）**：
- good 桶（8 片）：G01=2 / G02=1 / G03=2 / G04=3 / G05=0 / G06=7 / G07=2 / G08=4，**21/80 = 26%**。G06=7 最优；G05=0 需目检是被 farShot 拒还是板身角度过陡。
- middle 桶（10 片）：M01=1 / M02=1 / M03=0 / M04=1 / M05=0 / M06=3 / M07=2 / M08=0 / M09=1 / M10=2，**11/100 = 11%**。中间地带远景 + 站姿飘忽为主，M03/M05/M08=0 需教练确认是否连一帧稳定近景都没有。
- bad 桶（1 片）：B01=5/10 = **50%**（B01 板身相对清晰，教练可确认档位）。
- 整体 **37/190 ≈ 19%**。观测：middle 桶命中率显著低于 Phase 0 主 corpus 的 5-6/10——**符合先验**（中间地带样本本身远景更多、rejectVertical/farShot 更多），也**不能作 Gate-G1 覆盖率证据**（G1 要求生产口径 `--board-edge` 在 5fps 全帧上覆盖率 ≥60%，接触表口径每片仅 10 抽帧、且脚本不含实例归属 / 站姿状态两项 Phase 1 必修门控）。

**目检抽样**：CAND_M06（middle 桶 3/10 命中）——绿轴精确落在 #2/#3/#4 帧的板身上、ROI 黄框位置合理；rejectLength/farShot 状态文字清晰、红轴或不画轴处理正确；顶栏 hint 中级/score=68 与拼图上稳定滑行段吻合，可以直接交给教练判档。

**spec 更新**（[2026-09-18-board-edge-trajectory-detection-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md)）：
- §12.3 从"脚本待落地"改为"2026-09-18 已落地"，补充 19 片命中率明细与"接触表 ≠ Gate-G1 证据"的口径说明。
- §12.4 前置检查表首项打勾：`[x] Phase 2 起步 1：19 片候选池接触表脚本落地并全跑通`。

**验证**：本轮零 Sources 变更，`swift build` / `swift test` 未跑（Phase 1 274 通过基线不变）。脚本运行日志（示例）：`swift scripts/p2_candidate_contact_sheets.swift ONLY=CAND_M01,CAND_M06,CAND_M09` 打印 3 行 `[CAND_… ] board=N/10  → outputs/board_edge_p2/contact_sheets/CAND_…jpg`；全量 19 片同样跑通。

**遗留任务**（未开始，等教练回流）：
1. 教练用接触表判 ≥9 片档位 + 稳定刻滑标注，回填 [calibration_anchors.md §4.4](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md)（新列 `教练档位 / 稳定刻滑? / 弯形备注`）。
2. §4.4 扩集后同步 [bestthird_aggregator_audit.py CLIPS](file:///Users/mingsen/Project/FallLine/scripts/bestthird_aggregator_audit.py#L38-L64) 与 [lowend_separability_audit.py BEGINNER/EMERGING](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py#L41-L42)，重跑聚合器 / 可分性审计。
3. 再启动 Phase 2 主体：CLI `--board-edge` 覆盖率 ≥60% (G1) → 时序特征 → margin≥1.5σ + LOOCV≥90% (G2)。

### 2026-09-18（刃线/轨迹检测 Phase 2 起步：候选池盘点入 spec §12，等待教练判档回流）

**本轮性质**：Phase 1 观测器上线后，落 Phase 2 前置的扩样盘点。**零代码改动**，仅更新 spec / WORK_LOG / .gitignore。

**盘点**（[video/](file:///Users/mingsen/Project/FallLine/video) 库 44 片）：
- 已标注 25 片（BND* + BND2_*，见 [calibration_anchors.md §4.4](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md)），剩余 **19 片候选池**未打教练档位。分布 good 8 / middle 10 / bad 1。
- Phase 2 起步至少需教练判 **9 片**（n=11→≥20）。信息增益优先次序（[spec §12.2](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L369)）：中间地带 60–70 分 4 片、专业候补 2 片（v0200…d7r0017=GOOD_A、96001e…，2026-05 已认专业但未入 §4.4）、中偏上 72–78 3 片。

**spec 更新**（[2026-09-18-board-edge-trajectory-detection-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md)）：
- §5 Phase 2 起步条目细化为「扩样→接触表→回流扩表→G1 覆盖率/性能→时序特征→G2」六步。
- 新增 **§12 Phase 2 起步：扩样候选池**：12.1 19 片候选表（含历史分与弱先验档位）、12.2 教练判档优先次序、12.3 接触表产物路径（脚本 [scripts/p2_candidate_contact_sheets.swift](file:///Users/mingsen/Project/FallLine/scripts/p2_candidate_contact_sheets.swift) 待落地，Swift 版无 ffmpeg 依赖）、12.4 Gate-G1/G2 前置检查表 6 项。

**.gitignore**：新增 `outputs/board_edge_p2/contact_sheets/` 规则，避免下一步生成的接触表 JPG 大文件入库。

**遗留 / 下一步**：
1. 落 [scripts/p2_candidate_contact_sheets.swift](file:///Users/mingsen/Project/FallLine/scripts/p2_candidate_contact_sheets.swift)（AVAssetImageGenerator + Vision + `BoardEdgeDetector` + Core Graphics 拼图），生成 19 片 5×2 接触表 JPG。
2. 教练判档回流后同步扩 §4.4 表 + [bestthird_aggregator_audit.py CLIPS](file:///Users/mingsen/Project/FallLine/scripts/bestthird_aggregator_audit.py#L38-L64) + [lowend_separability_audit.py BEGINNER/EMERGING](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py#L41-L42) 三处。
3. 进 Phase 2 主体（时序特征 + Gate-G1 覆盖率/确定性/性能 + Gate-G2 margin≥1.5σ）。Gate-G2 通过前不联动评分。

### 2026-09-18（刃线/轨迹检测 Phase 1：生产级板身刃线观测器落地，默认关、纯诊断、零评分接触）

**本轮性质**：执行 [立项 spec](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md) Phase 1，把候选 A（前景分割 + 踝下 ROI PCA）从离线原型升级为生产代码并接入分析管线。**全程不改任何评分逻辑、聚合器、报告结构与 iOS UI**；默认关闭，仅显式开启时产出诊断观测。

**A. 新增生产代码**
- [BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift)：`BoardEdgeConfig`（阈值公开常量，默认 `.standard` = Gate-G0 校准值，`minAxisLength=0.07`）+ `AxisGeometry`（纯数值 PCA 结果，Equatable）+ `BoardEdgeDetector.detect(cgImage:pose:config:)`。落实 Phase 0 指定的两条必修：**实例归属校验**（姿态框与各前景实例框算 IoU，取 ≥0.15 中最高者，否则 `rejectOwnership`）、**站姿状态联合门控**（躯干倾角 + 髋高于踝，摔倒/坐姿判 `rejectPosture`）。门控链：ankleLowCnf → noMask → rejectOwnership → farShot(subjFrac<0.02) → rejectPosture → noAxis/rejectVertical(>45°)/rejectLength/rejectBlob(elong<2.0) → board。
- [Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L594-L661)：`BoardEdgeStatus`（11 态，board + disabled + 9 种具体不可用原因）、`BoardEdgeObservation`（归一几何量 + Codable，init 对越界字段做 [0,1] 钳制）；`DetectionResult` 新增可选 `boardEdgeObservation`。
- [VideoAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L343-L354)：init 增 `enableBoardEdge`（默认 false）/`boardEdgeConfig`，`analyzeFrame` 同帧调用检测器。**诊断失败局部隔离**（`try?` → `.noMask` 占位），避免分割抛错拖垮同帧已成功的姿态/评分。
- [PoseSmoother.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift)：三处重建 `DetectionResult` 全部透传 `boardEdgeObservation`，平滑不丢诊断字段。

**B. CLI / overlay**
- [main.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/main.swift)：新增 `--board-edge` flag（用法同步 help），透传 `enableBoardEdge`。
- [DebugOverlayRenderer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/DebugOverlayRenderer.swift#L359-L380)：新增 `drawBoardEdgeObservation`，仅 `status==.board` 时画青色板轴（用图宽 × lengthRatio 定长，与骨架/黄紫板线区分）。

**C. 测试与验证**
- 新增 [BoardEdgeDetectorTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardEdgeDetectorTests.swift)：21 用例覆盖踝点均值/单踝/低置信/缺失、IoU（同框/不交/部分）、实例归属（最高 IoU/低 IoU 拒绝/无姿态框回退最大）、站姿（站立/横倒/坐姿/证据不足）、ROI PCA（水平条角度0+长度/竖直条90°/团块低延伸/像素不足/短条长度越界/ROI 外忽略）、观测字段钳制。
- `swift build` 通过；`swift test` 全量 **274 通过 0 失败**（基线 253 + 21 新用例）。
- 真实冒烟 `testvideo/1.MP4 --board-edge`：117 采样帧状态分布 farShot 92 / rejectLength 10 / **board 8** / ankleLowCnf 6 / rejectVertical 1，与 Phase 0 GT 结论一致；8 个 board 帧 axisAngle 3.4–10.4°、elong 4.6–8.4。叠加 `--debug-overlay` 118 张图正常产出，目检 board 帧青色轴精确落在真实雪板上。

**遗留 / 下一步**：观测仍为诊断字段，Phase 2 须在边界集（当前 n=11，待扩 ≥20）上以 Gate-G2（margin≥1.5σ + LOOCV≥90%）验证后才允许联动评分；远景帧继续诚实输出不可用，不做补偿。

### 2026-09-18（刃线/轨迹检测 Phase 0 离线可行性验证：Gate-G0 PASS，A 路 go / C1 路 no-go）

**本轮性质**：执行 [2026-09-18 立项 spec](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md) 的 Phase 0 闸门，全程离线脚本原型 + 人工逐帧 GT，**生产代码、评分、iOS UI 零改动**。抽帧口径 11 片 × 10 个均匀时间点（0.08–0.92，AVAssetImageGenerator 精确取帧）= 110 帧。

**A. 候选 A（前景分割 + 踝下 ROI PCA 板轴）→ GO**
- 原型：[p0_board_axis_dense_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_board_axis_dense_spike.swift)（加密版；早期 1 帧/片版 [p0_board_axis_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_board_axis_spike.swift)）。同帧 Vision bodyPose 踝点 → `VNGenerateForegroundInstanceMaskRequest` → 踝下 ROI（x±0.24，y −0.16…−0.01）主体像素 PCA → unsigned 主轴角/延伸率/归一长度。
- Gate-G0 三硬指标（先验门控 ankCnf≥0.30/subjFrac≥0.02/angle≤45°/axisLen 0.10–0.55/elong≥2.0）：近景子集 52/110。①**检出率**：0.10 口径 28/52=54% 未达标，但 17 帧 rejectLength 长度连续分布（0.04–0.098）、7 帧在 0.07–0.098 为阈值边界效应；按 GT 把 `G_MIN_LEN` 校准到 **0.07** 后放行 38/52=**73%≥70%**，新增 10 帧逐帧核对全真板。②**角度误差**：28 个 board 目测中位 **≤8°**（绝大多数 ≤5°，全部 ≤10°，阈值 ≤12°）。③**门控精度 100%**（28 board 全在近景子集；非近景 58 帧 0 误放；雪杖/裤腿/竖直他人均被 rejectVertical 拦截）。
- **零硬假阳**；远景（BND_L1 金色夕阳、BND_L2 雪雾）0 board 诚实输出不可用。两处 Phase 1 必修：**实例归属校验**（BND2_L5#7 轴 28° 对准背景中他人的板——物理真板但错对象）、**站姿状态联合门控**（BND2_LB 摔倒/坐姿帧轴不代表刃线质量）。
- GT 工具与产物：[p0_gt_contact_sheets.py](file:///Users/mingsen/Project/FallLine/scripts/p0_gt_contact_sheets.py) → [outputs/edge_spike/gt_sheets/](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/gt_sheets)（11 张逐片接触表）+ [p0_board_axis_dense.tsv](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/p0_board_axis_dense.tsv)。

**B. 候选 C1（VNTranslational 相机补偿 + 踝轨迹弯形）→ NO-GO**
- 原型：全图配准 [p0_camera_registration_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_camera_registration_spike.swift)（成功率 75–100%）、人体框外背景掩膜版 [p0_camera_registration_bg_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_camera_registration_bg_spike.swift)（70–100%），两版位移向量 y 相关≈1.0、x 多 0.65–0.95（"主体锁定"担心不成立）。
- 补偿后分析 [p0_compensated_pathshape_audit.py](file:///Users/mingsen/Project/FallLine/scripts/p0_compensated_pathshape_audit.py)：全图补偿 turnStd within-set margin 0.38→**2.00σ 但方向与假设相反**（雏形踝中点 S 弧多→转角大；初级近景跟拍轨迹反被压平），系机位类型与水平混淆的假阳性。
- LOO 判定 [p0_loo_classify.py](file:///Users/mingsen/Project/FallLine/scripts/p0_loo_classify.py)：标准化 5 维（straight/turnStd/turnPerLen/curvMed/pathLen）单/双特征留一交叉验证，raw/全图/背景三口径最好分别 **6/6/5 错分**（11 中），2.00σ margin 不转化为判别力。**C1/C2/C3 不做 Phase 1 主线**；远景只能诚实输出"板轴不可用"。

**C. 判定与入口**：spec 状态 Proposed → **Gate-G0 PASS**，追加 §10（含 Phase 1 四条入口要求：实例归属门控、站姿状态门控、G_MIN_LEN=0.07、踝下 ROI 全分辨率裁剪缓存）。下一步 Phase 1 生产级板轴观测器（默认关、诊断命名空间 + debug overlay，不接触评分字段；Phase 2 仍须 Gate-G2 margin≥1.5σ + LOOCV≥90% 才联动）。中优先：边界集 n=11→≥20。

**验证**：4 个 swift 原型均编译运行 exit 0；3 个 python 脚本 exit 0；无 Core/CLI 代码变更，未跑 swift test（基线维持 253）。

### 2026-09-18（低端 62 分地板归因闭环：bestThird 修正证伪 + 2D 特征可分性穷尽审计，负结论归档）

**本轮性质**：针对 2026-09-16 两批人眼标注（n=25）定位的"6 份教练判初级 bad 片被 cap 顶在 60-65"问题，先按计划验证 bestThird 选择偏差修正，再穷尽现有 2D 检测信号的可分性。**两个假设均被数据证伪；本轮不改任何评分代码**，只新增两个可复现审计脚本 + 归档产物，结论转入"可靠刃线/轨迹检测"新能力立项。

**A. bestThird 聚合器扫描（[scripts/bestthird_aggregator_audit.py](file:///Users/mingsen/Project/FallLine/scripts/bestthird_aggregator_audit.py)）**
- 方法：离线复刻 [VideoAnalyzer.generateSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift) 完整封顶链路（stable baseline / edge 62 / edgeQuality 72 / board 62 / duration ramp + flow factor + 0.30 门控），**唯一可替换环节是可靠帧聚合函数**。18 种聚合器：top33（baseline）/wmean/median/wmedian/top50/top25/p67/blend25-75/headroom25-60/trim10-25_33。
- 仿真基线校验：25 片 sim 终分 vs JSON averageScore **max Δ=0.00**，封顶链路复刻可信。
- 结果：**baseline top33 本身就是 18 种里最好的**——档位命中 13/25、MAE 12.25、越界样本 MAE **1.08**、全部样本都在 ±1 档内。任何更"全片化"的聚合器（wmean 8 中、越界 MAE 4.72；median 9 中、最差跨 3 档）都会在中高端造成大面积低估（wmean 15 处低估），trim 系列虽能压低端但把 M2/M3 真中级误压到初级（最差跨 3 档）。
- **bestThird 选择偏差不是低端地板的可修复成因**：低端被顶分的真正机制是 `min(top33, edge cap 62)`——top33 虚高（59.9-84.1）只是被 cap 截断前的中间量，换聚合器要么穿不透 cap（低端仍 62），要么误伤中高端。
- 产物：[outputs/bestthird_rerun/aggregator_scores.tsv](file:///Users/mingsen/Project/FallLine/outputs/bestthird_rerun/aggregator_scores.tsv)（25 片 ×18 聚合器终分矩阵）+ [clips.txt](file:///Users/mingsen/Project/FallLine/outputs/bestthird_rerun/clips.txt)（第二批 15 片清单）+ logs/（15 份 release 重跑日志）。

**B. 低端可分性穷尽审计（[scripts/lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py)）**
- 样本：7 片教练判初级（BND2_LB/L6/L5/L4/L3/L2/L1，被 62 地板顶进中级带）vs 4 片真中级雏形（BND_L1/L2/L3、BND2_LM，同分带 60-65）。
- 特征空间（25 维，7 类）：①聚合分布（wmean/bestThird/median/p67/below60frac）②时长/stability/flow（coherence/smoothness）③姿态维度（knee/calf/gravity/sym/edgeQuality/pressure）④跨弯时序结构（leanSwaps 倒伏换弯、latAutoCo 横向位移自相关、kneeAutoCo 膝屈伸节律、turnSegments）⑤几何代理（kneeOverAnkle/ankleOverHip/knockKnee 犁式站姿宽度、travelAngle、edgeSignal）。
- 1D：最强单特征 **sym（初级更高，acc 仅 81.8%，margin −0.73σ）**，误分 BND2_L1 与 BND_L1；与 §4.5 sym 负相关结论一致——楔形站姿对称是初级特征，但不是分档器。
- 2D：枚举全部轴对齐合取规则，仅 8 个能在 n=11 上 11/11 全对，**最强 margin 只有 0.50σ**（初级⊂ 低 smoothness & 低 ankleOverHip），多数 0.0-0.37σ，全部落在测量噪声/采样波动内，属小样本过拟合，不具备任何稳健阈值。
- **结论：当前 2D Vision 信号空间中，推坡初级与平行雏形中级线性（及轴对齐规则）不可分**。物理上可分的信号（弯形 C/S 弧、板身刃线轨迹、搓雪 vs 刻滑的速度-方向耦合）现有检测管线完全没有观测。

**C. 决策（用户拍板）**
1. 本轮不改评分、不动 bestThird、不新增 2D 代理阈值（0.50σ margin 规则若上线必然在新样本翻车，重蹈 knee 动态加权 margin 0.44 的覆辙）。
2. **立项新检测能力：可靠板身刃线 / 轨迹检测**。候选方向（预研，未排期）：板身/雪板实例分割或线段检测提取刃线方向、跨弯轨迹曲率（C 弧 vs 直滑降-急转）、速度方向一致性（搓雪急转 vs 刻滑顺弧）；产出新特征后再回到本审计脚本验证 n=11 边界集能否以 ≥1.5σ margin 分开，届时才谈低端 cap/聚合器联动。
3. calf≈45.5 刻滑软信号（23/25）与本审计不冲突——它分刻滑/搓雪，不分推坡/平行雏形。

**验证**：两个脚本 `python3` 直接运行 exit 0，baseline max Δ=0.00；无 Core 代码变更，未跑 swift test（测试数维持 253，上轮 §4.1/§4.3 后基线）。

**遗留**：
- 15 份第二批样本的 release 重跑报告 md（[video/bad](file:///Users/mingsen/Project/FallLine/video/bad)/[video/good](file:///Users/mingsen/Project/FallLine/video/good) 各 8/7 份）为本轮批跑刷新，与脚本消费的本地 JSON 同批生成；JSON 按 [.gitignore](file:///Users/mingsen/Project/FallLine/.gitignore) `*.json` 约定不入库，脚本只可在已重跑过的本机复现，换机器需先按 clips.txt 重跑 release CLI。

---

### 2026-09-18（续：刃线/轨迹检测新能力立项 spec，仅文档变更）

**本轮性质**：承接上一轮负结论，正式立项"可靠板身刃线/跨弯轨迹检测"。**零评分/生产代码改动**，仅新增 1 份立项 spec + WORK_LOG 同步；先复跑并固化 4 项 spike 证据，再做 Vision 能力调研。

**A. spike 证据复跑固化**（脚本上一轮已建，产物 [outputs/edge_spike/](file:///Users/mingsen/Project/FallLine/outputs/edge_spike)）
- ROI（[edge_spike_roi_audit.py](file:///Users/mingsen/Project/FallLine/scripts/edge_spike_roi_audit.py)）：脚下纵向余量中位 585–1022px（P10 437–939）充足，但双踝站姿宽仅 2–46px（BND2_L1 147 除外），单板多只检出单踝中心，无法靠两脚连线定板轴；有效姿态帧 34–92%。
- 雪面静态脊线（[edge_spike_trajectory_audit.py](file:///Users/mingsen/Project/FallLine/scripts/edge_spike_trajectory_audit.py)）：手工理想 ROI 下初级 entropy 0.638–0.894/peak3 0.099–0.150，雏形 0.588–0.849/0.113–0.158，**区间重叠不可分**（他人轨迹/雪雾/相机俯仰污染），单帧/短窗用法否决。
- 踝 2D 轨迹弯形（[edge_spike_pathshape_audit.py](file:///Users/mingsen/Project/FallLine/scripts/edge_spike_pathshape_audit.py)）：turnStd 33.9–62.3 vs 46.7–55.6、curvMed 116–1114 vs 56–983，**严重重叠不可分**，手持相机运动主导。
- 前景实例分割（[edge_spike_foreground_mask.swift](file:///Users/mingsen/Project/FallLine/scripts/edge_spike_foreground_mask.swift)）：近景侧视（L1）/室内教学（LM）mask **含完整雪板**；户外中景（L3）切板；金色夕阳远景大全景（MIDL1）只剩人体小剪影、板丢失 → 只能做带严格可用性门控的近景信号。

**B. Vision 能力调研**：`VNDetectContoursRequest`（macOS11/iOS14，无门槛）、`VNGenerateForegroundInstanceMaskRequest`（macOS14/iOS17，与现部署目标一致）可用；`VNDetectTrajectoriesRequest` 仅检测**抛物线抛体且需稳定相机**，不适用滑雪弧线，排除。

**C. 立项 spec**：[2026-09-18-board-edge-trajectory-detection-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md)（状态 Proposed）。方向矩阵 A=mask+contours 板轴几何（近景门控）/B=CoreML 板身专项（A 不达标才升级）/C=图像配准补偿相机+滑者尾迹归属+跨弯弯形描述子（远景主线）。分 Phase 0–3，硬闸门 **Gate-G2 要求新信号 margin≥1.5σ + LOOCV≥90% 才允许进入评分联动（Phase 3 另立项）**；本期评分链路、bestThird、iOS UI 全部零改动。Phase 0（扩边界集 ≥20 片 + A/C1 离线原型）**尚未开始，等用户确认**。

**验证**：无代码变更，未跑 swift test（测试数维持 253）；3 个 python spike 复跑 exit 0，数值与上一轮一致。

---

### 2026-09-15（方向 α：edgeQuality 正式取代 sideslip 走刃语义）

**本轮性质**：Foot-Plant 诊断证伪（同日上一轮 [footplant_diagnose.py](file:///Users/mingsen/Project/FallLine/scripts/footplant_diagnose.py)）后落地的替代方向——把走刃结论从"依赖 sideslip 几何量"改为"由姿态派生的 edgeQuality 承担"。改动**只发生在报告展示/语义层**，综合分链路（flow 门控 + 62 分时长 cap 仍独立消费 `boardKinematicConfidence`）零改动。

**A. 报告核心语义（[ReportGenerator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift)）**
- 走刃行命名从"走刃质量 / 走刃倾向"双轨**统一为恒定"走刃质量"**（[L302-L312](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L302-L312)），不再据 `averageSideslipAngle` 是否存在切换命名。
- `edgeConfidence` 直接使用 `ski.edgeQualityConfidence`——不再与 `boardKinematicConfidence` 取 min。旧实现导致 v1/v2/v4/v6（几何置信度 0.16-0.29）的走刃行被错误压成"暂不评分"；现按姿态派生置信度正常展示。反向契约：`edgeQualityConfidence` 不足时仍"暂不评分"，几何高置信度不得补救。
- 板身方向段（[L968-L979](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L968-L979)）：删除 `boardKinematicsLabel`（"沿板身移动/走刃倾向/横滑偏多/以横滑为主"）及 `carvingConfidence` 展示，sideslip 以中性的"**板身-行进夹角（2D 几何）**"保留为原始诊断，行末标注"原始诊断，不代表走刃/搓雪"，段末标注"结论以走刃质量为准，本段不参与评分"。段标题改"🏂 板身方向（几何诊断）"。
- **JSON 字段保留承诺**：`averageSideslipAngle` / `carvingConfidence` 字段仍在 [BoardAnalysisSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L626-L646) 产物中输出（供 debug / 诊断脚本消费），只是报告不再作走刃结论使用。

**B. 契约测试（[ReportGeneratorEdgeQualitySemanticsTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/ReportGeneratorEdgeQualitySemanticsTests.swift)，5 条用例）**
1. `test_edgeRow_isReliable_whenGeometryConfidenceIsLow`——姿态置信度 0.80、几何 0.10 时，走刃行必须正常给分（v1/v4/v6 修复场景）。
2. `test_edgeRow_isNotScored_whenEdgeQualityConfidenceIsLow_evenIfGeometryIsHigh`——反向契约：edgeQualityConfidence=0.20 时几何 0.90 不得补救。
3. `test_edgeName_isAlways走刃质量_whenBoardSummaryAbsent`——无 board summary 时命名仍恒定"走刃质量"（旧"走刃倾向"下线）。
4. `test_boardSection_isRawGeometryDiagnostic_only`——板身段只保留中性几何夹角，不出现"横滑角/走刃置信/沿板身移动/以横滑为主/有走刃倾向"。
5. `test_boardSection_withoutSideslip_saysAngleUnavailable`——sideslip 缺失时展示"暂不估计板身-行进夹角"，不出现"横滑角"。

**C. 主 corpus 6 份 release 端到端回放（综合分不变契约）**

| 视频 | avgScore 基线→新 | edgeScore | edgeConf | boardConf | sideslip° | gated |
|---|---|---|---|---|---|---|
| v1 | 60.67 → 60.67 | 36.60 | 0.75 | 0.24 | 44.2 | False |
| v2 | 86.53 → 86.53 | 72.08 | 0.57 | 0.29 | 50.5 | False |
| v3 | 88.13 → 88.13 | 68.62 | 0.69 | 0.55 | 50.3 | False |
| v4 | 78.80 → 78.80 | 55.02 | 0.58 | 0.16 | 45.3 | True |
| v5 | 73.86 → 73.86 | 52.15 | 0.65 | 0.51 | 39.4 | False |
| v6 | 90.16 → 90.16 | 71.58 | 0.65 | 0.28 | 51.3 | True |

- 全部 JSON 字段（rawPose/bestThird/evidenceCapped/flowFactor/gated/edgeScore/edgeConf/boardConf/sideslip 9 项）逐字段 bit-identical，gated 集合仍为 {v4, v6}。仅 `testvideo/{1..6}.md` 按新语义刷新——v1 走刃行由"暂不评分"恢复为"走刃质量 37/100 · 搓雪为主 · 置信度 75/100"；6 份板身段标题全部改为"🏂 板身方向（几何诊断）"，行文改为"板身-行进夹角（2D 几何）xx° · 几何置信度 xx/100 · 原始诊断，不代表走刃/搓雪"。

**验证**：`swift build` 0 warning；`swift test` **240 tests, 0 failures**（新增 5 条 α 契约用例）；主 corpus 6 份 release 端到端回放综合分字段级 bit-identical。

**遗留**：
- iOS 副本 [SkiAnaylze/SkiAnaylze/Sources](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Sources) 未同步 α 报告文案，随 [REFACTOR_PLAN.md](file:///Users/mingsen/Project/FallLine/REFACTOR_PLAN.md) Phase 2 处理。
- 方向 α 只完成"从走刃语义中拆走 sideslip"，并未修复 sideslip 2D 几何本身的 42-53° 系统偏差；如需修复 sideslip 数值本身，需升级关键点拓扑（3D 骨架 / 板身分割），不在本轮范围。

---

### 2026-09-15（评分确定性 repeatability 探针 + 30fps 实验结论）

**本轮性质**：先给出 30fps 采样实验结论（用户实测：**效果不好，暂缓**，未产生代码变更），随后落地对标 SportsReflector 方法的评分确定性探针。仅新增脚本 + 文档，无 FallLineCore 代码变更。

**A. 30fps 原生采样实验：不采纳（暂缓）**
- 此前 [Hard Constraint](file:///Users/mingsen/Project/FallLine/AGENTS.md) 登记"5fps → 30fps"，用户完成对照实验后反馈**效果不好**，本轮决定暂不切换默认采样率、代码维持 5fps。
- 具体失败形态（抖动/耗时/分数漂移）及对照数据未留档；后续若重启该方向，需先补对照实验数据。

**B. repeatability 探针（新增脚本，确定性基线 SD=0.000）**
- 新增 [scripts/repeatability_probe.py](file:///Users/mingsen/Project/FallLine/scripts/repeatability_probe.py)：同一视频 N 次全新 release CLI 进程（独立临时目录 + symlink，不污染 testvideo/），抽取 averageScore/raw/bestThird/capped/flowMod/scoreStdDev/boardConfidence 等 9 字段统计 mean·sample-SD·range·uniq；对剔除 `videoPath` 的 JSON 算 SHA256 判 bit-level 确定性；`--deep` 逐帧对比 `frames[].poseScore.totalScore` 报首个分歧帧。对标 SportsReflector 公开基线 ±3.0 pts（10 次重复）。
- 全量结果（主 corpus v1-v6 × 10 = 60 次 release 运行，单进程 17s/视频）：

  | 视频 | mean | SD | range | 确定性 |
  |---|---|---|---|---|
  | v1 | 60.67 | 0.000 | 0.000 | bit-identical ✅ |
  | v2 | 86.53 | 0.000 | 0.000 | bit-identical ✅ |
  | v3 | 88.13 | 0.000 | 0.000 | bit-identical ✅ |
  | v4 | 78.80 | 0.000 | 0.000 | bit-identical ✅ |
  | v5 | 73.86 | 0.000 | 0.000 | bit-identical ✅ |
  | v6 | 90.16 | 0.000 | 0.000 | bit-identical ✅ |

- **最大跨次 SD = 0.000 pts（PASS，基线 ±3.0）**；6 份视频 10 次运行的完整 JSON（除 videoPath）SHA256 均只有 1 个唯一值；`--deep` 帧级 totalScore 全部一致。
- 解释：[VideoAnalyzer](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L202) 的 task group 虽然并发分析帧批次，但结果按索引顺序回收、下游全部为顺序浮点归约；Vision 请求在固定输入上输出确定，熔断（3 连败）在相同输入序列下也确定。因此并发架构没有引入跨次非确定性。
- 用法：`python3 scripts/repeatability_probe.py`（默认 6×10）、`-n 3 testvideo/1.MP4`（冒烟）、`--build`（先 release 构建）、`--deep --keep-workdir`（排查分歧帧）。完整日志：`/tmp/fallline_repeatability_20260915.log`（临时目录，不入库）。

**验证**：探针脚本冒烟（v1 ×3 --deep）+ 全量 60 次运行 exit 0；无 Core 代码变更，未跑 swift test（测试数维持 235）。

**遗留**：
- SD=0 是"固定输入 + 同一二进制"的进程间确定性；尚未覆盖跨设备、跨 macOS 版本、跨 Xcode/Swift 工具链的维度。
- 探针只验证了主 corpus 6 份；后续若引入自适应抽帧/多线程归约顺序变化，需重跑本探针守门。

---

### 2026-09-15（PoseScorer edge-first 重构收尾 + flow 走刃置信度门控）

**本轮性质**：两条关联的评分线在同一天闭环并推送 origin/main。前半段是更早开始、此前未写 delta 的 **PoseScorer edge-first 重构**（Tick 1-4 + 一次 sigmoid 中点微调 + spec 归档）；后半段是 edge-first 完成后补上的**下游护栏**——flow modulation 走刃置信度门控。两份 spec 均转 Landed。

**A. PoseScorer edge-first 重构（把 calfLean 从"外部 cap"升级为评分主导维度）**
- Tick 1-4 commit：`ce751a4`（[PoseScorer.Weights](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift) struct 前置重构）→ `06f5ed7`（权重重分配 lean/knee/calf/gravity/symmetry = 0.15/0.25/0.35/0.15/0.10）→ `48ea262`（calfLean 改 sigmoid，初版 k=0.10 c=35）→ `b584b12`（edge cap 放宽为 fallback-only ramp）。
- **c=40 微调 `fbeb1da`（本轮重点）**：[calfSigmoidMidpoint](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift#L170) 35→40（k 不变）。动机：c=35 让 30° 就跨过中点得 37.8 分，导致专业档普涨 4-5 分、video 5 中级→高级、video 4 中级→专业，与教练分档不符。中点右移到"入门—中级刻滑分界（40°=50 分及格）"后，30-50° 段陡度保留（~2.31 分/°）。
- edge cap 现状（[edgeEvidenceCapValue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L509-L513)）：`edge<30 → 62` 兜底，`30–42` 分段线性放行，`≥42 → 100`；纯扫雪防误抬，不再是分档悬崖。
- 测试：[PoseScorerCalfSigmoidTests](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/PoseScorerCalfSigmoidTests.swift) 8 采样锚点 + 中点 + 参数契约按 c=40 更新；另有 weights-sum 与 edge-cap-ramp 契约。
- Corpus 对照（无 gating，md 归档 [_review_tick4](file:///Users/mingsen/Project/FallLine/testvideo/_review_tick4) = c=35、[_edgefirst_c40](file:///Users/mingsen/Project/FallLine/testvideo/_edgefirst_c40) = c=40）：v1 63→61、v2 88→87、v3 89→88、v4 86→83、v5 78→74（高级退回中级）、v6 96→95。12 份 md 与 spec 表逐值一致；JSON 按 `*.json` ignore 约定仅本地。
- Spec：[2026-09-15-posescorer-edge-first-refactor-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md) 转 Landed（`21a24f8`）。

**B. Flow modulation 走刃置信度门控（edge-first 的下游护栏，Tick 1-4）**
- 动机：edge-first 后 flow ×1.05 coherence 加成成为高分样本关键抬升器，但走刃证据不足时该高分主要来自相机/全画面平移，会放大噪声。
- 实现 `ab16817`：
  - [FlowMetricsCalculator.computeModulation](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift) 扩展 6-param：新增 `boardKinematicConfidence` 与 `evidenceCappedScore`；门控 `boardC < 0.30 → min(modulation,1.0)`（**只禁上行、不扣分**）；方案 (c) 低分保护 `evidenceCappedScore < 60` 时关闭门控（避免 video 1 跨"中级/初级"档）。常量 `boardKinematicConfidenceGateThreshold=0.30`、`flowGateLowScoreProtectionThreshold=60`。
  - [VideoAnalyzer](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift) 新增私有 `computeBoardKinematicConfidence`（下沉 BoardDirectionAnalyzer 取 `summary.confidence`），`framePairsUsed<2` 时回退 boardC=1.0 不门控。
  - [VideoSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift) 新增 `flowModulationGated: Bool?`（init 默认 nil，向后兼容历史 JSON）；[ReportGenerator.formatFlowFactorText](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 在门控实际 kill 上行加成时追加"（走刃证据不足，未加成）"。
- 测试：19 条门控契约（[FlowMetricsCalculatorTests](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift)）+ 7 条透明度契约（[ReportGeneratorFlowGatingTests](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/ReportGeneratorFlowGatingTests.swift)）。
- Tick 4 端到端复核（release CLI 全量重跑，md 归档 [_tick4_gated](file:///Users/mingsen/Project/FallLine/testvideo/_tick4_gated)，spec 见 §5.4）：`gated=true` 集合精确 = **{v4, v6}**；v1 走方案 (c) 保护保持 60.67 不掉档、`gated=false`；阈值 [0.30,0.50] 为同一门控组，0.30 是覆盖 v6（boardC=0.280）的最小有效阈值，无需微调。
- 静态证据链脚本 [scripts/flow_gating_replay.py](file:///Users/mingsen/Project/FallLine/scripts/flow_gating_replay.py)（注：其 baseline 扫描建模的是**无方案 c 保护**的纯门控，故不把 landed 的 `_tick4_gated` 加入默认 baseline，以免 v1 行误报 kill）。
- Spec：[2026-09-15-flow-modulation-edge-gating-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-flow-modulation-edge-gating-design.md) 转 Landed（`31950a5`）。

**当前 corpus 顶层分数**（c=40 叠加 gating，[testvideo/1-6.md](file:///Users/mingsen/Project/FallLine/testvideo) 刷新于 `a60d93e`）：v1 61 · v2 87 · v3 88 · v4 79 · v5 74 · v6 90。基线（edge-first 前）61/83/85/74/70/92。

**验证**：`swift build` 0 warning；`swift test` **235 tests, 0 failures**；两组对照归档与 spec 表逐值核对一致。

**遗留**：
- iOS 副本 [SkiAnaylze/Sources](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Sources) 未同步 sigmoid/权重重构（该副本本就不含 sigmoid，Tick 3 起未同步），属 [AGENTS.md](file:///Users/mingsen/Project/FallLine/AGENTS.md) 已知 duplication debt，等 REFACTOR_PLAN Phase 2 SPM 迁移统一处理。
- 主 corpus 仅 6 份；等级分布向"专业"迁移后建议对 [calibration_anchors.md](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md) 做一次教练标注校准复核。
- 已推送 origin/main（`37932b5..21a24f8`）。

---

### 2026-09-10（P9-B：修 CenterOfMass 主问题 tie-break 抖动）

**本轮性质**：紧接 P9-A 的字典排序问题审计发现的第二处同型 bug，**不影响任何评分维度**，只影响 `CenterOfMassAnalysis.mainIssue` 这一顶层文案（进入报告与 JSON）。**抖动面比 P9-A 更大**：P9-A 只作用在 TurnSegment 段内标签，本处作用在整个视频的顶层重心结论。

**审计来源**：本轮先对 [Sources/](file:///Users/mingsen/Project/FallLine/Sources) 做了一次 dict/set 无序迭代影响输出的全量审计，命中 12+ 处，其中 11 处属 Array-based（Swift 语义保证顺序确定，无需处理）；唯一必修高风险点是 [CenterOfMassFitCalculator.dominantIssue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/CenterOfMassFitCalculator.swift) 的 `counts.max { $0.value < $1.value }`。

**根因**：`CenterOfMassFrameAnalysis.issue` 只可能取三个字面量：`当前阶段重心过低` / `当前阶段重心偏高` / `当前阶段重心适配`；`dominantIssue` 会过滤掉最后一个，剩下 `counts: [String: Int]` 上做 `max`。当"过低"与"偏高"各占 50% 时，`Dictionary.max` 返回哪个键完全依赖 Swift Dictionary 每进程 hash-seed，产生跨轮抖动。

**改动**：
- [CenterOfMassFitCalculator.swift#L167-L207](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/CenterOfMassFitCalculator.swift#L167-L207)：把 `dominantIssue(from:)` 从 `private extension` 挪到独立的 `extension CenterOfMassFitCalculator`（默认 internal），实现由 `counts.max { ... }` 改为 `counts.sorted { lhs, rhs in ... }.first?.key`；新增 fileprivate `issueSortRank(_:)` 定义语义优先级 **偏高 > 过低**。
- 优先级选择理据（写在 doc-comment 里）：
  - [score(hipRatio:targetRange:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/CenterOfMassFitCalculator.swift#L108-L120) 里"偏高"每 0.24 单位掉 100 分（约 416 分/单位），"过低"每 0.18 单位仅掉 55 分（约 305 分/单位）——偏高对总分的惩罚显著更重。
  - 教练视角：重心跟不上刃角是刻滑典型缺陷；重心过低多为防御性深蹲，相对次要。
- 未知 issue rank 归 `Int.max`，保证有效 issue 永远排在未知之前。

**测试**：新增 [CenterOfMassFitCalculatorTieBreakTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/CenterOfMassFitCalculatorTieBreakTests.swift)，9 条用例：
- 单赢家（高频过低 / 高频偏高）2 条：验证纯频率场景不受二级排序影响
- 同频 tie（多帧对多帧 / 单帧对单帧）2 条：定钉 **偏高 > 过低** 语义优先级
- 边界（empty / 全部适配 / 适配帧不参与计数 / 未知字面量 tie 时输给已知）4 条
- **稳定性 fuzz 1 条**：2000 次不同顺序构造 frames 反复调用 → 应始终返回同一 rawValue。

**验证**：
- `swift test` → **173 tests, 0 failures**（164 → 173，+9 P9-B 用例）
- 未跑 corpus 对比：本次改动只在同频 tie 时改变字面量选择，非 tie 场景（大多数视频）行为完全一致；tie 场景在原实现是"抽奖"，无法建立对照 baseline。
- `GetDiagnostics` 无 lint/type 问题。

**核心洞察**：P9-A 时留下的规约"任何依赖 Dictionary/Set 归约影响用户可见输出的地方必须显式声明 tie-break 顺序"在本处直接兑现。审计报告里剩余的 11 处 Array-based 命中经 Swift 语义分析确认确定性（`Array.max/min/sorted(by:)` 保证 stable 或返回首个最大值），无需处理。

**遗留**：无。评分与产物 JSON 结构完全兼容；`mainIssue` 字段类型 (`String?`) 不变。

---

### 2026-09-10（P9-A：修 TurnPhase 报告文案 tie-break 抖动）

**本轮性质**：报告可读性稳定性修复。**不影响任何评分维度**，只影响 `main.swift` 报告"转弯阶段分析"段落里"主要阶段"这个文案标签。

**问题**：P6-B 落地时观察到视频 1 / 2 里若干极短 phase 片段（≤3 秒）出现 `主要阶段：出弯释放` ↔ `弯中承压` 的无规律抖动，Round-1 与 Round-2 之间标签会切换。当时列为独立议题。

**根因**：[ReportGenerator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 原代码用 `phaseDistribution.max { $0.value < $1.value }` 挑主阶段。`phaseDistribution` 是 `[String: Double]`，Swift Dictionary 迭代顺序依赖每进程 hash seed，**同频 tie 时 `max` 返回哪个键完全是随机的**。短片段（只有 3~5 个 phase 样本）经常出现 40% / 40% 的双峰分布，就成了报告文案抽奖。

**改动**：
- [ReportGenerator.swift#L901-L933](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L901-L933)：新增 `static internal dominantPhaseRawValue(from:)` + `private static phaseSortRank(_:)`。稳定排序策略：**频率降序为主键，同频时按语义优先级 shaping (弯中承压) > initiation (入弯) > release (出弯释放) > transition (换刃/过渡) 二次排序**。`phaseSortRank` 未知 rawValue 归 `Int.max`，让有效 phase 永远排在前面。语义优先级选择遵循"技术含量最高的阶段优先展示"——报告核心是刻滑质量诊断，shaping 阶段承载了压刃能力这个最核心的信息量。
- 调用点从 `segment.phaseDistribution.max { ... }.map { phaseLabel($0.key) }` 简化为 `dominantPhaseRawValue(from:).map(phaseLabel)`。

**测试**：新增 [ReportGeneratorPhaseTieBreakTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/ReportGeneratorPhaseTieBreakTests.swift)，9 条用例：
- 单赢家（shaping / release）2 条：验证纯频率场景不受二级排序影响
- 同频 tie（shaping vs release / initiation vs release / shaping vs initiation / 四相全平）4 条：定钉语义优先级
- 边界（空 dict / 未知 rawValue vs 已知）2 条
- **稳定性 fuzz 1 条**：同一 dict 重构 2000 次调用 → 应始终返回同一 rawValue。这条如果 hash-order 抽奖复现，会显著失败。

**验证**：
- `swift test` → **164 tests, 0 failures**（155 → 164，+9 新用例）
- CLI 两轮独立跑 5 份 corpus，`diff` 全部 `identical`：**确定性行为已锁定**（before-fix 时观察到跨轮报告文案漂移，after-fix 消除）
- Before/After 对照：视频 1 有 2 个短片段（00:01-00:01、00:10-00:11）的"主要阶段"从"入弯"→"弯中承压"，这些片段的 `mainIssue` 已是"弯中刃角保持不足"，主阶段标签现在跟 issue 互相支持而不是打架
- 视频 2 / 3 / 4 / 6 报告文案 100% 不变（这些视频原本就没触及同频 tie）
- 全部 5 份 corpus final score 完全不变（0 评分回归）

**核心洞察**：Swift `Dictionary` 无序迭代 + 打平 tie 的 `max` 是一个隐蔽的非确定性源；一旦文案基于 dict 挑首元素，就应显式声明 tie-break 顺序。P6-B 里"次生现象"的成因至此闭环，独立于光流管线。

**遗留**：无。评分与产物 JSON 结构完全兼容。

---

### 2026-09-10（P6-B-r3 微调：窗采样半径 2 → 3）

**本轮性质**：P6-B 参数抬升。radius 2（5×5=25 采样点）→ radius 3（7×7=49 采样点），继续放大空间去噪覆盖。

**动机**：P6-B(r=2) 落地后主 corpus 5 份仍有部分弱一致 / 中等 smoothness 样本（视频 2、3）对空间噪声敏感；风险面主要是"7×7 窗溢出到相邻部位或背景"，用主 corpus 5 份重跑 A/B 对照直接验证。

**改动**：
- [FlowMetricsCalculator.swift#L92-L107](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift#L92-L107)：`init(flowSampleRadius:)` 默认值 2 → 3，注释追加"P6-B-r3"依据与已知边缘遮挡回退指引。
- [FlowMetricsCalculatorTests.swift#L319-L328](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift#L319-L328)：`testInit_flowSampleRadius_persistsAndClipsNegative` 期望默认值同步为 3；其余 5 条窗数学单测（均匀场恒等 / outlier 拑制 / 边界 clip / radius=0 回退 / 越界 nil）保持原状——纯 `averageFlowWindow` 函数不吃默认值，天然守护。

**A/B 对照（主 corpus 5 份，r=2 baseline 保存在 `/tmp/fl_p6b_r2/*.md.r2`）**：

| video | coherence | velocitySmoothness | final score |
|:-----:|:---------:|:------------------:|:-----------:|
| 1 | 87 → 87 | 79 → 79 | 61 → 61 |
| 2 | 53 → 53 | 81 → **84 (+3)** | 85 → 85 |
| 3 | 42 → 42 | 43 → **47 (+4)** | 86 → 86 |
| 4 | 99 → 99 | 58 → 58 | 87 → 87 |
| 6 | 70 → **71 (+1)** | 64 → 63 (-1) | 93 → 93 |

**验证**：
- `swift test`：**155 tests, 0 failures**（只有 `testInit_flowSampleRadius_persistsAndClipsNegative` 的期望值需要更新，其余不动）
- 主 corpus 5 份 CLI 重跑：velocitySmoothness 2 份显著改善 +3~+4，coherence 4/5 稳定 / 1 份微增 +1；**final score 5/5 完全不变**——evidence cap 和 flow modulation 完全稳态，无评分回归
- **越界风险实测检验**：如果 7×7 窗真溢出到相邻身体部位 / 背景，某维度应大幅反向跳变；实际数据没有观察到这种异常

**核心洞察**：radius 从 2 抬到 3 属于"参数微调"而非"结构变更"，收益集中在弱一致 / 中等 smoothness 样本上（这些样本恰好最需要空间去噪）；强一致样本已经在信号地板上，扩大窗不再帮助。

**遗留 / 后续**：
- radius=3 只在主 5 份 corpus 验证过，若发现极端遮挡或近骨盆构图样本出现异常，可通过 `FlowMetricsCalculator(flowSampleRadius: 2)` 或 `flowSampleRadius: 0` 逐级回退。
- 视频 6 smoothness -1 属噪声波动（P6-A median 已经在时序维度兜底），不视为回归。

---

### 2026-09-10（P6-B 落地：hip 光流窗采样）

**本轮性质**：稳定性系列延伸。P6-B 把光流关键点采样从单点 → 5×5 窗均值，在**输入层**给运动一致性 / 速度平滑度做去噪，与 P6-A（时序层 median）形成"空间+时序"双层抗噪。

**问题定位**：
- 单点采样对光流噪声（局部纹理、遮挡、亚像素抖动）无免疫力
- hipFlowDirections 的 circular variance 被随机方向污染（虽然 P7-A 已退役其评分调制，但报告展示的 `方向稳定性: 0*` 仍来自这条路径）
- coherence 的 hip vs ankle 方向差异被单像素噪声随机抬高，压低 coherence boost 触发概率
- velocity 的 changeRate 单帧跳变已由 P6-A median 兜底，本轮补齐空间维度

**改动**（[FlowMetricsCalculator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift)）：
- 新增 `flowSampleRadius: Int` 实例属性，默认 2（→ 5×5 = 25 采样点），负值 clip 到 0
- `init(sampleInterval:flowSampleRadius:)` 新增第二参数（默认参数保持向后兼容）
- [sampleFlowVectors](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift#L305-L398) 里内嵌的 `sample(atX:y:)` 从单点像素读取改为 `(2r+1)×(2r+1)` 邻域均值 + 边界 clip；radius=0 保留为紧急回退（一行分支）
- 新增 internal 纯函数 [averageFlowWindow](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift#L435-L466)，与生产采样路径共享窗遍历/边界 clip/均值语义，剥离 CVPixelBuffer 依赖供单测直接验证

**测试**（+6 用例，[FlowMetricsCalculatorTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift)）：
- 均匀场恒等（radius 变化不影响结果）
- 25 像素中 1 个 (100, 100) 噪声被稀释到 1/25 权重（`(24 + 100) / 25 = 4.96`，方向被拉回）
- 边界 clip（中心在 (0,0) radius=2 但 image 3×3 → 落点为整张 9 格）
- radius=0 回退为单点采样
- 越界坐标返回 nil
- init 默认 radius=2 + 负值 clip 到 0

**Corpus 重跑对照**（主 5 份，radius=2 vs 单点 baseline）：

| video | coherence | stability | smoothness | evidenceCapped | flowMod |
|---|---|---|---|---|---|
| 1 | 87 → 87 | 0* → 0* | 78 → **79** | 58.0 | 1.05 |
| 2 | 53 → 53 | 0* → 0* | 79 → **81** | 84.5 | 1.00 |
| 3 | 42 → 42 | 0* → 0* | 41 → **43** | 85.9 | 1.00 |
| 4 | 99 → 99 | 0* → 0* | 58 → 58 | 82.4 | 1.05 |
| 6 | 69 → **70** | 0* → 0* | 63 → **64** | 88.9 | 1.05 |

**核心洞察**：
- **velocitySmoothness 4/5 微增 +1~+2**：空间去噪压低了单点噪声对 median 的污染，与 P6-A 时序 median 叠加去噪
- **coherence 稳定（4/5 一致，视频 6 +1）**：符合"输入层去噪不改变主体趋势，只压噪声"的预期
- **evidence-capped 分与 flowMod 100% 稳定**：无回归，`applyModulation` 的双 0 熔断仍正常工作
- **directionalStability 仍全 0\***：P7-A 结论未变——2D 光流方向被相机运动主导 + 换刃天然 ~180° 摆动，窗采样只能消 pixel-level 噪声，不能改变信号性质（stability 已在 P7-A 退役评分调制，本轮为报告展示的知情预期）

**验证**：
- `swift test`：**155 tests, 0 failures**（149 → 155，+6 P6-B 用例）
- `swift build -c release`：PASS（9.95s）
- CLI 重跑 5 份 corpus：全部成功产出 md，无 crash

**未做/后续**：
- 未跑 49 视频大批量回归（主 5 份已充分覆盖 low/mid/high coherence + 各类置信度）
- radius=2 是保守选择；若 720p/1080p 上落点密度不够，可上调到 3（7×7=49），但需评估 hipCenter 采样偏移到骨盆边缘的风险
- 若未来要重新引入 stability 评分调制，光信号源换掉才有意义（IMU 或板身视觉线），本轮不涉及

### 2026-09-08（P6-A + P7-A 落地）


**本轮性质**：稳定性系列继续。P6-A（velocitySmoothness avg→median）验证、补测试、提交；directionalStability 只读诊断后用户拍板方案 A，P7-A（退役 stability 评分调制）落地。

**背景补记**：2026-09-01 至 2026-09-07 间有多个稳定性提交未逐轮记录（P2 flow 熔断、P3 sideslip 5 帧中值、P4-A 短缺口中值插补、P5-A/B 膝盖评分、P0-A/P0b/P0-D/P0-E despike 系列），详见 `git log`。本轮起恢复逐轮记录。

**P6-A 落地**（commit `be59c7c`）：
- 问题：velocitySmoothness 在 6 份主 corpus **100% 塌陷为 0** —— avg(changeRate) 被单帧极端跳变（max 75.2 vs median 0.62）主导，全部超过旧阈值上限 0.50
- 改动：[FlowMetricsCalculator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift) avg→median，阈值 [0.15, 0.50]→[0.30, 1.20]（0.30=corpus median 最小值，1.20=观测最大+45% buffer）；抽取 `computeVelocitySmoothness(fromChangeRates:)` 为 internal 供单测
- 测试：+4 用例（空序列回落 50、单帧 75.2 跳变不塌陷、阈值锚点、持续抖动仍扣 0）
- corpus 重跑：velocitySmoothness 0 → 40.8~78.7；**flowMod/averageScore 全部不变**（恢复值均高于 penalty 阈值 40，3.json 40.8 最接近）；testvideo/*.md 已刷新

**P7-A 落地**（commit `256d3f2`）：
- 诊断（只读）：directionalStability 24/24 样本塌陷为 0。用 JSON 逐帧数据测 6 种统计口径（全段/0.5s/1s 窗 × travelAngle/boardAngle × variance/median delta），**全部无法区分 corpus 质量排序**；medDelta 与质量**反相关**（最差样本 1.json=60.9 分 medΔ 最小 15.9°，刻滑样本 5.json medΔ 41.8°）
- 根因：滑雪换刃天然 ~180° 方向摆动 + 2D 光流方向被相机运动主导，信号源不携带质量信息。阈值重标/窗口化无法挽救
- 决策：用户拍板方案 A（退役评分调制）
- 改动：`computeModulation(4-param)` 移除 stability boost/penalty 两分支（与 3-param 行为一致）；stability 常量保留仅为 API 兼容；报告"方向稳定性"标注 `*不参与评分`
- 测试：更新 7 个受影响用例 + 新增 `testModulation_full_stabilityValueIsIgnoredAfterP7A` 退役守护（stability 取 0~100 结果必须一致）
- corpus 重跑：averageScore/flowMod 全部 Δ=0.00（stability 恒为 0 时分支本不触发，退役为零行为变化正式化）

**验证**：
- `swift test`：149 tests, 0 failures（两轮均绿）
- `swift build -c release`：PASS
- 诊断脚本为一次性 python heredoc，未落盘、无副作用

**未做/后续**：
- 光流调制有效范围现为 ±5%（coherence +0.05 / smoothness -0.05）；`applyModulation` 的双 0 熔断保留（仍防 smoothness 塌陷误调制）
- P6-A/P7-A 未跑 49 视频大批量回归（主 corpus 6 份已覆盖）
- 调制层只剩 coherence/smoothness 两项，若后续要恢复方向类指标需换信号源（IMU 或板身视觉线），不在当前范围

### 2026-09-01（CLI 复核方案 A）：主 corpus 重跑 + 实际分数对照

**本轮性质**：方案 A 落地后的**生产数据复核**。用 [FallLineCLI](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI) 重跑 6 份主 corpus 视频（[testvideo/1.MP4 - 6.MP4](file:///Users/mingsen/Project/FallLine/testvideo)），把方案 A 前后的 `summary.averageScore` 做逐份对照，坐实 audit 脚本预测。

**做了什么**：
- 备份 6 份主目录 JSON+MD 到临时 `_pre_planA/`（对照 baseline）
- 逐份跑 `swift run -c release FallLineCLI testvideo/N.MP4` 生成新产物
- Python 脚本对照 pre/post 的 `averageScore` / `evidenceCappedScore` / `boardKinematicHighScoreCap` / `flowModulationFactor`
- 删除 `_pre_planA/` 备份（历史 baseline 已有 [_p1_baseline/](file:///Users/mingsen/Project/FallLine/testvideo/_p1_baseline) / [_b_3d_baseline/](file:///Users/mingsen/Project/FallLine/testvideo/_b_3d_baseline) / [_c_2d/](file:///Users/mingsen/Project/FallLine/testvideo/_c_2d)，git 历史也可回溯）

**逐份对照结果**：

| 样本 | obsCnf | pre avg | post avg | Δ | 解释 |
|---|---|---|---|---|---|
| 1.json | 0.30 | 58.00 | 58.00 | 0 | obsCnf<0.55，pre 就不触发 cap |
| 2.json | 0.34 | 72.43 | 72.43 | 0 | 同上 |
| **3.json** | **0.59** | **55.10** | **73.91** | **+18.81** | **pre 触发 cap→58，post 阈值 0.7 拒绝→cap=nil，evidence 直通 84.95** |
| 4.json | 0.18 | 70.00 | 70.00 | 0 | obsCnf<0.55，pre 就不触发 cap |
| 5.json | 0.58 | 66.50 | 66.50 | 0 | pre 触发但 boardCap 值 70 与 evidence-cap 巧合等价，视觉无差 |
| 6.json | 0.33 | 75.99 | 75.99 | 0 | obsCnf<0.55，pre 就不触发 cap |
| **均值** | — | 66.34 | 69.47 | **+3.13** | — |

**核心洞察**：
- **audit 脚本预测 8 次 cap 触发** vs **CLI 实际只有 3.json + 5.json 属于 0.55-0.7 阈值区间**——脚本预测偏乐观，是因为它只判定"cap 输入条件"，未过滤"cap 值 > raw 时 [min](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L470-L477) 不生效"和"cap 值与 evidence-cap 巧合等价"这两种情况
- **实际生效的样本**：**3.json 一份**，改善 +18.81 分（与 audit 预测 Δ=18.4 高度吻合，微差来自 flowMod 抖动）
- **未受影响的样本（4 份）**：obsCnf < 0.55，pre 已经不 cap，方案 A 天然不生效
- **潜在受影响但视觉无差（1 份）**：5.json 的 evidence 与 cap 值巧合等价 70
- **上一轮"方案 A 预期修 3.json 类样本"完全兑现**：主线目标达成

**用户可见变化**（3.md）：
- 综合评分：55/100 → **74/100**
- 阶段判断：基础控速阶段 → **刻滑雏形阶段**
- ⚠️ "板身/滑行方向夹角偏大"警告：**消失**
- ✨ 高光时刻：无 → 2 段（74/100 越过高光阈值）
- 教练观察：从否定式改口为"部分弯已经有走刃倾向"

**改动文件**：
- [testvideo/1.md](file:///Users/mingsen/Project/FallLine/testvideo/1.md) / [3.md](file:///Users/mingsen/Project/FallLine/testvideo/3.md) / [4.md](file:///Users/mingsen/Project/FallLine/testvideo/4.md) / [5.md](file:///Users/mingsen/Project/FallLine/testvideo/5.md)：报告文本随 CLI 重跑更新（21 行 diff，3.md 是主变化）
- 2.md / 6.md 完全未变（Vision 本次输出稳定，与上一次跑完全一致）
- 6 份 JSON 是 [.gitignore](file:///Users/mingsen/Project/FallLine/.gitignore) 排除的（`*.json` 全局排除），只在本地存在，不进本次 commit

**验证**：
- 用户本地已确认方案 A 效果
- Δ_3.json = +18.81 与 audit 预测 Δ=18.4 匹配（差异来自 flowMod 从 0.95→0.87 自然抖动）
- 未跑 `swift test`（本轮无代码改动，只是重跑 CLI）

### 2026-09-01（补边界用例）：TrendAnalytics weekly.count == 1 真空区

**本轮性质**：hotfix 后续 nice-to-have，补齐"仅 1 周 sessions"边界回归。仅测试文件改动，无生产代码变化。

**做了什么**：
- [TrendAnalyticsTests.swift#L180-L219](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift#L180-L219) 新增 [test_detectMilestones_singleWeek_noWeeklyImprovementNoStreakNoCrash](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift#L180-L219)
- 构造 3 次 offset 0/1/2 天的 session（同周内），断言：
    - `weeklyImprovement` 不触发（本次守护上一轮 hotfix 的 `if weekly.count >= 2` guard，防阈值漂移退回崩溃）
    - `streak` 不触发（1 周 < 阈值 3）
    - `firstReached` 仍能上报"中级""高级"（独立于 weekly 判定）
    - `newPersonalBest` 仍能上报 68 和 82（同周内连续刷新最高分）

**覆盖真空区**：
- 之前 [test_analyze_emptySessions_returnsAllEmptyOrNil](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift#L45-L54) 覆盖 `weekly.count == 0`
- 之前 [test_detectMilestones_weeklyImprovement_triggersOnDeltaThreshold](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift#L135-L149) 等覆盖 `weekly.count >= 2`
- **本次**覆盖 `weekly.count == 1`（缺失区间）

**验证**：
- `swift test 2>&1`：**Executed 106 tests, with 0 failures in 0.107s**（TrendAnalytics suite 从 15 → 16）
- `GetDiagnostics` TrendAnalyticsTests.swift：空

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

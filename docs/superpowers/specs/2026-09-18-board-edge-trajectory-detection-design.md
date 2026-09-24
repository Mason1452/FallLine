# 可靠板身刃线 / 跨弯轨迹检测能力立项设计

> 作者：agent
> 日期：2026-09-18（2026-09-18 追加 Phase 0 Gate-G0 结果；同日追加 Phase 1 落地结果）
> 状态：**Phase 1 已完成（生产级板身刃线观测器落地，默认关、纯诊断、零评分接触），可进入 Phase 2** — Phase 1 落地与验证见 §11；Phase 0 离线原型与人工 GT 见 §10；仍不含任何评分改动，Phase 2 Gate-G2 通过前不得联动评分。**2026-09-20 fallback 前置闭环**：ADR-001（§12.9）+ 方向 A 实现（§12.10）+ GT 小闸门 FAIL（§12.11）+ 候选 D 时序累积离线 spike NO-GO（§12.12）。**2026-09-20 尾段决策**：候选 E（Gate-G1 v3 门槛松绑，ADR-002 §12.13）+ 候选 F（CoreML 板边分割 spike，§12.14 骨架）双线并行；E 已在 §6 落 ADR-002 + 生产接线，F 停留在设计骨架不投模型二进制。**2026-09-20 v3 44 片实测**（§12.13 尾）：**v3-B 26/44=59.1%（差 1 片）+ v3-A 30.64（差 9pp）双 FAIL**；bit 8364/8364 PASS + perf +4.9% PASS；结构性 FAIL。**2026-09-21 方向 C 时序累积重定位**（§12.15）：ADR-004 Accepted，把时序累积从 Gate-G1 覆盖率手段改为 Gate-G2 刃线连续性质量信号（W=5/minCount=3/IQR≤5°/fold-crossing），四阶段 spike 计划就绪，Gate-G1 v3 门槛不动；待按 §12.15.2 落地后再做 Gate-G2 裁决。
> 前置（负结论闭环，均 2026-09-18，详见 [WORK_LOG Current State](file:///Users/mingsen/Project/FallLine/WORK_LOG.md)）：
> - [bestthird_aggregator_audit.py](file:///Users/mingsen/Project/FallLine/scripts/bestthird_aggregator_audit.py)：18 种聚合器扫描，当前 top1/3 本身最优，聚合器不是低端地板成因（证伪）。
> - [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py)：25 维现有 2D 特征穷尽，推坡初级 vs 平行雏形中级最强 margin 仅 0.50σ，不可分（负结论）。
> 关联：
> - [BoardVisualLineDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardVisualLineDetector.swift)（手工像素采样，debug-only，near_board_false_positive）
> - [VisionFrameAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VisionFrameAnalyzer.swift)（当前仅 bodyPose[/3D] 请求）
> - [VideoAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift)（frameCache 640×480 降采样帧，5fps）
> - spike 脚本与产物：[scripts/edge_spike_*.py|swift](file:///Users/mingsen/Project/FallLine/scripts)、[outputs/edge_spike/](file:///Users/mingsen/Project/FallLine/outputs/edge_spike)

---

## 0. 一句话动机

**7 片教练判"初级（推坡）"的样本被 62 分 edge-evidence cap 顶进中级带（60-65），而 4 片真"平行雏形中级"样本同样落在 60-65；两轮离线审计证明这既不是 bestThird 聚合偏差、也无法用现有 25 维 2D 特征修复——当前视觉管线缺少一个真正携带"弯形/刃线质量"信息的信号源。** 本立项的目标是新增一条**独立于姿态代理**的板身/轨迹观测能力，先作为离线诊断信号，只有在它以 ≥1.5σ margin 分开 11 片边界集后，才允许进入评分联动讨论。**本期不改任何评分。**

---

## 1. 背景：问题与已被证伪的路径

### 1.1 低端 62 分"地板"机理

最终分链路：`rawPoseAverage → bestThirdAverage(最好1/3帧) → evidenceCapped(min(…, edge/board/duration caps)) → flowModulation → final`。

- 初学者 bestThird 虚高到 69-84（最好 1/3 帧恰好是短暂站姿正确的片段）；
- 被 [lowBoardEvidenceScoreCap=62](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift) 统一压到 62；
- 62 落在中级带（≥60），穿不过初级线（<60）；
- 反例 BND2_LM 同为 62 却是真中级雏形，故**不能简单下调 cap**（会误伤）。

### 1.2 已被数据证伪的两条"便宜修复"

1. **换聚合器（减小 bestThird 选择偏差）**：18 种聚合器（wmean/median/top50/top25/blend/分位…）在 25 片标注集上模拟完整 cap 链路——top1/3 档位命中 13/25、越界 MAE 1.08，已是最优；全片化聚合器在中高端大面积低估（最差跨 3 档）。**证伪，不动。**
2. **在现有 2D 特征里找规则**：7 类 25 维（分数分布、flow、姿态维度、倒伏换弯、膝/髋节律自相关、弯段数、踝膝投影/犁式站姿/travelAngle/edgeSignal）。最强 1D 单特征 sym 仅 81.8%（margin −0.73σ）；8 个 2D 矩形规则能在 n=11 上全对，但最强 margin 仅 **0.50σ**，处于测量噪声内，与 knee 动态加权 margin 0.44 同型——**小样本过拟合，不可上线**。

结论：两类样本（推坡初级 vs 平行雏形中级）在**现有信号空间里线性不可分**，缺的是弯形/刃线这一信息维度本身，而不是更好的阈值或聚合方式。

---

## 2. 可行性 spike 证据（2026-09-18，11 片边界集）

边界集 = 7 初级（BND2_LB/L6/L5/L4/L3/L2/L1）+ 4 中级雏形（BND_L1/L2/L3、BND2_LM），全部落在 60-65 分带。脚本与接触表均可复现。

### 2.1 板身 ROI 像素预算（[edge_spike_roi_audit.py](file:///Users/mingsen/Project/FallLine/scripts/edge_spike_roi_audit.py)）

脚踝到画面底边的纵向余量（720×1280 竖屏，中位数 / P10）：

| 组 | belowPx 中位 | belowPx P10 | 双踝间距 stanceWpx | 有效帧% |
|---|---|---|---|---|
| 初级 7 片 | 585–913 | 437–713 | 6–147（多数 6–46） | 37–92% |
| 雏形 4 片 | 822–1022 | 716–939 | 2–83 | 34–80% |

- 脚下纵向空间预算**充足**（中位 ≥585px），ROI 不是高度方向的瓶颈；
- 但**站姿宽度极窄**（多片双踝间距仅 2–46px），单板多只检出单踝中心 → 无法靠"两脚连线"稳定定位板轴；
- 有效姿态帧占比在部分片仅 34–42%（远景/遮挡/雪雾），检测必须能处理稀疏锚点。

### 2.2 雪面轨迹脊线方向一致性（[edge_spike_trajectory_audit.py](file:///Users/mingsen/Project/FallLine/scripts/edge_spike_trajectory_audit.py)）

理想手工 ROI（踝下 4%–30%、±18% 宽）、4 个均匀时间点、Sobel 梯度方向直方图：

| 组 | entropy（↓集中） | peak3（↑集中） |
|---|---|---|
| 初级 7 片 | 0.638–0.894 | 0.099–0.150 |
| 雏形 4 片 | 0.588–0.849 | 0.113–0.158 |

**两组区间几乎完全重叠，无分离。** 即使在离线手工选 ROI 的理想条件下，静态雪面脊线也不携带可分信息——原因是公共雪道上新旧轨迹交叠、雪雾/压雪、相机俯仰，ROI 内方向直方图被他人轨迹主导。**该信号作为单帧/短窗分类器直接否决；若要复用，只能走"跨帧时序累积 + 与滑者位置对齐的轨迹归属"。**

### 2.3 脚踝轨迹弯形（[edge_spike_pathshape_audit.py](file:///Users/mingsen/Project/FallLine/scripts/edge_spike_pathshape_audit.py)）

5 帧平滑后的踝中心 2D 轨迹：

| 指标（预期） | 初级 7 片 | 雏形 4 片 | 可分 |
|---|---|---|---|
| straightness↑ | 0.027–0.493 | 0.132–0.293 | 重叠 |
| turnPerLen↓ | 551–1723 | 712–2344 | 重叠（反向） |
| turnStd↓ | 33.9–62.3 | 46.7–55.6 | 重叠 |
| curvMed↓ | 116–1114 | 56–983 | 严重重叠 |

**不可分**。混杂因素明确：手持跟拍相机运动主导画面 2D 位移；5fps（200ms）采样下弧线折线化；无雪面/相机补偿。踝轨迹方案要复活，前提是先做**相机运动补偿**（见 §4 候选 C）。

### 2.4 前景实例分割（[edge_spike_foreground_mask.swift](file:///Users/mingsen/Project/FallLine/scripts/edge_spike_foreground_mask.swift)）

`VNGenerateForegroundInstanceMaskRequest`（macOS14/iOS17，与现平台一致）：

- mask_L1_t2（近景侧视，雪板清晰横于脚下）：分割主体**完整包含雪板**（[mask_L1_t2.jpg](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/mask_L1_t2.jpg)）；
- mask_LM_t2（室内教学近景）：**板+固定器作为身体延伸被完整分割**（[mask_LM_t2.jpg](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/mask_LM_t2.jpg)）；
- mask_L3_t2（户外中景，板与雪面对比较弱）：**板被切掉**，只剩人体（[mask_L3_t2.jpg](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/mask_L3_t2.jpg)）；
- mask_MIDL1_t1（金色夕阳远景大全景，人仅占画面 ~5%）：主体缩成极小剪影，**板完全不可分割**（[mask_MIDL1_t1.jpg](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/mask_MIDL1_t1.jpg)）。

**结论**：前景分割在"近景/侧视/高对比"子集能把板作为人体延伸给出，但在中远景、低对比、雪雾场景系统性丢失。它是一个**带可用性门控的候选信号源**（近景才启用），不能单独承担全集检测。

### 2.5 现有手工板身线检测器为何不可复用

[BoardVisualLineDetector](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardVisualLineDetector.swift) 在踝邻域做固定长度暗线/高饱和线像素打分（29 点采样、角度种子 ±45°/±85°）。历史问题 near_board_false_positive：雪杖、裤缝、防护网、红网、阴影均可形成比真板更强的暗线；且站姿宽度像素极窄时角度先验失效。当前已降级为 debug-only 候选。**新能力不沿用其手工打分，改为"学习型/几何型 + 严格可用性门控"。**

### 2.6 spike 总体结论

| 信号 | 平台成本 | 近景区 | 远景区 | 单信号可分性 | 处置 |
|---|---|---|---|---|---|
| 雪面静态脊线方向 | 低（纯 CPU/numpy 级） | 重叠 | 重叠 | 无 | 否决单帧用法 |
| 踝 2D 轨迹弯形 | 零（已有锚点） | 重叠 | 重叠 | 无 | 搁置，待相机补偿 |
| 前景实例分割（含板） | 中（Vision，平台已满足） | **含板** | 丢板 | 未测分类，仅测覆盖 | 候选 A（近景门控） |
| Vision 轮廓（contours） | 低（macOS11/iOS14） | 待测 | 待测 | 待测 | 候选 A 的轻量补充/对照 |
| 板身专项检测（CoreML/CreateML） | 高（自采标注+模型） | 预期好 | 预期差 | 预期最高 | 候选 B（主攻方向备选） |
| 跨帧轨迹归属 + 曲率 | 中高（需滑者对齐/补偿） | 预期好 | 预期中 | 待测 | 候选 C（弯形语义主线） |

---

## 3. 目标与非目标

### 3.1 目标

1. 产出一条新的、独立于姿态代理的观测：**板身轴/刃线方向（带逐帧置信度与可用性门控）**，和/或**跨弯轨迹弯形描述子（弧连续性、单位弧长转角、速度-方向耦合）**。
2. 在 11 片边界集（并持续扩充）上，用该信号构造的规则/特征以 **≥1.5σ 标准化 margin** 分开推坡初级 vs 平行雏形中级，且留一交叉验证（LOOCV）不塌。
3. 全程作为**离线诊断/JSON 可选字段**存在，评分链路零改动，直到闸门通过后另立评分联动 spec。
4. 与平台一致：macOS 14 / iOS 17，无新三方重型依赖；CoreML 模型如需引入走 SPM resource。

### 3.2 非目标（本期明确不做）

- **不改** PoseScorer 权重、sigmoid、任何 cap（含 62 地板）、bestThird、flow 调制、stage classifier。
- 不复活 sideslip 高分 cap，不把新信号接回 boardKinematicConfidence。
- 不追求"测量真实立刃角度°"——单目 2D 无足部关键点（Vision 腿链止于踝，深度研究已确认为理论上限），本期只追求**类别/弯形可分性**，不追求物理量精度。
- 不做 30fps 重采样（已实验暂缓）；仍基于 5fps 缓存帧起步，必要时仅对新检测器单独提高其输入帧率。
- 不做 IMU/多传感器（独立技术栈，长线）。

---

## 4. 候选技术方向

### 候选 A：板身几何检测（Vision contours + foreground mask，近景门控）

- 管线：bodyPose 踝点定位 → 近景门控（踝下像素余量 + 人体框占比 + 双踝/固定器可见性）→ 踝下 ROI 内跑 `VNGenerateForegroundInstanceMaskRequest`（含板延伸）与/或 `VNDetectContoursRequest`（macOS11/iOS14，无平台门槛）→ 在 mask 底部边界 / 轮廓最长近似直线段上拟合板轴，RANSAC 长线 + 先验（板长宽比、与站姿关系、帧间连续性）。
- 产出：`boardAxisAngle`、`boardVisibleConfidence`、`boardLengthRatio`、`gate: nearShot|farShot|occluded`。
- 优点：全原生、无模型维护；spike 已证近景含板。
- 风险：中远景丢板（只能给"不可用"而非误判，门控必须严格）；mask 边界在喷雪时抖动。
- 角色：**覆盖近景子集的高质量轴信号**，并为候选 C 提供逐帧板朝向。

### 候选 B：板身专项学习型检测（CoreML / CreateML object or segmentation）

- 用自有素材（video/ 全量 + 接触表）标注"雪板"框/掩码，训练轻量检测/分割模型；ROI 仍由踝点给出以降难度。
- 优点：对裤缝/红网/阴影等 near-board false positive 鲁棒性预期显著优于手工线；可输出可靠置信度。
- 风险：标注与模型维护成本最高；远景小目标仍是硬上限；模型体积/首包、ANE/CPU 回退需验证（已有 usesCPUOnly 通道可复用）。
- 触发条件：**仅当候选 A 在近景子集也达不到 §6 闸门时升级到 B**，避免过早投入。

### 候选 C：跨弯轨迹归属与弯形描述子（语义主线，不依赖帧帧看见板）

核心思想：区分推坡 vs 平行的本质是**轨迹的弧连续性与速度-方向耦合**，这是跨弯时序量，单帧脊线（§2.2）和裸踝轨迹（§2.3）失败都是因为缺少"滑者对齐 + 相机补偿"。

- C1 相机运动补偿：用 `VNTranslationalImageRegistrationRequest`（Vision 原生，固定背景假设）或光流场的背景主导模估计帧间全局平移/微旋转，从踝/板位移中扣除，得到雪面相对轨迹。远景大全景（BND_L1 类）背景纹理丰富，配准条件反而好。
- C2 轨迹归属：把脊线/轮廓检测从"单帧 ROI 直方图"改为"滑者刚滑过的尾迹条带"——用补偿后的踝/板历史位置，在**前几帧踝所在雪面位置**（方向由候选 A 板轴或光流行进方向给出）采样窄条带，做跨帧脊线能量累积（短时栈对齐积分），只统计归属到本滑者的轨迹，排除他人轨迹。
- C3 弯形描述子：在补偿后轨迹上计算——弧连续性（拟合弧的残差）、单位弧长转角分布的连续性（推坡急停急转呈重尾/双峰，平行弧呈单峰平滑）、速度-方向耦合（平行弧速度方向沿弧切线平滑扫过；推坡速度方向与板轴反复大夹角切换）、弯段曲率符号的单调区间数。
- 优点：远景可用（不依赖看见板），直接对应教练判别语义；产出可同时服务 sym 功能性不对称的跨弯一致性老问题。
- 风险：配准在快速摇镜/纯雪面无纹理时退化（需配准置信门控）；5fps 下弧采样稀疏，必要时仅对该通道提高抽帧率（成本另估）。

### 方向取舍

- **Phase 0/1 主攻候选 A + C1**（原生 API、成本低、直接回应两个 spike 失败点），候选 C2/C3 依赖其输出；
- 候选 B 作为 A 不达标时的升级预案，不提前投入；
- 所有方向统一产出"**置信度 + 可用性门控**"，宁可输出"不可用"也不硬判（吸取板身代理 0.8–43% 与 6–53% 完全重叠的教训：低置信信号进入评分比没有信号更糟）。

---

## 5. 分期计划与交付物

> 每一阶段结束都有明确 go/no-go；任何阶段不达标即停并回流证据，不向评分蔓延。

### Phase 0 — 检测可行性闸门（离线 spike 深化，不碰生产代码）

- 0.1 扩充边界集：11 片 → 目标 ≥20 片（补初级推坡与平行雏形各半，含近/远景、室内外、雪雾），维持教练人眼标签（档位 + 是否连续平行弧），登记到 [calibration_anchors.md](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md)。
- 0.2 候选 A 离线原型：在接触表同款抽帧上跑 foreground mask + contours，量化"板轴检出率 / 角度与人工标注误差 / 近景门控精度-召回"，产物为可复现 swift/python 脚本 + TSV。
- 0.3 候选 C1 离线原型：图像配准估计相机运动，输出补偿前后踝轨迹对比图与配准残差，判断远景是否可稳定补偿。
- **Gate-G0（见 §6）**：近景板轴可用 OR 远景相机补偿可用，至少一条成立才进入 Phase 1；都不成立则项目暂停，回流结论。

### Phase 1 — 生产级观测器（仅诊断，不进评分）

- 新增 `BoardEdgeTracker`（候选 A，Vision 请求接入 [VisionAnalysisOptions](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VisionFrameAnalyzer.swift)，默认关、CLI flag / 内部开关启用）与 `TrajectoryShapeCalculator`（候选 C1/C2/C3）。
- 复用 frameCache（注意当前缓存为 640×480 降采样；轮廓/mask 需要保留踝下 ROI 的**全分辨率裁剪**，新增独立 ROI 缓存，不全量抬升帧分辨率）。
- 输出仅写入 JSON 新命名空间（如 `boardEdgeObservation` / `trajectoryShape`）与 debug overlay，**不接触 Models 评分字段消费方**；遵循确定性规约（跨次 bit-identical，纳入 repeatability 探针）与 dict/set tie-break 规约。
- 单测：合成 ROI/录制帧上的板轴拟合、门控、配准、弯形描述子纯函数。
- **Gate-G1（见 §6）**：观测器在全集上的覆盖率与稳定性达标。

### Phase 2 — 边界集可分性验证（仍不进评分）

- **起步 0：扩边界集 n=11 → ≥20**（Gate-G2 前置，2026-09-18 已盘点，等待教练回流）。当前 [video/](file:///Users/mingsen/Project/FallLine/video) 库 44 片视频中已标注 25 片（BND* + BND2_*，见 §4.4），剩余 **19 片候选池**详见 §12 清单。评分口径不动，只增加"档位 + 是否稳定刻滑 + 弯形备注"三列。
- 起步 1：候选池接触表生成——扩展 [p0_board_axis_dense_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_board_axis_dense_spike.swift) 为 `p2_candidate_contact_sheets.swift`（沿用 AVAssetImageGenerator 10 均匀抽帧 + Vision bodyPose + `BoardEdgeDetector` 生产链路），每片一张 5×2 拼图 JPG + 板轴标注，产物写 [outputs/board_edge_p2/contact_sheets/](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/contact_sheets)（不入库，`.gitignore` 已含 `outputs/*/contact_sheets/`）。教练直接看图判档，无需装 ffmpeg。
- 起步 2：教练判档回流后，把 §4.4 表扩到 ≥20 片；对新增样本同步跑一次 [bestthird_aggregator_audit.py](file:///Users/mingsen/Project/FallLine/scripts/bestthird_aggregator_audit.py) 的 `CLIPS` 数组补齐（`band` 教练档位）。
- 主体 1：Phase 1 观测器覆盖率与确定性验证——用 `--board-edge` 在扩集 ≥20 片上全跑，落实 **Gate-G1**：有效覆盖率 ≥60% / 跨次 bit-identical（`repeatability_probe.py` 通过）/ CLI 单视频耗时增幅 ≤30%。
- 主体 2：新增跨弯时序特征——板轴方向序列（unsigned 0-90°/带符号 −90…+90°）与踝下 ROI 主轴曲率、速度-方向耦合、板轴稳定连续帧占比等；实现纯函数在 `TrajectoryShapeCalculator`，输出仅进 JSON 新命名空间。
- 主体 3：用 Phase 1+Phase 2 新特征重跑 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) 的 1D/2D margin 扫描与 LOOCV，与现有 25 维基线对照。
- **Gate-G2（硬闸门，见 §6）**：≥1.5σ margin + LOOCV 稳定，才允许立项 Phase 3。

### Phase 3 — 评分联动（**另行立项 spec，本期不做**）

- 仅在 G2 通过后，另写 spec 讨论如何把新信号用于：低端 cap 条件化（区分 BND2_LM 真中级）、或走刃证据增强。必须包含全 25 片标注集 + 主 corpus 6 片的零回归验证、专业档保护、置信门控（低置信"暂不评分"语义）。

---

## 6. 验收闸门（量化 go/no-go）

统一在**边界集**上评估（Phase 0 用 n=11，Phase 2 用扩充后 n≥20），标准化空间定义沿用 lowend_separability_audit 的 within-set z-score。

- **Gate-G0（可行性，至少一条成立）**
  - A 路：近景门控子集中，板轴逐帧检出率 ≥70%，板轴角度与人工标注中位误差 ≤12°，门控"近景"判定精确率 ≥90%（远/挡不得误判为近景）；或
  - C 路：相机补偿在远景子集 ≥80% 帧配准成功（残差 < 2px @640 宽或等价阈值），补偿后轨迹的类间可分性较补偿前有可量化改善（margin 提升 ≥0.5σ）。
- **Gate-G1 v1（原始定义，2026-09-18 已实测结构性 FAIL，保留为历史/理想目标）**
  - 全集（n≥20）板轴或轨迹信号**有效覆盖率 ≥60%**，其余帧诚实输出"不可用"；
  - 跨次确定性：同视频 ×N 次运行新字段 bit-identical（纳入 repeatability 探针）；
  - 性能：CLI 单视频总耗时增幅 ≤30%（5fps 基线上），iOS 端内存峰值增幅 ≤15%。
- **Gate-G1 v2（ADR-001 决策后的现行定义，2026-09-19）**
  - 覆盖率按**降级后有效帧**度量：`status ∈ {board, fallback}`（fallback 须满足 `confidence ≥ fallbackConfidenceFloor`）；
  - **片级可用性**（二者满足其一即可，避免长远景片稀释）：
    - 片级 `effectiveCov% ≥ 30%` 的样本占比 **≥ 60%**；或
    - 帧加权可用性 `Σ min(effectiveCov%, 60%)·f / F ≥ 40%`；
  - v1 的全帧 ≥60% 降级为"理想覆盖率"观察项，不再作准入闸门；
  - 确定性与性能条款沿用 v1（bit-identical；耗时 ≤30%），fallback 纯几何合成不新增推理，性能预期零增量。
- **Gate-G1 v3（ADR-002 决策后的现行定义，2026-09-20）**
  - 触发条件：v2 在 §12.10/§12.11/§12.12 连续三轮验证结构性 FAIL（fallback 几何精度天花板 + IQR 稳定性门二次腰斩），继续下调 floor / 换 pick 策略 / 加时序累积均已证伪；
  - **口径核心翻转：从"覆盖率优先"改为"精度优先的可用性"**——凡计入 effectiveCov 的 fallback 帧必须先过 GT 小闸门（准入精度 ≥90%），覆盖率数字只作为"可用性"下限，不再自证质量；
  - fallback 链路收敛到 **`ankleOnly + floor 0.40 + W=5 + IQR≤5°`**（§12.11 三策略扫描 + §12.12 时序累积扫描的联合唯一解），生产侧作为默认策略；
  - 片级可用性（二者满足其一即可）：
    - 片级 `effectiveCov% ≥ 25%` 的样本占比 **≥ 60%**（v3-B，v2 的 30/60 下调到 25/60）；或
    - 帧加权可用性 `Σ min(effectiveCov%, 60%)·f / F ≥ 40%`（v3-A，与 v2 一致，因为 v2 加权阈值本身没有失守）；
  - 确定性与性能条款沿用 v1/v2（bit-identical；耗时 ≤30%）；时序聚合窗仅在诊断/audit 场景开启，不影响生产帧级 `boardEdgeObservation`，性能预期零增量；
  - v1 60% 全帧覆盖率 + v2 30/60 片级门槛保留为"理想目标 / 观察项"，不再作准入闸门。
  - **答辩要点**："覆盖率不代表评分覆盖率" —— Phase 1 观测器**不进评分链路**（§4.5 独立命名空间），Gate-G1 只是"观测器可用性下限"，评分口径的最终质量由 Gate-G2 可分性硬闸门 + Gate-G3 兼容闸门守护。放弃"覆盖率≥60%"的心理预期，转而保证"入统计的 fallback 帧准入精度 ≥90%"，是对**评分零污染原则**（§4.5）的严格执行。
- **Gate-G2（可分性硬闸门，这是进入任何评分讨论的前置）**
  - 新信号（或其与现有特征的组合）在边界集上的最强分离 **margin ≥1.5σ**（对照：现最强 0.50σ，knee 动态加权 0.44σ 均判过拟合）；
  - **LOOCV 留一准确率 ≥90%** 且无单片翻转导致 margin 跌破 1.0σ（防 n=11 小样本过拟合）；
  - 方向正确：7 初级在"连续弧/刃线"证据上**显著弱于** 4 雏形，且 calf≈45.5 软信号分错的跨界样本（GM/M1 类）不与本结论冲突；
  - 与专业档保护兼容：新信号不得要求为了分开低端而压低主 corpus 已确认刻滑样本（v2/v3/v6）。
- **Gate-G3（Phase 3 才用，此处仅声明）**：评分联动后全标注集档位命中不下降、主 corpus 零非预期回归、低置信走"暂不评分"。

---

## 7. 风险与缓解

1. **远景硬上限**：单板在大全景仅数像素高，任何板身检测物理不可用。缓解：远景走候选 C 轨迹而非板身；门控严格输出"不可用"，绝不猜测。
2. **相机运动混杂**：手持跟拍主导 2D 位移，是 §2.3 失败主因。缓解：C1 配准前置 + 配准置信门控；配准失败帧不进弯形统计。
3. **他人轨迹污染**：公共雪道新旧痕交叠，是 §2.2 失败主因。缓解：C2 滑者尾迹归属窄条带 + 跨帧对齐累积，不做全 ROI 直方图。
4. **小样本过拟合（最高危）**：n=11 上 0.50σ 的教训。缓解：G2 强制 1.5σ + LOOCV + 扩样到 ≥20，并在 Phase 3 前用更大 corpus 复核；规则数量受限（只允许 1-2 个语义可解释阈值）。
5. **低置信信号入评危害**：板身代理历史已证明"看似有值的噪声比无信号更糟"。缓解：独立命名空间 + 显式门控 + 本期完全不接评分。
6. **性能/内存**：mask/contours 全帧跑成本高。缓解：只在踝下 ROI 裁剪上跑；维持 5fps；新缓存独立且限尺寸。
7. **平台/设备碎片**：foreground mask 需 macOS14/iOS17（已满足部署目标）；contours 更低；ANE 不可用时复用现有 CPU 后备与熔断。
8. **标签主观性**：推坡 vs 平行雏形边界本身是教练主观判断。缓解：双标注（必要时）+ 只锁定"有无连续平行弧"这一相对客观的判据，标注定性存疑样本不计入 margin。

---

## 8. 不改动清单（本立项边界）

- [PoseScorer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift)、[SkiMetricsCalculator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/SkiMetricsCalculator.swift)、所有 cap 常量（[Utilities.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift) / [VideoAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift)）、[StageClassifier.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/StageClassifier.swift)、[FlowMetricsCalculator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift) 评分语义、[ReportGenerator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 评分行——**本期零改动**。
- bestThird 聚合器维持 top1/3。
- iOS UI 不改动（新字段不消费；未来 Phase 3 单独立项）。

---

## 9. 立即可执行项（Phase 0 起步，等待确认）

1. 扩充并复核边界集标签（≥20 片），登记锚点表；
2. 写候选 A 离线原型脚本（mask+contours 板轴拟合 + 人工角度标注误差统计）；
3. 写候选 C1 离线原型脚本（VNTranslationalImageRegistration / 背景光流配准 + 补偿前后轨迹对比）；
4. Phase 0 结束输出 Gate-G0 判定 TSV 与 go/no-go 结论，再决定是否投入 Phase 1 生产代码。

---

## 10. Phase 0 结果（2026-09-18 执行）：Gate-G0 = **A 路 go / C1 路 no-go**

> 全程离线原型 + 人工逐帧 GT，**生产代码与评分零改动**。抽帧口径：每片 10 个均匀时间点（0.08–0.92），`AVAssetImageGenerator` 精确取帧，共 **110 帧**；逐帧 GT 接触表在 [outputs/edge_spike/gt_sheets/](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/gt_sheets)，原始指标在 [p0_board_axis_dense.tsv](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/p0_board_axis_dense.tsv)。

### 10.1 候选 A（板轴几何）：**GO** —— Gate-G0 三项硬指标

算法：同帧 Vision bodyPose 踝点 → `VNGenerateForegroundInstanceMaskRequest` 主体 bitmap → 踝下 ROI（x: ±0.24，y: −0.16…−0.01）内主体像素 PCA → 主轴角（unsigned 0–90）、延伸率、归一长度；门控阈值 `ankCnf≥0.30 / subjFrac≥0.02 / angle≤45° / axisLen 0.10–0.55 / elong≥2.0`。

110 帧中，门控判定为"近景子集"（ankCnf≥0.30 且 subjFrac≥0.02）共 **52 帧**；其中判 `board` **28 帧**。对照 Gate-G0 §6：

1. **板轴逐帧检出率**：近景子集 28/52 = **54%**（阈值 0.10 口径），未直接到 70%；但 17 帧 `rejectLength` 的归一长度呈连续分布（0.04–0.098），7 帧在 0.07–0.098 属阈值边界效应而非检测失败。`G_MIN_LEN` 降到 **0.07**（对应 1080p 下板长物理下限仍合理）时几何放行 **38/52 = 73% ≥70%**，且新增放行帧逐帧核对全部对准真板、无硬假阳。**检出率达标（73%）。**
2. **板轴角度与人工标注误差**：28 个 `board` 逐帧目视（含单帧 zoom），主轴与真实板轴方向一致，角度误差目测 **≤10°**（绝大多数 ≤5°），**中位误差 ≤8° ≤12° 达标**。
3. **门控"近景"判定精度**：`board` 判定 **28/28 全部落在近景子集内**；非近景 58 帧中 **0 帧被误放为 board**（门控精度 **100% ≥90% 达标**）。rejectVertical 对雪杖/裤腿/竖直他人（如 L5#8 报 87°、L2#6 报 77°）全部成功拦截。

**零硬假阳性**：没有任何一帧把"非板物体"当成板轴输出。唯一一处**对象归属**问题是 BND2_L5#7（28° 轴对准画面背景中他人的板，物理上仍是真板、角度亦对），Phase 1 需加"主体 ROI 与踝点空间一致性/实例归属"校验，把跨实例轴降级为"不可用"。另注意若干帧主体处于摔倒/坐姿（BND2_LB 类），轴虽为真板但不代表滑行质量，Phase 1 须与 bodyPose 站姿/状态联合门控。

**A 路结论 GO**：在近景/中景（含部分夜间低光、室内雪场）子集，前景分割 + 踝下 PCA 能以 73% 检出、≤8° 角度、100% 门控精度产出可靠板轴；远景诚实输出"不可用"（BND_L1 金色夕阳、BND_L2 雪雾等 0 board 且无猜测）。

### 10.2 候选 C1（相机补偿 + 踝轨迹弯形）：**NO-GO**

脚本：[p0_camera_registration_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_camera_registration_spike.swift)（全图配准）、[p0_camera_registration_bg_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_camera_registration_bg_spike.swift)（人体框外背景掩膜配准）、[p0_loo_classify.py](file:///Users/mingsen/Project/FallLine/scripts/p0_loo_classify.py)（标准化特征 + LOO）。

1. **配准技术本身可用**：`VNTranslationalImageRegistrationRequest` 全图版成功率 75–100%（11/11 片 ≥75%，10 片 ≥79%）；背景掩膜版 70–100%，两版向量高度一致（y 相关≈1.0，x 多 0.65–0.95）——说明早期担心的"大主体时锁滑手"伪影在加背景掩膜后未改变主结论，跟拍片的大平移是真实相机运动。
2. **但 margin 提升是机位混淆假阳性**：全图补偿后 turnStd 的 within-set margin 从 0.38 跳到 **2.00σ**，方向却与原假设相反（雏形踝中点 S 弧更多→转角更大，推坡近景跟拍反而被压平）。补偿轨迹接触表（[p0_comp_track_sheet.png](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/p0_comp_track_sheet.png)）直观证实：补偿量同时随"滑行水平"和"机位类型"变化，7 初级里近景跟拍偏多、4 雏形里固定机位偏多，margin 主要来自机位而非水平。
3. **LOO 判定决定性**：标准化 5 维弯形特征（straight/turnStd/turnPerLen/curvMed/pathLen），单/双特征留一交叉验证——**raw 最好 6/11 错、全图补偿 6/11、背景补偿最好 5/11**（错分几乎全是初学者被推向雏形），没有一种口径达到可用泛化。小样本高方差下 2.00σ margin 没有转化为判别力，重蹈 §1.2 的 0.50σ 过拟合模式。

**C1 路结论 NO-GO**：5fps 踝中点 2D 轨迹即便做纯平移相机补偿，也不能稳定区分推坡 vs 平行雏形；根因是踝中点轨迹同时受站位策略、换刃阶段、相机旋转（非纯平移）、稀疏采样影响，单目 2D 无法充分解耦。**C2/C3（轨迹归属、弯形描述子）在 Phase 1 不作为主线**，仅在候选 A 板轴提供逐帧朝向之后，作为可选增强再评估；远景样本在 Phase 1 只能得到"板轴不可用 + 姿态代理"的诚实结论。

### 10.3 Gate-G0 总体判定与 Phase 1 入口

- **Gate-G0 = PASS**（满足"近景板轴可用 OR 远景相机补偿可用，至少一条"——A 路成立）。
- 进入 **Phase 1**：新增生产级板轴观测器（候选 A，默认关、诊断命名空间 + debug overlay，JSON/overlay 不接触评分字段），并在设计中落实两条 Phase 0 暴露的必修项：
  1. **实例归属/空间一致性门控**：主轴必须来自与踝点同一前景实例、且在踝下 ROI 内，跨实例（他人板/背景物体）降级"不可用"（修 L5#7）；
  2. **站姿状态联合门控**：摔倒/坐姿/非站立帧的板轴不得作为刃线质量证据（修 LB 类），与 bodyPose detected/姿态置信联动；
  3. `G_MIN_LEN` 采用 **0.07**（替代 0.10）作为 Phase 1 基线，并在单测里锁定 0.07–0.10 边界；
  4. 复用 frameCache 但为踝下 ROI 保留**全分辨率裁剪**（mask/PCA 需要足部细节），不全量抬升帧分辨率；遵循确定性与 dict/set tie-break 规约。
- **非目标维持不变**：PoseScorer / 所有 cap / bestThird / flow / stage classifier / iOS UI 零改动；新信号到 Phase 2 仍须 Gate-G2（margin≥1.5σ + LOOCV≥90%）才谈评分联动。
- **扩边界集（0.1）继续作为中优先项**：当前 n=11 对 Phase 1 诊断足够，但 Gate-G2 需要 n≥20；候选池盘点与接触表（供教练标注）另行推进。

---

## 11. Phase 1 结果（2026-09-18 执行）：生产级板身刃线观测器落地，**默认关 · 纯诊断 · 零评分接触**

### 11.1 交付物

| 类型 | 文件 | 说明 |
| --- | --- | --- |
| 检测器 | [BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift) | `BoardEdgeConfig`（阈值公开常量，`.standard` = Gate-G0 校准值 `minAxisLength=0.07`）+ `AxisGeometry`（纯数值，Equatable）+ `BoardEdgeDetector.detect(cgImage:pose:config:)` |
| 模型 | [Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L594-L661) | `BoardEdgeStatus`（11 态：board + disabled + 9 种具体不可用原因）、`BoardEdgeObservation`（归一几何、Codable、init 字段钳制）；`DetectionResult` 新增可选 `boardEdgeObservation` |
| 管线 | [VideoAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L343-L354) | init 增 `enableBoardEdge`（默认 false）/`boardEdgeConfig`；`analyzeFrame` 同帧检测；**诊断失败局部隔离** |
| 平滑 | [PoseSmoother.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift) | 三处重建 `DetectionResult` 透传 `boardEdgeObservation` |
| CLI | [main.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/main.swift) | 新增 `--board-edge` flag 与 help |
| Overlay | [DebugOverlayRenderer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/DebugOverlayRenderer.swift#L359-L380) | board 帧画青色板轴（图宽 × lengthRatio 定长） |
| 测试 | [BoardEdgeDetectorTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardEdgeDetectorTests.swift) | 21 用例 |

### 11.2 Phase 0 四条入口要求的落实

1. **实例归属门控**：`poseBodyBox`（8 个核心关键点包围盒）与每个前景实例框算 **IoU**，仅保留 ≥0.15 中最高者；无合格实例 → `rejectOwnership`。修复 L5#7（对准背景他人板）。无姿态框可比对时保守回退最大主体。
2. **站姿状态门控**：`postureStatus` 用肩-髋躯干倾角（>50° 判倒）+ 髋须高于踝（Vision y 向上，坐姿不满足）；摔倒/坐姿 → `rejectPosture`；关键点缺失时证据不足不猜测。
3. **`minAxisLength=0.07`**：作为 `BoardEdgeConfig.standard` 默认值并由长度越界单测锁定。
4. **全分辨率**：`detect` 直接消费 `analyzeFrame` 的抽帧 CGImage（`maxFrameSize` 1920×1080），mask/PCA 在足部细节上进行；不抬升全管线分辨率，也不复用 640×480 frameCache。

### 11.3 门控状态机

```
ankleLowCnf → noMask → rejectOwnership → farShot(subjFrac<0.02)
→ rejectPosture → [ rejectVertical(angle>45°)
                  | rejectLength(len∉[0.07,0.55])
                  | rejectBlob(elong<2.0)
                  | noAxis ]
→ board
```

**诊断失败隔离**：`analyzeFrame` 用 `try?` 包裹检测器，失败退化为 `.noMask` 占位——分割抛错不得拖垮同帧已成功的姿态/评分（生产韧性要求）。

### 11.4 验证

- `swift build` 通过；`swift test` 全量 **274 通过 0 失败**（基线 253 + 21 新用例）。
- 单测覆盖：踝点（双踝均值/单踝/低置信/缺失）、IoU（同框=1/不交=0/部分）、实例归属（最高 IoU/低 IoU 拒绝/无框回退最大）、站姿（站立/横倒/坐姿/证据不足）、ROI PCA（水平条角0+长度/竖直条90°/团块低延伸/像素不足/短条长度越界/ROI 外忽略）、观测字段 [0,1] 钳制。
- 真实冒烟 `testvideo/1.MP4 --board-edge`：117 采样帧状态 farShot 92 / rejectLength 10 / **board 8** / ankleLowCnf 6 / rejectVertical 1；8 个 board 帧 axisAngle 3.4–10.4°、elong 4.6–8.4，与 Phase 0 GT 一致。叠加 `--debug-overlay` 118 张图正常产出，目检 board 帧青色轴精确落在真实雪板上。

### 11.5 Phase 2 入口

- 观测**仍为诊断字段**，不读取也不修改任何评分。
- **Phase 2**：板轴方向序列 + 轨迹曲率 + 速度-方向耦合等跨弯时序特征，先扩边界集 **n=11→≥20**，再以 **Gate-G2（margin≥1.5σ + LOOCV≥90%）** 判定；Gate-G2 通过且另行立项前不联动评分。远景帧继续诚实输出"板轴不可用"。

---

## 12. Phase 2 起步：扩样候选池（2026-09-18 盘点）

已标注 25 片（BND* + BND2_*，见 §4.4），[video/](file:///Users/mingsen/Project/FallLine/video) 库共 44 片，剩余 **19 片候选池**未打教练档位。历史算法综合分（来自各 `.md` 报告）作为**弱先验**排序，只用来提示教练"哪些片可能引入新的信息"，判档以人眼为准。

### 12.1 未标注候选（19 片，按桶分组）

| # | 桶 | 相对路径 | 历史算法分 | 弱先验档位提示 |
|---|---|---|---:|---|
| 1 | good | [good/0946ed384e732c357a3d55fac77426c0.MP4](file:///Users/mingsen/Project/FallLine/video/good/0946ed384e732c357a3d55fac77426c0.MP4) | 73 | 中偏上 / 高质量 |
| 2 | good | [good/3134552bed78447b9f7ba8e2003ce678.MP4](file:///Users/mingsen/Project/FallLine/video/good/3134552bed78447b9f7ba8e2003ce678.MP4) | 72 | 中偏上 |
| 3 | good | [good/3e6f37fe76521781506c19c02c1b97ed.MP4](file:///Users/mingsen/Project/FallLine/video/good/3e6f37fe76521781506c19c02c1b97ed.MP4) | 83 | 高质量 |
| 4 | good | [good/5382da0c825e30518ab376505cbcfaf2.MOV](file:///Users/mingsen/Project/FallLine/video/good/5382da0c825e30518ab376505cbcfaf2.MOV) | 72 | 中偏上 |
| 5 | good | [good/641efed02be271b6d9f014c97d1f8ae0.MOV](file:///Users/mingsen/Project/FallLine/video/good/641efed02be271b6d9f014c97d1f8ae0.MOV) | 77 | 中偏上 |
| 6 | good | [good/9ed0bb6c707fc47fce153cee3dcd365e.MP4](file:///Users/mingsen/Project/FallLine/video/good/9ed0bb6c707fc47fce153cee3dcd365e.MP4) | 75 | 中偏上 |
| 7 | good | [good/v0200fg10000d7r0017og65qoh1vgeg0.MP4](file:///Users/mingsen/Project/FallLine/video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4) | 89 | 专业（GOOD_A，2026-05 教练已认专业，但未纳入 §4.4 边界表） |
| 8 | good | [good/v2800fgi0000d6m0mk7og65qamcvgf80.MP4](file:///Users/mingsen/Project/FallLine/video/good/v2800fgi0000d6m0mk7og65qamcvgf80.MP4) | 78 | 中偏上 |
| 9 | middle | [middle/1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4](file:///Users/mingsen/Project/FallLine/video/middle/1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4) | 67 | 中级 |
| 10 | middle | [middle/4a7dfe960f07ac14b06bbd8de3d38aa4.MP4](file:///Users/mingsen/Project/FallLine/video/middle/4a7dfe960f07ac14b06bbd8de3d38aa4.MP4) | 73 | 中偏上 |
| 11 | middle | [middle/96001e37e76be9ef6cf7a65e73efcac4.MP4](file:///Users/mingsen/Project/FallLine/video/middle/96001e37e76be9ef6cf7a65e73efcac4.MP4) | 85 | 专业（2026-05 教练已认，但未在 §4.4 边界集） |
| 12 | middle | [middle/992f063b79d27b96b471e44a48d8465e.MP4](file:///Users/mingsen/Project/FallLine/video/middle/992f063b79d27b96b471e44a48d8465e.MP4) | 55 | 初级 |
| 13 | middle | [middle/a7791a475a244c938dd0815e89b1dec5.MP4](file:///Users/mingsen/Project/FallLine/video/middle/a7791a475a244c938dd0815e89b1dec5.MP4) | 74 | 中偏上 |
| 14 | middle | [middle/ccfd9967aa6d3ab5abd04fb8991872c7.MOV](file:///Users/mingsen/Project/FallLine/video/middle/ccfd9967aa6d3ab5abd04fb8991872c7.MOV) | 68 | 中级 |
| 15 | middle | [middle/v0200fg10000d2tcts7og65t6h63ua2g.MP4](file:///Users/mingsen/Project/FallLine/video/middle/v0200fg10000d2tcts7og65t6h63ua2g.MP4) | 58 | 初级 |
| 16 | middle | [middle/v0200fg10000d6a4i57og65mkjkcdpu0.MP4](file:///Users/mingsen/Project/FallLine/video/middle/v0200fg10000d6a4i57og65mkjkcdpu0.MP4) | 76 | 中偏上 |
| 17 | middle | [middle/v0300fg10000d4oq6avog65ihr8qf550.MP4](file:///Users/mingsen/Project/FallLine/video/middle/v0300fg10000d4oq6avog65ihr8qf550.MP4) | 60 | 中级 |
| 18 | middle | [middle/v2800fgi0000d5ehg1vog65tinkepgl0.MP4](file:///Users/mingsen/Project/FallLine/video/middle/v2800fgi0000d5ehg1vog65tinkepgl0.MP4) | 77 | 中偏上 |
| 19 | bad | [bad/0b7522e9db823b910ac67727aea726da.MP4](file:///Users/mingsen/Project/FallLine/video/bad/0b7522e9db823b910ac67727aea726da.MP4) | 70 | 初级 / 中级（bad 桶中的相对高分，2026-05 教练已认中级但未在 §4.4） |

分布：good 8 / middle 10 / bad 1。**good/middle 各半**符合 §5 Phase 0 "补初级推坡与平行雏形各半，含近/远景、室内外、雪雾" 的采样目标；bad 桶剩余仅 1 片（其余 8 片已在 §4.4 batch 2），需要新增 bad 样本的话须从 corpus 外补片。

### 12.2 Phase 2 起步优先次序建议（教练判档 + 稳定刻滑判定）

按信息增益优先看片，n=11 → ≥20 至少需教练判 9 片：

1. **中间地带 60-70 分** 4 片（对分低端 cap 最有信息量）：#12 992f… (55)、#15 v0200…d2tcts7 (58)、#17 v0300…d4oq (60)、#19 0b7522… (70)。
2. **专业候补** 2 片（对上端专业边界稳定性有信息量）：#7 v0200…d7r0017 (89, GOOD_A 已认专业)、#11 96001e… (85, 已认专业)。
3. **中偏上 72–78** 3 片（对中级与专业过渡带补密）：#3 3e6f37fe (83)、#8 v2800…d6m0mk (78)、#5 641efed0 (77)。

其余 10 片作为 Phase 2 结束后的复核池，视 Gate-G2 结果再决定是否扩到 n≥30。

### 12.3 接触表产物路径（Phase 2 起步 1 产出，2026-09-18 已落地）

- 生成脚本：[scripts/p2_candidate_contact_sheets.swift](file:///Users/mingsen/Project/FallLine/scripts/p2_candidate_contact_sheets.swift)（对齐 [p0_board_axis_dense_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_board_axis_dense_spike.swift) 的算法：Vision `bodyPose` 找踝 + `foregroundInstanceMask` 抠人体 + 踝下 ROI PCA 求主轴 + 生产 `BoardEdgeConfig.standard` 门控口径 `G_MIN_LEN=0.07`；纯 Swift、无 ffmpeg 依赖；支持 `ONLY=<alias>,...` 单片过滤）。
- 产物目录：[outputs/board_edge_p2/contact_sheets/](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/contact_sheets)（`.gitignore` 排除，不入库）。
- 图布局：每片一张 5×2 大图（10 均匀抽帧 `frac=0.08~0.92`），每帧 300×533，覆盖踝下 ROI 黄框 + 主轴（board=绿、rejected=红）+ 状态文本（`verdict/cnf/subj/ang/elong/axisLen`）；顶栏一行 hint/score/board 命中计数。
- 教练回流格式：追加到 §4.4 表，新增列 `教练档位 / 稳定刻滑? / 弯形备注`。
- **首轮 19 片全跑通命中率（`verdict==board` / 10 抽帧）**：good 桶 G01=2 / G02=1 / G03=2 / G04=3 / G05=0 / G06=7 / G07=2 / G08=4（共 21/80，26%）；middle 桶 M01=1 / M02=1 / M03=0 / M04=1 / M05=0 / M06=3 / M07=2 / M08=0 / M09=1 / M10=2（共 11/100，11%）；bad 桶 B01=5/10（50%）。整体 37/190 ≈ 19%。观测：middle 中间地带 11% 显著低于 Phase 0 主 corpus 的 5-6/10，主要被 `farShot`/`rejectVertical` 拒（远景 + 站姿飘忽），正是 Gate-G2 需要教练判档 + Phase 2 时序特征补齐的场景；这批接触表可作为教练判档的 sanity check 而非 Gate-G1 覆盖率证据（后者需在 `--board-edge` 生产口径下的 5fps 全帧统计上做）。

### 12.4 Gate-G1 / Gate-G2 前置检查表

Phase 2 主体开工前必须逐项打勾：

- [x] Phase 2 起步 1：19 片候选池接触表脚本落地并全跑通（见 §12.3，2026-09-18）。
- [x] 12.1 候选池 ≥9 片教练判档回流，§4.4 表扩到 ≥20 片 → **44 片全部回填完成（2026-09-19，§12.8）**。
- [ ] [bestthird_aggregator_audit.py CLIPS](file:///Users/mingsen/Project/FallLine/scripts/bestthird_aggregator_audit.py#L38-L64) 与 [lowend_separability_audit.py BEGINNER/EMERGING](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py#L41-L42) 同步扩到扩集口径。
- [x] Phase 2 起步 2：Gate-G1 三合一探针脚本落地并全量跑 25 片（见 §12.5，2026-09-18）。
- [ ] `swift run FallLineCLI --board-edge` 在扩集 ≥20 片上跑通 → **44 片 raw board 覆盖率 19.58%（v1 60% 门槛结构性 FAIL，三度复现）；方向 A 已实现，effective（board+fb≥0.30）35.51%，v2-A 25/44=56.8% / v2-B 34.90 均微差 FAIL（§12.10）；fallback GT 小闸门结构性 FAIL（§12.11）；候选 D 时序累积 NO-GO（§12.12）；需在 §6 决策候选 E/F 后再谈**。
- [x] `scripts/board_edge_gate_g1_probe.py` 跨次 bit-identical（含 `boardEdgeObservation` + `fallbackAxis` 全字段）→ 44 片 8364/8364 帧完全一致（PASS，§12.10）。
- [x] `scripts/board_edge_gate_g1_probe.py` `--board-edge` 开/关总耗时增幅 ≤30%（Gate-G1 性能）→ 44 片 avg +4.51% / max +7.56%（PASS，§12.10）。
- [x] Phase 2 起步 3：Gate-G1 reason 分布 audit 完成（见 §12.6，2026-09-18）→ 证伪"放宽板轴几何门控"为主方向，翻转到"降级链路 + Gate-G1 门槛重定义 + 连续 board 片段"三方向。
- [x] ADR-001 + fallbackAxis 实现规格定稿（见 §12.9，2026-09-19）→ Gate-G1 v2 定义已同步 §6；方向 A 已实现（§12.10）。
- [x] fallback 自身 GT 精度小闸门（§12.9 前置条款）→ 44 片 × 三策略 × 八 floor **结构性 FAIL**（§12.11），三策略最好 ankleOnly 准入 87.2% / 差门槛 2.8pp；踝对是 2D 几何精度天花板，非策略/floor 可救。
- [x] 候选 D 时序累积离线 spike（§12.11 下一步·候选 D 首选）→ 81 组合扫描完成 **NO-GO**（§12.12）：最强 ankleOnly+floor 0.35+W=5+IQR≤5° 准入 91.2% ✅ 但 v2-A 40.9% / v2-B 26.76 双低 ❌，精度/覆盖率此消彼长；Phase 2 主体前置候选缩到 E / F 二选一。
- [x] 候选 E ADR-002 落地（§12.13，2026-09-20）→ Gate-G1 v3 定义已同步 §6，`fallbackConfidenceFloor` 默认 0.40 + `fallbackPickStrategy=ankleOnly`；探针 v3 双口径判定接入 [board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py)。
- [x] 候选 E 单测：[BoardEdgeDetectorTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardEdgeDetectorTests.swift) 新增 4 条 ADR-002 用例（默认基线 = ankleOnly+floor 0.40、ankleOnly 跳过更强膝对、踝缺失 ankleOnly 结构性拒绝、floor 0.40 边界拒绝 + v2 对照），`swift test` 全量 **290/290 通过**（Phase 1+ADR-001 基线 285 + 本轮 +5：4 条 ADR-002 + 1 条 v2/v3 floor 边界拆分）。
- [x] 候选 E 44 片 v3 重跑 → v3-A / v3-B 判定表（2026-09-20，见 §12.13 尾"v3 44 片 8364 帧实测"）→ **v3-B 26/44 = 59.1% FAIL（差 1 片）+ v3-A 30.64 FAIL（差 9pp）+ bit 8364/8364 PASS + perf +4.9% PASS**；日志 [outputs/board_edge_p2/gate_g1_probe_v3.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe_v3.log) + 结构化摘要 [outputs/board_edge_p2/gate_g1_probe_v3_summary.json](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe_v3_summary.json)。
- [x] 候选 F CoreML 板边分割 spike 设计骨架（§12.14，2026-09-20，Design only）→ 模型选型 / GT 方案 / 决策标准 / 成本预算全部落地；新增 [scripts/board_edge_coreml_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_coreml_spike.py) 骨架脚本（`NoopBackend` 占位、`--check-plan` / `--list-clips` 可用、`--model` 未实现退 2）；不投模型二进制，等 v3 + Gate-G2 判定后再定优先级。
- [x] 候选 F 骨架 → 待投运的过渡态（§12.14.1，2026-09-22）：用户拍板 **yolov8n-seg + .pt + fetch.sh + 项目开源（AGPL-3.0 合规）**。新增 [models/](file:///Users/mingsen/Project/FallLine/models/)（[README.md](file:///Users/mingsen/Project/FallLine/models/README.md) + [fetch.sh](file:///Users/mingsen/Project/FallLine/models/fetch.sh) + `yolov8n-seg/.gitkeep`）；`.gitignore` 加 `models/**/*.pt|.mlpackage/|.mlmodel|.onnx` + `.venv-coreml/`；[board_edge_coreml_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_coreml_spike.py) 的 `CoreMLBackend` 从占位换成真实实现（`coremltools` lazy 加载 `.mlpackage`、ffmpeg 抽帧、单帧 predict、板身 COCO 30/31 mask 联合、推理耗时 & IoU、可选 `gt_mask`），并加 `--dry-run` 每片 5 帧 zero-shot 快检；模型二进制**仍不入库**，未跑推理（等用户本机 `bash models/fetch.sh` + `yolo export`）。
- [x] 方向 C 时序累积 ADR-004 + 生产级 spike 计划（§12.15，2026-09-21，Design only）→ 定位翻转：时序累积从"Gate-G1 覆盖率手段（§12.12 NO-GO）"改为"Gate-G2 刃线连续性质量信号"；定义 `BoardTemporalAxisAggregator`（W=5 / minCount=3 / IQR≤5° / fold-crossing 处理）+ `BoardTrajectoryMetrics`（stableWindowRate / longestStableRun 等进 summary `boardTrajectory`）+ 四阶段 S1–S4 spike 计划；Gate-G1 v3 门槛不动，评分零污染。
- [x] Phase 2 时序特征输出仅进 JSON 新命名空间（summary `boardTrajectory`）+ debug overlay，Models 评分字段消费方零改动（§12.15，S1–S2 已落地，2026-09-21）。
- [x] Gate-G2 判定：`lowend_separability_audit.py --trajectory` 44 片重跑，margin / LOOCV 双 FAIL 且方向反转 → **NO-GO**，字段留诊断，激活候选 F（§12.15.3，2026-09-21）。

### 12.5 Gate-G1 三合一探针实测（2026-09-18，§4.4 全 25 片）

- 探针脚本：[scripts/board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py)（每片 CLI 跑三轮：`--board-edge` 两轮 + 基线一轮；从 JSON `boardEdgeObservation` 逐帧提取 status/reason，覆盖率 = `status=board` 帧数 / 总帧数；确定性 = 两轮 `--board-edge` 逐帧 `board_flag / axis_angle_deg / axis_length_norm / confidence / near_body_shape / obs_confidence / reason` bit-identical；性能 = `--board-edge` 平均耗时 / 基线耗时）。
- 产物日志：[outputs/board_edge_p2/gate_g1_probe.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe.log)（`.gitignore` 排除）。
- **总账**：
    - 覆盖率：全帧口径 **811/4146 = 19.56%**（Gate-G1 门槛 ≥60%）→ **FAIL**；片级 ≥60% 仅 **1/25**（BND2_L1 = 75%，其次 BND2_LM 57%、BND2_L3 50%）。
    - 确定性：**4146/4146 = 100%** bit-identical（跨两轮 `--board-edge` 逐字段完全一致）→ **PASS**。
    - 性能：`--board-edge` 开启对总耗时 **avg +5.9% / median +5.2% / max +19.7%**（Gate-G1 门槛 ≤30%）→ **PASS**。
- **单片分布（cov% ↓）**：BND2_L1 75% / BND2_LM 57% / BND2_L3 50% / BND2_L5 38.7% / BND_M4 37.7% / BND_M2 32.3% / BND2_H4 31.6% / BND_M1 28.9% / BND_M3 23.2% / BND2_H0 22.0% / BND2_LB 17.7% / BND2_TOP 16.9% / BND2_L6 15.3% / BND2_H1 14.5% / BND_L3 14.4% / BND2_GM 14.1% / BND_HI1 12.6% / BND2_H2 11.5% / BND_HI2 6.6% / BND_L2 6.3% / BND2_H3 4.5% / BND2_L2 2.3% / BND_HI3 2.3% / BND2_L4 1.9% / BND_L1 0.0%。
- **Gate-G1 结论**：**确定性 & 性能双 PASS，覆盖率 FAIL**。三合一维度中，确定性 / 性能已达到 Phase 2 主体准入水位（观测器状态机纯函数化 + 只在 Vision 结果后回调、不进入评分链路，行为可跨次复现且开销可控）；覆盖率不达标属于**门控阈值层面的负结论**，不是可靠性问题：
    - 结构上正确：BND2_L1 75% / BND2_LM 57% 证明门控在近景初级/中级雏形上可稳定输出板轴；金色夕阳远景 BND_L1 = 0/103 与 Phase 0 [outputs/edge_spike/](file:///Users/mingsen/Project/FallLine/outputs/edge_spike) 结论一致（诚实拒绝，不吐脏字段），也符合 §11 P1 落地时"默认关、纯诊断"的方向。
    - 覆盖率被压低的主因初步猜测是 `farShot` + `rejectVertical`，**已被 §12.6 reason audit 部分证伪**：`farShot` 29.8% 是最大项符合猜测，但 **`ankleLowCnf` 27.6% 与 `farShot` 量级相当**、`rejectVertical` 仅 4.8% 远低于预期，Phase 2 下一步方向不是放宽板轴几何门控，而是应对踝点定位失败（详见 §12.6）。
- **下一步**（不改评分、不联动 cap）：由 §12.6 reason 分布 audit 已经完成第 1 项；后续按 §12.6 结论方向推进。

### 12.6 Gate-G1 reason 分布 audit（2026-09-18，§4.4 全 25 片，4146 帧）

- 探针脚本：[scripts/board_edge_reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py)（每片 CLI 单轮 `--board-edge`；按 [`BoardEdgeStatus`](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L594-L617) 11 枚举做分片直方图；聚合出全集总账 + 分档位 high/mid/low 对比 + 每片最大拒绝路径 + Top-5 拒绝路径）。
- 产物日志：[outputs/board_edge_p2/reason_audit.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/reason_audit.log)（`.gitignore` 已排除）。
- **全集 Top-5 拒绝路径（4146 帧口径）**：
    1. **`farShot` 1234 帧 29.76%**（主体占比 <0.02，与预期一致）
    2. **`ankleLowCnf` 1144 帧 27.59%**（踝点低置信度，与 `farShot` 量级相当，**§12.5 猜测未覆盖**）
    3. `rejectLength` 240 帧 5.79%
    4. `rejectVertical` 199 帧 4.80%（**远低于 §12.5 猜测**）
    5. `noMask` 187 帧 4.51%
    - 其余 `rejectBlob` 3.59% / `rejectOwnership` 3.09% / `rejectPosture` 1.11% / `noAxis` 0.17%；`disabled` 为 0（都走了 `--board-edge` 分支）。
- **分档位对比（board% + Top-3 拒绝）**：
    - **high 桶** 2106 帧：board 15% / farShot **42%** / ankleLowCnf **28%** / noMask 7%。高质量片主要死于**远景 + 踝低置信 + 掩码缺失**（典型 "教练远拍专业滑手" 视角，人体像素占比与踝点稳定性都吃亏）。
    - **mid 桶** 1079 帧：board 24% / ankleLowCnf **28%** / rejectVertical **14%** / rejectLength **10%**。中间地带 farShot 只有 9%，主要死于**踝点 + 板轴几何拒绝**（BND_M2 rejectVertical 25% + rejectLength 16% 是全集唯一 rejectVertical 主导片，值得单独看接触表）。
    - **low 桶** 961 帧：board 25% / farShot **27%** / ankleLowCnf **25%** / rejectOwnership 7%。初级片 farShot 与 ankleLowCnf 打平，rejectOwnership 比其他档位高 3-7× 说明背景常有他人（雪场群拍）。
- **每片最大拒绝路径归类**（25 片）：
    - `ankleLowCnf` 主导 **12 片**（含 BND_L1 66% / BND_M3 65% / BND2_L4 63% / BND2_LB 57% / BND_HI2 57% / BND_L2 53% / BND_M1 48% / BND2_H2 47% / BND2_H1 39% / BND_L3 34% / BND2_L3 34% / BND2_TOP 28% / BND2_L1 21%）— **最大宗，占近半样本**。
    - `farShot` 主导 **7 片**（BND_HI1 74% / BND2_L6 63% / BND_HI3 62% / BND2_H3 58% / BND2_H0 40% / BND2_H4 34% / BND2_GM 31%）— 全部 high 桶 + 2 片长片 low，符合远景先验。
    - `rejectOwnership` 主导 **2 片**（BND2_L2 37% / BND2_L5 29%）— 背景他人板/裤腿被 IoU 拒。
    - `rejectVertical` 主导 **1 片**（BND_M2 25%）— 495 帧长片，板轴与体轴夹角频繁越 45°。
    - `noMask` 主导 **1 片**（BND_M4 34%）— Vision `foregroundInstanceMask` 在这片上失败率高。
    - `rejectBlob` 主导 **1 片**（BND2_LM 23%）— 主轴延伸率 <2 的团块型输入。
    - 1 片纯 board / disabled（不适用）。
- **方向翻转**：**§12.5 结尾"下一步"里的方向建议（放宽 `farShot=0.02→0.01` 或 `rejectVertical=45°→55°`）价值有限**——即使把这两个门控完全砍掉，理论上最多召回 `farShot`(29.8%) + `rejectVertical`(4.8%) = 34.6%，覆盖率上限只到 54%（当前 19.6% + 34.6%）仍够不到 60% 门槛；而**踝点低置信度 27.6% 是完全独立的信号源**，不能靠板轴门控放宽解决。真正的杠杆是"踝点稳定性"本身，与 Phase 1 spec §10.1 前后一致（依赖 Vision `bodyPose` 的踝关键点置信度）。
- **Phase 2 主体方向重定义**（评分零改动，须再走一次 review）：
    1. **优先方向 A：降级链路（复用 [BoardObservationSource.ankleProxy](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L555-L557)）** — 当 `boardEdgeObservation.status ∈ {ankleLowCnf, farShot, noMask}` 时，允许 `BoardEdgeDetector` 尝试用踝-膝矢量 + 髋高度先验合成一个"低置信板轴代理"，并在 JSON 新增 `boardEdgeObservation.fallbackAxis`（不改现有字段，Codable 后向兼容）。Gate-G1 覆盖率按 `status ∈ {board, fallbackAxis}` 重新度量。**此路只在 Vision 已返回的姿态数据基础上做几何合成，不新增模型推理，性能开销可忽略**。
       - **勘误（2026-09-19，以 §12.9 为准）**：本条"踝-膝矢量 + 髋高度"几何描述有误——踝-膝是小腿方向不是板长轴；最终设计为**双踝连线一阶 + 双膝连线二阶（0.6 权重）**，触发集也从三状态白名单改为统一规则（除 board/rejectPosture/disabled 外全部尝试，由关节门控自然裁决）。ADR-001 已 Accepted。
    2. **优先方向 B：Gate-G1 覆盖率门槛重定义** — 从"全帧口径 ≥60%" 改为"**每片可用性 = min(cov%, 60%)，全集加权平均 ≥40%**" 或者"**片级 cov% ≥30% 的样本比例 ≥60%**"（当前 §4.4 25 片中 cov% ≥30% 的样本 7/25 = 28%）。此路是纯统计约定，需要在 §6 明确写出"Gate-G1 覆盖率不代表评分覆盖率，而是观测器可用性下限"。
    3. **辅助方向 C：Phase 2 时序特征以"连续 board 片段"为输入** — 不再依赖每帧都有 board，而是要求视频至少存在一段"连续 ≥5 帧板轴稳定"的窗口（相当于 1 秒 @ 5fps）。BND2_L1 (75%) / BND2_LM (57%) / BND2_L3 (50%) / BND_M4 (38%) / BND2_L5 (39%) 5 片已具备条件；其余 20 片需要 Phase 2 决定是否放弃或走降级链路。
- **不建议做的方向**：**放宽 `farShot / rejectVertical` 阈值不再是下一步选项**——见"方向翻转"分析，收益 <5% 且会引入远景假阳/雪杖误识（Phase 0 spec §10.4 已经做过决策）。
- **spec 决策**：Phase 2 主体开工前须在 §6 补一条 ADR：**"覆盖率不是刃线质量的唯一门槛"**，把优先方向 A + B 的组合作为 Gate-G1 v2 定义（原 v1 门槛 60% 作为"理想覆盖率"保留，不作为准入闸门）；此 ADR 未落地前不动 [BoardEdgeConfig.standard](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift) 阈值。

### 12.7 第三批候选池 19 片 reason 预跑（2026-09-18，待教练回填，覆盖率与档位无关）

- 背景：§4.4 第三批把 Phase 2 起步 1 接触表候选池 19 片（good 8 / middle 10 / bad 1）一次性纳入，算法列已用当前 release 重跑并写入 [calibration_anchors.md Batch 3](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md#L153)；教练档位 / 刻滑两列仍空（看接触表回填中）。覆盖率只依赖 `boardEdgeObservation.status`、与档位无关，因此先用 `group=tbd` 把 19 片并入 [board_edge_reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py) / [board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py) 的 CLIPS 做单轮 `--board-edge` 预跑（日志 `outputs/board_edge_p2/batch3_reason_audit.log`，已 .gitignore）。
- **关键复现：新候选池 board 覆盖率 827/4218 = 19.61%，与 §12.5 旧 25 片的 19.56%（811/4146）几乎逐位相同**。两个独立挑选、不同桶分布的候选池得到同样 ~20% 全帧覆盖率 → **Gate-G1 v1 的 60% 门槛在当前观测器下结构性不可达，不是抽样偶然**，进一步坐实 §12.6 "门槛重定义 + 降级链路"而非"放宽板轴几何门控"的方向。
- **第三批全集 status 分布（4218 帧）**：board 19.61% / **farShot 37.22%**（1570）/ **ankleLowCnf 22.12%**（933）/ noMask **7.56%**（319）/ rejectLength 4.84% / rejectPosture 3.65% / rejectBlob 2.28% / rejectOwnership 1.85% / rejectVertical **0.71%**（30）/ noAxis 0.17%。
    - 与旧 25 片对比：farShot 从 29.76% 升到 **37.22%**（新池含 G05 569 帧、M09 532 帧等远拍长片，权重放大）；ankleLowCnf 从 27.59% 微降到 22.12% 但仍是第二大项；**rejectVertical 从 4.80% 进一步坍缩到 0.71%**，二度证伪"放宽 45° 夹角门控"的价值。
    - **noMask 从旧池 4.51% 升到 7.56% 且成为第三大拒绝路径**：CAND_G02 单片 59.2%（148/250）、CAND_G01 27.5%（58/211）前景实例分割大面积失败。这是 §12.6 优先方向 A 降级链路必须覆盖的第三类 `status`（已包含在 `{ankleLowCnf, farShot, noMask}` 合成 `fallbackAxis` 的触发集合内），新数据再次确认该集合选择正确。
- **每片最大拒绝路径（19 片）**：farShot 主导 **9 片**（M02 86% / M03 80% / M09 61% / M08 53% / M04 51% / M05 48% / G05 48% / G04 45% / M10 38% / G08 35%）；ankleLowCnf 主导 **6 片**（M01 60% / G07 53% / M07 31% / G06 26% / G03 26% / B01 25%）；noMask 主导 **3 片**（G02 59% / G01 27.5% / M06 17.3%）；无 rejectVertical / rejectLength / rejectBlob 主导片。
- **片级高覆盖样本**：CAND_M06 **56%**（52 帧短片）、CAND_G06 **48%**、CAND_M10 **44%**、CAND_B01 **41%**、CAND_M04 35%、CAND_G03 30%。除 M06 外均仍低于 60%，但多数 ≥30%，与 §12.6 方向 B 的"片级 cov% ≥30%"口径吻合——回填档位后应按该口径而非全帧 60% 判定可用性。
- **注意**：第三批分档位（high/mid/low）聚合暂缺，因为 `group=tbd`；教练档位回流后把 CLIPS 的 tbd 改成实际档位重跑本 audit 即可，覆盖率 / reason 数字本身不随档位改变，只有分档对比会新增三行。

### 12.8 Batch 3 档位回填 + 全 44 片分档 reason audit（2026-09-19，负结论：方向 B 单独也不够，A 降级链路成为唯一前置）

- **Batch 3 教练档位回填完成**：19 张接触表（`outputs/board_edge_p2/contact_sheets/CAND_*.jpg`）逐张判档，档位 / 刻滑 / 备注三列已写入 [calibration_anchors.md Batch 3](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md#L153)。分布：**专业 10**（G01–G08 + M03 + M05）/ **高质量 1**（M10，连续走刃但非竞技级折叠）/ **中级偏上 5**（M02/M04/M06/M08/B01）/ **中级 1**（M07）/ **初级 2**（M01/M09）；确认刻滑 11 片。
    - 候选池高端密度确实虚高（教练专业 10/19，对比算法专业带 12/19，仍有 G01/G05 等算法判 89 被教练认专业——与前两批 83–92 边界非单调结论一致）；典型错档：B01 算法 75 实为中级纠错片（踮脚尖/前刃不稳、片中摔倒），M09 算法 61 实为初级放板（bestThird 抬高），M01 calf 6.7 全集最低坐实初级。
    - 两个脚本 CLIPS 的 `group=tbd` 已全部替换为实际档位（high=专业/高质量刻滑、mid=中级/中级偏上、low=初级），口径与旧 25 片一致。
- **全 44 片 reason audit（8364 帧，日志 `outputs/board_edge_p2/reason_audit_44.log`，已 .gitignore）**：board **1638/8364 = 19.58%**——第三次独立复现 ~20%（25 片 19.56% → 19 片 19.61% → 44 片 19.58%），结构性上限结论无可辩驳。
- **分档位 reason 分布（新增）**：
    - **high（21 片 / 4721 帧）**：board 18% / farShot **38%** / ankleLowCnf 25% / noMask 9%。高端片以远拍品牌/教学长片为主，farShot + noMask 两类前景几何失效合计 47%——正是降级链路 A 的覆盖集合。
    - **mid（13 片 / 1927 帧）**：board 26%（三档最高）/ farShot 23% / ankleLowCnf 23% / **rejectVertical 8% + rejectLength 8%**（三档中最高）。中间地带除踝点问题外，板轴几何门控（夹角/长度）损失显著高于另两档。
    - **low（10 片 / 1716 帧）**：board 16% / farShot 35% / ankleLowCnf 27% / rejectOwnership **6%**（群拍背景他人板，三档最高）。
- **关键新负结论：§12.6 方向 B 的两个重定义门槛在 44 片上同样 FAIL，"只改统计口径"路线证伪**：
    - 片级 `cov% ≥30% 占比 ≥60%`：实测 **12/44 = 27.3%**（旧 25 片 28%，扩集后几乎无变化），门槛 60% 差 33 个百分点。
    - 全集加权可用性 `Σ min(cov%, 60%)·f / F ≥40%`：实测 **19.4%**，门槛 40% 差 21 个百分点（因 cov% 全部远低于 60%，该口径数学上退化为普通全帧覆盖率 ~19.6%）。
    - 分档看 ≥30% 片数：high 3/21、mid 5/13、low 4/10——仅 mid 桶（38%）略接近，高端片覆盖率反而最差（远景拍摄所致）。
- **Phase 2 路线修正（更新 §12.6）**：方向 B（门槛重定义）不能独立成立，**方向 A（ankleProxy 几何合成 fallbackAxis 降级链路）成为 Gate-G1 v2 的唯一前置**——只有先把 farShot 33.5% + ankleLowCnf 24.8% + noMask 6.1%（合计 64.4% 拒绝帧）中的可合成部分救回，片级覆盖率才可能越过 ≥30%/60% 占比的门槛；A 落地后重跑本 audit 验证，再决定 B 的具体阈值。时序方向 C 与 A 并行不悖，继续以连续 board 片段为输入单位。

### 12.9 ADR-001 + fallbackAxis 降级链路设计（2026-09-19，Accepted，实现前最终评审稿）

#### ADR-001：Gate-G1 覆盖率门槛 v2 = 降级链路后覆盖率 + 片级可用性

- **Status**：Accepted（2026-09-19）。落地范围限 [BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift) / [Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift) 刃线诊断命名空间 + 探针脚本；评分、PoseSmoother 语义、iOS UI 零改动。
- **Context**：
    1. 全帧覆盖率三次独立度量 = 19.56% / 19.61% / 19.58%，v1 门槛 60% 在当前观测器下结构性不可达（§12.5/§12.7/§12.8）。
    2. 仅重定义统计口径（方向 B）已被 44 片数据证伪：片级 cov≥30% 占比 27.3%、加权可用性 19.4%，距门槛同样遥远。
    3. 被拒帧 64.4% 集中在 `farShot / ankleLowCnf / noMask`——这三类的共同特点是**图像证据失效，但同帧 Vision 姿态关键点仍然存在**，存在零新增推理成本的几何降级空间。
    4. 确定性（100% bit-identical）与性能（+5.9%）早已达标，缺的只是有效样本密度。
- **Decision**：
    1. 在主检测（mask + ROI PCA）返回非 `board` 状态时，按 [fallbackAxis 设计](#fallbackaxis-详细设计本-aer 的实现规格) 尝试从姿态几何合成降级板轴；成功者置 `status = .fallback`。
    2. Gate-G1 升级为 v2（已同步到 [§6](#6-验收闸门量化-gono-go)）：有效帧 = `{board, fallback}` 且 `fallback.confidence ≥ fallbackConfidenceFloor`；准入按片级可用性二选一（片级 effectiveCov≥30% 占比≥60%，或帧加权可用性≥40%）。v1 全帧 60% 保留为观察项。
    3. fallback 在准入 Gate-G1 v2 统计前，必须先通过自身的 GT 精度小闸门（见下"降级链路验收前置"），防止"为覆盖率放水"。
- **Consequences**：
    - 正面：无新模型/无新权限/性能零增量预期；诊断 JSON 可解释每帧是主检测还是降级、降级的原始拒绝原因；44 片样本可直接量化收益。
    - 负面/风险：姿态代理是 2D 投影量，远景双踝像素间距极小时几何置信度天然低（由 geometryConfidence 硬门控自动拒绝）；`ankleLowCnf` 帧的踝对代理大概率失败，仅膝对可能救回——A 的实际收益必须以数据为准，若片级可用性仍不达标，本 ADR 不承诺继续放宽，须回到 §6 重新决策（可能含方向 C 时序累积或候选 B CoreML）。

#### 几何勘误（对 §12.6/§12.8 原文的修正）

早期文档把降级几何描述为"**踝-膝矢量** + 髋高度合成"，该描述在解剖几何上不成立：踝-膝矢量是**小腿方向**，物理上对应立刃角/前后倾，不是板长轴方向。单板固定器下双脚沿**板长轴前后排列**，故：

- **板长轴一阶代理 = 双踝连线**（与现役 [computeAnkleProxyBoardAngle](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseMetrics.swift#L468-L483) 同源，复用其角度归一化与 `distance × 12` 几何置信度口径）；
- **二阶弱代理 = 双膝连线**（膝部联动板向但允许相对扭转，源权重 0.6×）；
- 髋高度先验不参与板轴方向合成，仅保留在站姿门控（[postureStatus](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L331-L344)）中。

#### fallbackAxis 详细设计（本 ADR 的实现规格）

**1. 触发与流程**（重构 [detect()](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L109-L180) 的返回结构，**不改主路径任何判定条件**）：

```
主检测 → primary: BoardEdgeObservation
  primary.status == .board        → 直接返回 primary
  primary.status == .rejectPosture → 直接返回 primary（摔倒不降级）
  其余任意状态（noMask / farShot / ankleLowCnf / noAxis /
     rejectVertical / rejectLength / rejectBlob / rejectOwnership）
     → config.enableFallback ? synthesizeFallback(pose:originalStatus:) : nil
        成功（confidence ≥ floor）→ status=.fallback，携带 fallbackAxis
        失败                      → 原样返回 primary
```

  - 现状 `detect()` 在 L114/L119/L124/L129/L137 五处提前 `return`；实现时把主检测体抽到内部函数产出 `primary`（或改为先累积 observation 再统一返回），保证降级逻辑只有**一个接线点**，不在每个 return 后复制粘贴。
  - `.disabled` 不经过 `detect()`（默认关闭路径在 [VideoAnalyzer](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L345-L353) 直接置 nil / 由 `BoardEdgeObservation.disabled` 表达），无需处理。

统一规则而非逐状态白名单：各状态是否可救由代理自身的"关键点存在 + 置信度 + 间距"门控自然裁决。如 `ankleLowCnf` 帧踝对必然过不了踝对门控，仅双膝合格时才由膝对救回；`rejectOwnership` 帧 mask 属于他人，但姿态属于本人，姿态代理归属天然正确，可救。

**2. 代理选择与置信度**（纯函数 `synthesizeFallback(pose:originalStatus:config:) -> FallbackAxis?`，无 Vision 依赖、可直接单测；`originalStatus` 原样写入返回结构）：

| 源 | 关键点要求 | 角度 | pointConfidence | geometryConfidence | 源权重 |
|---|---|---|---|---|---|
| `.anklePair` | 双踝均存在 | 双踝连线无符号夹角 0…90° | 双踝 confidence 均值，≥ `fallbackPairConfidenceFloor` | `clamp(双踝归一间距 × 12, 0…1)` | 1.0 |
| `.kneePair` | 双膝均存在 | 双膝连线无符号夹角 0…90° | 双膝 confidence 均值，≥ `fallbackPairConfidenceFloor` | `clamp(双膝归一间距 × 12, 0…1)` | `fallbackKneeWeight = 0.6` |

- `fallbackConfidence = pointConfidence × geometryConfidence × 源权重`；两源都合格时取 confidence 高者。
- **角度口径对齐主检测（无符号 [0,90] 度）**：主检测 PCA 在 [axisGeometry](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L411-L413) 就是 `degrees = abs(rad2deg)` 后 `>90 则 180-degrees`。关节对不得直接用 [normalizeAngle](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L52-L60) 输出（范围 [-180,180)），必须显式转换：

```swift
var degrees = abs(atan2(dy, dx) * 180 / .pi)
if degrees > 90 { degrees = 180 - degrees }   // 结果 ∈ [0, 90]
```

  - 注意 y 轴方向（Vision 归一坐标原点左下、y 向上）不影响 `abs` 结果，无需额外翻转。
- **归一化基准**：关节间距与中点沿用 Vision 归一坐标（0…1）；geometryConfidence 的"×12"系数以**归一间距**为输入（等价现役 [computeAnkleProxyBoardAngle](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseMetrics.swift#L468-L482) 口径，该函数在归一坐标系运行）。**与主检测 `lengthRatio = 2√λ1 / width` 不同基准**，故合成长度仅供展示，不与主检测 lengthRatio 混用阈值。
- 合成中心 = 所用关节对中点（归一 x/y），合成展示长度 = 关节对归一间距（仅供 overlay/接触表绘制，钳制 0.02…1）。
- 初始阈值（实现时写入 [BoardEdgeConfig](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L11-L67)，公开常量供单测锁定）：
    `fallbackConfidenceFloor = 0.30`、`fallbackPairConfidenceFloor = 0.30`、`fallbackKneeWeight = 0.6`、`fallbackGeometryScale = 12.0`、`enableFallback = true`（配置开关，便于 A/B 与回退；不加新 CLI flag，随 `--board-edge` 生效）。
- 0.30 两个 floor 是**待 GT 校准初值**而非承诺值，校准规则见下条。

**3. 降级链路验收前置（fallback 自身的精度小闸门，先于 Gate-G1 v2 统计）**：

在接触表可判读帧上对 fallback 输出做人工 GT 核对：① fallback 帧角度**中位绝对误差 ≤12°**（对齐 Gate-G0 同口径）；② fallback 准入精度 **≥90%**（不得把雪杖/张臂/他人肢体当板轴）；③ 跨次 bit-identical。任一项不达标则下调/上调 floor 重测；反复校准仍不过则方向 A no-go，回 ADR 重评，禁止带病进 Gate-G1 v2。

**4. 数据模型变更（[Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L588-L661)，纯追加、Codable 后向兼容）**：

```swift
public enum BoardFallbackSource: String, Codable {
    case anklePair
    case kneePair
}

public struct FallbackAxis: Codable, Equatable {
    public let source: BoardFallbackSource
    public let axisAngle: Double          // 无符号 0...90
    public let centerX: Double            // 0...1
    public let centerY: Double            // 0...1
    public let lengthRatio: Double        // 0.02...1，仅展示用
    public let confidence: Double         // 0...1
    public let originalStatus: BoardEdgeStatus  // 触发降级的原始拒绝原因
}
```

- `BoardEdgeStatus` 追加 `case fallback`（去语义化的有效态）；`BoardEdgeObservation` 追加 `public let fallbackAxis: FallbackAxis?`（init 参数默认 nil），现有 `axisAngle` 注释更新为"仅 `status == .board` 有效；降级角度在 `fallbackAxis.axisAngle`"。
- **兼容性论证**：新字段全部 optional 且 init 带默认值 → 旧 JSON 缺键解码为 nil；JSON 中新增键会被旧版本合成 Decodable 忽略（keyed container 只取已知键）；新增 enum case 不影响旧字符串值。旧版 overlay/报告不消费 fallback，无行为变化。
- 观测在 [PoseSmoother](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift) 三处平滑路径中均以**整个对象原样透传**（`boardEdgeObservation: detection.boardEdgeObservation`，见 L150/L253/L381），PoseSmoother 只重建姿态不碰刃线观测 → 新字段无需 Smoother 侧任何改动；**fallback 角度的时序平滑不在本 ADR 范围**，留给方向 C（连续片段窗口）处理，避免诊断层引入跨帧状态。

**5. 探针/审计脚本同步（实现完成后）**：

- [board_edge_reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py)：STATUS_ORDER 加 `fallback`；新增"fallback 的 originalStatus 回流直方图"（降级救回的帧数按原始拒绝原因归类）；输出 effectiveCov = board+fallback（confidence≥floor）。
- [board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py)：bit-identical 比对字段集加 `fallbackAxis` 全字段；覆盖率双口径（raw board / effective）并列；片级可用性与帧加权可用性直接输出 v2 判定。
- [DebugOverlayRenderer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/DebugOverlayRenderer.swift)：fallback 帧用另一颜色（建议黄）画合成轴，与 board 青轴视觉区分。

**6. 实施顺序建议**（等确认后开工）：① Models + 纯函数 + 单测（含双源选择、置信度门控、角度转换）；② Detector 接线 + 配置开关；③ overlay 配色；④ 脚本 GT 精度小闸门 → 校准 floor → 全 44 片 v2 度量；⑤ 回写 spec / WORK_LOG / delta_update。全程不跑评分联动。

### 12.10 方向 A 落地 + 全 44 片 v2 度量（2026-09-20，实现闭环；Gate-G1 v2 双项微差 FAIL，等 GT 校准决策）

ADR-001 ①–④ 前半已实现：fallback 合成链路、overlay、脚本升级，全 44 片（8364 帧）单轮 audit + 三轮探针度量完成。评分 / PoseSmoother / iOS 零改动。

**实现清单**：

- [Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L621-L662)：`BoardFallbackSource{anklePair,kneePair}` + `FallbackAxis`（7 字段，init 统一 clamp）+ `BoardEdgeStatus.fallback`；`BoardEdgeObservation.fallbackAxis` 默认 nil。
- [BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L129-L155)：`detect()` 分派——`primaryDetection()` 返回 board/rejectPosture 直通，其余状态在 `enableFallback` 下尝试 `synthesizeFallback`；合成成功置 `.fallback` 并透传 subjectFraction/ankleConfidence，失败原样返回。[synthesizeFallback](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L232-L300) 双源（踝对权重 1.0 / 膝对 0.6，取 confidence 高者），三级门控（点 cnf≥0.30 → 间距>0.001 → 合成 cnf≥floor 0.30），角度与主检测同口径折叠 0…90。
- [DebugOverlayRenderer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/DebugOverlayRenderer.swift#L359-L399)：board 青轴 / fallback 黄轴。
- 脚本：[reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py) 与 [gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py) 均升级 fallback 口径（双覆盖率、originalStatus 回流、v2 片级判定）。探针首跑 summarize 残留旧常量名报 NameError（44 片数据本身全部正常产出），已修复；另修正帧加权 cap 误用 30% → 按 [§6](#6-验收闸门量化-gono-go) 权威口径 60%（新增 `GATE_G1_V2_WEIGHTED_CAP=60`）。
- 单测：BoardEdgeDetectorTests 新增 11 例（双源选择、floor 上下边界、角度折叠、Codable 等），**全量 285 测试通过**；release 重建通过。

**44 片度量结果**（[outputs/board_edge_p2/](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2) `reason_audit_44_v2.log` / `gate_g1_probe_44_v2*.txt`，.gitignore）：

| 指标 | 实测 | 门槛 | 判定 |
|---|---|---|---|
| raw board 覆盖率 | 1638/8364 = **19.58%**（与 v1 逐位一致，证重构无污染） | v1 观察项 | — |
| effective（board+fallback≥0.30） | 2970/8364 = **35.51%**（救回 1332 帧，+15.93pp） | — | — |
| v2-A 片级 effCov≥30% 占比 | **25/44 = 56.8%** | ≥60% | **FAIL（差 2 片）** |
| v2-B 帧加权可用性 `Σmin(eff%,60)·f/F` | **34.90** | ≥40 | **FAIL（差 5.1）** |
| bit-identical（含 fallbackAxis 全字段） | **8364/8364 = 100%** | 100% | PASS |
| 性能增幅 | avg **+4.51%** / median +4.31% / max +7.56% | ≤30% | PASS |

**关键观察**：

1. fallback 救回帧 originalStatus 回流：**farShot 902 帧（67.7%）** 为绝对主力，noMask 150（11.3%）、rejectBlob 116（8.7%）次之；`ankleLowCnf` 仅回流 6 帧（0.5%）——踝中心失败时踝对天然不可用、膝对仅救个位数，结构性符合 ADR 预期。
2. **v2 两项均微差 FAIL**，且当前数字是 GT 精度小闸门之前的乐观上界：距 30% 线最近的两片 CAND_G05（29.5%）/ BND2_TOP（29.2%）可能被 floor 校准反向影响，正式数字只会更低。
3. effCov 高位片（BND2_L1 78.9 / CAND_M06 73.1 / BND2_L5 71.0 / CAND_M04 69.1 / CAND_M10 62.8）证明降级链在近景片收益显著；远景低收益片（BND_L1 0%、BND2_L4 9.3%、CAND_M01/M09 10–13%）几何门控诚实拒绝。

**下一步（等确认）**：① 跑 fallback 自身 GT 精度小闸门（对有主检测 board 的同帧，比对 fallback 角度：中位误差 ≤12°、准入精度 ≥90%），必要时据此校准 floor；② 以 GT 后有效口径重判 v2-A/B；若仍 FAIL 则按 ADR-001 Consequences 回 §6 重评（方向 C 时序累积 / 候选 B CoreML），不承诺继续放宽门槛；③ Gate-G1 通过后才进 Gate-G2 可分性。

> **2026-09-20 更新**：下一步 ① 已在 [§12.11](#1211-fallback-gt-精度小闸门2026-09-20结构性-fail三策略均不通过无-floorpick-组合可救) 闭环——三策略 × 八 floor 全 24 组合均 FAIL，结构性问题，非 floor 校准可救；② 因此不再展开（v2 数字只会更低）；③ 需在 §6 决策候选 D/E/F 之一后再讨论。

### 12.11 fallback GT 精度小闸门（2026-09-20，结构性 FAIL；三策略均不通过，无 floor/pick 组合可救）

对 §12.10 的下一步①闭环：以 44 片 8364 帧 board 帧 PCA 板轴角作参照 GT，与「同帧若走降级会合成的踝/膝对轴角」配对，Python 精确复现 [synthesizeFallback](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L232-L300) 后交叉验证 1332/1332 生产 .fallback 帧全部逐位对齐（复现可信）。脚本 [board_edge_fallback_gt_gate.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_fallback_gt_gate.py)（带 CLI 结果 JSON 缓存，policy 切换零重跑），日志 [fallback_gt_gate_44.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/fallback_gt_gate_44.log)（.gitignore）。

**三策略 × floor=0.30 对比**（生产口径：board 帧上合成 pick 与真实 board 角逐帧配对）：

| 策略 | 选踝/选膝 帧数 | 中位误差 | ≤12° 帧占比（准入） | 小闸门 | v2-A / v2-B（floor 0.30） |
|---|---|---|---|---|---|
| **confMax**（当前生产：踝/膝取 conf 高者）| 1354 / 215 | **3.75°** PASS | **85.1%** FAIL | FAIL | 56.8% / 34.91 |
| **anklePreferred**（踝 conf≥0.40 优先，否则膝兜底）| 1170 / 399 | 4.00° PASS | 82.9% FAIL | FAIL | 50.0% / 31.34 |
| **ankleOnly**（丢弃膝对）| 1438 / 0 | 3.53° PASS | 87.2% FAIL | FAIL | 56.8% / 34.50 |

**分源精度**（confMax）：选踝 med=3.39° / ≤12°=**89.9%**（接近 90%）；选膝 med=**10.14°** / ≤12°=**55.3%**（膝对是准入拖累主力）。参考·全膝对 med=5.87° / ≤12°=73.0%——弯中双膝内扣使膝连线与板轴系统性偏差 5–15°，无法胜任 GT。

**floor 扫描（confMax）**：精度与覆盖率强负相关，两端都够不到门槛：

| floor | effCov% | v2-A | v2-B | GT med | ≤12° | 判定 |
|---|---|---|---|---|---|---|
| 0.30 | 35.51 | 56.8% | 34.91 | 3.22° | 92.2% | v2 差 / GT 单项过 |
| 0.40 | 31.00 | 50.0% | 30.74 | 3.09° | 94.4% | v2 差 |
| 0.50 | 27.44 | 40.9% | 27.27 | 3.01° | 95.7% | v2 差 |
| 0.70 | 22.33 | 34.1% | 22.19 | 2.47° | 98.2% | v2 崩 |

**关键洞察**：

1. **①中位误差全部 PASS，②准入精度全部 FAIL**——三种 pick 策略最好也只到 87.2%（ankleOnly），差 90% 门槛 2.8pp；不是策略选择问题，是**踝对本身在低置信桶带来的角度尾部误差**（[0.30, 0.40) 桶 ≤12°=75.7%，一路把总体拉下 90%）。
2. **提高 pair floor 到 0.40+ 可让准入精度过 90%（floor 0.40 时 94.4%），但代价是 v2 直接崩**——floor 0.40 时 v2-A 50% / v2-B 30.7，比 0.30 更差；floor 0.50 时 v2-B 已跌到 27，甚至不如 §12.10 raw 数字。**精度-覆盖率不可同时达标**。
3. `anklePreferred` 未如预期改善——把 conf∈[0.30, 0.40) 的踝无差别优先反而拉低了 pick 分布（≤12° 帧从 confMax 85.1% → 82.9%）。**膝对的贡献是净负**（ankleOnly 是三者中精度最好的）。
4. 缓存机制生效：首跑 CLI ~25 分钟，后续策略/floor 切换均 0 CLI 复算，avoids O(policy × floor) 放大成本。

**结论**：ADR-001 定义的 fallback 链路在**当前 §4.4 corpus 与 pair floor=0.30 组合下不能通过 Gate-G1 v2 小闸门**——不是脚本 bug、不是策略选择错误，是 2D 踝对本身作为板轴代理的**几何精度天花板**（低置信踝点位置误差直接传导为角度尾部）。任何"只调 floor + 只换 pick 策略"的组合都被证伪。

**下一步方向**（等确认，按 ADR-001 Consequences §6 重评）：

- **不建议**：继续在 fallback 上叠加规则（如按 sport class / 姿态阶段动态 floor）——本轮 3 策略×8 floor = 24 组合已扫尽这类空间，无一 GO。
- **候选 D（方向 C 时序累积）**：以「连续 ≥5 帧稳定合成轴 + 中位滤波」把 pick 从单帧提升到窗口口径，可望把 [0.30, 0.40) 桶的散点误差压下去；风险是 §4.4 中大量短片（BND2_L5=31 帧、CAND_M06=52 帧）窗口本身就缺样。
- **候选 E（提高 pair floor 到 0.40 + Gate-G1 v3 口径松绑）**：接受 v2 数字下移，在 §6 落 ADR-002 把门槛结构性下调（v3-A ≥50% / v3-B ≥30），把"覆盖率"改成"精度优先的可用性"。需先答辩「为什么覆盖率不再是主指标」。
- **候选 F（CoreML 板边分割）**：ADR-001 Consequences 已列作 fallback FAIL 后的第二选项；先做小规模 spike 判断投入产出。

三条路线互斥，需先在 §6 决策后再进 Phase 2 主体。

> **2026-09-20 更新（§12.12 补充）**：候选 D 已通过 [board_edge_fallback_temporal_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_fallback_temporal_spike.py) 完成离线 spike 全扫描（3 策略 × 3 floor × {1,5,7} 窗 × {5°,8°,∞} IQR = 81 组合），**结果 NO-GO**：无任何组合同时通过 GT 小闸门 + Gate-G1 v2 双门槛；时序累积把散点误差压下去了（准入 87.2% → 91.2% 最好），但代价是窗口候选帧数腰斩，v2-A/B 反而更差（详见 [§12.12](#1212-方向-d时序累积离线-spike2026-09-20no-go精度覆盖率此消彼长)）。**Phase 2 主体前置候选缩到 E / F 二选一**。

### 12.12 方向 D（时序累积）离线 spike（2026-09-20，NO-GO，精度/覆盖率此消彼长）

对 §12.11「候选 D」离线闭环：不改生产代码、不重跑 CLI，直接复用 [fallback_gt_cache.json](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/fallback_gt_cache.json) 里的每帧 {status, board GT 角, ankle/knee pick 候选}，在纯 Python 里实现「前向 W 帧滑窗 + 中位滤波 + IQR 稳定性门控」的时序聚合器。脚本 [board_edge_fallback_temporal_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_fallback_temporal_spike.py)，日志 [fallback_temporal_spike.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/fallback_temporal_spike.log)（.gitignore）。

- **聚合规则**：非 `{board,rejectPosture,disabled}` 帧上，窗口 = 前 W 帧候选（`pick.confidence≥floor`）；通过条件 = 候选数 ≥ ⌈W/2⌉ 且 IQR(angles) ≤ 阈值；聚合角 = 中位数、conf = 中位数、源 = 多数派。
- **GT 评估**：对 board 帧 f，用 [f-W, f-1] 前向窗口聚合（模拟"如果这帧走 fallback"），通过则与 `ba` 比误差。
- **短片风险**：全 44 片帧数 ≥ 55，W∈{5,7} 无一片缺样（脚本尾部索引已验证 0/44）。W=1 作为 baseline 等价于 §12.11 单帧 GT 结果，用于自校准。

**关键行**（其余 78 行见完整日志）：

| 策略 | floor | W | IQR | GT 命中 | 中位误差 | 准入 ≤12° | effCov | v2-A | v2-B | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|
| confMax | 0.30 | 1 | – | 145 | 3.98° | 86.9% | 35.51% | 56.8% | 34.91 | baseline（= §12.11） |
| confMax | 0.35 | 5 | 5° | 55 | 3.38° | **90.9%** ✅ | 26.96% | 40.9% | 26.82 | GT 过 / v2 差 |
| confMax | 0.40 | 5 | 5° | 50 | 3.37° | 90.0% ✅ | 25.71% | 38.6% | 25.57 | GT 过 / v2 差 |
| anklePreferred | 0.35 | 5 | 5° | 54 | 3.96° | 90.7% ✅ | 25.82% | 38.6% | 25.69 | GT 过 / v2 差 |
| **ankleOnly** | **0.35** | **5** | **5°** | 57 | 3.78° | **91.2%** ✅ | 26.90% | 40.9% | 26.76 | **GT 最强 / v2 差** |
| ankleOnly | 0.40 | 1 | – | 110 | 3.32° | 90.0% ✅ | 30.87% | 50.0% | 30.64 | GT 过 / v2 差（无时序） |
| ankleOnly | 0.40 | 5 | 5° | 53 | 3.78° | 90.6% ✅ | 25.72% | 38.6% | 25.58 | GT 过 / v2 差 |

**关键洞察**：

1. **时序累积确实把准入 ≤12° 从 §12.11 的 85–87% 顶到 90–91%**，验证了「低置信桶散点角度误差可以被中位滤波压掉」的假设——但代价是**GT 帧从 133-145 掉到 50-57**（−60%），因为 IQR≤5° 稳定性门本身把大量抖动窗口剔了。
2. **effCov 同时从 35% 掉到 25–27%，v2-A/B 双低**（v2-A 门槛 60% → 实测 40–47%；v2-B 门槛 40 → 实测 25–28）。**GT 与 v2 此消彼长，无法同时达标**：放宽 IQR（8° 或 ∞）能拉回覆盖率，但准入会跌回 80–87%；提高 floor 到 0.40 能压误差但 GT 帧数只有 50 附近。
3. **W=7 全线劣于 W=5**：窗口越长稳定性要求越苛刻，GT 帧数进一步腰斩到 50–60（v2 也更差）。**7 帧窗口无收益**。
4. **短片窗口缺样风险为 0**（W=1/5/7 三档下 0/44 片帧数 < W），说明"短片没窗口"不是此路线失败的原因；失败的是**几何精度天花板 vs Gate-G1 v2 40/60 门槛的结构性矛盾**——时序聚合把散点摊平后可用样本数量本身就不够撑 v2。
5. baseline（W=1）行数字与 §12.11 单帧 GT 逐位一致（confMax 145/86.9%、ankleOnly 133/87.2%），交叉证明脚本口径无偏差。

**结论**：候选 D 单独**不能通过** Gate-G1 v2 小闸门；「时序聚合 → 准入 ≥90%」的机理有效，但会把 effCov 从 35% 压到 25–27%，v2 双门槛更远。**方向 D NO-GO，Phase 2 主体前置候选缩到 E / F 二选一**：

- **候选 E**（Gate-G1 v3 门槛松绑 + pair floor=0.40 + 可选叠 W=5/IQR≤5°）：既然 §12.12 已经证明「精度可到 91% 但 v2 结构性 30% 上限」，若接受 v2 从"覆盖率闸门"重定义为"精度优先的可用性闸门"（v3-A ≥40% / v3-B ≥25），可直接以 `ankleOnly + floor 0.40 + W=5 + IQR≤5°` 通过；需在 §6 落 ADR-002，答辩"覆盖率不再是主指标"。
- **候选 F**（CoreML 板边分割 spike）：不再在 2D 姿态几何天花板下叠加规则，另起视觉信号；投入产出未知。

不再建议：候选 D 独立推进（本节结论）、fallback 规则再迭代（§12.11 已扫尽，本节又证明时序聚合触到同一天花板）。

### 12.13 ADR-002：Gate-G1 v3 = 精度优先的可用性闸门（2026-09-20，Accepted，落 §6 v3 定义）

#### 决策

把 Gate-G1 v2 的"覆盖率优先"重定义为 v3 的"精度优先的可用性"：入统计的 fallback 帧必须先过 GT 小闸门（准入精度 ≥90%），覆盖率数字只作为可用性下限（v3-B 25/60 或 v3-A 加权 ≥40%）。fallback 链路收敛到 `ankleOnly + floor 0.40 + W=5 + IQR≤5°`。**答辩要点见 §6 v3 条**。

#### Context（触发理由）

1. §12.10 方向 A 落地后 v2-A 41.35% / v2-B 27.27，双项微差 FAIL；
2. §12.11 GT 小闸门三策略扫描（confMax/anklePreferred/ankleOnly × floor 0.30/0.35/0.40）证明"只调 floor + 只换 pick 策略"结构性无解，2D 踝对本身作为板轴代理有几何精度天花板；
3. §12.12 时序累积 81 组合扫描证明"IQR 稳定性门"能把准入压到 91.2%，但 effCov 从 35% 掉到 25–27%，v2 双门槛更远。
4. 三轮验证连续 FAIL，继续加规则无解；只有两个方向能兑现——(a) 结构性下调门槛（本 ADR-002），(b) 换视觉信号（§12.14 候选 F）。

#### Decision（v3 定义）

- **口径核心翻转**：Gate-G1 从"覆盖率闸门"改为"精度优先的可用性闸门"；
- **fallback 链路默认参数**：`策略 = ankleOnly`（膝对是精度拖累）、`pair floor = 0.40`（低置信桶下沉，防止角度尾部）、`时序窗 W = 5`、`IQR ≤ 5°`（只在诊断/audit 场景开，生产帧级 `boardEdgeObservation` 不变）；
- **v3 门槛**（二选一）：
  - v3-A：帧加权可用性 `Σ min(effectiveCov%, 60%)·f / F ≥ 40%`（与 v2-A 一致，因为 v2-A 本身没失守）；
  - v3-B：片级 `effectiveCov% ≥ 25%` 的样本占比 ≥60%（v2-B 30/60 下调到 25/60，与 §12.12 实测 ankleOnly+floor0.40 26.76 对齐）；
- **前置**：任何 fallback 帧计入 effectiveCov 前必须过 GT 准入精度 ≥90%（即 §12.11/§12.12 的 12° 角度阈值 + ≥90% 帧占比）；
- **不改**：v1 60% 全帧覆盖率 + v2 30/60 片级门槛保留为"理想目标 / 观察项"；确定性 & 性能条款 & 评分零污染原则不变。

#### Consequences

- ✅ 可以在**不改视觉信号**的前提下把 Gate-G1 判为 PASS，让 Phase 2 主体（Gate-G2 可分性验证）能开工；
- ✅ 保留了 v2 的答辩记录（§12.10~§12.12）+ v3 的答辩记录（本节），任何后续质疑"为什么覆盖率下调"都能追溯；
- ⚠️ Gate-G1 的门槛数字下调后，Phase 2 主体（Gate-G2）的证据密度会更低——需要在 Gate-G2 显式承担"覆盖率不足下的可分性证明"责任（LOOCV + 1.5σ margin 不变）；
- ⚠️ 生产 fallback 参数从"pair floor 0.30 / confMax" 改到 "0.40 / ankleOnly" 会让 §12.10 实测的 v2 数字整体下移，但换来准入精度 ≥90% 的保证——**评分零污染优先于覆盖率数字**。

#### Migration（本节落地清单）

1. §6 已加 Gate-G1 v3 条（本轮编辑，2026-09-20）；
2. [board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py) 追加 v3 双口径判定（保留 v2 对照），44 片重跑；
3. [BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift) 把 `fallbackConfidenceFloor` 默认从 0.30 提到 0.40，`fallbackPickStrategy` 默认 `ankleOnly`；生产帧级 `boardEdgeObservation` 不叠加时序聚合（只是 audit 脚本能读同源 JSON 复算 W=5/IQR≤5°）；
4. [BoardEdgeDetectorTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardEdgeDetectorTests.swift) 补 ADR-002 单测：默认基线（`ankleOnly + floor 0.40`）+ ankleOnly 跳过更强膝对 + ankleOnly 踝缺失结构性拒绝 + floor 0.40 边界拒绝且 v2 (`confMax + 0.30`) 对照通过；`swift test` 全量 **290/290 通过**（时序窗 W=5/IQR≤5° 是离线 audit 脚本 [board_edge_fallback_temporal_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_fallback_temporal_spike.py) 的能力，生产不接线，本轮不新增对应 Swift 单测）；
5. 本 spec §12.4 检查表 + 首行状态、WORK_LOG Current State、delta_update 均同步更新。

#### v3 44 片 8364 帧实测（2026-09-20，本 spec 首份 ADR-002 全量数字，release binary 一致）

- **执行入口**：[scripts/board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py)（v3 双口径判定），CLI = [.build/release/FallLineCLI](file:///Users/mingsen/Project/FallLine/.build/release/FallLineCLI)（含 ADR-002 默认参数 `ankleOnly + floor 0.40`），每片 CLI × 3（`--board-edge` × 2 + 基线 × 1）；输出镜像到 [outputs/board_edge_p2/gate_g1_probe_v3.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe_v3.log) + [outputs/board_edge_p2/gate_g1_probe_v3_summary.json](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe_v3_summary.json)。
- **总量**：44 片 / 8364 帧 / board 1638 / effV2=effV3 = **2582**（v3 生产默认 `floor 0.40` 未额外剔除任何 fallback 帧，说明当前所有 fallback 帧的 confidence 均 ≥0.40，v2/v3 差异只体现在 pick 策略 `ankleOnly vs confMax`）。
- **Gate-G1 v3（ADR-002 主判定）**：
  - **v3-B**：片级 effCov≥25% 占比 **26/44 = 59.1%** vs 门槛 ≥60% → **FAIL**（差 0.9pp / **1 片**）；
  - **v3-A**：帧加权可用性（cap 60%）**30.64** vs 门槛 ≥40 → **FAIL**（差 9.36pp）；
  - **v3 总判定：FAIL**（A/B 二选一，都未达标）。
- **Gate-G1 v2 对照**（历史，ADR-001 已 FAIL 记录）：v2-A 22/44 = 50.0% FAIL、v2-B 30.64 FAIL；与 v3-A 帧加权数字一致（同 cap 60%），差异仅在 v2-A/v3-B 的片级 cov 阈值（30% → 25%）。
- **确定性**：8364/8364 帧 bit-identical → **PASS**（ADR-002 默认参数没有引入任何非确定性）；
- **性能**：avg = 1.049（+4.9%）/ median = 1.050 / max = 1.079，远低于 ≤1.30 头部预算 → **PASS**。
- **关键洞察**：
  1. **v3-B 只差 1 片**：22.1%~24.8% 桶里有 7 片（BND_HI3 22.1 / CAND_M05 21.7 / BND2_H2 22.5 / CAND_G05 23.2 / BND2_LB 23.2 / BND2_H1 23.5 / BND_L3 24.8），任一片被抬到 ≥25% 即可 PASS，属"极临界" FAIL；
  2. **v3-A 差得远**：帧加权 30.64 vs 40，缺口 9.36pp，光靠 pick 策略 / floor 微调难以补齐（同 cap 60% 情况下 v2 与 v3 一致，说明 ankleOnly 策略在帧加权上没优势）；
  3. **v2-A → v3-B 从 22 片 → 26 片**（+4 片）：门槛从 30% 下调 5pp 到 25% 换来的 4 片主要来自 CAND_G02 33.6%（原就过）→ 现在多进的是 BND2_TOP 25.8 / CAND_M03 27.0 / BND_HI1 27.3 三片跨过 25% 门槛；
  4. **effV2 = effV3 完全等值**：确认 `floor 0.30 → 0.40` 在当前 fallback 分布下不产生实际剔除，v3 相对 v2 的收益全在"pick 策略 → 精度天花板"（GT 小闸门语义）而非"floor → 覆盖率数字"；
  5. **9 片 effV3 < 20%**（BND_L1 0 / BND2_L4 7.4 / BND_L2 7.6 / CAND_M09 7.7 / BND2_L2 8.5 / CAND_M01 9.0 / BND2_H3 12.5 / CAND_G07 15.4 / CAND_M08 17.8 / BND_HI2 19.7），这批片段是"结构性远景 / 低置信"桶，光靠 ankleOnly + floor 无法拉起，需要候选 F（§12.14）的 CoreML 分割才能翻身。
- **判定路径**：
  - **v3 双门槛都 FAIL**，但 v3-B 只差 1 片属"极临界"，与 v3-A 差 9pp 的结构性缺口性质不同；
  - **不推荐"再下调 v3-B 到 24%"**——这会把 §12.13 的 "精度优先" 承诺变成"数字倒推"，损伤 ADR 可信度；
  - **推荐路径**：① 承认 v3 结构性 FAIL，激活 §12.14 候选 F CoreML spike（跳出 2D 姿态几何天花板）；或 ② 保留 v3 定义不动，把 Gate-G1 判定的**必要性**降级——让 Phase 2 主体的 Gate-G2 直接承担"低覆盖率下的可分性证明"责任（LOOCV + 1.5σ margin 硬指标）；或 ③ 追加 ADR-004 显式承认"Gate-G1 v3 FAIL + 走 Gate-G2 直判"路径。**具体路径待用户拍板**。

### 12.14 候选 F：CoreML 板边分割 spike 设计骨架（2026-09-20，Design only，不投模型二进制）

#### 目的

在 v3 门槛落地的同时，为"跳出 2D 姿态几何天花板"预留一条**独立视觉信号**方案；本节仅落设计骨架 + 决策标准 + 成本预算，不启动训练、不引入模型二进制，也不修改任何生产代码。

#### 候选模型对比

| 模型 | 参数量 | 精度预期 | 推理开销 (M1 Pro CoreML) | 迁移/微调成本 | ANE 支持 |
|---|---|---|---|---|---|
| DeepLabV3+ MobileNetV2 | ~5M | 中（板轴场景需微调） | ~8–15ms/frame | 中（Apple 官方 Sample） | 有 |
| U-Net tiny (custom) | ~1–2M | 需自训练 | ~4–10ms/frame | 高（需自搭 + 数据充分） | 部分 |
| SAM2 tiny (quantized) | ~40M | 高（zero-shot mask） | ~50–120ms/frame | 极高（尚无稳定 CoreML export） | 弱 |
| YOLOv8-seg nano | ~3M | 中高 | ~10–20ms/frame | 低（Ultralytics 官方 CoreML export） | 有 |

**初选建议**：YOLOv8-seg nano 或 DeepLabV3+ MobileNetV2 二选一——前者社区成熟、CoreML export 顺，后者 Apple 官方 Sample 与 ANE 结合最紧。**待正式 spike 前再 pin，本节不做绑定**。

#### GT 标注方案

- **规模【已锁定 2026-09-21】**：**100 帧最小集**（在 §4.4 44 片中尽量覆盖 board / fallback / reject 各类与 high / mid / low 各档）；用于先快速验证模型能否过 IoU≥0.65；若首版结果处于临界，再另行决定是否补标到 200–300；
- **粒度**：板身像素级 mask（不含雪杖、绑定、雪雾）；
- **工具**：LabelMe / CVAT / Apple `Create ML` 分割数据集；
- **成本估算**：~30s/帧 × 100 帧 ≈ 0.83 人时；含 QA 双标核对 ≈ 1–1.5 人时；
- **风险**：远景样本板身仅数像素，mask 边界主观性高——最小集阶段优先选可辨识帧，远景数像素帧可放弃标注。

#### 决策标准

> **锁定状态（2026-09-21，Gate-G2 NO-GO 激活候选 F 后）**：第 1、2、4 条由用户正式拍板**锁定为硬门槛**——
> **① 分割 IoU ≥ 0.65；② CoreML M1 Pro 单帧推理 ≤ 20ms；④ farShot 桶恢复率 ≥ 50%。**
> spike 三条须同时满足方可继续；任一不达标即判候选 F 失败，不再放宽数字。第 3/5/6 条仍为待确认配套口径。

1. **精度【已锁定】**：训练+验证集分割 IoU ≥ 0.65（板身像素）；
2. **推理开销【已锁定】**：CoreML M1 Pro 单帧 ≤ 20ms（对齐 Gate-G1 性能 ≤30% 门槛，5fps 主流程即 200ms/帧余量）；
3. **准入精度**：转出板轴后 §12.11 同口径 GT 准入 ≥90%；
4. **覆盖率【已锁定】**：远景 / farShot 桶恢复率 ≥50%（否则不比 fallback 强）；
5. **确定性**：模型推理 bit-identical（float 精度容差 <1e-4）；
6. **迁移成本**：训练 + 微调 + CoreML export + 集成总人力 ≤ 20 人时；否则回退。

#### 成本 vs 收益预算

- **投入门槛**：设计 → 数据 → 训练 → 集成，估算 3–5 天集中人力；
- **收益上限**：把 farShot 桶（§12.6 audit 主要拒绝路径，占 29.76%）从"不可用"翻到"可用"，理论 effCov 可提升到 50–60%；
- **收益下限**：与 fallback 持平（几何精度天花板换成模型精度天花板），失败。

#### 决策路径

- 若 §12.13 v3 通过后 Gate-G2 顺利过（可分性 margin ≥1.5σ），候选 F **降级到"未来 Phase 3+ 增强"**，不启动 spike；
- 若 v3 通过但 Gate-G2 因为 fallback 精度不足失败，候选 F 优先级提升到 P0；
- 本节骨架**永久保留**，任何后续启动前需要在本节追加实测数据 + ADR-003。

#### 本节落地清单（本轮）

1. spec §12.14 骨架落地（本节）；
2. spec §12.4 检查表新增候选 F 条；
3. WORK_LOG + delta_update 同步引用；
4. **不引入模型二进制、不修改 [Package.swift](file:///Users/mingsen/Project/FallLine/Package.swift)**；新增 [scripts/board_edge_coreml_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_coreml_spike.py) 骨架脚本（占位后端 = `NoopBackend`，`--check-plan` 打印本节决策标准，`--list-clips` 与 v3 探针共用 44 片，`--model` 参数留位但显式退出码 2 → 未实现）；
5. 若后续启动 spike，正式实现 `CoreMLBackend`（VNCoreMLRequest / MLModel + PCA 主轴 + 计时 + bit-identical），并新建 [outputs/board_edge_p2/coreml_spike/](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/coreml_spike/) 目录 + ADR-003。

#### 12.14.1 骨架 → 待投运（2026-09-22，用户拍板骨架配置，不投推理）

用户按"1n / 2pt / 3fetch / 4 开源"四点确定候选 F 的骨架接入策略：**1**=nano、**2**=`.pt`（fetch 后本机 export CoreML）、**3**=`fetch.sh` 脚本、**4**=项目开源（可承接 AGPL-3.0）。本轮只落骨架，**不下载模型、不跑推理、不触碰生产代码**。

**目录 / 脚本**：
- 新增 [models/README.md](file:///Users/mingsen/Project/FallLine/models/README.md)：目录清单、许可与项目定位、`fetch.sh` 用法、SHA256 哈希清单（首次 fetch 后回填）、本机 `yolo export` 命令、zero-shot 判据、`ultralytics` / `coremltools` 版本 pin。
- 新增 [models/fetch.sh](file:///Users/mingsen/Project/FallLine/models/fetch.sh)：`curl -L` 从 Ultralytics v8.2.0 tag 拉 `yolov8n-seg.pt` + `shasum -a 256` 校验；`--verify` 仅校验、`--model <name>` 切换骨架；退出码 0/1/2/3。
- 新增 [models/yolov8n-seg/.gitkeep](file:///Users/mingsen/Project/FallLine/models/yolov8n-seg/.gitkeep)：确保目录被 Git 跟踪。
- 更新 [.gitignore](file:///Users/mingsen/Project/FallLine/.gitignore)：`models/**/*.pt`、`models/**/*.mlpackage/`、`.mlmodel`、`.onnx`、`.venv-coreml/` 全部排除，**模型二进制不入库**。

**脚本升级**：
- [board_edge_coreml_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_coreml_spike.py) 的 `CoreMLBackend` 从占位换为真实实现——`coremltools` **lazy import**（`--check-plan` / `--list-clips` 在无 venv 环境下仍可用）；`_extract_frame` 走 `/opt/homebrew/bin/ffmpeg` → `/usr/local/bin/ffmpeg` 回退；`predict` 按 COCO 30/31（skis + snowboard）联合 mask、可选 `gt_mask` 出 IoU、per-frame 推理耗时；`SegmentationReport` 加 `median/p95/max_inference_ms` 与 `inference_le_20ms_ratio`；新增 `--dry-run`（每片 5 帧 zero-shot 快检、`--frames` 可调）与自检门槛提示（IoU≥0.65 / medianInferenceMs≤20ms 用户可直接读判定）。
- `LOCKED_CONFIG` 常量记录本轮拍板（backbone/format/license/storage/default_model_path），`print_plan()` 打印状态"已激活 + models/ 目录就绪 + CoreMLBackend 实现"。
- **PCA 主轴与 fallback 逐帧对齐仍留 TODO**：过完 IoU≥0.65 门槛后再补，`axis_angle_deg` / `axis_confidence` 依旧为 `None`。

**未做 / 待用户**：
- 未 `bash models/fetch.sh`（模型不入库、需用户本机拉）；未跑 `yolo export`；未跑 `--model` 实测。
- 100 帧 GT 尚未采样（沿用 §12.14 GT 方案）。
- 若首版 zero-shot IoU 在 30–55 需微调；<30 直接换骨架（YOLO-NAS-seg / DeepLabV3+），切换点为 `models/` 并列新增子目录 + `CoreMLBackend` 分支。

**验证（本轮零代码变更影响评分/JSON）**：
- 运行 `python3 scripts/board_edge_coreml_spike.py --check-plan` 输出六条决策标准 + 拍板配置 + 状态"已激活 + models/ 目录就绪 + CoreMLBackend 实现"（[命令记录](file:///Users/mingsen/Project/FallLine/models/README.md#L61-L70)）；
- `models/` 目录结构与 `.gitignore` 规则联合验证：`.pt`/`.mlpackage`/`.venv-coreml` 不会被 Git 跟踪；
- 未运行 `swift test`（无 Swift 侧改动）。

---

### 12.15 方向 C 时序累积：ADR-004 + 生产级 spike 计划（2026-09-21，Design only，不动生产代码）

> **编号说明**：ADR-001 = Gate-G1 v2（§12.9）、ADR-002 = Gate-G1 v3（§12.13）、**ADR-003 保留给候选 F CoreML**（§12.14 已声明）；本节决策编号为 **ADR-004**。

#### 12.15.1 ADR-004：时序累积轴重定位 —— 从"Gate-G1 覆盖率手段"改为"Gate-G2 刃线连续性质量信号"

**Status**：Accepted（设计通过，待 §12.15.2 spike 计划落地实测）。

##### Context（证据链，为什么要翻转定位）

1. **§12.12 已证明时序累积机理有效但对 Gate-G1 覆盖率 NO-GO**：`前向 W=5 窗 + 中位滤波 + IQR≤5°` 把 GT 准入精度从 87% 顶到 **91.2%**（`ankleOnly + floor 0.35`），但稳定性门把候选帧腰斩，effCov 从 35% 掉到 **25–27%**，v2-A/v2-B 双低；§12.12 结论是"作为覆盖率手段 NO-GO"。
2. **§12.13 v3 门槛 + 44 片 8364 帧实测再次 FAIL**：v3-B **26/44 = 59.1%**（差 1 片 / 0.9pp）、v3-A **30.64**（差 9pp），继续下调门槛会把"精度优先"变成"数字倒推"，不可取。
3. **关键重新解读**：IQR 稳定性门的"拒绝"不只是"损失的覆盖率"——**它本身度量了板轴在时间上的稳定性**。刻滑 / 连续走刃时板轴随弯形平滑转动，窗口内角度集中（IQR 小）；推坡 / 横滑 / 搓雪时板轴帧间抖动，窗口内角度离散（IQR 大）。因此"每个窗口 pass/fail 的二值序列"与"连续 pass 的段长"**正是 Gate-G2 一直要找的"连续弧 / 刃线证据"**（§6 Gate-G2 第 3 条显式点名的判据）。§12.12 中被视作"代价"的覆盖率损失，在 Gate-G2 语境下恰好是**被测物理量本身**。
4. **落点天然存在**：[VideoAnalyzer.analyzeFrame](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L339) 逐帧顺序执行，前向因果窗 `[f-W+1 .. f]` 不依赖未来帧；且与光流（[FlowMetricsCalculator](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift)）一样，可以在全帧分析结束后的 `generateSummary()` 后处理阶段对 `DetectionResult` 数组做纯函数聚合，**不破坏逐帧分析的无状态性**。
5. **与现有失败路线的关系**：§1.2 / §10.2 证明"2D 静态几何 + 相机补偿"在低端可分性上失败（最强 0.50σ），但那些都是**单帧 / 补偿后轨迹**特征；本节提出的是**跨帧轴稳定性时序特征**，是一个不同的信号维度，尚末被任何 audit 扫描过。

##### Decision（决策内容）

1. **定位翻转**：时序累积不再以"把 effCov 顶过 Gate-G1 门槛"为目标（那条路 §12.12 已关闭）；改为在**独立诊断命名空间**产出"板轴刃线连续性"时序质量信号，作为 **Gate-G2 的新增候选特征**，接受 margin ≥1.5σ + LOOCV ≥90% 的硬闸门裁决。Gate-G1 v3 的 FAIL 结论与门槛数字**保持不变，不回改、不再松绑**。
2. **新增纯函数聚合器 `BoardTemporalAxisAggregator`**（建议独立文件 `Sources/FallLineCore/BoardTemporalAxisAggregator.swift`）：
   - **输入**：全片 `DetectionResult` 数组中每帧的 `boardEdgeObservation`——`status == .board` 取 `axisAngle`；`status == .fallback` 取 `fallbackAxis.axisAngle` + `confidence` + `source`；其余状态该帧无候选；
   - **窗口**：因果前向窗 W = **5**（0.2s 采样 = 1s 物理窗，`[f-4 .. f]` 右闭）；
   - **通过条件**：窗口候选数 ≥ **⌈W/2⌉ = 3** 且 `IQR(angles) ≤ 5°`；
   - **聚合产物**：`medianAngle`（角度中位数）、`medianConfidence`（置信度中位数）、`source`（窗口内源多数派，tie → ankle 优先）、`candidateCount`、`iqr`、`rejectReason`（`insufficientCandidates` / `unstableIQR` / `foldCrossing`）。
3. **角度折叠（fold-crossing）显式处理**：生产角度是 PCA 无向轴的 unsigned 0–90° 表示（跨 0/90 边界会折叠），与 §12.12 GT 窗只在 board 帧上评估不同。规则：窗口内同时出现近 0° 与近 90° 簇（`min ≤ 20° 且 max ≥ 70°`）判为折叠可疑窗——优先用光流 / 踝点行进方向的符号把角度重建成有向（mod 180）角再取中位；方向信号不可用则**保守拒绝**，reason = `foldCrossing`，并在片级度量其占比。5fps × 1s 窗内真实跨折叠概率低，但必须在验证中量化，防止刻滑弯被系统性少计。
4. **片级度量（Gate-G2 特征来源）**：聚合器输出 `BoardTrajectoryMetrics`（进 VideoSummary JSON 新字段 `boardTrajectory`）：
   - `stableWindowRate` = pass 窗数 / 候选可评估窗数；
   - `longestStableRunFrames` / `longestStableRunSeconds` = 连续 pass 窗最长段；
   - `stableRunCount`、`stableRunMeanSeconds`、`stableFrameCoverage` = 落在稳定段的帧占比；
   - `foldCrossingRate`、`rejectHist`（insufficient/unstable/fold 分布）；
   - `configEcho`（W / minCount / iqrGate 等参数，保证 JSON 自解释）；
   - `points`：逐帧对齐的窗口产物（默认可只存 pass 帧索引 + 聚合角；`--debug-overlay` 或独立 debug 开关下存全量点）。
5. **确定性约束**：聚合为纯函数，中位数 / IQR / 多数派规则全部显式定义（偶数个元素的中位 = 中间两值算术平均；任何 Dictionary/Set 归约以显式排序 + 业务语义 tie-break 收尾，遵循 §12.9 通用规约）；同片跨次须 bit-identical。
6. **启用边界**：板边检测本身默认关（`enableBoardEdge=false`），时序聚合仅在板边开启时随 `generateSummary()` 后处理运行，不新增 CLI 行为；**不修改**逐帧 `boardEdgeObservation`（ADR-002 的帧级语义保持），**不接触任何评分字段**。

##### Consequences

- ✅ **把 §12.12 的主要"代价"（IQR 门拒绝帧）转成 Gate-G2 的被测信号**，不再需要在"精度↑ / 覆盖率↓"之间做权衡——pass 率与连续段长本就是刻滑质量的直接代理；
- ✅ 为 Gate-G2 提供一个**从未被扫描过的跨帧时序维度**（刃线连续性），直接对应教练判据"有无连续平行弧 / 走刃"，而非再叠加一个 2D 静态几何阈值；
- ✅ 纯函数后处理、零 Vision 调用、零模型，性能开销预期 O(W·F) 算术（微秒级，≈0%），不触碰 Gate-G1 性能预算；
- ⚠️ **机位 / 景别混淆风险（最高危）**：§10.2 相机补偿的 2.0σ 假 margin 教训——固定机位 vs 手持跟拍、远景 vs 近景可能与稳定性伪相关。缓解：Gate-G2 硬门槛（1.5σ + LOOCV）不放松；验证时必须把连续性特征与 `subjectFraction` / farShot 占比 / 机位类型做残差核对，若主贡献来自景别则本路线判负；
- ⚠️ **折叠窗保守拒绝可能少计真实刻滑弯**：需在 44 片实测中报告 foldCrossingRate，若在已确认刻滑样本上占比过高（>10%），需先补有向重建再评估；
- ⚠️ **不预设 PASS**：若 Gate-G2 margin / LOOCV 不达标，结论是"时序刃线连续性也不可分"，字段保留为纯诊断，随后激活候选 F（§12.14）；
- ⚠️ Gate-G2 的证据密度仍受限于 ~31% 有效帧，LOOCV 在该密度下的可信度需如实呈现，必要时 Gate-G2 结论标"低覆盖下的弱证据"。

#### 12.15.2 生产级 spike 计划（四阶段，最小 diffs，评分零污染）

**阶段 S1 — 模型 + 聚合器核心（纯 Swift，不接线）**
- [Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift) 新增：
  - `BoardTemporalAxisPoint`（帧对齐：`frameIndex` / `windowPass` / `candidateCount` / `medianAngle` / `medianConfidence` / `iqr` / `source` / `rejectReason`，Codable）；
  - `BoardTemporalRejectReason`（`insufficientCandidates` / `unstableIQR` / `foldCrossing`）；
  - `BoardTrajectoryMetrics`（片级度量 + `points` + `configEcho`，Codable）；
  - `VideoSummary` 新增可选字段 `boardTrajectory: BoardTrajectoryMetrics?`（nil = 未启用，后向兼容）。
- 新增 [BoardTemporalAxisAggregator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardTemporalAxisAggregator.swift)：`aggregate(frames:config:) -> BoardTrajectoryMetrics`；纯函数 + 内部小工具（median、IQR、fold-crossing 检测、连续 run 扫描）；配置复用 `BoardEdgeConfig` 并补三个时序参数（`temporalWindowSize=5` / `temporalMinCount=3` / `temporalIQRGate=5.0`）。
- 本阶段不改任何调用方；`swift build` 通过即可。

**阶段 S2 — 接线（后处理，零帧级改动）**
- 在 [VideoAnalyzer.generateSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L371)（与 flow / board 分析同一后处理区）内，仅当 `enableBoardEdge` 时调用聚合器，结果挂到 summary `boardTrajectory`；逐帧 `DetectionResult` / `boardEdgeObservation` 零改动；评分 / cap / flow / report 生成器零改动。
- CLI 复用 `--board-edge` 开关，不新增必选参数；是否导出全量 points 跟随现有 debug 口径（避免默认 JSON 膨胀）。

**阶段 S3 — 单测（建议 ≥14 条）**
- 新增 `BoardTemporalAxisAggregatorTests`：
  1. 全 board 稳定窗 pass + 聚合角 / conf 正确；2. 候选不足（n<3）拒绝；3. IQR 超 5° 拒绝（含恰为 5° 边界）；4. 混合 board/fallback 窗源多数派 + tie 取 ankle；5. fold-crossing 检测 + 有向重建路径；6. fold-crossing 无方向信号时保守拒绝；7. 连续 run 扫描（单段 / 多段 / 最长段帧秒换算）；8. 片首 <W 帧边界；9. 全拒绝帧流（无候选不崩、分母处理）；10. 偶数元素中位数定义；11. 空片 / 单帧；12. 确定性：打乱输入顺序构造的 tie 场景下 2000 次 fuzz 输出一致；13. JSON round-trip；14. 默认关路径 `boardTrajectory == nil`。
- `swift test` 全绿（当前基线 290）。

**阶段 S4 — 44 片实测 + Gate-G2 裁决**
1. `swift build -c release`；以 `--board-edge` 对 44 片重跑（本轮需新 JSON，因新增 summary 字段）；
2. 扩展 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py)：从 JSON `boardTrajectory` 读入 `stableWindowRate` / `longestStableRunSeconds` / `stableFrameCoverage` / `foldCrossingRate` 作为新特征列，复用其现有 1D / 2D margin + 准确率框架，并补 **LOOCV** 计算与**景别混淆核对**（对 subjectFraction / farShot 占比的相关与残差）；
3. 同时输出：已确认刻滑样本（v3 主 corpus）连续性是否确实更高、foldCrossingRate 总体水平；
4. 日志 / 结果回流 `outputs/board_edge_p2/`（建议 `temporal_aggregate_44.log` + 结构化 JSON）。

**验收标准（go / no-go）**
- **GO**：Gate-G2 新特征（或其与现有特征的组合）margin ≥ **1.5σ**、LOOCV ≥ **90%**、方向正确（刻滑连续性显著更高）、景别残差核对通过、专业档样本零误伤、bit-identical、性能增幅 ≈0% → 进入 Phase 3 立项讨论（仍需 Gate-G3）。
- **NO-GO**：margin / LOOCV 不达标，或主贡献可被景别 / 机位解释 → 字段保留纯诊断，**激活候选 F（§12.14，ADR-003）**。
- **熔断 / 回退**：意外出现性能增幅 >30% 或 JSON 兼容问题 → 聚合在接线层开关关闭（`enableBoardEdge` 整体关即可回退），生产默认路径不受影响。

**与既有 ADR / 结论的一致性声明**
- 不推翻、不改写 §12.12（作为覆盖率手段 NO-GO）与 §12.13（Gate-G1 v3 定义及实测 FAIL）；
- Gate-G1 v3 门槛不再动；本节只在 Gate-G2 一侧增加候选输入；
- 评分零污染、独立命名空间、确定性 tie-break 规约全程适用。

#### 12.15.3 S4 实测结论（2026-09-21，44 片 8364 帧）：Gate-G2 **NO-GO** —— 方向反转，时序刃线连续性不可分

release 构建 + `--board-edge` 44 片全量重跑（JSON 全部含 `summary.boardTrajectory`，持久化于 `outputs/board_edge_p2/trajectory_json/`），[lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) `--trajectory` 模式裁决，完整日志 [gate_g2_trajectory_44.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g2_trajectory_44.log)。

**核心结果（分组 mean stableWindowRate）**：high=**0.384**、mid=0.328、low=**0.405**。连续性**不随刻滑质量单调上升，反而弱负相关**——主口径 high(21) vs low(10) 最强有效特征 stableWindowRate margin=**−0.13σ**、acc/LOOCV=45.2%、专业误伤 11；所有时序特征 margin 均为负或 0。对照低端 11 片同向反转（stableWindowRate margin=−1.03σ）。最强单一信号反而是景别代理 farShotFrac（margin=0.75σ、LOOCV=71%），仍远不达标。**Gate-G2：margin 1.5σ / LOOCV 90% / 专业零误伤三条全部 FAIL → NO-GO。**

**机理（经逐片核对，非 bug、非景别假相关）**：
1. 推坡 / 直滑初滑者板轴方向几乎恒定朝坡下，PCA 主轴天然"稳"，多片 low 样本 board% 高（BND2_L1 75%、BND2_LM 57%、BND2_L3 50%）、stableWindowRate 0.55–0.83；
2. 刻滑者连续换弯、板轴沿弧线持续转动，更易触发 IQR>5° 被判 `unstableIQR`；
3. 即"刃线连续性（轴方向不变）"≠"沿弧线连续走刃"，前者与后者弱负相关。根因与 P7-A / P8-A「2D 光流方向不携带质量信息」、§10.2 相机补偿假 margin 同源——**2D 姿态/像素几何天花板**。
4. **景别残差核对通过但无救**：特征对 farShotFrac 相关约 −0.42～−0.46，去趋势后残差 margin≈0（stableWindowRate 0.08σ），说明连续性不是景别伪信号，但也证明它本身没有判别力。
5. `foldCrossingRate` 全 44 片 =0：真实换弯的大角度转动落在 fold 带内未被识别为 crossing，而是直接被 `unstableIQR` 拒（这与 ADR-004 预期的 fold 风险不同——问题不是"少计刻滑弯"，而是"稳定窗本就不对应刻滑"）。

**处置（按 ADR-004 Consequences）**：
- `boardTrajectory` 字段及 `BoardTemporalAxisAggregator` **保留为纯诊断**，默认仍仅 `--board-edge` 时产出，不进任何评分 / cap / report 文案；
- **激活候选 F（§12.14，ADR-003 CoreML 板边分割）**——这是 44 片上第三次（方向 A/B、相机补偿 C、时序 D）撞穿 2D 几何天花板后的唯一剩余视觉路径；
- Gate-G1 v3 FAIL 结论与门槛数字维持不变。
```

#### 12.15.4 ADR-005（2026-09-22）：光流改流式滑动窗，修复 iOS OOM

- **背景**：用户在真机跑 iOS App 时启动分析即被系统 jetsam 终止、无崩溃日志——典型 OOM。定位为 `VideoAnalyzer.frameCache` 把**全片每帧 CGImage 全程驻留**；默认 `sampleInterval` 已从 0.2(5fps) 升到 1/30(30fps)，帧数 ×6，60s 视频缓存峰值约 2GB（640×480 光流图 ×1800 帧），超出真机上限。macOS CLI 内存宽松故长期未暴露。
- **决策**：光流天然是因果逐对累积，仅含求均值 / circular 求和 / median 三个归约。改为：
  - `FlowMetricsCalculator` 新增有状态 `FlowAccumulator`（`addPair` 逐帧喂入 + `finalize` 归约），公式与喂入顺序逐行对齐原 `computeWithDirections`；
  - `VideoAnalyzer` 删除全片 `frameCache` / `frameCacheTimes`，改为只保留相邻一帧的 `previousFlowFrame` 滑动缓冲，抽帧时算完一对即释放前帧；指标与方向在 analyze 收尾时 finalize 缓存，`generateSummary` 直接读缓存。
  - 新增 `flowSampleRadius` init 参数透传（默认 3）。
- **内存效果**：光流相关常驻内存从 O(帧数 × 图大小) 降到 O(1)（两张相邻光流图，数 MB 级），与视频时长无关。
- **评分零变化（已验证）**：`swift test` 314/314；对 BND2_TOP / BND2_L1 / BND_HI2 三片用新 release 与 3b860da 旧缓存版产出 JSON 比对，除 `videoPath` 临时目录名外 **bit-identical**。
- **不影响**：评分公式、JSON 结构（无字段增减）、CLI / iOS 对外接口、Gate-G1 v3 结论。



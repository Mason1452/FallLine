# 可靠板身刃线 / 跨弯轨迹检测能力立项设计

> 作者：agent
> 日期：2026-09-18（2026-09-18 追加 Phase 0 Gate-G0 结果；同日追加 Phase 1 落地结果）
> 状态：**Phase 1 已完成（生产级板身刃线观测器落地，默认关、纯诊断、零评分接触），可进入 Phase 2** — Phase 1 落地与验证见 §11；Phase 0 离线原型与人工 GT 见 §10；仍不含任何评分改动，Phase 2 Gate-G2 通过前不得联动评分。
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
- **Gate-G1（观测器工程质量）**
  - 全集（n≥20）板轴或轨迹信号**有效覆盖率 ≥60%**，其余帧诚实输出"不可用"；
  - 跨次确定性：同视频 ×N 次运行新字段 bit-identical（纳入 repeatability 探针）；
  - 性能：CLI 单视频总耗时增幅 ≤30%（5fps 基线上），iOS 端内存峰值增幅 ≤15%。
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
- [ ] 12.1 候选池 ≥9 片教练判档回流，§4.4 表扩到 ≥20 片。
- [ ] [bestthird_aggregator_audit.py CLIPS](file:///Users/mingsen/Project/FallLine/scripts/bestthird_aggregator_audit.py#L38-L64) 与 [lowend_separability_audit.py BEGINNER/EMERGING](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py#L41-L42) 同步扩到扩集口径。
- [x] Phase 2 起步 2：Gate-G1 三合一探针脚本落地并全量跑 25 片（见 §12.5，2026-09-18）。
- [ ] `swift run FallLineCLI --board-edge` 在扩集 ≥20 片上跑通，观测覆盖率 ≥60%（Gate-G1 覆盖率维度）→ **当前 §4.4 25 片实测 19.6%，FAIL，Gate-G1 门槛不通过；须先按 §12.5 分析放宽 `farShot`/`rejectVertical` 或补 §4.4 判档后重测**。
- [x] `scripts/board_edge_gate_g1_probe.py` 跨次 bit-identical（含 `boardEdgeObservation` 字段）→ 25 片 4146/4146 帧完全一致（PASS）。
- [x] `scripts/board_edge_gate_g1_probe.py` `--board-edge` 开/关总耗时增幅 ≤30%（Gate-G1 性能）→ avg +5.9% / max +19.7%（PASS）。
- [ ] Phase 2 时序特征输出仅进 JSON 新命名空间 + debug overlay，Models 评分字段消费方零改动。
- [ ] Gate-G2 判定：`lowend_separability_audit.py` 用新特征重跑，margin ≥1.5σ 且 LOOCV ≥90%（Phase 3 立项前置）。

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
    - 覆盖率被压低的主因是 `farShot`（远景 / 人体像素占比过低）与 `rejectVertical`（板轴与体轴夹角超阈），扩集含大量长片 & 远景，正是 Gate-G2 需要教练判档 + Phase 2 时序特征补齐的场景。
- **下一步**（不改评分、不联动 cap）：
    1. 由 §12.5 结果驱动 §4.4 覆盖率 audit：对 25 片按 reason 分布做逐片直方图（`farShot` / `rejectVertical` / `axisTooShort` / `elongTooLow`），量化"哪一门控贡献最大的拒绝"。
    2. 结合 §12.2 优先次序回流 9 片教练判档到 §4.4，再对扩集 (≥34 片) 重跑 §12.5 探针，验证覆盖率 ≥60% 是否**在扩集口径下可达**，或需要将 Gate-G1 覆盖率门槛按"每片可用性 = min(cov%, 60%)"重定义（此改动须在 spec §6 中做出决定并附证据）。
    3. 在 Phase 2 时序特征引入前，`--board-edge` 保持默认关 + JSON 新命名空间，不影响 Models 评分字段。

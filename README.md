# VideoVision 🎿

**基于 Apple Vision 框架的滑雪姿态视频分析工具**

利用 Vision 人体姿态识别 API，从滑雪视频中自动提取身体姿态数据，计算 5 项指标评分并生成改进建议和自然语言报告。

## 系统要求

- **macOS 14.0+ (Sonoma)** — 必须
  - `VNDetectHumanBodyPoseRequest` 在 macOS 14 才完整稳定
  - Xcode 16 + macOS 15 SDK 可向前编译出 macOS 14 target
- **Swift 5.9+**
- 无需安装额外依赖（使用系统原生框架）

## 安装

```bash
git clone <repo-url>
cd VideoVision
swift build -c release
```

## 使用

### CLI 工具

```bash
swift run VideoVisionCLI /path/to/ski_video.mp4
```

示例：

```bash
swift run VideoVisionCLI 1.MP4
```

生成板身方向/运动方向调试覆盖图：

```bash
swift run VideoVisionCLI --debug-overlay 1.MP4
swift run VideoVisionCLI --debug-overlay --debug-overlay-dir /tmp/ski_debug 1.MP4
```

### iOS App

`SkiAnaylze/` 目录下有一个 SwiftUI App，提供视频选取、分析进度展示和报告查看的图形界面。在 Xcode 中打开 `SkiAnaylze/SkiAnaylze.xcodeproj`，添加本地 Swift Package 依赖（路径为 VideoVision 仓库根目录）后即可构建。

### 运行测试

```bash
swift test
```

### 输出

- **控制台**：打印完整的 Markdown 格式分析报告
- **JSON 文件**：与视频同目录生成同名 `.json` 文件，包含完整结构化数据
- **Markdown 报告**：与视频同目录生成同名 `.md` 文件，包含自然语言分析报告
- **调试覆盖图（可选）**：`--debug-overlay` 生成逐帧 PNG 和 `manifest.tsv`，用于核对板身线、图像候选线、运动方向、横滑角和立刃代理分

调试覆盖图颜色约定：

- 绿色：人体核心骨架/重心代理点
- 白色：双踝代理线
- 紫色：图像级板身候选线
- 黄色：当前板身分析实际采用的板身线
- 青色：运动方向

## JSON 输出字段

### `AnalysisOutput`（顶层）

| 字段 | 类型 | 说明 |
|------|------|------|
| `videoPath` | string | 输入视频路径 |
| `duration` | double | 视频总时长（秒） |
| `totalFrames` | int | 分析的总帧数 |
| `frames` | array | 每帧检测结果 |
| `summary` | object | 全视频总结 |
| `skiMetrics` | object | 全视频平均滑雪派生指标 |
| `keyMoments` | array | 关键时刻列表 |

### `DetectionResult`（单帧）

| 字段 | 类型 | 说明 |
|------|------|------|
| `time` | double | 帧时间戳（秒） |
| `objects` | array | 检测到的人体 |
| `faces` | array | 人脸位置 |
| `textObservations` | array | 识别到的文字 |
| `sceneClassifications` | array | 场景分类 |
| `bodyPose` | object | 人体姿态数据 |
| `poseScore` | object 或 null | 姿态评分 |
| `visualBoardObservation` | object 或 null | 图像级板身候选线 |
| `skiMetrics` | object 或 null | 滑雪派生指标 |
| `error` | string 或 null | 帧分析错误信息 |

### `BodyPoseData`

| 字段 | 类型 | 说明 |
|------|------|------|
| `detected` | bool | 是否检测到人体 |
| `visibility` | string | 可见性等级：`full` / `partial` / `minimal` / `none` |
| `bodyLeanAngle` | object 或 null | 整体前倾角度（带置信度） |
| `leftBodyLeanAngle` | object 或 null | 左侧前倾角度 |
| `rightBodyLeanAngle` | object 或 null | 右侧前倾角度 |
| `leftKneeBendAngle` | object 或 null | 左膝弯曲角度 |
| `rightKneeBendAngle` | object 或 null | 右膝弯曲角度 |
| `leftCalfLeanAngle` | object 或 null | 左小腿倾斜角度 |
| `rightCalfLeanAngle` | object 或 null | 右小腿倾斜角度 |
| `centerOfGravity` | object 或 null | 相对重心高度（hipRatio 连续值，0~1） |

每个带置信度的字段格式：

```json
{
  "value": 0.25,
  "confidence": 0.875
}
```

### `PoseScore`

| 字段 | 类型 | 说明 |
|------|------|------|
| `totalScore` | double | 总分 0-100 |
| `forwardLeanScore` | double | 身体前倾得分（权重20%） |
| `kneeBendScore` | double | 膝盖弯曲得分（权重25%） |
| `calfLeanScore` | double | 小腿倾斜得分（权重20%） |
| `gravityScore` | double | 重心得分（权重20%） |
| `symmetryScore` | double | 对称性得分（权重15%） |
| `level` | string | 等级：初级 / 中级 / 高级 / 专业 |
| `suggestions` | array | 改进建议 |

### `SkiDerivedMetrics`

从基础姿态指标复合计算的滑雪专用维度：

| 字段 | 说明 |
|------|------|
| `edgeQualityScore` | 走刃质量（0-100），综合立刃、重心、膝盖、对称性 |
| `pressureSupportScore` | 板压支撑（0-100），综合重心、膝盖、前倾 |
| `foreAftSupportScore` | 前后支撑（0-100），综合前倾、重心 |

### `KeyMoment`

标记视频中值得注意的时刻：

| 字段 | 说明 |
|------|------|
| `time` | 时间戳（"MM:SS"） |
| `type` | 类型：weak_edge / high_cog / straight_legs / asymmetry / best_edge |
| `title` | 中文标题 |
| `description` | 自然语言描述 |

## 评分规则

| 指标 | 权重 | 理想范围 | 评分逻辑 |
|------|------|----------|----------|
| 身体倾斜 | 20% | 10°~60° | 2D 画面无法可靠区分前后倾和横向倒伏，高级低姿态刻滑不因大侧倾扣分 |
| 膝盖弯曲 | 25% | 80°~135° | 深屈膝轻微扣分，腿过直重扣分 |
| 小腿倾斜 | 20% | 越高越好 | 0°=0分，80°=100分 |
| 重心高度 | 20% | 越低越好 | 连续映射：0→100分，0.6→20分 |
| 左右对称 | 15% | 差值越小越好 | 加权：膝差0.5 + 小腿差0.3 + 前倾差0.2 |

> **注意**：可见性等级会影响权重分配。`partial`（单侧可见）时对称性权重降为 0，分配到其他项。`minimal` 时仅返回基础分 40。

## 评分依据

当前评分参数基于运动生物力学的一般原则和滑雪教练的实践经验，并非来自严格控制的实验数据。它们应被视为"合理参考范围"而非权威判据。不同滑雪流派、地形、速度下，理想姿态会有差异。

各维度权重的逻辑：
- **膝盖弯曲权重最高（0.25）**：腿部弹性是滑雪所有动作的基础
- **前倾、小腿、重心各 0.20**：三者共同决定姿态质量
- **对称性 0.15**：相对次要——不对称通常是其他问题的表现而非根源

重心评分已从旧版的三档离散值（低/中/高→90/60/30）改为连续映射，保留更多姿态细节。

低姿态、大立刃和遮挡会让 Vision 缺失膝/踝关键点。系统会保留这些低置信度帧的原始数据，但在全视频评分、走刃关键时刻和转弯阶段结论中优先使用可靠姿态帧，避免把“无法可靠识别”误判为“动作差”。

### 板身方向与横滑判断

当前主判断使用左右脚踝连线代理板身方向，再用连续帧身体中心/脚踝中心位移估计滑行方向。两者夹角越小，越像沿板身走刃；夹角越大，越像横滑、推坡或搓雪。

| 板身/滑行方向夹角 | 解释 | 高分处理 |
|------------------|------|----------|
| `0°~15°` | 沿板身移动明显 | 可作为走刃证据 |
| `15°~30°` | 有走刃倾向 | 谨慎参考 |
| `30°~45°` | 横滑偏多 | 不保留高刻滑分 |
| `45°+` | 以横滑/推坡为主 | 基本不按刻滑处理 |

紫色图像候选线目前只作为调试覆盖图证据，不参与评分或横滑计算。人工复核显示，高置信紫色线也可能只是脚/板附近的雪面纹理或阴影。

## 稳定性算法

`stabilityScore` 使用姿态指标的时间平滑度：计算相邻有效姿态帧之间的关键角度变化速率，容忍度基于各维度的典型变化范围。低置信度指标会被过滤或降权。

`scoreConsistencyScore` 保留旧的总分波动视角，用于解释评分是否跳变，但不代表真实滑行动作稳定性。

## 评分等级

| 总分范围 | 等级 |
|----------|------|
| 85~100 | 专业 |
| 75~84 | 高级 |
| 60~74 | 中级 |
| 0~59 | 初级 |

## 项目结构

```
VideoVision/
├── Package.swift                    # SwiftPM 清单（VideoVisionCore + VideoVisionCLI）
├── Sources/
│   ├── VideoVisionCore/             # 核心分析库
│   │   ├── Models.swift             # Codable 数据模型
│   │   ├── VideoAnalyzer.swift      # 视频抽帧 & 分析编排
│   │   ├── VisionFrameAnalyzer.swift # Vision 请求封装（可配置）
│   │   ├── PoseMetrics.swift        # 关键点→角度/指标 + 置信度
│   │   ├── PoseScorer.swift         # 评分规则 + 改进建议
│   │   ├── SkiMetricsCalculator.swift # 滑雪派生指标
│   │   ├── KeyMomentDetector.swift  # 关键时刻检测
│   │   ├── ReportGenerator.swift    # 自然语言报告生成
│   │   └── Utilities.swift          # 公共工具函数
│   └── VideoVisionCLI/
│       └── main.swift               # CLI 入口
├── SkiAnaylze/                      # iOS SwiftUI App
│   ├── Package.swift                # App 依赖声明
│   └── SkiAnaylze/
│       ├── SkiAnaylzeApp.swift       # App 入口
│       ├── VideoAnalysisManager.swift # 分析状态管理
│       └── Views/                    # SwiftUI 视图
├── Tests/
│   └── VideoVisionCoreTests/        # 单元测试
│       ├── AngleCalculationTests.swift
│       ├── PoseScorerTests.swift
│       └── EdgeCaseTests.swift
├── video/                           # 示例视频
└── output/                          # 分析输出示例
```

## 已知限制

- 仅分析每秒第一帧，非逐帧分析（采样率可配置，默认 1fps）
- 仅检测画面中 **最显著的人体**（多人体时只取第一个）
- 2D 姿态检测影响所有角度计算精度——侧视角和 45° 角拍摄的结果不可直接比较
- 侧视角 / 遮挡时关键点置信度下降，评分参考性降低
- 当前为 **滑雪场景定制**，通用运动场景仅供参考
- 重心估算基于 2D 关键点的身体比例，无法精确测量 3D 重心位置

## 许可

MIT

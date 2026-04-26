# VideoVision 🎿

**基于 Apple Vision 框架的滑雪姿态视频分析工具**

利用 Vision 人体姿态识别 API，从滑雪视频中自动提取身体姿态数据，计算 5 项指标评分并生成改进建议。

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

```bash
swift run VideoVision /path/to/ski_video.mp4
```

示例：

```bash
swift run VideoVision 1.MP4
```

### 输出

- **控制台**：实时打印每帧的分析结果（物体检测、人脸、文字、场景、评分）
- **JSON 文件**：与视频同目录生成同名 `.json` 文件，包含完整结构化数据

## JSON 输出字段

### `AnalysisOutput`（顶层）

| 字段 | 类型 | 说明 |
|------|------|------|
| `videoPath` | string | 输入视频路径 |
| `duration` | double | 视频总时长（秒） |
| `totalFrames` | int | 分析的总帧数 |
| `frames` | array | 每帧检测结果 |
| `summary` | object | 全视频总结 |

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
| `centerOfGravity` | object 或 null | 相对重心高度：低/中/高 |

每个带置信度的字段格式：

```json
{
  "value": 15.2,
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

### `VideoSummary`

| 字段 | 类型 | 说明 |
|------|------|------|
| `averageScore` | double | 姿态总分平均值 |
| `bestFrame` | object | 总分最高帧 |
| `worstFrame` | object | 总分最低帧 |
| `stabilityScore` | double | 动作稳定性评分 0-100，基于姿态指标的相邻帧变化，越高越稳定 |
| `scoreConsistencyScore` | double | 姿态总分一致性 0-100，仅表示总分波动大小 |
| `scoreStdDev` | double | 姿态总分标准差，用于解释 `scoreConsistencyScore` |
| `overallLevel` | string | 基于平均分的整体等级 |

## 评分规则

| 指标 | 权重 | 理想范围 | 评分逻辑 |
|------|------|----------|----------|
| 身体前倾 | 20% | 10°~25° | 每偏离5°扣10分 |
| 膝盖弯曲 | 25% | 100°~140° | 每偏离10°扣8分 |
| 小腿倾斜 | 20% | 越高越好 | 0°=0分，80°=100分 |
| 重心高度 | 20% | 越低越好 | 低=90分，中=60分，高=30分 |
| 左右对称 | 15% | 差值越小越好 | 每差5°扣10分 |

> **注意**：可见性等级会影响权重分配。`partial`（单侧可见）时对称性权重降为 0，分配到其他项。`minimal` 时仅返回基础分。

## 稳定性算法

`stabilityScore` 不再使用姿态总分标准差，而是计算有效姿态帧之间的关键指标变化率：

- 身体前倾角
- 左右膝盖弯曲角
- 左右小腿倾斜角
- 重心等级变化

低置信度指标会被过滤或降权。`scoreConsistencyScore` 保留旧的总分波动视角，用于解释评分是否跳变，但不代表真实滑行动作稳定性。

## 评分等级

| 总分范围 | 等级 |
|----------|------|
| 85~100 | 专业 |
| 75~84 | 高级 |
| 60~74 | 中级 |
| 0~59 | 初级 |

## 项目结构

```
Sources/
├── main.swift                # CLI 入口
├── Models.swift              # Codable 数据结构
├── VideoAnalyzer.swift       # 视频抽帧 & 分析编排
├── VisionFrameAnalyzer.swift # Vision 请求封装
├── PoseMetrics.swift         # 关键点→角度/指标 + 置信度
└── PoseScorer.swift          # 评分规则 + 改进建议
```

## 已知限制

- 仅分析每秒第一帧，非逐帧分析
- 仅检测画面中 **最显著的人体**（多人体时只取第一个）
- 侧视角 / 遮挡时关键点置信度下降，评分参考性降低
- 当前为 **滑雪场景定制**，通用运动场景仅供参考
- 重心估算基于 2D 关键点，无法精确测量 3D 重心位置

## 许可

MIT

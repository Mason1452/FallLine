# --output-video: 输出带标注的 MP4 视频

## 背景

FallLine 当前通过 `--debug-overlay` 可以将分析结果（姿态骨架、角度、评分等）渲染到每帧画面上，但输出的是独立 PNG 文件 + TSV manifest，用户查看不够方便。新增 `--output-video` 开关，将标注帧直接合成为单一 MP4 视频，播放即可查看分析结果。

## 需求

- 新增独立 CLI 开关 `--output-video`
- 输出 MP4 (H.264)，无音频
- 标注内容与 `--debug-overlay` 的 PNG 画面完全一致
- 默认输出路径：原视频同目录，`<视频名>_analyzed.mp4`

## 用法

```bash
# 仅输出视频
swift run FallLineCLI --output-video 1.MP4

# 同时输出 PNG 帧 + 视频
swift run FallLineCLI --debug-overlay --output-video 1.MP4
```

## 设计

### 修改范围

| 文件 | 改动 |
|---|---|
| `Sources/FallLineCLI/main.swift` | 新增 `--output-video` 参数解析；`CLIOptions` 增加 `outputVideo: Bool`；主流程增加调用分支 |
| `Sources/FallLineCLI/DebugOverlayRenderer.swift` | 新增 `renderVideoOverlay()` 方法，复用 `renderOverlay()` 渲染逻辑 |

不修改 FallLineCore、VideoAnalyzer、JSON/Markdown 输出逻辑。

### 核心流程

```
--output-video 触发
  → 复用 renderOverlay() 逐帧渲染标注
  → NSBitmapImageRep → CVPixelBuffer → AVAssetWriter
  → H.264 编码 → <视频名>_analyzed.mp4
```

### renderVideoOverlay 方法签名

```swift
public static func renderVideoOverlay(
    videoURL: URL,
    analysis: AnalysisOutput,
    outputURL: URL,
    maxDimension: CGFloat = 1280
) async throws -> RenderVideoResult

struct RenderVideoResult {
    let outputURL: URL
    let frameCount: Int
    let duration: Double
}
```

### AVAssetWriter 管线参数

- Codec: H.264 (`AVVideoCodecType.h264`)，Baseline profile
- 分辨率: maxDimension=1280，保持宽高比
- 帧率: 匹配分析采样率（默认 5fps，由 `sampleInterval` 决定）
- PTS: 每帧按实际分析时间戳
- 音频: 无
- 跳过 error 帧，只写入有效帧

### 实现要点

1. **复用渲染**：直接调用现有 `renderOverlay(image:frame:boardFrame:summary:)` 生成每帧的 NSBitmapImageRep
2. **Pixel buffer 转换**：将 NSBitmapImageRep 的 RGBA 数据拷贝到 CVPixelBuffer
3. **逐帧写入**：`AVAssetWriterInput.append()` 按时间戳顺序写入，帧间不做插值
4. **完成处理**：`finishWriting` 后返回结果，失败则 throw

### 不做

- 不修改 `--debug-overlay` 现有行为
- 不做帧间插值/补帧
- 不保留原视频音频
- 不支持自定义编码参数

## 验证

```bash
swift build -c release
swift run FallLineCLI --output-video <测试视频.MP4>
# 验证:
# 1. 输出 `<视频名>_analyzed.mp4` 存在且可播放
# 2. 视频时长与 JSON 中 duration 一致
# 3. 标注内容与 --debug-overlay 的 PNG 一致（逐帧对比）
# 4. swift test 全量通过
```

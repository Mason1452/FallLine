# --output-video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--output-video` CLI flag to render pose-analysis overlays into an H.264 MP4 video file.

**Architecture:** Extend `DebugOverlayRenderer` with a new `renderVideoOverlay()` method that reuses the existing `renderOverlay()` per-frame drawing (pose skeleton, angles, scores, board direction). Convert each rendered `NSBitmapImageRep` to a `CVPixelBuffer` and feed it into an `AVAssetWriter` pipeline. Wire the new `--output-video` flag into `main.swift`'s `CLIOptions` and `parseOptions()`.

**Tech Stack:** Swift 5.9, AVFoundation (AVAssetWriter/AVAssetWriterInput/AVAssetWriterInputPixelBufferAdaptor), AppKit (existing overlay drawing), macOS 14+

---

### Task 1: Add `outputVideo` to CLIOptions and parse `--output-video`

**Files:**
- Modify: `Sources/FallLineCLI/main.swift:5-9`, `Sources/FallLineCLI/main.swift:11-16`, `Sources/FallLineCLI/main.swift:18-49`

- [ ] **Step 1: Add `outputVideo` field to CLIOptions**

In `Sources/FallLineCLI/main.swift`, update the `CLIOptions` struct (lines 5-9):

```swift
struct CLIOptions {
    let videoPath: String
    let debugOverlay: Bool
    let debugOverlayDirectory: String?
    let outputVideo: Bool
}
```

- [ ] **Step 2: Update printUsage() with new flag**

In `Sources/FallLineCLI/main.swift`, update `printUsage()` (lines 11-16):

```swift
func printUsage() {
    print("用法: swift run FallLineCLI <视频路径>")
    print("  例: swift run FallLineCLI 1.MP4")
    print("  调试覆盖图: swift run FallLineCLI --debug-overlay 1.MP4")
    print("  指定输出目录: swift run FallLineCLI --debug-overlay --debug-overlay-dir /tmp/debug_frames 1.MP4")
    print("  输出标注视频: swift run FallLineCLI --output-video 1.MP4")
}
```

- [ ] **Step 3: Parse `--output-video` in parseOptions()**

In `Sources/FallLineCLI/main.swift`, add a case in `parseOptions()` (after line 31, inside the switch):

```swift
var outputVideo = false

// ... inside the switch block, add:
case "--output-video":
    outputVideo = true
```

Also update the return statement to include `outputVideo`:

```swift
return CLIOptions(
    videoPath: videoPath,
    debugOverlay: debugOverlay,
    debugOverlayDirectory: debugOverlayDirectory,
    outputVideo: outputVideo
)
```

- [ ] **Step 4: Build to verify compilation**

```bash
swift build -c release 2>&1 | tail -5
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/FallLineCLI/main.swift
git commit -m "feat: add --output-video flag to CLIOptions and argument parser"
```

---

### Task 2: Add `RenderVideoResult` and `renderVideoOverlay()` to DebugOverlayRenderer

**Files:**
- Modify: `Sources/FallLineCLI/DebugOverlayRenderer.swift`

- [ ] **Step 1: Add `RenderVideoResult` struct**

In `Sources/FallLineCLI/DebugOverlayRenderer.swift`, add after the existing `RenderResult` struct (after line 14):

```swift
public struct RenderVideoResult {
    public let outputURL: URL
    public let frameCount: Int
    public let duration: Double
}
```

- [ ] **Step 2: Add `renderVideoOverlay()` static method skeleton**

Add after `renderFrameOverlays()` closing brace (after line 91, before the `}` that closes `DebugOverlayRenderer`):

```swift
public static func renderVideoOverlay(
    videoURL: URL,
    analysis: AnalysisOutput,
    outputURL: URL,
    maxDimension: CGFloat = 1280
) async throws -> RenderVideoResult {
    let asset = AVAsset(url: videoURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

    let frames = analysis.frames.sorted { $0.time < $1.time }
    let boardFrames = analysis.boardAnalysis.frames.sorted { $0.time < $1.time }
    let interval = medianSampleInterval(frames.map(\.time))

    // Determine output dimensions from first successfully extracted frame
    guard let (outputWidth, outputHeight) = try await outputDimensions(
        generator: generator,
        frames: frames,
        maxDimension: maxDimension
    ) else {
        throw RenderError.noValidFrames
    }

    // Set up AVAssetWriter
    let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: outputWidth,
        AVVideoHeightKey: outputHeight,
        AVVideoCompressionPropertiesKey: [
            AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
            AVVideoAverageBitRateKey: 3_000_000
        ]
    ]
    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    writerInput.expectsMediaDataInRealTime = false
    writer.add(writerInput)

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: writerInput,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputWidth,
            kCVPixelBufferHeightKey as String: outputHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
    )

    guard writer.startWriting() else {
        throw RenderError.writerFailed(writer.error)
    }
    writer.startSession(atSourceTime: .zero)

    var frameCount = 0
    let frameDuration = CMTime(
        seconds: interval > 0 ? interval : 0.2,
        preferredTimescale: 600
    )

    for frame in frames {
        guard writerInput.isReadyForMoreMediaData else {
            // Wait for writer to be ready
            try await Task.sleep(nanoseconds: 10_000_000)
            continue
        }

        let time = CMTime(seconds: frame.time, preferredTimescale: 600)
        let cgImage: CGImage
        do {
            cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        } catch {
            continue
        }

        let boardFrame = nearestBoardFrame(
            to: frame.time,
            in: boardFrames,
            tolerance: max(interval * 0.75, 0.55)
        )

        // Reuse existing renderOverlay for identical output
        let bitmap = renderOverlay(
            image: cgImage,
            frame: frame,
            boardFrame: boardFrame,
            summary: analysis.summary
        )

        guard let pixelBuffer = pixelBuffer(from: bitmap, width: outputWidth, height: outputHeight) else {
            continue
        }

        let pts = CMTimeMultiply(frameDuration, multiplier: Int32(frameCount))
        adaptor.append(pixelBuffer, withPresentationTime: pts)
        frameCount += 1
    }

    writerInput.markAsFinished()
    await writer.finishWriting()

    if writer.status == .failed {
        throw RenderError.writerFailed(writer.error)
    }

    let duration = Double(frameCount) * CMTimeGetSeconds(frameDuration)
    return RenderVideoResult(
        outputURL: outputURL,
        frameCount: frameCount,
        duration: duration
    )
}
```

- [ ] **Step 3: Add `RenderError` enum**

Add after `RenderVideoResult`:

```swift
enum RenderError: Error, LocalizedError {
    case noValidFrames
    case writerFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .noValidFrames:
            return "没有可写入的视频帧"
        case .writerFailed(let error):
            return "视频写入失败: \(error?.localizedDescription ?? "未知错误")"
        }
    }
}
```

- [ ] **Step 4: Add `outputDimensions` helper**

Add inside the private extension of `DebugOverlayRenderer`:

```swift
static func outputDimensions(
    generator: AVAssetImageGenerator,
    frames: [DetectionResult],
    maxDimension: CGFloat
) async throws -> (Int, Int)? {
    for frame in frames {
        let time = CMTime(seconds: frame.time, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            continue
        }
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let scale = min(maxDimension / w, maxDimension / h, 1.0)
        return (Int(w * scale), Int(h * scale))
    }
    return nil
}
```

- [ ] **Step 5: Add `pixelBuffer(from:width:height:)` conversion helper**

Add inside the same private extension:

```swift
static func pixelBuffer(
    from bitmap: NSBitmapImageRep,
    width: Int,
    height: Int
) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        nil,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard let destBase = CVPixelBufferGetBaseAddress(pixelBuffer),
          let srcBase = bitmap.bitmapData else {
        return nil
    }
    let destBPR = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let srcBPR = bitmap.bytesPerRow

    // NSBitmapImageRep deviceRGB produces RGBA; CVPixelBuffer BGRA needs R↔B swap
    for row in 0..<height {
        let src = srcBase.advanced(by: row * srcBPR)
        let dst = destBase.advanced(by: row * destBPR)
        for col in 0..<width {
            let r = src.load(fromByteOffset: col * 4 + 0, as: UInt8.self)
            let g = src.load(fromByteOffset: col * 4 + 1, as: UInt8.self)
            let b = src.load(fromByteOffset: col * 4 + 2, as: UInt8.self)
            let a = src.load(fromByteOffset: col * 4 + 3, as: UInt8.self)
            dst.storeBytes(of: b, toByteOffset: col * 4 + 0, as: UInt8.self)
            dst.storeBytes(of: g, toByteOffset: col * 4 + 1, as: UInt8.self)
            dst.storeBytes(of: r, toByteOffset: col * 4 + 2, as: UInt8.self)
            dst.storeBytes(of: a, toByteOffset: col * 4 + 3, as: UInt8.self)
        }
    }
    return pixelBuffer
}
```

- [ ] **Step 6: `renderOverlay` is private — make it accessible**

The `renderOverlay` method is currently inside `private extension DebugOverlayRenderer` (line 94). It's called from both the existing `renderFrameOverlays` (also in that extension) and the new `renderVideoOverlay` (also in that extension), so no visibility change is needed. Confirm: both methods are in the same `private extension` block, so `renderOverlay` is accessible.

No change needed.

- [ ] **Step 7: Build to verify compilation**

```bash
swift build -c release 2>&1 | tail -10
```

Expected: Build succeeds with no errors.

- [ ] **Step 8: Commit**

```bash
git add Sources/FallLineCLI/DebugOverlayRenderer.swift
git commit -m "feat: add renderVideoOverlay with AVAssetWriter H.264 pipeline"
```

---

### Task 3: Wire up main.swift to call renderVideoOverlay

**Files:**
- Modify: `Sources/FallLineCLI/main.swift:168-177`

- [ ] **Step 1: Add --output-video branch in main flow**

In `Sources/FallLineCLI/main.swift`, add after the debug overlay block (after line 177):

```swift
if options.outputVideo {
    let videoDir = videoURL.deletingLastPathComponent()
    let baseName = videoURL.deletingPathExtension().lastPathComponent
    let outputFile = videoDir
        .appendingPathComponent("\(baseName)_analyzed")
        .appendingPathExtension("mp4")
    let videoResult = try await DebugOverlayRenderer.renderVideoOverlay(
        videoURL: videoURL,
        analysis: output,
        outputURL: outputFile
    )
    print("✅ 标注视频已保存至: \(videoResult.outputURL.path)")
    print("   帧数: \(videoResult.frameCount) · 时长: \(String(format: "%.1f", videoResult.duration))s")
}
```

Note: replace lines 168-177 approach — actually this is an addition AFTER the existing debug overlay block, not a replacement. The existing `if options.debugOverlay { ... }` block at lines 168-177 stays unchanged.

- [ ] **Step 2: Build to verify compilation**

```bash
swift build -c release 2>&1 | tail -5
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/FallLineCLI/main.swift
git commit -m "feat: wire --output-video to renderVideoOverlay in main flow"
```

---

### Task 4: Run full test suite to verify no regressions

- [ ] **Step 1: Run all tests**

```bash
swift test 2>&1 | tail -10
```

Expected: All 88 tests pass (or same count as baseline).

- [ ] **Step 2: If any test failures, diagnose and fix**

```bash
swift test --filter <FailingTestName> 2>&1
```

- [ ] **Step 3: Commit if any test fixes were needed**

```bash
git add -A && git commit -m "fix: address test regressions from --output-video changes"
```

---

### Task 5: End-to-end manual verification

- [ ] **Step 1: Run on a test video with --output-video**

```bash
swift run FallLineCLI --output-video <path/to/test.mp4>
```

- [ ] **Step 2: Verify output**

Check that:
1. `<test>_analyzed.mp4` exists and is not zero bytes
2. Video plays back in QuickTime Player
3. Each frame shows pose skeleton overlays matching the debug PNG output
4. Framerate matches the analysis sampling rate (default 5fps)
5. `swift test` still passes at 88 tests

- [ ] **Step 3: Verify --debug-overlay + --output-video works together**

```bash
swift run FallLineCLI --debug-overlay --output-video <path/to/test.mp4>
```

Expected: Both `<test>.debug_frames/` directory and `<test>_analyzed.mp4` are produced.

---

### Implementation Notes

- `renderOverlay()` remains untouched — it's called by both `renderFrameOverlays` (PNG) and `renderVideoOverlay` (MP4)
- The `AVAssetImageGenerator` is created independently in `renderVideoOverlay` (same pattern as `renderFrameOverlays`) to keep the two paths decoupled
- Frame PTS uses sequential frame index × frame duration (not the analysis timestamp directly). This ensures constant frame rate in the output video — gaps from skipped error frames don't cause playback issues
- `NSBitmapImageRep` deviceRGB layout is RGBA; `kCVPixelFormatType_32BGRA` needs R↔B byte swap. The `pixelBuffer(from:width:height:)` helper handles this.
- IOSurface-backed pixel buffers (`kCVPixelBufferIOSurfacePropertiesKey`) enable GPU-accelerated encoding

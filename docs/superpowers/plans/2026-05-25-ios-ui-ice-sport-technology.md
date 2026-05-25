# iOS UI Ice Sport Technology Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the `SkiAnaylze/` SwiftUI interface around the approved Ice Sport Technology design while preserving all current app flows and analysis behavior.

**Architecture:** Keep the redesign in the iOS UI layer. Add reusable visual primitives in `AppTheme.swift`, then update each existing screen in place: `ContentView`, `HomeView`, `AnalysisProgressView`, `ReportDetailView`, and `HistoryView`. Do not modify analysis models, scoring logic, persistence logic, duplicated core analysis files, or CLI code.

**Tech Stack:** SwiftUI, AVKit `VideoPlayer`, PhotosUI, existing `VideoAnalysisManager`, existing model/report types, Xcode build verification for iPhone Simulator.

---

## Reference Documents

- Design spec: `docs/superpowers/specs/2026-05-25-ios-ui-ice-sport-technology-design.md`
- Project context: `WORK_LOG.md`
- File index: `file_manifest.md`
- Recent changes: `delta_update.md`

## File Structure

- Modify `SkiAnaylze/SkiAnaylze/AppTheme.swift`
  - Owns colors, gradients, glass panels, backgrounds, metric tiles, score rings, metric bars, and primary buttons.
- Modify `SkiAnaylze/SkiAnaylze/ContentView.swift`
  - Owns app shell, tab selection, and tab bar visual treatment.
- Modify `SkiAnaylze/SkiAnaylze/Views/HomeView.swift`
  - Owns home hero, upload CTA, recent reports, video picker, video confirmation sheet, and error sheet.
- Modify `SkiAnaylze/SkiAnaylze/Views/AnalysisProgressView.swift`
  - Owns scanning progress presentation and analysis step list.
- Modify `SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift`
  - Owns video report, score summary, key moments, metrics, issues, suggestions, and share image generation.
- Modify `SkiAnaylze/SkiAnaylze/Views/HistoryView.swift`
  - Owns training record list, empty state, and row design.
- Modify `WORK_LOG.md`, `CLAUDE.md`, `AGENTS.md`, `delta_update.md`, and `file_manifest.md`
  - Record the implemented UI work and verification state after implementation.

## Build Command

Use this command after each SwiftUI task:

```bash
xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Expected result: `** BUILD SUCCEEDED **`.

---

### Task 1: Add Ice Sport Theme Primitives

**Files:**
- Modify: `SkiAnaylze/SkiAnaylze/AppTheme.swift`

- [ ] **Step 1: Expand the color palette**

Replace the existing theme color constants with the approved palette while keeping compatibility names such as `themePrimary`, `themeBackground`, and `themeCard`.

```swift
extension Color {
    static let fallLineNight = Color(hex: "#02070D")
    static let fallLineNavy = Color(hex: "#06111E")
    static let fallLinePanel = Color(hex: "#0B1B2A")
    static let fallLineIce = Color(hex: "#F3FDFF")
    static let fallLineSnow = Color(hex: "#BFEFFF")
    static let fallLineCyan = Color(hex: "#29D7FF")
    static let fallLineMint = Color(hex: "#6DFFBF")
    static let fallLineBlue = Color(hex: "#7AB7FF")
    static let fallLineAmber = Color(hex: "#FFC15E")
    static let fallLineRed = Color(hex: "#FF6363")

    static let themePrimary = fallLineCyan
    static let themeBackground = fallLineNight
    static let themeCard = fallLineNavy
    static let themeCardSecondary = fallLinePanel
    static let themeSuccess = fallLineMint
    static let themeWarning = fallLineAmber
    static let themeProblem = fallLineAmber
    static let themeDanger = fallLineRed
    static let themeTextPrimary = fallLineIce
    static let themeTextSecondary = fallLineSnow.opacity(0.72)
    static let themeTextTertiary = fallLineSnow.opacity(0.46)
    static let themeAccent = fallLineCyan
    static let themeDivider = fallLineSnow.opacity(0.14)
}
```

- [ ] **Step 2: Add reusable gradients**

Add this extension below the color extension.

```swift
extension LinearGradient {
    static let fallLineBackground = LinearGradient(
        colors: [.fallLineNight, .fallLineNavy, .fallLineNight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let fallLineIceButton = LinearGradient(
        colors: [.fallLineIce, .fallLineCyan, .fallLineMint],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let fallLineMetric = LinearGradient(
        colors: [.fallLineCyan, .fallLineMint],
        startPoint: .leading,
        endPoint: .trailing
    )
}
```

- [ ] **Step 3: Add background and trace components**

Add these SwiftUI views in `AppTheme.swift`.

```swift
struct FallLineBackground: View {
    var showGrid = true
    var showTrace = true

    var body: some View {
        ZStack {
            LinearGradient.fallLineBackground
            MountainSilhouette()
                .fill(Color.fallLineSnow.opacity(0.10))
                .frame(height: 260)
                .frame(maxHeight: .infinity, alignment: .bottom)
            if showGrid {
                GridOverlay()
                    .stroke(Color.fallLineSnow.opacity(0.055), lineWidth: 0.6)
            }
            if showTrace {
                CarvingTrace()
                    .stroke(Color.fallLineCyan.opacity(0.68), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .shadow(color: .fallLineCyan.opacity(0.45), radius: 12)
                    .padding(.trailing, -40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .ignoresSafeArea()
    }
}

struct MountainSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.46))
        path.addLine(to: CGPoint(x: rect.width * 0.30, y: rect.height * 0.70))
        path.addLine(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.34))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct GridOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 28
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

struct CarvingTrace: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX + 70, y: rect.minY + 80))
        path.addCurve(
            to: CGPoint(x: rect.midX + 8, y: rect.maxY - 80),
            control1: CGPoint(x: rect.maxX + 10, y: rect.midY * 0.72),
            control2: CGPoint(x: rect.midX - 90, y: rect.midY * 1.28)
        )
        return path
    }
}
```

- [ ] **Step 4: Add glass, button, metric, score, and bar components**

Add these reusable views in `AppTheme.swift`.

```swift
struct GlassPanel<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.fallLineSnow.opacity(0.16), lineWidth: 1)
            )
    }
}

struct PrimaryIceButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.fallLineNight)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(LinearGradient.fallLineIceButton, in: Capsule())
            .shadow(color: .fallLineCyan.opacity(0.35), radius: 18, y: 8)
    }
}

struct MetricTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.themeTextPrimary)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.themeTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.fallLineSnow.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ScoreRing: View {
    let score: Double
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.fallLineSnow.opacity(0.12), lineWidth: size * 0.10)
            Circle()
                .trim(from: 0, to: min(max(score / 100, 0), 1))
                .stroke(
                    AngularGradient(colors: [.fallLineCyan, .fallLineMint, .fallLineCyan], center: .center),
                    style: StrokeStyle(lineWidth: size * 0.10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int(score.rounded()))")
                .font(.system(size: size * 0.28, weight: .black))
                .foregroundColor(.themeTextPrimary)
        }
        .frame(width: size, height: size)
    }
}

struct MetricBar: View {
    let label: String
    let score: Double
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.themeTextSecondary)
                Spacer()
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(color)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.fallLineSnow.opacity(0.11))
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(min(max(score / 100, 0), 1)))
                }
            }
            .frame(height: 7)
        }
    }
}
```

- [ ] **Step 5: Preserve existing helper compatibility**

Update `CardStyle`, `card()`, and `ScoreBar` to use `GlassPanel` and `MetricBar`, so older screen code still compiles during intermediate tasks.

```swift
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        GlassPanel {
            content
        }
    }
}

struct ScoreBar: View {
    let label: String
    let score: Double
    let color: Color

    var body: some View {
        MetricBar(label: label, score: score, color: color)
    }
}
```

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add SkiAnaylze/SkiAnaylze/AppTheme.swift
git commit -m "feat: add FallLine ice sport theme"
```

---

### Task 2: Rework App Shell and Home Screen

**Files:**
- Modify: `SkiAnaylze/SkiAnaylze/ContentView.swift`
- Modify: `SkiAnaylze/SkiAnaylze/Views/HomeView.swift`

- [ ] **Step 1: Keep the two-tab structure in `ContentView`**

Update visual labels and accent treatment only. Keep `HomeView`, `HistoryView`, `selectedTab`, and the shared manager.

```swift
TabView(selection: $selectedTab) {
    HomeView()
        .environmentObject(manager)
        .tabItem {
            Image(systemName: "figure.skiing.downhill")
            Text("分析")
        }
        .tag(0)

    HistoryView()
        .environmentObject(manager)
        .tabItem {
            Image(systemName: "chart.line.uptrend.xyaxis")
            Text("记录")
        }
        .tag(1)
}
.preferredColorScheme(.dark)
.tint(.themePrimary)
```

- [ ] **Step 2: Replace `HomeView.headerArea`**

Use a sport-tech hero instead of the snowflake logo block.

```swift
private var headerArea: some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("AI Ski Motion Coach")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.themeTextTertiary)
                    .textCase(.uppercase)
                Text("Carve\nSharper.")
                    .font(.system(size: 42, weight: .black))
                    .foregroundColor(.themeTextPrimary)
                    .lineSpacing(-4)
            }
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.themePrimary)
                .padding(12)
                .background(Color.fallLineSnow.opacity(0.08), in: Circle())
        }

        Text("上传滑雪视频，分析走刃、重心、支撑和稳定性。")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.themeTextSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 28)
}
```

- [ ] **Step 3: Replace `selectVideoButton`**

Use `PrimaryIceButtonLabel` and keep the existing `showPicker = true` action.

```swift
private var selectVideoButton: some View {
    Button {
        showPicker = true
    } label: {
        PrimaryIceButtonLabel(title: "选择滑雪视频", systemImage: "plus")
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 4: Replace auxiliary cards with last-session metrics**

Remove the inactive auxiliary buttons from the main visual path. Add a compact panel when a recent output exists.

```swift
private var lastSessionPanel: some View {
    let output = manager.historyURLs.first.flatMap { manager.output(for: $0) }
    let totalValue: String
    let edgeValue: String
    let supportValue: String
    if let output {
        totalValue = "\(Int(output.summary.averageScore.rounded()))"
        edgeValue = "\(Int(output.skiMetrics.edgeQualityScore.rounded()))"
        supportValue = "\(Int(output.skiMetrics.pressureSupportScore.rounded()))"
    } else {
        totalValue = "--"
        edgeValue = "--"
        supportValue = "--"
    }
    return GlassPanel {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last Session")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.themeTextTertiary)
                .textCase(.uppercase)
            HStack(spacing: 10) {
                MetricTile(value: totalValue, label: "总分")
                MetricTile(value: edgeValue, label: "走刃")
                MetricTile(value: supportValue, label: "支撑")
            }
        }
    }
}
```

- [ ] **Step 5: Update `HomeView.body` background and ordering**

Use `FallLineBackground` and this content order:

```swift
ZStack {
    FallLineBackground()
    ScrollView {
        VStack(spacing: 22) {
            headerArea
            lastSessionPanel
            selectVideoButton
            if !manager.historyURLs.isEmpty {
                recentReportsSection
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }
}
```

Keep the existing `.sheet`, `.fullScreenCover`, `sheetItem`, `VideoPicker`, `VideoConfirmationView`, and `ErrorView` logic wired exactly as it is.

- [ ] **Step 6: Retheme recent report rows**

In `recentReportRow(url:)`, replace the leading film icon with `ScoreRing(score:size:)` when output exists and keep the button action unchanged.

```swift
if let output = output {
    ScoreRing(score: output.summary.averageScore, size: 44)
} else {
    Image(systemName: "chart.line.uptrend.xyaxis")
        .foregroundColor(.themePrimary)
        .font(.title3)
}
```

- [ ] **Step 7: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add SkiAnaylze/SkiAnaylze/ContentView.swift SkiAnaylze/SkiAnaylze/Views/HomeView.swift
git commit -m "feat: redesign FallLine home screen"
```

---

### Task 3: Redesign Video Confirmation and Error States

**Files:**
- Modify: `SkiAnaylze/SkiAnaylze/Views/HomeView.swift`

- [ ] **Step 1: Update `VideoConfirmationView.body`**

Use `FallLineBackground(showTrace: false)` and keep the same `startButton` action.

```swift
NavigationStack {
    ZStack {
        FallLineBackground(showTrace: false)
        ScrollView {
            VStack(spacing: 18) {
                videoPreview
                infoCard
                qualityTips
                startButton
            }
            .padding(20)
        }
    }
    .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("取消") { dismiss() }
                .foregroundColor(.themeTextSecondary)
        }
    }
    .navigationTitle("确认分析")
    .navigationBarTitleDisplayMode(.inline)
}
```

- [ ] **Step 2: Retheme `videoPreview`**

Use an alpine preview with a play control.

```swift
private var videoPreview: some View {
    ZStack(alignment: .bottomLeading) {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.fallLineIce.opacity(0.85), .fallLineBlue.opacity(0.55), .fallLineNavy],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(16/9, contentMode: .fit)
            .overlay(MountainSilhouette().fill(Color.fallLineSnow.opacity(0.32)).padding(.top, 44))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.fallLineSnow.opacity(0.16), lineWidth: 1)
            )

        Image(systemName: "play.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.fallLineNight)
            .padding(14)
            .background(Color.fallLineIce, in: Circle())
            .padding(16)
    }
}
```

- [ ] **Step 3: Replace `infoCard` with metric tiles**

```swift
private var infoCard: some View {
    HStack(spacing: 10) {
        MetricTile(value: formatDuration(duration), label: "视频时长")
        MetricTile(value: "9:16", label: "建议比例")
        MetricTile(value: "\(estimatedFrames)", label: "预估帧")
    }
}
```

- [ ] **Step 4: Retheme `qualityTips` as a scan panel**

```swift
private var qualityTips: some View {
    GlassPanel {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality Scan")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.themeTextTertiary)
                .textCase(.uppercase)
            Label("人物基本完整", systemImage: "checkmark.circle.fill")
            Label("可检测人体姿态", systemImage: "checkmark.circle.fill")
            Label("建议人物占画面更大", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.themeWarning)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.themeTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 5: Retheme `startButton`**

```swift
private var startButton: some View {
    Button {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            manager.startAnalysis(videoURL: videoURL)
        }
    } label: {
        PrimaryIceButtonLabel(title: "开始 AI 分析", systemImage: "waveform.path.ecg")
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 6: Retheme `ErrorView`**

Use `FallLineBackground(showTrace: false)` and a `GlassPanel` around the message. Keep `dismiss()` unchanged.

- [ ] **Step 7: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add SkiAnaylze/SkiAnaylze/Views/HomeView.swift
git commit -m "feat: redesign video confirmation flow"
```

---

### Task 4: Redesign Analysis Progress

**Files:**
- Modify: `SkiAnaylze/SkiAnaylze/Views/AnalysisProgressView.swift`

- [ ] **Step 1: Add scan ring helper inside the file**

Add this private view below `AnalysisProgressView`.

```swift
private struct ScanProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.fallLineSnow.opacity(0.12), lineWidth: 13)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: [.fallLineCyan, .fallLineMint, .fallLineCyan], center: .center),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .fallLineCyan.opacity(0.42), radius: 16)
            Text("\(Int(progress * 100))%")
                .font(.system(size: 34, weight: .black))
                .foregroundColor(.themeTextPrimary)
        }
        .frame(width: 156, height: 156)
    }
}
```

- [ ] **Step 2: Add step row helper**

```swift
private struct AnalysisStepStatusRow: View {
    let step: AnalysisStep
    let currentStep: AnalysisStep

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 16, height: 16)
                .shadow(color: indicatorColor.opacity(isActive ? 0.55 : 0), radius: 10)
            Text(step.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(step.rawValue <= currentStep.rawValue ? .themeTextPrimary : .themeTextTertiary)
            Spacer()
        }
    }

    private var isActive: Bool {
        step.rawValue == currentStep.rawValue
    }

    private var indicatorColor: Color {
        if step.rawValue < currentStep.rawValue { return .themeSuccess }
        if isActive { return .themePrimary }
        return .fallLineSnow.opacity(0.16)
    }
}
```

- [ ] **Step 3: Replace the progress body**

Use the existing manager state and cancel behavior.

```swift
ZStack {
    FallLineBackground()
    if case .analyzing(let progress, let currentStep) = manager.state {
        VStack(spacing: 28) {
            Spacer()
            ScanProgressRing(progress: progress)
            VStack(spacing: 8) {
                Text("Pose + Edge Detection")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.themeTextTertiary)
                    .textCase(.uppercase)
                Text("正在识别人体骨架、雪板方向和运动稳定性")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.themeTextSecondary)
                    .multilineTextAlignment(.center)
            }
            GlassPanel {
                VStack(spacing: 14) {
                    ForEach(AnalysisStep.allCases, id: \.rawValue) { step in
                        AnalysisStepStatusRow(step: step, currentStep: currentStep)
                    }
                }
            }
            .padding(.horizontal, 28)
            Spacer()
            Button {
                manager.cancelAnalysis()
                dismiss()
            } label: {
                Text("取消分析")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.themeTextSecondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 28)
                    .background(Color.fallLineSnow.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
    }
}
```

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SkiAnaylze/SkiAnaylze/Views/AnalysisProgressView.swift
git commit -m "feat: redesign analysis progress screen"
```

---

### Task 5: Redesign Report Detail

**Files:**
- Modify: `SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift`

- [ ] **Step 1: Update the screen background**

Wrap the existing `ScrollView` in `ZStack { FallLineBackground(showTrace: false) ... }`. Keep `setupPlayer()`, `seekTo(seconds:)`, sheet sharing, and toolbar actions unchanged.

- [ ] **Step 2: Retheme `videoPlayerSection`**

Keep `VideoPlayer` when `player` exists. Add a HUD strip below the video when key moments exist.

```swift
private var videoPlayerSection: some View {
    VStack(spacing: 10) {
        ZStack(alignment: .bottomLeading) {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(9/16, contentMode: .fit)
            } else {
                missingVideoFallback
            }

            if let bestMoment = output.keyMoments.first {
                GlassPanel(padding: 10) {
                    HStack {
                        Text(bestMoment.time)
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.themePrimary)
                        Text(bestMoment.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.themeTextPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.fallLineSnow.opacity(0.14), lineWidth: 1)
        )

        if !output.keyMoments.isEmpty {
            momentTimeline
        }
    }
}
```

Add `missingVideoFallback`:

```swift
private var missingVideoFallback: some View {
    ZStack {
        LinearGradient(
            colors: [.fallLinePanel, .fallLineNavy],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        VStack(spacing: 10) {
            Image(systemName: "play.slash")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.themeTextTertiary)
            Text("视频文件未找到")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.themeTextTertiary)
        }
    }
    .aspectRatio(9/16, contentMode: .fit)
}
```

- [ ] **Step 3: Replace `scoreCardSection`**

Use `ScoreRing`, metric bars, and level text.

```swift
private var scoreCardSection: some View {
    let score = output.summary.averageScore
    return GlassPanel {
        HStack(spacing: 16) {
            ScoreRing(score: score, size: 96)
            VStack(alignment: .leading, spacing: 10) {
                Text(output.summary.overallLevel)
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.themeTextPrimary)
                Text(stageDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.themeTextSecondary)
                    .lineLimit(3)
                MetricBar(label: "动作稳定性", score: output.summary.stabilityScore, color: Color.scoreColor(output.summary.stabilityScore))
            }
        }
    }
}
```

- [ ] **Step 4: Update key moment rows**

In `keyMomentsSection`, replace the generic thumbnail with an alpine gradient thumbnail and keep `seekTo(seconds:)` unchanged.

```swift
RoundedRectangle(cornerRadius: 10, style: .continuous)
    .fill(
        LinearGradient(
            colors: [.fallLineIce.opacity(0.8), .fallLineBlue.opacity(0.5), .fallLinePanel],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .frame(width: 66, height: 48)
    .overlay(Image(systemName: "play.fill").font(.caption).foregroundColor(.fallLineNight))
```

- [ ] **Step 5: Replace report cards with `GlassPanel`**

Update `coachObservationSection`, `keyMomentsSection`, `skiMetricsSection`, `mainIssuesSection`, and `trainingSuggestionSection` to use `GlassPanel` instead of `.card()`.

- [ ] **Step 6: Retheme `shareButton`**

```swift
private var shareButton: some View {
    Button {
        generateShareImage()
    } label: {
        PrimaryIceButtonLabel(title: "分享报告图片", systemImage: "square.and.arrow.up")
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 7: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift
git commit -m "feat: redesign report detail screen"
```

---

### Task 6: Redesign History and Share Image

**Files:**
- Modify: `SkiAnaylze/SkiAnaylze/Views/HistoryView.swift`
- Modify: `SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift`

- [ ] **Step 1: Retheme `HistoryView.body`**

Use `FallLineBackground()` behind the existing empty/list switch and keep `.sheet(item:)` unchanged.

```swift
NavigationStack {
    ZStack {
        FallLineBackground()
        Group {
            if manager.historyURLs.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
    }
    .navigationTitle("训练记录")
    .navigationBarTitleDisplayMode(.large)
    .sheet(item: $selectedOutput) { output in
        ReportDetailView(output: output)
    }
}
```

- [ ] **Step 2: Retheme empty state**

Use a ski-analysis message.

```swift
private var emptyState: some View {
    VStack(spacing: 16) {
        Spacer()
        Image(systemName: "figure.skiing.downhill")
            .font(.system(size: 50, weight: .bold))
            .foregroundColor(.themePrimary)
        Text("还没有训练记录")
            .font(.system(size: 20, weight: .black))
            .foregroundColor(.themeTextPrimary)
        Text("完成一次视频分析后，这里会显示你的分数、主要问题和训练进展。")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.themeTextSecondary)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
        Spacer()
    }
    .padding(40)
}
```

- [ ] **Step 3: Retheme `historyRow`**

Use `ScoreRing(score:size:)`, keep `mainIssueSummary(from:)`, delete behavior, and tap behavior unchanged.

```swift
return HStack(spacing: 14) {
    ScoreRing(score: score, size: 54)

    VStack(alignment: .leading, spacing: 5) {
        Text(url.lastPathComponent)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.themeTextPrimary)
            .lineLimit(1)

        HStack(spacing: 8) {
            Text(stage)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.fallLineNight)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.scoreColor(score), in: Capsule())

            Text(dateText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.themeTextTertiary)
        }

        if let output = output {
            Text("主要问题：\(mainIssueSummary(from: output))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.themeTextTertiary)
                .lineLimit(1)
        }
    }

    Spacer()
    Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundColor(.themeTextTertiary)
}
.padding(14)
.background(Color.fallLineSnow.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.fallLineSnow.opacity(0.10), lineWidth: 1)
)
```

- [ ] **Step 4: Redesign `generateShareImage()`**

Use the approved share-card visual. Keep `shareImage = image` and `showShareSheet = true`.

```swift
private func generateShareImage() {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 690))
    let image = renderer.image { ctx in
        let c = ctx.cgContext
        let rect = CGRect(x: 0, y: 0, width: 390, height: 690)

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(Color.fallLineNavy).cgColor,
                UIColor(Color.fallLineNight).cgColor
            ] as CFArray,
            locations: [0, 1]
        )
        c.drawLinearGradient(gradient!, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 390, y: 690), options: [])

        UIColor(Color.fallLineCyan.opacity(0.45)).setStroke()
        c.setLineWidth(3)
        c.move(to: CGPoint(x: 330, y: 120))
        c.addCurve(to: CGPoint(x: 230, y: 520), control1: CGPoint(x: 420, y: 250), control2: CGPoint(x: 120, y: 360))
        c.strokePath()

        "FallLine Report".draw(at: CGPoint(x: 28, y: 48), withAttributes: [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor(Color.fallLineSnow)
        ])

        "Carve\\nSharper.".draw(at: CGPoint(x: 28, y: 88), withAttributes: [
            .font: UIFont.boldSystemFont(ofSize: 42),
            .foregroundColor: UIColor(Color.themeTextPrimary)
        ])

        "\(Int(output.summary.averageScore.rounded()))".draw(at: CGPoint(x: 28, y: 250), withAttributes: [
            .font: UIFont.boldSystemFont(ofSize: 92),
            .foregroundColor: UIColor(Color.themeTextPrimary)
        ])

        output.summary.overallLevel.draw(at: CGPoint(x: 34, y: 348), withAttributes: [
            .font: UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: UIColor(Color.fallLineCyan)
        ])

        let dims = [
            "走刃质量  \(Int(output.skiMetrics.edgeQualityScore.rounded()))",
            "板压支撑  \(Int(output.skiMetrics.pressureSupportScore.rounded()))",
            "动作稳定  \(Int(output.summary.stabilityScore.rounded()))"
        ]
        var y: CGFloat = 414
        for dim in dims {
            dim.draw(at: CGPoint(x: 34, y: y), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 17),
                .foregroundColor: UIColor(Color.fallLineSnow)
            ])
            y += 34
        }

        "AI Ski Motion Coach".draw(at: CGPoint(x: 28, y: 630), withAttributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor(Color.themeTextTertiary)
        ])
    }
    shareImage = image
    showShareSheet = true
}
```

- [ ] **Step 5: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add SkiAnaylze/SkiAnaylze/Views/HistoryView.swift SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift
git commit -m "feat: redesign history and share card"
```

---

### Task 7: Visual QA and Documentation Update

**Files:**
- Modify: `WORK_LOG.md`
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`
- Modify: `delta_update.md`
- Modify: `file_manifest.md`

- [ ] **Step 1: Run final build**

Run:

```bash
xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run Swift package tests for unchanged core confidence**

Run:

```bash
swift test
```

Expected: `88 tests` and `0 failures`.

- [ ] **Step 3: Manual simulator QA**

Launch the app in iPhone 16 Pro Simulator and verify:

```text
1. First launch with no persisted history injects the demo report.
2. Home screen shows Ice Sport Technology visual language.
3. Select-video button still opens the picker.
4. Demo report opens from recent reports and history.
5. Report video fallback or player renders without layout overlap.
6. Key moment buttons still seek when a playable video exists.
7. History delete still removes the selected row.
8. Share button still opens the iOS share sheet with a generated image.
```

- [ ] **Step 4: Update project docs**

Update `WORK_LOG.md`, `CLAUDE.md`, `AGENTS.md`, `delta_update.md`, and `file_manifest.md` with:

```text
Current state: iOS Ice Sport Technology UI implementation completed.
Verification: record xcodebuild result, swift test result, and simulator QA result.
Important files: AppTheme.swift plus HomeView, AnalysisProgressView, ReportDetailView, HistoryView.
Known follow-up: any visual issue found during QA, described as a concrete screen and symptom.
```

- [ ] **Step 5: Review diff**

Run:

```bash
git diff --stat
git diff -- SkiAnaylze/SkiAnaylze/AppTheme.swift SkiAnaylze/SkiAnaylze/ContentView.swift SkiAnaylze/SkiAnaylze/Views/HomeView.swift SkiAnaylze/SkiAnaylze/Views/AnalysisProgressView.swift SkiAnaylze/SkiAnaylze/Views/HistoryView.swift SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift
```

Expected:

```text
Only iOS UI/theme files and required project docs changed.
No changes under Sources/FallLineCore/.
No changes under Sources/FallLineCLI/.
No changes under SkiAnaylze/SkiAnaylze/Sources/.
```

- [ ] **Step 6: Commit**

```bash
git add WORK_LOG.md CLAUDE.md AGENTS.md delta_update.md file_manifest.md
git commit -m "docs: record iOS UI redesign implementation"
```

---

## Self-Review

Spec coverage:

- Ski-specific visual language: covered by Tasks 1-6.
- Premium sport-tech personality: covered by theme primitives, home, progress, report, and share card tasks.
- Home: covered by Task 2.
- Video confirmation: covered by Task 3.
- Analysis progress: covered by Task 4.
- Report detail: covered by Task 5.
- History: covered by Task 6.
- Share card: covered by Task 6.
- Verification criteria: covered by Task 7.
- Scope boundary against scoring/model/persistence changes: stated in architecture, file structure, and Task 7 diff review.

No blocking gaps remain.

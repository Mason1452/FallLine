import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers
import FallLineCore

struct HomeView: View {
    @EnvironmentObject var manager: VideoAnalysisManager
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
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
            .sheet(isPresented: $showPicker) {
                VideoPicker { url in
                    manager.didPickVideo(url: url)
                }
            }
            .sheet(item: sheetItem) { item in
                switch item {
                case .confirmation(let url, let duration, let frames):
                    VideoConfirmationView(
                        videoURL: url,
                        duration: duration,
                        estimatedFrames: frames
                    )
                case .report(let output):
                    ReportDetailView(output: output)
                case .error(let message):
                    ErrorView(message: message)
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: {
                    if case .analyzing = manager.state { return true }
                    return false
                },
                set: { newValue in
                    if !newValue {
                        manager.cancelAnalysis()
                    }
                }
            )) {
                AnalysisProgressView()
                    .environmentObject(manager)
            }

        }
    }

    // MARK: - Header

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

    // MARK: - 选择视频按钮

    private var selectVideoButton: some View {
        Button {
            showPicker = true
        } label: {
            PrimaryIceButtonLabel(title: "选择滑雪视频", systemImage: "plus")
        }
        .buttonStyle(.plain)
    }

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

    // MARK: - 辅助入口

    private var auxiliaryLinks: some View {
        HStack(spacing: 12) {
            auxiliaryCard(
                icon: "camera.viewfinder",
                title: "拍摄建议",
                color: .themeSuccess
            )
            auxiliaryCard(
                icon: "doc.text.magnifyingglass",
                title: "示例报告",
                color: .themeWarning
            )
        }
    }

    private func auxiliaryCard(icon: String, title: String, color: Color) -> some View {
        Button {} label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.themeTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.themeCard)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 最近报告

    private var recentReportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近报告")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.themeTextPrimary)

            ForEach(Array(manager.historyURLs.prefix(5)), id: \.self) { url in
                recentReportRow(url: url)
            }
        }
    }

    private func recentReportRow(url: URL) -> some View {
        let output = manager.output(for: url)
        return Button {
            if let output = output {
                manager.state = .completed(output: output)
            }
        } label: {
            HStack {
                if let output = output {
                    ScoreRing(score: output.summary.averageScore, size: 44)
                } else {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.themePrimary)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.themeTextPrimary)
                    if let output = output {
                        HStack(spacing: 6) {
                            Text(output.summary.overallLevel)
                                .font(.system(size: 12))
                                .foregroundColor(.themeTextTertiary)
                            Text("·")
                                .foregroundColor(.themeTextTertiary)
                            Text("\(Int(output.summary.averageScore.rounded()))分")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.scoreColor(output.summary.averageScore))
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.themeTextTertiary)
            }
            .padding(12)
            .background(Color.themeCardSecondary)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sheet item

    private enum SheetItem: Identifiable {
        case confirmation(url: URL, duration: TimeInterval, frames: Int)
        case report(AnalysisOutput)
        case error(String)

        var id: String {
            switch self {
            case .confirmation: return "confirmation"
            case .report: return "report"
            case .error(let m): return "error-\(m)"
            }
        }
    }

    private var sheetItem: Binding<SheetItem?> {
        Binding {
            switch manager.state {
            case .confirmingVideo(let url, let duration, let frames):
                return .confirmation(url: url, duration: duration, frames: frames)
            case .completed(let output):
                return .report(output)
            case .failed(let error):
                return .error(error)
            default:
                return nil
            }
        } set: { _ in
            manager.state = .idle
        }

    }
}

// MARK: - Video Picker（支持相册 + 文件）

struct VideoPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else { return }
            let provider = result.itemProvider

            guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { return }

            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                guard let url = url, error == nil else { return }

                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)

                try? FileManager.default.removeItem(at: tempURL)

                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    DispatchQueue.main.async {
                        self.onPick(tempURL)
                    }
                } catch {
                    let data = try? Data(contentsOf: url)
                    if let data = data {
                        try? data.write(to: tempURL)
                        DispatchQueue.main.async {
                            self.onPick(tempURL)
                        }
                    }
                }
            }
        }
    }
}
// MARK: - 视频确认页

struct VideoConfirmationView: View {
    let videoURL: URL
    let duration: TimeInterval
    let estimatedFrames: Int

    @EnvironmentObject var manager: VideoAnalysisManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
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
    }

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

    private var infoCard: some View {
        HStack(spacing: 10) {
            MetricTile(value: formatDuration(duration), label: "视频时长")
            MetricTile(value: "9:16", label: "建议比例")
            MetricTile(value: "\(estimatedFrames)", label: "预估帧")
        }
    }

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

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m)m \(s)s"
    }
}

// MARK: - 错误页面

struct ErrorView: View {
    let message: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            FallLineBackground(showTrace: false)
            GlassPanel {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.themeDanger)

                    Text("分析失败")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.themeTextPrimary)

                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(.themeTextSecondary)
                        .multilineTextAlignment(.center)

                    Button("返回") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.themePrimary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(40)
        }
    }
}

// MARK: - 预览

#Preview {
    HomeView()
        .environmentObject(VideoAnalysisManager.shared)
        .preferredColorScheme(.dark)
}

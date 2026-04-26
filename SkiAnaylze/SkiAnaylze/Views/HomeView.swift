import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var manager: VideoAnalysisManager
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 顶部 Logo 区
                    headerArea

                    // 选择视频按钮
                    selectVideoButton

                    // 辅助入口
                    auxiliaryLinks

                    // 最近报告
                    if !manager.historyURLs.isEmpty {
                        recentReportsSection
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(Color.themeBackground.ignoresSafeArea())
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
        VStack(spacing: 8) {
            Image(systemName: "snowflake")
                .font(.system(size: 40))
                .foregroundColor(.themePrimary)

            Text("VideoVision")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.themeTextPrimary)

            Text("滑雪动作分析")
                .font(.system(size: 16))
                .foregroundColor(.themeTextSecondary)

            Text("上传滑雪视频，自动生成动作报告")
                .font(.system(size: 14))
                .foregroundColor(.themeTextTertiary)
                .padding(.top, 4)
        }
        .padding(.top, 20)
    }

    // MARK: - 选择视频按钮

    private var selectVideoButton: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择滑雪视频")
                        .font(.system(size: 18, weight: .semibold))
                    Text("支持 .mp4 / .mov 格式")
                        .font(.system(size: 13))
                        .foregroundColor(.themeTextTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.themeTextTertiary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.themePrimary.opacity(0.2), Color.themeCard],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.themePrimary.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
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
                Image(systemName: "film")
                    .foregroundColor(.themePrimary)
                    .font(.title3)

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
            VStack(spacing: 24) {
                // 视频预览
                videoPreview

                // 信息卡片
                infoCard

                // 质量提示
                qualityTips

                Spacer()

                // 开始分析按钮
                startButton
            }
            .padding(20)
            .background(Color.themeBackground.ignoresSafeArea())
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
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.themeCard)
                .aspectRatio(16/9, contentMode: .fit)

            Image(systemName: "play.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.themePrimary)
        }
    }

    private var infoCard: some View {
        HStack(spacing: 24) {
            infoItem(icon: "clock", label: "时长", value: formatDuration(duration))
            Divider().frame(height: 30).background(Color.themeDivider)
            infoItem(icon: "film", label: "分辨率", value: "1080p")
            Divider().frame(height: 30).background(Color.themeDivider)
            infoItem(icon: "square.grid.2x2", label: "预估帧数", value: "\(estimatedFrames)帧")
        }
        .padding(16)
        .background(Color.themeCard)
        .cornerRadius(12)
    }

    private func infoItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.themePrimary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.themeTextPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.themeTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var qualityTips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("视频质量提示")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.themeTextPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Label("人物基本完整", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.themeSuccess)
                Label("可检测人体姿态", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.themeSuccess)
                Label("建议人物占画面更大", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.themeWarning)
            }
            .font(.system(size: 13))
            .foregroundColor(.themeTextSecondary)
        }
        .padding(16)
        .background(Color.themeCard)
        .cornerRadius(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startButton: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                manager.startAnalysis(videoURL: videoURL)
            }
        } label: {
            Text("开始分析")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.themePrimary)
                .cornerRadius(14)
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
        .padding(40)
        .background(Color.themeBackground.ignoresSafeArea())
    }
}

// MARK: - 预览

#Preview {
    HomeView()
        .environmentObject(VideoAnalysisManager.shared)
        .preferredColorScheme(.dark)
}

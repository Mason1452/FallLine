import SwiftUI

struct AnalysisProgressView: View {
    @EnvironmentObject var manager: VideoAnalysisManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FallLineBackground()
                if case .analyzing(let progress, let currentStep) = manager.state {
                    GeometryReader { proxy in
                        ScrollView {
                            VStack(spacing: 28) {
                                Spacer(minLength: 28)
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
                                Spacer(minLength: 20)
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
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: proxy.size.height)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .toolbarBackground(Color.themeBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("分析中")
            .navigationBarTitleDisplayMode(.inline)
        }

    }
}

private struct ScanProgressRing: View {
    let progress: Double

    private var sanitizedProgress: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.fallLineSnow.opacity(0.12), lineWidth: 13)
            Circle()
                .trim(from: 0, to: sanitizedProgress)
                .stroke(
                    AngularGradient(colors: [.fallLineCyan, .fallLineMint, .fallLineCyan], center: .center),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .fallLineCyan.opacity(0.42), radius: 16)
                .animation(.easeInOut(duration: 0.3), value: sanitizedProgress)
            Text("\(Int((sanitizedProgress * 100).rounded()))%")
                .font(.system(size: 34, weight: .black))
                .foregroundColor(.themeTextPrimary)
        }
        .frame(width: 156, height: 156)
    }
}

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

#Preview {
    let manager = VideoAnalysisManager.shared
    manager.state = .analyzing(progress: 0.42, step: .poseDetection)
    return AnalysisProgressView()
        .environmentObject(manager)
        .preferredColorScheme(.dark)
}

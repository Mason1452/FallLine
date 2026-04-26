import SwiftUI

struct AnalysisProgressView: View {
    @EnvironmentObject var manager: VideoAnalysisManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // 全屏深色背景
                Color.themeBackground
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // 视频图标
                    Image(systemName: "video.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.themePrimary)

                    // 进度条
                    if case .analyzing(let progress, let currentStep) = manager.state {
                        // 总进度
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.themeTextTertiary.opacity(0.3))
                                .frame(height: 12)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [.themePrimary, Color.themePrimary.opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: UIScreen.main.bounds.width * 0.65 * CGFloat(progress),
                                    height: 12
                                )
                                .animation(.easeInOut(duration: 0.3), value: progress)
                        }
                        .frame(width: UIScreen.main.bounds.width * 0.65)

                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.themePrimary)

                        Text("正在分析视频...")
                            .font(.system(size: 16))
                            .foregroundColor(.themeTextSecondary)

                        // 步骤列表
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(AnalysisStep.allCases, id: \.rawValue) { step in
                                HStack(spacing: 12) {
                                    if step.rawValue < currentStep.rawValue {
                                        // 已完成
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.themeSuccess)
                                            .font(.system(size: 18))
                                    } else if step.rawValue == currentStep.rawValue {
                                        // 正在进行
                                        ProgressView()
                                            .tint(.themePrimary)
                                            .scaleEffect(0.8)
                                    } else {
                                        // 未开始
                                        Image(systemName: "circle")
                                            .foregroundColor(.themeTextTertiary.opacity(0.4))
                                            .font(.system(size: 18))
                                    }

                                    Text(step.label)
                                        .font(.system(size: 14))
                                        .foregroundColor(
                                            step.rawValue <= currentStep.rawValue
                                                ? .themeTextPrimary
                                                : .themeTextTertiary.opacity(0.5)
                                        )
                                }
                            }
                        }
                        .padding(20)
                        .background(Color.themeCard)
                        .cornerRadius(12)
                        .padding(.horizontal, 40)
                    }

                    Spacer()

                    // 取消按钮
                    Button {
                        manager.cancelAnalysis()
                        dismiss()
                    } label: {
                        Text("取消分析")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.themeTextSecondary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 32)
                            .background(Color.themeCard)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbarBackground(Color.themeBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("分析中")
            .navigationBarTitleDisplayMode(.inline)
        }

    }
}

#Preview {
    let manager = VideoAnalysisManager.shared
    manager.state = .analyzing(progress: 0.42, step: .poseDetection)
    return AnalysisProgressView()
        .environmentObject(manager)
        .preferredColorScheme(.dark)
}

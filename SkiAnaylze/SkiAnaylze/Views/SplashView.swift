import SwiftUI

struct SplashView: View {
    let onFinish: () -> Void

    @Environment(\.adProvider) private var adProvider

    @State private var phase = 0
    @State private var traceProgress: CGFloat = 0
    @State private var countdownProgress: CGFloat = 1.0

    var body: some View {
        ZStack {
            LinearGradient.fallLineBackground
                .ignoresSafeArea()

            MountainSilhouette()
                .fill(Color.fallLineSnow.opacity(0.12))
                .frame(height: 280)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: phase >= 1 ? 0 : 140)
                .animation(.easeOut(duration: 0.9), value: phase)

            if phase >= 2 {
                GridOverlay()
                    .stroke(Color.fallLineSnow.opacity(0.06), lineWidth: 0.6)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if phase >= 3 {
                CarvingTrace()
                    .trim(from: 0, to: traceProgress)
                    .stroke(
                        Color.fallLineCyan.opacity(0.72),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .shadow(color: .fallLineCyan.opacity(0.5), radius: 14)
                    .padding(.trailing, -40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }

            VStack(spacing: 0) {
                Spacer()

                if phase >= 2 {
                    Text("AI SKI MOTION COACH")
                        .font(.system(size: 14, weight: .semibold).monospaced())
                        .foregroundColor(.themeTextTertiary)
                        .tracking(4)
                        .transition(.opacity)
                }

                if phase >= 3 {
                    Text("FALL LINE")
                        .font(.system(size: 42, weight: .black))
                        .foregroundStyle(LinearGradient.fallLineIceButton)
                        .tracking(2)
                        .padding(.top, 8)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                if phase >= 3 {
                    Text("carve sharper.")
                        .font(.system(size: 14, weight: .medium).italic())
                        .foregroundColor(.themeTextSecondary)
                        .padding(.top, 4)
                        .transition(.opacity)
                }

                if phase >= 4 {
                    countdownRing
                        .padding(.top, 36)
                        .transition(.opacity)
                }

                Spacer()

                adProvider.makeSplashAdView()
                    .frame(height: 60)
                    .padding(.bottom, 64)
            }
            .padding(.horizontal, 32)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: {
                onFinish()
            }) {
                Text("跳过 >")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.themeTextSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial.opacity(0.60), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.fallLineSnow.opacity(0.18), lineWidth: 1)
                    )
            }
            .padding(.top, 64)
            .padding(.trailing, 24)
        }
        .onAppear(perform: startAnimation)
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Color.fallLineSnow.opacity(0.10), lineWidth: 4)
                .frame(width: 44, height: 44)

            Circle()
                .trim(from: 0, to: max(countdownProgress, 0))
                .stroke(
                    AngularGradient(colors: [.fallLineCyan, .fallLineMint, .fallLineCyan], center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1.5), value: countdownProgress)
        }
    }

    private func startAnimation() {
        phase = 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.4)) { phase = 2 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) { phase = 3 }
            withAnimation(.easeInOut(duration: 0.8)) { traceProgress = 1.0 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) { phase = 4 }
            countdownProgress = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            onFinish()
        }
    }
}

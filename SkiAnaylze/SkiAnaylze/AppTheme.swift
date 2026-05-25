import SwiftUI

// MARK: - 设计系统

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

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

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

struct GlassPanel<Content: View>: View {
    let padding: CGFloat
    let content: Content

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

// MARK: - 分数颜色映射

extension Color {
    static func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0..<30:  return .themeDanger
        case 30..<50: return .themeProblem
        case 50..<70: return .themeWarning
        case 70..<85: return .themeSuccess
        default:      return .themePrimary
        }
    }
}

// MARK: - 卡片样式

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        GlassPanel {
            content
        }
    }
}

extension View {
    func card() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - 分段进度条

struct SegmentedProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .frame(height: 4)
                    .foregroundColor(i < currentStep ? .themePrimary : Color.themeTextTertiary.opacity(0.3))
            }
        }
    }
}

// MARK: - 横向评分条

struct ScoreBar: View {
    let label: String
    let score: Double
    let color: Color

    var body: some View {
        MetricBar(label: label, score: score, color: color)
    }
}

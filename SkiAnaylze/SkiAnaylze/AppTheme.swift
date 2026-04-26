import SwiftUI

// MARK: - 设计系统

extension Color {
    static let themePrimary = Color(hex: "#35A7FF")
    static let themeBackground = Color(hex: "#0B1220")
    static let themeCard = Color(hex: "#111827")
    static let themeCardSecondary = Color(hex: "#1A2332")
    static let themeSuccess = Color(hex: "#34D399")
    static let themeWarning = Color(hex: "#FBBF24")
    static let themeProblem = Color(hex: "#F97316")
    static let themeDanger = Color(hex: "#EF4444")
    static let themeTextPrimary = Color.white
    static let themeTextSecondary = Color(hex: "#9CA3AF")
    static let themeTextTertiary = Color(hex: "#6B7280")
    static let themeAccent = Color(hex: "#35A7FF")
    static let themeDivider = Color(hex: "#1F2937")

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
        content
            .padding(16)
            .background(Color.themeCard)
            .cornerRadius(12)
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
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.themeTextPrimary)
                Spacer()
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.themeTextTertiary.opacity(0.3))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score / 100), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

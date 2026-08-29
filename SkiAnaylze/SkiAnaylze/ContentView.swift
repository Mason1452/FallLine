import SwiftUI

struct ContentView: View {
    @StateObject private var manager = VideoAnalysisManager.shared
    @State private var selectedTab = 0

    var body: some View {
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

            TrendView(store: manager.trendStore)
                .tabItem {
                    Image(systemName: "chart.xyaxis.line")
                    Text("趋势")
                }
                .tag(2)
        }
        .preferredColorScheme(.dark)
        .tint(.themePrimary)
    }
}

#Preview {
    ContentView()
}

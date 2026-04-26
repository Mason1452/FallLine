import SwiftUI

struct ContentView: View {
    @StateObject private var manager = VideoAnalysisManager.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .environmentObject(manager)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("分析")
                }
                .tag(0)

            HistoryView()
                .environmentObject(manager)
                .tabItem {
                    Image(systemName: "clock.fill")
                    Text("历史")
                }
                .tag(1)
        }
        .preferredColorScheme(.dark)
        .accentColor(.themePrimary)
    }
}

#Preview {
    ContentView()
}

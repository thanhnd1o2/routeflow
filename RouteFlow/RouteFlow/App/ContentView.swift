import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .dashboard

    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case rules = "Rules"
        case traffic = "Traffic"
        case logs = "Logs"

        var icon: String {
            switch self {
            case .dashboard: return "gauge.medium"
            case .rules: return "list.bullet.rectangle"
            case .traffic: return "arrow.up.arrow.down.circle"
            case .logs: return "doc.text"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .navigationTitle("RouteFlow")
            .listStyle(.sidebar)
        } detail: {
            switch selectedTab {
            case .dashboard:
                DashboardView()
            case .rules:
                RulesView()
            case .traffic:
                TrafficView()
            case .logs:
                LogsView()
            }
        }
    }
}

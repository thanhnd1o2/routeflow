import SwiftUI

@main
struct RouteFlowApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
    }
}

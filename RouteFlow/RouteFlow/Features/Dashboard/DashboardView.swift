import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            // Service Status Card
            serviceStatusCard

            // Interface Status
            interfaceStatusSection

            // Quick Stats
            statsSection

            Spacer()
        }
        .padding(24)
        .navigationTitle("Dashboard")
    }

    // MARK: - Service Status

    private var serviceStatusCard: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(appState.isRunning ? Color.green : Color.gray)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(appState.isRunning ? "Service Running" : "Service Stopped")
                    .font(.headline)
                Text(appState.isRunning ? "Routing traffic based on \(appState.rules.count) rules" : "Press Start to begin routing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: toggleService) {
                Text(appState.isRunning ? "Stop" : "Start")
                    .frame(width: 80)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(appState.isRunning ? .red : .green)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 1))
    }

    // MARK: - Interface Status

    private var interfaceStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Interfaces")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(appState.interfaces) { iface in
                    interfaceCard(iface)
                }
            }
        }
    }

    private func interfaceCard(_ iface: NetworkInterface) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iface.type.icon)
                .font(.title2)
                .foregroundStyle(iface.isActive ? .blue : .gray)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(iface.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(iface.isActive ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundStyle(iface.isActive ? .green : .secondary)
            }

            Spacer()

            if iface.id == appState.defaultInterface {
                Text("Default")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.blue.opacity(0.1)))
                    .foregroundStyle(.blue)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Stats")
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                statCard(title: "Rules", value: "\(appState.rules.count)", icon: "list.bullet")
                statCard(title: "Log Entries", value: "\(appState.logs.count)", icon: "doc.text")
                statCard(title: "Interfaces", value: "\(appState.interfaces.filter { $0.isActive }.count)", icon: "network")
            }
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))
    }

    // MARK: - Actions

    private func toggleService() {
        if appState.isRunning {
            appState.stop()
        } else {
            appState.start()
        }
    }
}

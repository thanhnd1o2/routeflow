import SwiftUI

struct TrafficView: View {
    @StateObject private var monitor = ConnectionMonitor()
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Stats Bar
            statsBar

            Divider()

            // Interface breakdown + connections
            HSplitView {
                interfacePanel
                    .frame(minWidth: 220, maxWidth: 280)

                connectionTable
            }
        }
        .navigationTitle("Traffic")
        .onAppear {
            if appState.isRunning {
                monitor.startMonitoring()
            }
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
        .onChange(of: appState.isRunning) { _, running in
            if running {
                monitor.startMonitoring()
            } else {
                monitor.stopMonitoring()
            }
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 24) {
            statItem(label: "Active", value: "\(monitor.activeConnections.count)", color: .green)
            statItem(label: "Total", value: "\(monitor.connections.count)", color: .blue)

            Divider().frame(height: 24)

            statItem(label: "↓ In", value: monitor.totalBytesIn.formattedBytes, color: .cyan)
            statItem(label: "↑ Out", value: monitor.totalBytesOut.formattedBytes, color: .orange)

            Spacer()

            Button(action: { monitor.clearHistory() }) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Interface Panel

    private var interfacePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per Interface")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if monitor.interfaceStats.isEmpty {
                Text("No traffic yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                List(monitor.interfaceStats) { stat in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(stat.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(stat.activeConnections) active")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        HStack(spacing: 12) {
                            Label("\(stat.totalConnections)", systemImage: "link")
                                .font(.caption)
                            Label(stat.totalBytes.formattedBytes, systemImage: "arrow.up.arrow.down")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)

                        // Traffic bar
                        GeometryReader { geo in
                            let maxBytes = monitor.interfaceStats.map { $0.totalBytes }.max() ?? 1
                            let ratio = CGFloat(stat.totalBytes) / CGFloat(maxBytes)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(interfaceColor(stat.name))
                                .frame(width: geo.size.width * ratio, height: 6)
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Connection Table

    private var connectionTable: some View {
        Table(monitor.recentConnections) {
            TableColumn("Status") { conn in
                Circle()
                    .fill(statusColor(conn.status))
                    .frame(width: 8, height: 8)
            }
            .width(min: 40, ideal: 45)

            TableColumn("Time") { conn in
                Text(conn.startTime, style: .time)
                    .font(.caption)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 70)

            TableColumn("Domain") { conn in
                Text(conn.domain)
                    .font(.body)
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 220)

            TableColumn("Interface") { conn in
                Text(conn.interface)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(interfaceColor(conn.interface).opacity(0.15)))
                    .foregroundStyle(interfaceColor(conn.interface))
            }
            .width(min: 70, ideal: 90)

            TableColumn("Port") { conn in
                Text("\(conn.remotePort)")
                    .font(.caption)
                    .monospacedDigit()
            }
            .width(min: 45, ideal: 50)

            TableColumn("↓ In") { conn in
                Text(conn.bytesIn.formattedBytes)
                    .font(.caption)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 70)

            TableColumn("↑ Out") { conn in
                Text(conn.bytesOut.formattedBytes)
                    .font(.caption)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 70)

            TableColumn("Rule") { conn in
                Text(conn.matchedRule ?? "default")
                    .font(.caption2)
                    .foregroundStyle(conn.matchedRule != nil ? .primary : .secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: ConnectionInfo.Status) -> Color {
        switch status {
        case .active: return .green
        case .closed: return .gray
        case .error: return .red
        }
    }

    private func interfaceColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "wifi": return .blue
        case "ethernet": return .purple
        case "vpn": return .orange
        default: return .gray
        }
    }
}

import SwiftUI

struct LogsView: View {
    @EnvironmentObject var appState: AppState
    @State private var filterText: String = ""
    @State private var selectedLevel: LogEntry.Level? = nil

    private var filteredLogs: [LogEntry] {
        appState.logs.filter { entry in
            let matchesText = filterText.isEmpty ||
                entry.domain.localizedCaseInsensitiveContains(filterText) ||
                entry.resolvedInterface.localizedCaseInsensitiveContains(filterText)
            let matchesLevel = selectedLevel == nil || entry.level == selectedLevel
            return matchesText && matchesLevel
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            filterBar

            Divider()

            // Log Table
            if filteredLogs.isEmpty {
                emptyState
            } else {
                logTable
            }
        }
        .navigationTitle("Logs")
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Filter by domain or interface...", text: $filterText)
                .textFieldStyle(.plain)

            if !filterText.isEmpty {
                Button(action: { filterText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 20)

            Picker("Level", selection: $selectedLevel) {
                Text("All").tag(nil as LogEntry.Level?)
                Text("Info").tag(LogEntry.Level.info as LogEntry.Level?)
                Text("Warning").tag(LogEntry.Level.warning as LogEntry.Level?)
                Text("Error").tag(LogEntry.Level.error as LogEntry.Level?)
            }
            .pickerStyle(.segmented)
            .frame(width: 250)

            Spacer()

            Text("\(filteredLogs.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: clearLogs) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    // MARK: - Log Table

    private var logTable: some View {
        Table(filteredLogs) {
            TableColumn("Time") { entry in
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 80)

            TableColumn("Level") { entry in
                Text(entry.level.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(levelColor(entry.level))
            }
            .width(min: 50, ideal: 55)

            TableColumn("Domain") { entry in
                Text(entry.domain)
                    .font(.body)
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 250)

            TableColumn("Interface") { entry in
                Text(entry.resolvedInterface)
                    .font(.body)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.blue.opacity(0.1)))
                    .foregroundStyle(.blue)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Matched Rule") { entry in
                Text(entry.matchedRule ?? "default")
                    .font(.caption)
                    .foregroundStyle(entry.matchedRule != nil ? .primary : .secondary)
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 250)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No log entries")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Start the service to see routing logs")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func levelColor(_ level: LogEntry.Level) -> Color {
        switch level {
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func clearLogs() {
        appState.logs.removeAll()
    }
}

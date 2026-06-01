import Foundation
import Combine

/// Monitors active connections and tracks traffic statistics.
/// Reads real traffic events from the shared App Group container (written by the extension)
/// and falls back to mock simulation when the extension isn't running.
class ConnectionMonitor: ObservableObject {
    @Published var connections: [ConnectionInfo] = []
    @Published var interfaceStats: [InterfaceStats] = []
    @Published var totalBytesIn: UInt64 = 0
    @Published var totalBytesOut: UInt64 = 0
    @Published var isUsingRealData: Bool = false

    private let appGroupID = "group.com.whateverbest.routeflow"
    private let eventsFileName = "traffic_events.json"

    private var pollTimer: Timer?
    private var isMonitoring = false
    private var lastEventCount = 0
    private var darwinNotifyToken: Int32 = 0

    var activeConnections: [ConnectionInfo] {
        connections.filter { $0.status == .active }
    }

    var recentConnections: [ConnectionInfo] {
        Array(connections.prefix(50))
    }

    // MARK: - Control

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        isUsingRealData = readTrafficEvents()
        startPolling()
        registerDarwinNotification()
    }

    func stopMonitoring() {
        isMonitoring = false
        pollTimer?.invalidate()
        pollTimer = nil
        unregisterDarwinNotification()
    }

    func clearHistory() {
        connections.removeAll(where: { $0.status != .active })
        updateInterfaceStats()
    }

    // MARK: - Real Data from Extension (App Group IPC)

    /// Poll the shared App Group file for traffic events.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isMonitoring else { return }
            _ = self.readTrafficEvents()
        }
    }

    /// Register for Darwin notifications from the extension.
    private func registerDarwinNotification() {
        let name = "com.whateverbest.routeflow.traffic-update" as CFString
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let monitor = Unmanaged<ConnectionMonitor>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    _ = monitor.readTrafficEvents()
                }
            },
            name,
            nil,
            .deliverImmediately
        )
    }

    private func unregisterDarwinNotification() {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    /// Read and process traffic events from the shared file.
    @discardableResult
    private func readTrafficEvents() -> Bool {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return false
        }

        let fileURL = containerURL.appendingPathComponent(eventsFileName)
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? JSONDecoder().decode([TrafficEvent].self, from: data) else {
            return false
        }

        // Only process if there are new events
        guard events.count != lastEventCount else { return true }
        lastEventCount = events.count

        processTrafficEvents(events)
        return true
    }

    /// Process raw traffic events into ConnectionInfo objects.
    private func processTrafficEvents(_ events: [TrafficEvent]) {
        var connectionMap: [String: ConnectionInfo] = [:]

        // Build connection state from events
        for event in events {
            switch event.type {
            case .start:
                let conn = ConnectionInfo(
                    id: UUID(uuidString: event.id) ?? UUID(),
                    startTime: Date(timeIntervalSince1970: event.timestamp),
                    domain: event.domain ?? "unknown",
                    remotePort: event.remotePort ?? 0,
                    interface: event.interface ?? "unknown",
                    matchedRule: nil,
                    bytesIn: 0,
                    bytesOut: 0,
                    status: .active
                )
                connectionMap[event.id] = conn

            case .end:
                if var conn = connectionMap[event.id] {
                    conn.status = event.error ? ConnectionInfo.Status.error : ConnectionInfo.Status.closed
                    conn.endTime = Date(timeIntervalSince1970: event.timestamp)
                    connectionMap[event.id] = conn
                }

            case .bytesIn:
                if var conn = connectionMap[event.id] {
                    conn.bytesIn += event.bytesIn
                    connectionMap[event.id] = conn
                }

            case .bytesOut:
                if var conn = connectionMap[event.id] {
                    conn.bytesOut += event.bytesOut
                    connectionMap[event.id] = conn
                }
            }
        }

        // Update published state
        DispatchQueue.main.async {
            self.connections = Array(connectionMap.values)
                .sorted { $0.startTime > $1.startTime }

            self.totalBytesIn = self.connections.reduce(0) { $0 + $1.bytesIn }
            self.totalBytesOut = self.connections.reduce(0) { $0 + $1.bytesOut }
            self.updateInterfaceStats()
        }
    }

    // MARK: - Connection Tracking (for mock or direct use)

    func recordConnection(domain: String, interface: String, rule: String?) {
        let conn = ConnectionInfo(
            domain: domain,
            remotePort: [80, 443, 8080].randomElement() ?? 443,
            interface: interface,
            matchedRule: rule,
            bytesIn: UInt64.random(in: 512...65536),
            bytesOut: UInt64.random(in: 128...8192)
        )

        DispatchQueue.main.async {
            self.connections.insert(conn, at: 0)
            self.totalBytesIn += conn.bytesIn
            self.totalBytesOut += conn.bytesOut
            self.updateInterfaceStats()

            if self.connections.count > 200 {
                self.connections = Array(self.connections.prefix(200))
            }
        }
    }

    func closeConnection(id: UUID) {
        if let idx = connections.firstIndex(where: { $0.id == id }) {
            connections[idx].status = .closed
            connections[idx].endTime = Date()
        }
    }

    // MARK: - Statistics

    private func updateInterfaceStats() {
        var stats: [String: InterfaceStats] = [:]

        for conn in connections {
            if stats[conn.interface] == nil {
                stats[conn.interface] = InterfaceStats(
                    id: conn.interface,
                    name: conn.interface,
                    activeConnections: 0,
                    totalConnections: 0,
                    bytesIn: 0,
                    bytesOut: 0
                )
            }
            stats[conn.interface]?.totalConnections += 1
            stats[conn.interface]?.bytesIn += conn.bytesIn
            stats[conn.interface]?.bytesOut += conn.bytesOut
            if conn.status == .active {
                stats[conn.interface]?.activeConnections += 1
            }
        }

        interfaceStats = Array(stats.values).sorted { $0.totalConnections > $1.totalConnections }
    }


}

// MARK: - Formatting Helpers

extension UInt64 {
    var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(self))
    }
}

import Foundation
import os.log

/// Reports traffic events from the Network Extension to the main app
/// via the shared App Group container.
///
/// Uses a JSON file in the App Group container as a lightweight IPC mechanism.
/// The main app's ConnectionMonitor reads this file to display live traffic.
final class TrafficReporter {

    private let logger = Logger(subsystem: "com.whateverbest.routeflow.extension", category: "traffic-reporter")

    private let appGroupID = "group.com.whateverbest.routeflow"
    private let eventsFileName = "traffic_events.json"
    private let maxEvents = 200

    private var pendingEvents: [TrafficEvent] = []
    private let queue = DispatchQueue(label: "com.routeflow.traffic-reporter", qos: .utility)
    private var flushTimer: DispatchSourceTimer?

    init() {
        startPeriodicFlush()
    }

    deinit {
        flushTimer?.cancel()
        flush()
    }

    // MARK: - Public API

    func reportConnectionStart(id: UUID, domain: String, interface: String, remotePort: UInt16) {
        let event = TrafficEvent(
            id: id.uuidString,
            type: .start,
            domain: domain,
            interface: interface,
            remotePort: remotePort,
            timestamp: Date().timeIntervalSince1970,
            bytesIn: 0,
            bytesOut: 0,
            error: false
        )
        enqueue(event)
    }

    func reportConnectionEnd(id: UUID, error: Bool) {
        let event = TrafficEvent(
            id: id.uuidString,
            type: .end,
            domain: nil,
            interface: nil,
            remotePort: nil,
            timestamp: Date().timeIntervalSince1970,
            bytesIn: 0,
            bytesOut: 0,
            error: error
        )
        enqueue(event)
    }

    func reportBytesIn(id: UUID, bytes: UInt64) {
        let event = TrafficEvent(
            id: id.uuidString,
            type: .bytesIn,
            domain: nil,
            interface: nil,
            remotePort: nil,
            timestamp: Date().timeIntervalSince1970,
            bytesIn: bytes,
            bytesOut: 0,
            error: false
        )
        enqueue(event)
    }

    func reportBytesOut(id: UUID, bytes: UInt64) {
        let event = TrafficEvent(
            id: id.uuidString,
            type: .bytesOut,
            domain: nil,
            interface: nil,
            remotePort: nil,
            timestamp: Date().timeIntervalSince1970,
            bytesIn: 0,
            bytesOut: bytes,
            error: false
        )
        enqueue(event)
    }

    // MARK: - Internal

    private func enqueue(_ event: TrafficEvent) {
        queue.async { [weak self] in
            self?.pendingEvents.append(event)
            // Flush immediately for start/end events
            if event.type == .start || event.type == .end {
                self?.flush()
            }
        }
    }

    /// Periodically flush byte count updates to disk.
    private func startPeriodicFlush() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.flush()
        }
        timer.resume()
        flushTimer = timer
    }

    private func flush() {
        guard !pendingEvents.isEmpty else { return }

        let eventsToWrite = pendingEvents
        pendingEvents.removeAll()

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            logger.error("Cannot access App Group container for traffic reporting")
            return
        }

        let fileURL = containerURL.appendingPathComponent(eventsFileName)

        // Read existing events, append new ones, trim to max
        var allEvents: [TrafficEvent] = []
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONDecoder().decode([TrafficEvent].self, from: data) {
            allEvents = existing
        }

        allEvents.append(contentsOf: eventsToWrite)

        // Keep only the most recent events
        if allEvents.count > maxEvents {
            allEvents = Array(allEvents.suffix(maxEvents))
        }

        do {
            let data = try JSONEncoder().encode(allEvents)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to write traffic events: \(error.localizedDescription)")
        }

        // Post Darwin notification to signal the main app
        let notifyName = "com.whateverbest.routeflow.traffic-update" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notifyName),
            nil,
            nil,
            true
        )
    }
}

// NOTE: TrafficEvent model is defined in Shared/Models/TrafficEvent.swift
// and must be included in both the main app and extension targets.

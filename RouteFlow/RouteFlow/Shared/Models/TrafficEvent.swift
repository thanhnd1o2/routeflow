import Foundation

/// Represents a traffic event communicated between the Network Extension
/// and the main app via the shared App Group container.
///
/// This model is shared between both targets:
/// - Extension writes events via TrafficReporter
/// - Main app reads events via ConnectionMonitor
struct TrafficEvent: Codable {
    enum EventType: String, Codable {
        case start
        case end
        case bytesIn
        case bytesOut
    }

    let id: String
    let type: EventType
    let domain: String?
    let interface: String?
    let remotePort: UInt16?
    let timestamp: TimeInterval
    let bytesIn: UInt64
    let bytesOut: UInt64
    let error: Bool
}

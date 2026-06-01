import Foundation

/// Represents an active or recent network connection.
struct ConnectionInfo: Identifiable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    let domain: String
    let remoteAddress: String
    let remotePort: UInt16
    let interface: String
    let matchedRule: String?
    var bytesIn: UInt64
    var bytesOut: UInt64
    var status: Status

    enum Status: String {
        case active = "Active"
        case closed = "Closed"
        case error = "Error"

        var color: String {
            switch self {
            case .active: return "green"
            case .closed: return "gray"
            case .error: return "red"
            }
        }
    }

    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    var totalBytes: UInt64 {
        bytesIn + bytesOut
    }

    init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        domain: String,
        remoteAddress: String = "",
        remotePort: UInt16 = 443,
        interface: String,
        matchedRule: String? = nil,
        bytesIn: UInt64 = 0,
        bytesOut: UInt64 = 0,
        status: Status = .active
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = nil
        self.domain = domain
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.interface = interface
        self.matchedRule = matchedRule
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.status = status
    }
}

/// Traffic statistics per interface.
struct InterfaceStats: Identifiable {
    let id: String
    let name: String
    var activeConnections: Int
    var totalConnections: Int
    var bytesIn: UInt64
    var bytesOut: UInt64

    var totalBytes: UInt64 { bytesIn + bytesOut }
}

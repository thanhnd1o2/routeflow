import Foundation

/// A log entry representing a routing event.
struct LogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let domain: String
    let resolvedInterface: String
    let matchedRule: String?
    let level: Level

    enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"

        var color: String {
            switch self {
            case .info: return "green"
            case .warning: return "orange"
            case .error: return "red"
            }
        }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        domain: String,
        resolvedInterface: String,
        matchedRule: String? = nil,
        level: Level = .info
    ) {
        self.id = id
        self.timestamp = timestamp
        self.domain = domain
        self.resolvedInterface = resolvedInterface
        self.matchedRule = matchedRule
        self.level = level
    }
}

extension LogEntry {
    static let mockLogs: [LogEntry] = [
        LogEntry(domain: "api.github.com", resolvedInterface: "wifi", matchedRule: "DOMAIN-SUFFIX,github.com,wifi"),
        LogEntry(domain: "mail.company.com", resolvedInterface: "ethernet", matchedRule: "DOMAIN-SUFFIX,company.com,ethernet"),
        LogEntry(domain: "cdn.example.com", resolvedInterface: "wifi", matchedRule: "DOMAIN-KEYWORD,cdn,wifi"),
        LogEntry(domain: "random.site.org", resolvedInterface: "wifi", matchedRule: nil),
        LogEntry(domain: "vpn.partner.org", resolvedInterface: "vpn", matchedRule: "DOMAIN,vpn.partner.org,vpn"),
        LogEntry(domain: "internal.company.com", resolvedInterface: "ethernet", matchedRule: "DOMAIN-SUFFIX,company.com,ethernet"),
    ]
}

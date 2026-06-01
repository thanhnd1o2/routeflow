import Foundation

/// A domain-based routing rule.
struct RoutingRule: Identifiable, Hashable, Codable {
    let id: UUID
    var matchType: MatchType
    var pattern: String
    var interfaceId: String
    var isEnabled: Bool

    enum MatchType: String, CaseIterable, Codable {
        case domain = "DOMAIN"
        case domainSuffix = "DOMAIN-SUFFIX"
        case domainKeyword = "DOMAIN-KEYWORD"

        var displayName: String {
            switch self {
            case .domain: return "Exact Domain"
            case .domainSuffix: return "Domain Suffix"
            case .domainKeyword: return "Domain Keyword"
            }
        }
    }

    init(
        id: UUID = UUID(),
        matchType: MatchType,
        pattern: String,
        interfaceId: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.matchType = matchType
        self.pattern = pattern
        self.interfaceId = interfaceId
        self.isEnabled = isEnabled
    }

    /// Format as config string: "MATCH_TYPE,pattern,interface"
    var configString: String {
        "\(matchType.rawValue),\(pattern),\(interfaceId)"
    }
}

extension RoutingRule {
    /// Default empty rules. Users add their own rules via the UI.
    static let defaultRules: [RoutingRule] = []
}

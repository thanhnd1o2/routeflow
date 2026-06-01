import Foundation
import Combine

/// Central application state managing service status, rules, and logs.
class AppState: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var rules: [RoutingRule] = []
    @Published var interfaces: [NetworkInterface] = []
    @Published var logs: [LogEntry] = []
    @Published var defaultInterface: String = "wifi"

    private let interfaceDetector = InterfaceDetector()
    private var interfaceCancellable: Any?

    private static let rulesFileName = "routeflow_rules.json"

    #if ROUTEFLOW_FFI
    private var bridge: RouteFlowBridge?
    #endif

    init() {
        rules = Self.loadRulesFromDisk() ?? RoutingRule.defaultRules

        // Subscribe to real interface updates
        interfaceCancellable = interfaceDetector.$interfaces
            .receive(on: DispatchQueue.main)
            .assign(to: &$interfaces)

        #if ROUTEFLOW_FFI
        initializeBridge()
        #endif
    }

    // MARK: - Service Control

    func start() {
        isRunning = true
        addLog(domain: "system", interface: "--", rule: "Service started", level: .info)
    }

    func stop() {
        isRunning = false
        addLog(domain: "system", interface: "--", rule: "Service stopped", level: .info)
    }

    // MARK: - Rule Management

    func addRule(_ rule: RoutingRule) {
        rules.append(rule)
        saveRulesToDisk()
        #if ROUTEFLOW_FFI
        rebuildBridge()
        #endif
    }

    func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        saveRulesToDisk()
        #if ROUTEFLOW_FFI
        rebuildBridge()
        #endif
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        saveRulesToDisk()
        #if ROUTEFLOW_FFI
        rebuildBridge()
        #endif
    }

    func updateRule(_ rule: RoutingRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            saveRulesToDisk()
            #if ROUTEFLOW_FFI
            rebuildBridge()
            #endif
        }
    }

    func toggleRule(id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].isEnabled.toggle()
            saveRulesToDisk()
            #if ROUTEFLOW_FFI
            rebuildBridge()
            #endif
        }
    }

    // MARK: - Persistence

    private static let storageKey = "com.routeflow.saved_rules"
    private static let defaultInterfaceStorageKey = "com.routeflow.default_interface"

    private func saveRulesToDisk() {
        guard let data = try? JSONEncoder().encode(rules) else {
            print("[RouteFlow] ERROR: Failed to encode rules")
            return
        }

        // UserDefaults is the most reliable storage for sandboxed apps
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        UserDefaults.standard.set(defaultInterface, forKey: Self.defaultInterfaceStorageKey)
        print("[RouteFlow] Saved \(rules.count) rules to UserDefaults")
    }

    private static func loadRulesFromDisk() -> [RoutingRule]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            print("[RouteFlow] No saved rules in UserDefaults")
            return nil
        }

        guard let rules = try? JSONDecoder().decode([RoutingRule].self, from: data) else {
            print("[RouteFlow] ERROR: Failed to decode saved rules")
            return nil
        }

        print("[RouteFlow] Loaded \(rules.count) rules from UserDefaults")
        return rules.isEmpty ? nil : rules
    }

    // MARK: - Resolution

    /// Resolve a domain to an interface using the Rust engine or mock fallback.
    func resolve(domain: String) -> (interface: String, rule: String?) {
        #if ROUTEFLOW_FFI
        if let bridge = bridge {
            let iface = bridge.resolve(domain: domain) ?? defaultInterface
            let rule = bridge.resolveRule(domain: domain)
            return (iface, rule)
        }
        #endif
        return mockResolve(domain: domain)
    }



    // MARK: - Rust Bridge

    #if ROUTEFLOW_FFI
    private func initializeBridge() {
        let yaml = buildYAMLConfig()
        bridge = RouteFlowBridge(configYAML: yaml)
        if bridge != nil {
            addLog(domain: "system", interface: "--", rule: "Rust engine initialized (\(bridge!.ruleCount) rules)", level: .info)
        } else {
            addLog(domain: "system", interface: "--", rule: "Failed to initialize Rust engine, using mock", level: .warning)
        }
    }

    private func rebuildBridge() {
        let yaml = buildYAMLConfig()
        bridge = RouteFlowBridge(configYAML: yaml)
    }
    #endif

    /// Build YAML config string from current rules.
    private func buildYAMLConfig() -> String {
        var yaml = "interfaces:\n"
        for iface in interfaces {
            let typeName: String
            switch iface.type {
            case .wifi: typeName = "wifi"
            case .ethernet: typeName = "ethernet"
            case .vpn: typeName = "vpn"
            case .other: typeName = "other"
            }
            yaml += "  - name: \(iface.id)\n    type: \(typeName)\n"
        }
        yaml += "\nrules:\n"
        for rule in rules where rule.isEnabled {
            yaml += "  - \(rule.configString)\n"
        }
        yaml += "\ndefault: \(defaultInterface)\n"
        return yaml
    }

    // MARK: - Mock Resolver (fallback when Rust not linked)

    private func mockResolve(domain: String) -> (interface: String, rule: String?) {
        let lowered = domain.lowercased()
        for rule in rules where rule.isEnabled {
            let pattern = rule.pattern.lowercased()
            let matched: Bool
            switch rule.matchType {
            case .domain:
                matched = lowered == pattern
            case .domainSuffix:
                matched = lowered == pattern || lowered.hasSuffix("." + pattern)
            case .domainKeyword:
                matched = lowered.contains(pattern)
            }
            if matched {
                return (rule.interfaceId, rule.configString)
            }
        }
        return (defaultInterface, nil)
    }

    // MARK: - Logging

    private func addLog(domain: String, interface: String, rule: String?, level: LogEntry.Level) {
        let entry = LogEntry(
            domain: domain,
            resolvedInterface: interface,
            matchedRule: rule,
            level: level
        )
        DispatchQueue.main.async {
            self.logs.insert(entry, at: 0)
            if self.logs.count > 100 {
                self.logs = Array(self.logs.prefix(100))
            }
        }
    }
}

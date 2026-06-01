import Foundation

#if ROUTEFLOW_FFI

/// Swift wrapper around the Rust RouteFlow rule engine.
/// Provides a safe, idiomatic Swift API over the C FFI layer.
///
/// To enable: add `ROUTEFLOW_FFI` to Swift Active Compilation Conditions
/// and link `librouteflow_core.a` to your target.
final class RouteFlowBridge {
    private var engine: OpaquePointer?

    /// Initialize the engine from a YAML configuration file.
    /// - Parameter path: Absolute path to the YAML config file.
    /// - Returns: nil if the config file could not be loaded or parsed.
    init?(configFile path: String) {
        engine = path.withCString { cPath in
            routeflow_engine_create_from_file(cPath)
        }
        if engine == nil { return nil }
    }

    /// Initialize the engine from a YAML configuration string.
    /// - Parameter yaml: YAML configuration content.
    /// - Returns: nil if the config could not be parsed.
    init?(configYAML yaml: String) {
        engine = yaml.withCString { cYaml in
            routeflow_engine_create_from_string(cYaml)
        }
        if engine == nil { return nil }
    }

    deinit {
        if let engine = engine {
            routeflow_engine_destroy(engine)
        }
    }

    // MARK: - Public API

    /// Resolve a domain to a network interface name.
    /// - Parameter domain: The domain to resolve (e.g. "github.com").
    /// - Returns: The interface name (e.g. "wifi"), or nil on error.
    func resolve(domain: String) -> String? {
        guard let engine = engine else { return nil }

        let result = domain.withCString { cDomain in
            routeflow_resolve(engine, cDomain)
        }

        return convertAndFree(result)
    }

    /// Resolve a domain and return the matched rule description.
    /// - Parameter domain: The domain to resolve.
    /// - Returns: The rule description string, or nil if default was used.
    func resolveRule(domain: String) -> String? {
        guard let engine = engine else { return nil }

        let result = domain.withCString { cDomain in
            routeflow_resolve_rule(engine, cDomain)
        }

        return convertAndFree(result)
    }

    /// The number of rules loaded in the engine.
    var ruleCount: Int {
        guard let engine = engine else { return 0 }
        return Int(routeflow_rule_count(engine))
    }

    /// The default interface name used when no rule matches.
    var defaultInterface: String? {
        guard let engine = engine else { return nil }
        let result = routeflow_default_interface(engine)
        return convertAndFree(result)
    }

    // MARK: - Helpers

    /// Convert a C string to Swift String and free the C memory.
    private func convertAndFree(_ cString: UnsafeMutablePointer<CChar>?) -> String? {
        guard let cString = cString else { return nil }
        let swift = String(cString: cString)
        routeflow_free_string(cString)
        return swift
    }
}

// MARK: - Routing Decision

extension RouteFlowBridge {
    /// A complete routing decision with interface and optional rule match.
    struct Decision {
        let interface: String
        let matchedRule: String?

        var isDefault: Bool { matchedRule == nil }
    }

    /// Resolve a domain and return a full routing decision.
    func resolveDecision(domain: String) -> Decision? {
        guard let interface = resolve(domain: domain) else { return nil }
        let rule = resolveRule(domain: domain)
        return Decision(interface: interface, matchedRule: rule)
    }
}

#endif

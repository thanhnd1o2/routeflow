import Foundation
import NetworkExtension
import SystemExtensions
import os.log

/// Manages the RouteFlow Network Extension lifecycle.
/// Handles installation, activation, starting, and stopping the transparent proxy.
class ProxyManager: NSObject, ObservableObject {
    static let shared = ProxyManager()

    @Published var extensionStatus: ExtensionStatus = .unknown
    @Published var proxyStatus: ProxyStatus = .disconnected
    @Published var errorMessage: String?

    private let logger = Logger(subsystem: "com.whateverbest.routeflow", category: "proxy-manager")
    private var manager: NETunnelProviderManager?

    enum ExtensionStatus: String {
        case unknown = "Unknown"
        case installing = "Installing..."
        case installed = "Installed"
        case needsApproval = "Needs Approval"
        case failed = "Failed"
    }

    enum ProxyStatus: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting..."
        case connected = "Connected"
        case disconnecting = "Disconnecting..."
        case error = "Error"
    }

    private override init() {
        super.init()
    }

    // MARK: - System Extension Installation

    /// Install the Network Extension as a System Extension.
    func installExtension() {
        extensionStatus = .installing
        logger.info("Requesting system extension installation...")

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.whateverbest.routeflow.extension",
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: - Proxy Configuration

    /// Load or create the VPN/proxy configuration.
    func loadConfiguration() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()

            if let existing = managers.first {
                manager = existing
                logger.info("Loaded existing proxy configuration")
            } else {
                manager = createNewManager()
                try await manager?.saveToPreferences()
                logger.info("Created new proxy configuration")
            }

            updateProxyStatus()
        } catch {
            logger.error("Failed to load configuration: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func createNewManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "RouteFlow"

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.whateverbest.routeflow.extension"
        proto.serverAddress = "RouteFlow"

        manager.protocolConfiguration = proto
        manager.isEnabled = true

        return manager
    }

    // MARK: - Start / Stop

    /// Start the transparent proxy.
    func startProxy() async {
        guard let manager = manager else {
            errorMessage = "No proxy configuration loaded"
            return
        }

        proxyStatus = .connecting

        do {
            try manager.connection.startVPNTunnel()
            proxyStatus = .connected
            logger.info("Proxy started")
        } catch {
            proxyStatus = .error
            errorMessage = error.localizedDescription
            logger.error("Failed to start proxy: \(error.localizedDescription)")
        }
    }

    /// Stop the transparent proxy.
    func stopProxy() {
        guard let manager = manager else { return }

        proxyStatus = .disconnecting
        manager.connection.stopVPNTunnel()
        proxyStatus = .disconnected
        logger.info("Proxy stopped")
    }

    // MARK: - Status

    private func updateProxyStatus() {
        guard let manager = manager else {
            proxyStatus = .disconnected
            return
        }

        switch manager.connection.status {
        case .invalid, .disconnected:
            proxyStatus = .disconnected
        case .connecting:
            proxyStatus = .connecting
        case .connected:
            proxyStatus = .connected
        case .disconnecting:
            proxyStatus = .disconnecting
        case .reasserting:
            proxyStatus = .connecting
        @unknown default:
            proxyStatus = .disconnected
        }
    }

    // MARK: - Shared Config

    /// Write the current rules to the shared App Group container
    /// so the extension can read them.
    func syncRulesToExtension(rules: [RoutingRule], interfaces: [NetworkInterface], defaultInterface: String) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.whateverbest.routeflow"
        ) else {
            logger.error("Cannot access App Group container")
            return
        }

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

        let configURL = containerURL.appendingPathComponent("rules.yaml")
        do {
            try yaml.write(to: configURL, atomically: true, encoding: .utf8)
            logger.info("Rules synced to extension (\(rules.count) rules)")
        } catch {
            logger.error("Failed to write rules: \(error.localizedDescription)")
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension ProxyManager: OSSystemExtensionRequestDelegate {
    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        switch result {
        case .completed:
            extensionStatus = .installed
            logger.info("System extension installed successfully")
            Task { await loadConfiguration() }
        case .willCompleteAfterReboot:
            extensionStatus = .needsApproval
            logger.info("System extension will complete after reboot")
        @unknown default:
            extensionStatus = .unknown
        }
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: Error
    ) {
        extensionStatus = .failed
        errorMessage = error.localizedDescription
        logger.error("System extension failed: \(error.localizedDescription)")
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        extensionStatus = .needsApproval
        logger.info("System extension needs user approval in System Settings")
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }
}

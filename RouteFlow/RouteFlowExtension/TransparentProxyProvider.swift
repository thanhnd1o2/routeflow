import NetworkExtension
import Network
import os.log

/// RouteFlow Transparent Proxy Provider.
/// Intercepts outbound TCP connections, extracts the destination hostname,
/// queries the Rust rule engine for a routing decision, and directs traffic
/// to the appropriate network interface.
class TransparentProxyProvider: NETransparentProxyProvider {

    private let logger = Logger(subsystem: "com.whateverbest.routeflow.extension", category: "proxy")
    private let trafficReporter = TrafficReporter()
    private var pathMonitor: NWPathMonitor?
    private var availableInterfaces: [NWInterface] = []

    #if ROUTEFLOW_FFI
    private var bridge: RouteFlowBridge?
    #endif

    // MARK: - Lifecycle

    override func startProxy(options: [String: Any]? = nil) async throws {
        logger.info("RouteFlow proxy starting...")

        #if ROUTEFLOW_FFI
        loadRulesEngine()
        #endif

        startInterfaceMonitoring()

        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // Include all outbound TCP traffic
        let networkRule = NENetworkRule(
            remoteNetwork: nil,
            remotePrefix: 0,
            localNetwork: nil,
            localPrefix: 0,
            protocol: .TCP,
            direction: .outbound
        )

        settings.includedNetworkRules = [networkRule]

        try await setTunnelNetworkSettings(settings)
        logger.info("RouteFlow proxy started successfully")
    }

    override func stopProxy(with reason: NEProviderStopReason) async {
        logger.info("RouteFlow proxy stopping, reason: \(String(describing: reason))")
        pathMonitor?.cancel()
        pathMonitor = nil
        #if ROUTEFLOW_FFI
        bridge = nil
        #endif
    }

    // MARK: - Connection Handling

    override func handleNewFlow(_ flow: NETransparentProxyFlow) -> Bool {
        guard let tcpFlow = flow as? NETransparentProxyTCPFlow else {
            return false
        }

        let hostname = extractHostname(from: tcpFlow)
        let interfaceName = resolveInterface(for: hostname)
        let remotePort = extractPort(from: tcpFlow)
        let connectionID = UUID()

        logger.debug("Flow \(connectionID.uuidString.prefix(8)): \(hostname):\(remotePort) → \(interfaceName)")

        // Report connection start
        trafficReporter.reportConnectionStart(
            id: connectionID,
            domain: hostname,
            interface: interfaceName,
            remotePort: remotePort
        )

        // Handle the flow with interface binding
        Task {
            await handleTCPFlow(tcpFlow, interface: interfaceName, connectionID: connectionID)
        }

        return true
    }

    // MARK: - Flow Management with Interface Binding

    private func handleTCPFlow(_ flow: NETransparentProxyTCPFlow, interface: String, connectionID: UUID) async {
        guard let endpoint = flow.remoteEndpoint as? NWHostEndpoint else {
            trafficReporter.reportConnectionEnd(id: connectionID, error: true)
            return
        }

        // Create an outbound NWConnection bound to the target interface
        let host = NWEndpoint.Host(endpoint.hostname)
        let port = NWEndpoint.Port(endpoint.port) ?? NWEndpoint.Port(integerLiteral: 443)

        let parameters = NWParameters.tcp
        if let nwInterface = findInterface(named: interface) {
            parameters.requiredInterface = nwInterface
            logger.debug("Binding to interface: \(nwInterface.name)")
        }

        let connection = NWConnection(host: host, port: port, using: parameters)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logger.debug("Outbound connection ready for \(endpoint.hostname)")
                self.startRelay(flow: flow, connection: connection, connectionID: connectionID)
            case .failed(let error):
                self.logger.error("Outbound connection failed: \(error.localizedDescription)")
                self.trafficReporter.reportConnectionEnd(id: connectionID, error: true)
                flow.closeReadWithError(error as? Error)
                flow.closeWriteWithError(error as? Error)
            case .cancelled:
                self.trafficReporter.reportConnectionEnd(id: connectionID, error: false)
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    /// Relay data bidirectionally between the NETransparentProxyTCPFlow and the NWConnection.
    private func startRelay(flow: NETransparentProxyTCPFlow, connection: NWConnection, connectionID: UUID) {
        // Flow → Connection (app sends data out)
        relayFlowToConnection(flow: flow, connection: connection, connectionID: connectionID)
        // Connection → Flow (remote sends data back)
        relayConnectionToFlow(flow: flow, connection: connection, connectionID: connectionID)
    }

    private func relayFlowToConnection(flow: NETransparentProxyTCPFlow, connection: NWConnection, connectionID: UUID) {
        flow.readData { [weak self] data, error in
            guard let self else { return }

            if let error = error {
                self.logger.debug("Flow read ended: \(error.localizedDescription)")
                connection.cancel()
                self.trafficReporter.reportConnectionEnd(id: connectionID, error: false)
                return
            }

            guard let data = data, !data.isEmpty else {
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
                return
            }

            self.trafficReporter.reportBytesOut(id: connectionID, bytes: UInt64(data.count))

            connection.send(content: data, completion: .contentProcessed { sendError in
                if let sendError = sendError {
                    self.logger.debug("Connection send error: \(sendError.localizedDescription)")
                    return
                }
                // Continue reading from flow
                self.relayFlowToConnection(flow: flow, connection: connection, connectionID: connectionID)
            })
        }
    }

    private func relayConnectionToFlow(flow: NETransparentProxyTCPFlow, connection: NWConnection, connectionID: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error = error {
                self.logger.debug("Connection receive error: \(error.localizedDescription)")
                flow.closeReadWithError(nil)
                self.trafficReporter.reportConnectionEnd(id: connectionID, error: true)
                return
            }

            if let data = data, !data.isEmpty {
                self.trafficReporter.reportBytesIn(id: connectionID, bytes: UInt64(data.count))

                flow.write(data) { writeError in
                    if let writeError = writeError {
                        self.logger.debug("Flow write error: \(writeError.localizedDescription)")
                        connection.cancel()
                        return
                    }
                    if !isComplete {
                        self.relayConnectionToFlow(flow: flow, connection: connection, connectionID: connectionID)
                    }
                }
            }

            if isComplete {
                flow.closeWriteWithError(nil)
                self.trafficReporter.reportConnectionEnd(id: connectionID, error: false)
            }
        }
    }

    // MARK: - Interface Monitoring

    private func startInterfaceMonitoring() {
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            self?.availableInterfaces = path.availableInterfaces
            self?.logger.debug("Interfaces updated: \(path.availableInterfaces.map { $0.name })")
        }
        pathMonitor?.start(queue: DispatchQueue(label: "com.routeflow.path-monitor"))
    }

    /// Find a real NWInterface by name or type.
    private func findInterface(named name: String) -> NWInterface? {
        let lowered = name.lowercased()

        // Try exact name match first
        if let exact = availableInterfaces.first(where: { $0.name == name }) {
            return exact
        }

        // Match by type keyword
        switch lowered {
        case "wifi", "wi-fi":
            return availableInterfaces.first(where: { $0.type == .wifi })
        case "ethernet", "wired":
            return availableInterfaces.first(where: { $0.type == .wiredEthernet })
        case "vpn", "tunnel":
            return availableInterfaces.first(where: { $0.type == .other })
        case "cellular":
            return availableInterfaces.first(where: { $0.type == .cellular })
        default:
            return nil
        }
    }

    // MARK: - Hostname & Port Extraction

    private func extractHostname(from flow: NETransparentProxyTCPFlow) -> String {
        if let endpoint = flow.remoteEndpoint as? NWHostEndpoint {
            return endpoint.hostname
        }
        return "unknown"
    }

    private func extractPort(from flow: NETransparentProxyTCPFlow) -> UInt16 {
        if let endpoint = flow.remoteEndpoint as? NWHostEndpoint,
           let port = UInt16(endpoint.port) {
            return port
        }
        return 0
    }

    // MARK: - Interface Resolution

    private func resolveInterface(for hostname: String) -> String {
        #if ROUTEFLOW_FFI
        if let bridge = bridge,
           let iface = bridge.resolve(domain: hostname) {
            return iface
        }
        #endif
        return "wifi"
    }

    // MARK: - Rules Engine

    #if ROUTEFLOW_FFI
    private func loadRulesEngine() {
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.whateverbest.routeflow"
        ) {
            let configPath = containerURL.appendingPathComponent("rules.yaml").path
            if FileManager.default.fileExists(atPath: configPath) {
                bridge = RouteFlowBridge(configFile: configPath)
                if let bridge = bridge {
                    logger.info("Rust engine loaded: \(bridge.ruleCount) rules")
                } else {
                    logger.error("Failed to initialize Rust engine from \(configPath)")
                    loadDefaultConfig()
                }
            } else {
                logger.warning("No config at \(configPath), using defaults")
                loadDefaultConfig()
            }
        } else {
            logger.error("Cannot access App Group container")
            loadDefaultConfig()
        }
    }

    private func loadDefaultConfig() {
        let yaml = """
        interfaces:
          - name: wifi
            type: wifi
          - name: ethernet
            type: ethernet
        rules:
          - DOMAIN-SUFFIX,github.com,wifi
          - DOMAIN-SUFFIX,company.com,ethernet
        default: wifi
        """
        bridge = RouteFlowBridge(configYAML: yaml)
    }
    #endif
}

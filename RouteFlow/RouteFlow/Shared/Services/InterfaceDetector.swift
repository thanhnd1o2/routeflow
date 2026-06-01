import Foundation
import Network

/// Detects real network interfaces on the system using NWPathMonitor.
class InterfaceDetector: ObservableObject {
    @Published var interfaces: [NetworkInterface] = []

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.routeflow.interface-detector")

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { [weak self] path in
            var seen = Set<String>()
            let detected = path.availableInterfaces.compactMap { iface -> NetworkInterface? in
                // Deduplicate by interface name
                guard !seen.contains(iface.name) else { return nil }
                seen.insert(iface.name)
                return NetworkInterface(
                    id: iface.name,
                    name: Self.displayName(for: iface),
                    type: Self.mapType(iface.type),
                    isActive: path.status == .satisfied
                )
            }

            DispatchQueue.main.async {
                self?.interfaces = detected
            }
        }
        monitor?.start(queue: queue)
    }

    func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
    }

    // MARK: - Helpers

    private static func mapType(_ type: NWInterface.InterfaceType) -> NetworkInterface.InterfaceType {
        switch type {
        case .wifi:
            return .wifi
        case .wiredEthernet:
            return .ethernet
        case .cellular:
            return .other
        case .loopback:
            return .other
        case .other:
            return .vpn
        @unknown default:
            return .other
        }
    }

    private static func displayName(for iface: NWInterface) -> String {
        switch iface.type {
        case .wifi:
            return "Wi-Fi (\(iface.name))"
        case .wiredEthernet:
            return "Ethernet (\(iface.name))"
        case .cellular:
            return "Cellular (\(iface.name))"
        case .loopback:
            return "Loopback (\(iface.name))"
        case .other:
            return "VPN/Other (\(iface.name))"
        @unknown default:
            return iface.name
        }
    }
}

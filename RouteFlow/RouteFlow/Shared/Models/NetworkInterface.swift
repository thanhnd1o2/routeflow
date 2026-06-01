import Foundation

/// Represents a network interface available on the system.
struct NetworkInterface: Identifiable, Hashable {
    let id: String
    let name: String
    let type: InterfaceType
    var isActive: Bool

    enum InterfaceType: String, CaseIterable {
        case wifi = "Wi-Fi"
        case ethernet = "Ethernet"
        case vpn = "VPN"
        case other = "Other"

        var icon: String {
            switch self {
            case .wifi: return "wifi"
            case .ethernet: return "cable.connector"
            case .vpn: return "lock.shield"
            case .other: return "network"
            }
        }
    }
}

extension NetworkInterface {
    static let mockInterfaces: [NetworkInterface] = [
        NetworkInterface(id: "wifi", name: "Wi-Fi", type: .wifi, isActive: true),
        NetworkInterface(id: "ethernet", name: "Ethernet", type: .ethernet, isActive: true),
        NetworkInterface(id: "vpn", name: "VPN", type: .vpn, isActive: false),
    ]
}

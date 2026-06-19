import Foundation

/// A human-readable label for the machine the benchmark ran on.
/// On iOS this resolves the marketing name (e.g. "iPhone 14 Pro Max"); on macOS the model id.
enum DeviceInfo {

    static var label: String {
        #if os(macOS)
        let id = sysctl("hw.model") ?? "Mac"
        return "\(marketingName(for: id)) · \(id)"
        #else
        let id = machineIdentifier
        let name = marketingName(for: id)
        return name == id ? id : "\(name)"
        #endif
    }

    static var machineIdentifier: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        #if os(macOS)
        return sysctl("hw.model") ?? "Mac"
        #else
        return sysctl("hw.machine") ?? "iPhone"
        #endif
        #endif
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    /// Minimal map for the devices most likely in the room. Unknown ids fall back to the identifier.
    private static func marketingName(for id: String) -> String {
        let map: [String: String] = [
            // iPhones (A-series)
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
        ]
        return map[id] ?? id
    }
}

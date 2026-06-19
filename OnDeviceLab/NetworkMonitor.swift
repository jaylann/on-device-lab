import Foundation
import Network

/// Milestone 3: a live online/offline indicator. Turn off Wi-Fi mid-generation and watch
/// this flip to "offline" while tokens keep streaming — that's the whole point of the talk.
@MainActor
@Observable
final class NetworkMonitor {
    var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = (path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "dev.lanfermann.ondevicelab.net"))
    }
}

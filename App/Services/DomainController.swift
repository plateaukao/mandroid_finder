import FileProvider
import Foundation
import Observation
import MandroidCore

/// Reconciles the set of registered `NSFileProviderDomain`s with the set of
/// currently-connected devices. One domain per device serial — the system
/// uses the identifier as a stable key, so replug → same sidebar entry.
@MainActor
@Observable
final class DomainController {
    private(set) var registeredSerials: Set<String> = []

    func reconcile(with devices: [DeviceInfo]) async {
        let connected = Set(devices.map(\.serial))

        let systemDomains = (try? await loadAllDomains()) ?? []
        let systemSerials = Set(systemDomains.map(\.identifier.rawValue))

        for device in devices where !systemSerials.contains(device.serial) {
            let domain = NSFileProviderDomain(
                identifier: NSFileProviderDomainIdentifier(device.serial),
                displayName: device.uniqueDisplayName(among: devices)
            )
            try? await NSFileProviderManager.add(domain)
        }

        for domain in systemDomains where !connected.contains(domain.identifier.rawValue) {
            try? await NSFileProviderManager.remove(domain)
        }

        registeredSerials = connected
    }

    func removeAll() async {
        let systemDomains = (try? await loadAllDomains()) ?? []
        for domain in systemDomains {
            try? await NSFileProviderManager.remove(domain)
        }
        registeredSerials.removeAll()
    }

    private func loadAllDomains() async throws -> [NSFileProviderDomain] {
        try await withCheckedThrowingContinuation { cont in
            NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: domains)
                }
            }
        }
    }
}

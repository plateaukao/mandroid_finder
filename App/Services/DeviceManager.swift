import Foundation
import Observation
import MandroidCore

@MainActor
@Observable
final class DeviceManager {
    private(set) var devices: [DeviceInfo] = []
    private(set) var lastError: String?

    private var pollingTask: Task<Void, Never>?
    private let pollInterval: Duration = .seconds(2)

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func pollOnce() async {
        await poll()
    }

    private func poll() async {
        do {
            let snapshot = try await ADBService.shared.devices()
                .filter { $0.isOnline }
            if snapshot != self.devices {
                self.devices = snapshot
            }
            self.lastError = nil
        } catch {
            self.lastError = String(describing: error)
        }
    }
}

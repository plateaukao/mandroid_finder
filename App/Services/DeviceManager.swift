import Foundation
import Observation
import MandroidCore

@MainActor
@Observable
final class DeviceManager {
    private(set) var devices: [DeviceInfo] = []
    private(set) var lastError: String?
    private(set) var firstUpdateReceived = false

    private var trackingTask: Task<Void, Never>?
    private var firstUpdateContinuation: CheckedContinuation<Void, Never>?

    /// 2-second back-off between failed `host:track-devices` connection
    /// attempts (server not running, mid-`adb kill-server`, etc.).
    private let reconnectBackoff: Duration = .seconds(2)

    func start() {
        guard trackingTask == nil else { return }
        trackingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.runStream()
                try? await Task.sleep(for: self.reconnectBackoff)
            }
        }
    }

    func stop() {
        trackingTask?.cancel()
        trackingTask = nil
    }

    /// Resolves the first time we either receive a snapshot from the adb
    /// server or fail to connect. Used by app bootstrap to perform the
    /// initial domain reconcile against a known device list rather than
    /// against the empty placeholder.
    func awaitFirstUpdate() async {
        if firstUpdateReceived { return }
        await withCheckedContinuation { cont in
            firstUpdateContinuation = cont
        }
    }

    private func runStream() async {
        do {
            for try await snapshot in ADBService.shared.trackDevices() {
                let online = snapshot.filter { $0.isOnline }
                if online != self.devices {
                    self.devices = online
                }
                self.lastError = nil
                signalFirstUpdate()
            }
            // Stream ended cleanly (server closed without error). Treat as
            // disconnect — caller will back off and reconnect.
            self.devices = []
            self.lastError = "adb server closed connection"
            signalFirstUpdate()
        } catch {
            self.devices = []
            self.lastError = String(describing: error)
            signalFirstUpdate()
        }
    }

    private func signalFirstUpdate() {
        guard !firstUpdateReceived else { return }
        firstUpdateReceived = true
        firstUpdateContinuation?.resume()
        firstUpdateContinuation = nil
    }
}

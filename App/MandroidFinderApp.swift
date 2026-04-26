import SwiftUI
import MandroidCore

@main
struct MandroidFinderApp: App {
    @State private var deviceManager = DeviceManager()
    @State private var domainController = DomainController()

    var body: some Scene {
        WindowGroup("Mandroid Finder") {
            StatusWindow(
                deviceManager: deviceManager,
                domainController: domainController
            )
            .task {
                await bootstrap()
            }
            .onChange(of: deviceManager.devices) { _, newDevices in
                Task { await domainController.reconcile(with: newDevices) }
            }
        }
        .windowResizability(.contentSize)
    }

    private func bootstrap() async {
        deviceManager.start()
        await deviceManager.pollOnce()
        await domainController.reconcile(with: deviceManager.devices)
    }
}

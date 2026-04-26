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
        // Wait for the first track-devices snapshot (or first connection
        // failure) before reconciling so we don't blindly remove every
        // existing domain on launch when the adb server is briefly slow.
        await deviceManager.awaitFirstUpdate()
        await domainController.reconcile(with: deviceManager.devices)
    }
}

import SwiftUI
import MandroidCore

struct StatusWindow: View {
    @Bindable var deviceManager: DeviceManager
    @Bindable var domainController: DomainController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            serverStatus
            Divider()
            deviceList
            Spacer()
            footer
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 340)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mandroid Finder")
                .font(.title2.bold())
            Text("Connected Android devices appear under Locations in any Finder window.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var serverStatus: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ADB server:")
                .fontWeight(.medium)
            if deviceManager.lastError == nil {
                Label("connected (127.0.0.1:5037)", systemImage: "circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(.body, design: .monospaced))
            } else {
                Label("unreachable — start adb (e.g. `adb start-server`)", systemImage: "circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Devices")
                .fontWeight(.medium)
            if deviceManager.devices.isEmpty {
                Text("No devices connected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(deviceManager.devices) { device in
                    HStack {
                        Image(systemName: "iphone")
                        VStack(alignment: .leading) {
                            Text(device.displayName)
                            Text(device.serial)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if domainController.registeredSerials.contains(device.serial) {
                            Label("In Finder", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var footer: some View {
        Group {
            if let err = deviceManager.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

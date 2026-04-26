import Foundation

public struct DeviceInfo: Sendable, Hashable, Identifiable, Codable {
    public let serial: String
    public let state: String
    public let model: String?

    public var id: String { serial }

    public var displayName: String {
        if let model, !model.isEmpty { return model }
        return serial
    }

    /// Returns a display name guaranteed to be unique within `peers`.
    /// Two devices with the same model get a serial-suffixed disambiguator.
    public func uniqueDisplayName(among peers: [DeviceInfo]) -> String {
        let base = displayName
        let collisions = peers.filter { $0.displayName == base }
        if collisions.count <= 1 { return base }
        return "\(base) (\(serial.suffix(6)))"
    }

    public init(serial: String, state: String, model: String? = nil) {
        self.serial = serial
        self.state = state
        self.model = model
    }

    public var isOnline: Bool { state == "device" }
}

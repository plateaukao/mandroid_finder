import Foundation

public enum AppGroup {
    /// Derived from the running bundle's identifier so the Swift code holds
    /// no reverse-domain prefix. Both targets ship with App Group entitlement
    /// `group.<host-bundle-id>`. The host's bundle ID is the prefix; the
    /// extension/framework bundle IDs add `.fileprovider` / `.core` suffixes
    /// which we strip to recover the prefix.
    public static var identifier: String {
        var bid = Bundle.main.bundleIdentifier ?? ""
        for suffix in [".fileprovider", ".core"] {
            if bid.hasSuffix(suffix) {
                bid.removeLast(suffix.count)
                break
            }
        }
        return "group.\(bid)"
    }

    public enum Keys {
        public static let adbPath = "adbPath"
        public static let knownDeviceSerials = "knownDeviceSerials"
    }

    public static var defaults: UserDefaults {
        guard let suite = UserDefaults(suiteName: identifier) else {
            return .standard
        }
        return suite
    }
}

/// Writes diagnostic lines to a file inside the calling process's sandbox
/// container at `~/Library/Containers/<bundle-id>/Data/Library/Caches/mandroid.log`.
/// Used during development to debug extension activity, since NSLog from a
/// sandboxed extension is heavily redacted in the unified log.
public enum ContainerLog {
    private static let url: URL? = {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir.appendingPathComponent("mandroid.log")
    }()

    public static func write(_ msg: String) {
        guard let url else { return }
        let line = "\(Date()) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}


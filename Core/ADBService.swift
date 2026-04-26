import Foundation

public enum ADBError: Error, CustomStringConvertible {
    case serverUnreachable(Error?)
    case serverFailed(String)
    case protocolError(String)
    case ioError(Error)
    case shellExitNonZero(stderr: String)

    public var description: String {
        switch self {
        case .serverUnreachable(let underlying):
            if let underlying { return "adb server unreachable: \(underlying)" }
            return "adb server unreachable (is it running? try `adb start-server`)"
        case .serverFailed(let msg): return "adb server returned FAIL: \(msg)"
        case .protocolError(let msg): return "adb protocol error: \(msg)"
        case .ioError(let underlying): return "adb i/o error: \(underlying)"
        case .shellExitNonZero(let stderr): return "shell command failed: \(stderr)"
        }
    }
}

public actor ADBService {
    public static let shared = ADBService()

    public init() {}

    /// No-op kept for source-compat with earlier versions that needed to be
    /// told where adb lived on disk.
    public func setPath(_ path: String?) {}

    // MARK: - Devices

    public func devices() async throws -> [DeviceInfo] {
        try await ADBClient.devices()
    }

    // MARK: - Filesystem

    public func list(serial: String, path: String) async throws -> [AndroidFile] {
        guard !path.isEmpty else { return [] }
        // Trailing slash forces ls to list the target's contents when the path
        // is a symlink (e.g., /sdcard -> /storage/self/primary on Android).
        let listed = path.hasSuffix("/") ? path : path + "/"
        let output = try await ADBClient.shell(serial: serial, command: "ls -la \(quoted(listed))")
        return LSParser.parse(output, parentPath: path)
    }

    public func mkdir(serial: String, path: String) async throws {
        _ = try await ADBClient.shell(serial: serial, command: "mkdir -p \(quoted(path))")
    }

    public func remove(serial: String, path: String) async throws {
        _ = try await ADBClient.shell(serial: serial, command: "rm -rf \(quoted(path))")
    }

    public func rename(serial: String, from: String, to: String) async throws {
        _ = try await ADBClient.shell(serial: serial, command: "mv \(quoted(from)) \(quoted(to))")
    }

    // MARK: - Transfers

    public func pull(serial: String, remote: String, localFile: URL) async throws {
        let conn = try await ADBClient.openTransport(serial: serial)
        defer { conn.close() }
        try await ADBSync.enter(conn)
        try await ADBSync.recv(conn, remotePath: remote, into: localFile)
    }

    public func push(serial: String, localFile: URL, remote: String) async throws {
        let conn = try await ADBClient.openTransport(serial: serial)
        defer { conn.close() }
        try await ADBSync.enter(conn)
        try await ADBSync.send(conn, localFile: localFile, remotePath: remote)
    }

    private func quoted(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

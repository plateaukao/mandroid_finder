import Foundation

/// High-level adb client built on `ADBConnection`. Implements the host-service
/// handshake, the transport-switch step, and shell-mode reads.
///
/// Wire protocol (https://android.googlesource.com/platform/packages/modules/adb):
///
///   client → server:  "<4-hex-len><utf8 service string>"
///   server → client:  "OKAY" (success) or "FAIL<4-hex-len><utf8 message>"
///
/// After a `host:transport:<serial>` switch, the connection is bound to a
/// single device and the next framed request is interpreted by that device
/// instead of the host server.
public enum ADBClient {

    // MARK: - Public

    public static func devices() async throws -> [DeviceInfo] {
        let conn = try await ADBConnection.connect()
        defer { conn.close() }
        try await sendService(conn, "host:devices-l")
        try await readStatus(conn)
        let payload = try await readHexLengthPayload(conn)
        return parseDevicesL(payload)
    }

    /// Runs `command` on the device's shell and returns combined stdout+stderr.
    /// Uses lossy UTF-8 decoding so non-UTF-8 filenames (Shift-JIS, GBK, …)
    /// still surface — invalid bytes become U+FFFD.
    public static func shell(serial: String, command: String) async throws -> String {
        let conn = try await openTransport(serial: serial)
        defer { conn.close() }
        try await sendService(conn, "shell:\(command)")
        try await readStatus(conn)
        let raw = try await conn.readUntilClose()
        return String(decoding: raw, as: UTF8.self)
    }

    /// Opens a connection and binds it to the given device. Caller is
    /// responsible for closing. Used by both shell and sync clients.
    public static func openTransport(serial: String) async throws -> ADBConnection {
        let conn = try await ADBConnection.connect()
        do {
            try await sendService(conn, "host:transport:\(serial)")
            try await readStatus(conn)
            return conn
        } catch {
            conn.close()
            throw error
        }
    }

    // MARK: - Framing helpers

    /// Writes a framed host-service request: 4-byte ASCII hex length + payload.
    public static func sendService(_ conn: ADBConnection, _ service: String) async throws {
        guard let payload = service.data(using: .utf8) else {
            throw ADBError.protocolError("non-utf8 service string")
        }
        guard payload.count <= 0xFFFF else {
            throw ADBError.protocolError("service string too long: \(payload.count) bytes")
        }
        let header = String(format: "%04x", payload.count)
        guard let headerBytes = header.data(using: .ascii) else {
            throw ADBError.protocolError("could not encode hex length")
        }
        try await conn.send(headerBytes + payload)
    }

    /// Reads the 4-byte status word and translates FAIL into a thrown error.
    public static func readStatus(_ conn: ADBConnection) async throws {
        let status = try await conn.readExact(4)
        let s = String(decoding: status, as: UTF8.self)
        switch s {
        case "OKAY":
            return
        case "FAIL":
            let payload = try await readHexLengthPayload(conn)
            let message = String(decoding: payload, as: UTF8.self)
            throw ADBError.serverFailed(message)
        default:
            throw ADBError.protocolError("unexpected status word: \(s)")
        }
    }

    /// Reads a 4-byte ASCII hex length, then that many bytes of payload.
    public static func readHexLengthPayload(_ conn: ADBConnection) async throws -> Data {
        let header = try await conn.readExact(4)
        let s = String(decoding: header, as: UTF8.self)
        guard let length = Int(s, radix: 16) else {
            throw ADBError.protocolError("bad hex length: \(s)")
        }
        if length == 0 { return Data() }
        return try await conn.readExact(length)
    }

    // MARK: - Parsers

    /// Parses `host:devices-l` payload (one line per device, space-separated):
    /// `6DB5F8BF       device usb:2-1 product:GoColor7 model:GoColor7 device:GoColor7 transport_id:2`
    static func parseDevicesL(_ data: Data) -> [DeviceInfo] {
        let text = String(decoding: data, as: UTF8.self)
        var result: [DeviceInfo] = []
        for raw in text.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 2 else { continue }
            let serial = cols[0]
            let state = cols[1]
            var model: String?
            for token in cols.dropFirst(2) where token.hasPrefix("model:") {
                model = String(token.dropFirst("model:".count))
                    .replacingOccurrences(of: "_", with: " ")
            }
            result.append(DeviceInfo(serial: serial, state: state, model: model))
        }
        return result
    }
}

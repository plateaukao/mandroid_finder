import Foundation

/// adb sync sub-protocol — used after `host:transport:<serial>` followed by
/// the `sync:` framed service. Once entered, the connection speaks 8-byte
/// frames: 4-byte ASCII command + 4-byte little-endian uint32. The uint32
/// is variously a length, mode, or mtime depending on the command.
///
/// Reference: https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/SYNC.TXT
public enum ADBSync {

    // MARK: - Tags

    private static let STAT = ascii("STAT")
    private static let RECV = ascii("RECV")
    private static let SEND = ascii("SEND")
    private static let LIST = ascii("LIST")
    private static let DATA = ascii("DATA")
    private static let DONE = ascii("DONE")
    private static let OKAY = ascii("OKAY")
    private static let FAIL = ascii("FAIL")
    private static let DENT = ascii("DENT")

    /// Sync data frames may not exceed 64 KiB of payload.
    private static let maxFramePayload = 64 * 1024

    // MARK: - Mode

    /// Tells the connection to switch into the sync sub-protocol.
    /// Must be called after `ADBClient.openTransport(serial:)`.
    public static func enter(_ conn: ADBConnection) async throws {
        try await ADBClient.sendService(conn, "sync:")
        try await ADBClient.readStatus(conn)
    }

    /// Pulls a remote file into a local URL.
    public static func recv(_ conn: ADBConnection, remotePath: String, into localURL: URL) async throws {
        try await writeRequest(tag: RECV, payload: remotePath, conn: conn)

        let fm = FileManager.default
        if fm.fileExists(atPath: localURL.path) {
            try fm.removeItem(at: localURL)
        }
        fm.createFile(atPath: localURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: localURL) else {
            throw ADBError.ioError(NSError(domain: NSPOSIXErrorDomain, code: 13))
        }
        defer { try? handle.close() }

        while true {
            let header = try await conn.readExact(8)
            let tag = Data(header.prefix(4))
            let length = leUInt32(header.suffix(4))

            if tag == DATA {
                let chunk = try await conn.readExact(Int(length))
                try handle.write(contentsOf: chunk)
            } else if tag == DONE {
                return
            } else if tag == FAIL {
                let msg = try await conn.readExact(Int(length))
                throw ADBError.serverFailed(String(decoding: msg, as: UTF8.self))
            } else {
                throw ADBError.protocolError(
                    "unexpected sync tag during RECV: \(String(decoding: tag, as: UTF8.self))"
                )
            }
        }
    }

    /// Pushes a local file to a remote path. Mode defaults to 0644 for files.
    public static func send(
        _ conn: ADBConnection,
        localFile: URL,
        remotePath: String,
        mode: UInt32 = 0o100644
    ) async throws {
        // SEND header carries "path,mode" as a single string.
        let header = "\(remotePath),\(mode)"
        try await writeRequest(tag: SEND, payload: header, conn: conn)

        guard let handle = try? FileHandle(forReadingFrom: localFile) else {
            throw ADBError.ioError(NSError(domain: NSPOSIXErrorDomain, code: 2))
        }
        defer { try? handle.close() }

        while autoreleasepool(invoking: { true }) {
            let chunk = try handle.read(upToCount: maxFramePayload) ?? Data()
            if chunk.isEmpty { break }
            var frame = Data()
            frame.append(DATA)
            frame.append(leUInt32Bytes(UInt32(chunk.count)))
            frame.append(chunk)
            try await conn.send(frame)
        }

        // DONE carries the file's mtime in the length slot.
        let mtime = UInt32(Date().timeIntervalSince1970)
        var done = Data()
        done.append(DONE)
        done.append(leUInt32Bytes(mtime))
        try await conn.send(done)

        // Server replies OKAY (length 0) or FAIL + msg.
        let reply = try await conn.readExact(8)
        let replyTag = Data(reply.prefix(4))
        let replyLen = leUInt32(reply.suffix(4))
        if replyTag == OKAY {
            return
        } else if replyTag == FAIL {
            let msg = try await conn.readExact(Int(replyLen))
            throw ADBError.serverFailed(String(decoding: msg, as: UTF8.self))
        } else {
            throw ADBError.protocolError(
                "unexpected sync reply after SEND: \(String(decoding: replyTag, as: UTF8.self))"
            )
        }
    }

    // MARK: - Helpers

    /// Writes a sync request: tag(4) + len(4LE) + UTF-8 payload.
    private static func writeRequest(tag: Data, payload: String, conn: ADBConnection) async throws {
        guard let bytes = payload.data(using: .utf8) else {
            throw ADBError.protocolError("non-utf8 sync payload")
        }
        var frame = Data()
        frame.append(tag)
        frame.append(leUInt32Bytes(UInt32(bytes.count)))
        frame.append(bytes)
        try await conn.send(frame)
    }

    // MARK: - Bytes

    private static func ascii(_ s: String) -> Data { s.data(using: .ascii)! }

    private static func leUInt32(_ d: Data) -> UInt32 {
        precondition(d.count == 4)
        let b = Array(d)
        return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
    }

    private static func leUInt32Bytes(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }
}

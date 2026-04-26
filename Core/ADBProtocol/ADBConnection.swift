import Foundation
import Network

/// One short-lived TCP connection to the local adb server. Wraps `NWConnection`
/// and exposes blocking `async` reads/writes. Each top-level adb operation
/// (devices, shell, sync) opens a fresh connection — adb's protocol is
/// stateful per connection (host:transport:<serial> rebinds the connection
/// to a single device) and connections are cheap.
public final class ADBConnection: @unchecked Sendable {
    public static let defaultHost = "127.0.0.1"
    public static let defaultPort: UInt16 = 5037
    public static let connectTimeout: TimeInterval = 2.0

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "MandroidFinder.adb.connection")

    private init(connection: NWConnection) {
        self.connection = connection
    }

    /// Opens a connection to the adb server and waits for it to be ready.
    /// Throws `ADBError.serverUnreachable` if the server isn't running.
    public static func connect(
        host: String = defaultHost,
        port: UInt16 = defaultPort
    ) async throws -> ADBConnection {
        let endpoint = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ADBError.protocolError("invalid port \(port)")
        }
        let nw = NWConnection(host: endpoint, port: nwPort, using: .tcp)
        let conn = ADBConnection(connection: nw)
        try await conn.waitForReady()
        return conn
    }

    private func waitForReady() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = AtomicFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.set() { cont.resume() }
                case .failed(let err):
                    if resumed.set() { cont.resume(throwing: ADBError.serverUnreachable(err)) }
                case .cancelled:
                    if resumed.set() { cont.resume(throwing: ADBError.serverUnreachable(nil)) }
                case .waiting(let err):
                    // `.waiting` means the OS is still trying — for a local server
                    // that's effectively "not running". Surface immediately.
                    if resumed.set() { cont.resume(throwing: ADBError.serverUnreachable(err)) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    /// Writes all bytes; resumes when the OS confirms the send.
    public func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = AtomicFlag()
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    if resumed.set() { cont.resume(throwing: ADBError.ioError(error)) }
                } else {
                    if resumed.set() { cont.resume() }
                }
            })
        }
    }

    /// Reads exactly `count` bytes. Throws `protocolError("short read…")` if
    /// the peer closes early.
    public func readExact(_ count: Int) async throws -> Data {
        var accumulated = Data()
        accumulated.reserveCapacity(count)
        while accumulated.count < count {
            let chunk = try await readChunk(min: 1, max: count - accumulated.count)
            if chunk.isEmpty {
                throw ADBError.protocolError(
                    "short read: expected \(count), got \(accumulated.count) before close"
                )
            }
            accumulated.append(chunk)
        }
        return accumulated
    }

    /// Reads any amount up to 64 KiB. Returns empty `Data` when peer closes.
    public func readUntilClose() async throws -> Data {
        var accumulated = Data()
        while true {
            let chunk = try await readChunk(min: 1, max: 64 * 1024)
            if chunk.isEmpty { break }
            accumulated.append(chunk)
        }
        return accumulated
    }

    private func readChunk(min: Int, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let resumed = AtomicFlag()
            connection.receive(minimumIncompleteLength: min, maximumLength: max) { data, _, isComplete, error in
                if let error {
                    if resumed.set() { cont.resume(throwing: ADBError.ioError(error)) }
                    return
                }
                if let data, !data.isEmpty {
                    if resumed.set() { cont.resume(returning: data) }
                    return
                }
                if isComplete {
                    if resumed.set() { cont.resume(returning: Data()) }
                    return
                }
                // No data, not complete, no error — shouldn't happen, but treat as EOF.
                if resumed.set() { cont.resume(returning: Data()) }
            }
        }
    }

    public func close() {
        connection.cancel()
    }
}

/// One-shot flag used to guarantee a continuation resumes exactly once even
/// when NWConnection callbacks fire more than once (state transitions, etc.).
private final class AtomicFlag: @unchecked Sendable {
    private var fired = false
    private let lock = NSLock()
    func set() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

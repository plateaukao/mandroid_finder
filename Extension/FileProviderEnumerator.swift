import FileProvider
import MandroidCore

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let serial: String
    private let containerPath: String?  // nil = working set / trash / unsupported

    init(serial: String, containerPath: String?) {
        self.serial = serial
        self.containerPath = containerPath
        super.init()
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver,
                        startingAt page: NSFileProviderPage) {
        guard let path = containerPath else {
            // Empty working set / trash — nothing to enumerate.
            observer.finishEnumerating(upTo: nil)
            return
        }
        Task {
            do {
                let entries = try await ADBService.shared.list(serial: serial, path: path)
                let items = entries.map { FileProviderItem(file: $0, parentPath: path) }
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch {
                observer.finishEnumeratingWithError(NSFileProviderError(.serverUnreachable))
            }
        }
    }

    /// Working set / change tracking is a no-op for v1 — Finder will refresh
    /// directories on user navigation. Future: implement an anchor/sync token
    /// based on a checksum of `ls -la` output.
    func enumerateChanges(for observer: NSFileProviderChangeObserver,
                          from anchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(Data()))
    }
}

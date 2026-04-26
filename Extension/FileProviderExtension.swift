import FileProvider
import Foundation
import MandroidCore

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    /// Top of the device's user-visible storage. Matches what Android's own
    /// Files app considers "Internal storage".
    static let rootPath = "/sdcard"

    private let domain: NSFileProviderDomain
    private var serial: String { domain.identifier.rawValue }

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }

    func invalidate() {}

    // MARK: - Item lookup

    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        if identifier == .rootContainer {
            completionHandler(FileProviderItem(rootDisplayName: domain.displayName), nil)
            progress.completedUnitCount = 1
            return progress
        }
        let path = ItemID.decode(identifier)
        let parentPath = (path as NSString).deletingLastPathComponent
        let serial = self.serial
        Task {
            do {
                let parentEntries = try await ADBService.shared.list(serial: serial, path: parentPath)
                if let match = parentEntries.first(where: { $0.path == path }) {
                    completionHandler(FileProviderItem(file: match, parentPath: parentPath), nil)
                } else {
                    completionHandler(nil, NSFileProviderError(.noSuchItem))
                }
                progress.completedUnitCount = 1
            } catch {
                completionHandler(nil, error)
                progress.completedUnitCount = 1
            }
        }
        return progress
    }

    // MARK: - Enumeration

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        // Working set / trash containers are system-managed buckets that don't
        // correspond to a real device path; return an empty enumerator.
        if containerItemIdentifier == .workingSet || containerItemIdentifier == .trashContainer {
            return FileProviderEnumerator(serial: serial, containerPath: nil)
        }
        let path = ItemID.decode(containerItemIdentifier)
        return FileProviderEnumerator(serial: serial, containerPath: path)
    }

    // MARK: - Read

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let remotePath = ItemID.decode(itemIdentifier)
        let parentPath = (remotePath as NSString).deletingLastPathComponent
        let serial = self.serial
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((remotePath as NSString).pathExtension)
        Task {
            do {
                try await ADBService.shared.pull(serial: serial, remote: remotePath, localFile: tempURL)
                let parentEntries = try await ADBService.shared.list(serial: serial, path: parentPath)
                guard let entry = parentEntries.first(where: { $0.path == remotePath }) else {
                    completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
                    progress.completedUnitCount = 1
                    return
                }
                let item = FileProviderItem(file: entry, parentPath: parentPath)
                completionHandler(tempURL, item, nil)
                progress.completedUnitCount = 1
            } catch {
                completionHandler(nil, nil, error)
                progress.completedUnitCount = 1
            }
        }
        return progress
    }

    // MARK: - Write

    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let serial = self.serial
        let parentPath = ItemID.decode(itemTemplate.parentItemIdentifier)
        let remotePath = (parentPath as NSString).appendingPathComponent(itemTemplate.filename)
        let isDirectory = itemTemplate.contentType == .folder

        Task {
            do {
                if isDirectory {
                    try await ADBService.shared.mkdir(serial: serial, path: remotePath)
                } else if let local = url {
                    try await ADBService.shared.push(serial: serial, localFile: local, remote: remotePath)
                } else {
                    completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))
                    progress.completedUnitCount = 1
                    return
                }
                let entries = try await ADBService.shared.list(serial: serial, path: parentPath)
                guard let entry = entries.first(where: { $0.path == remotePath }) else {
                    completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))
                    progress.completedUnitCount = 1
                    return
                }
                let item = FileProviderItem(file: entry, parentPath: parentPath)
                completionHandler(item, [], false, nil)
                progress.completedUnitCount = 1
            } catch {
                completionHandler(nil, [], false, error)
                progress.completedUnitCount = 1
            }
        }
        return progress
    }

    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let serial = self.serial
        let oldPath = ItemID.decode(item.itemIdentifier)
        let parentPath = ItemID.decode(item.parentItemIdentifier)
        let newPath = (parentPath as NSString).appendingPathComponent(item.filename)

        Task {
            do {
                if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier),
                   oldPath != newPath {
                    try await ADBService.shared.rename(serial: serial, from: oldPath, to: newPath)
                }
                if changedFields.contains(.contents), let local = newContents {
                    try await ADBService.shared.push(serial: serial, localFile: local, remote: newPath)
                }
                let entries = try await ADBService.shared.list(serial: serial, path: parentPath)
                guard let entry = entries.first(where: { $0.path == newPath }) else {
                    completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))
                    progress.completedUnitCount = 1
                    return
                }
                completionHandler(FileProviderItem(file: entry, parentPath: parentPath), [], false, nil)
                progress.completedUnitCount = 1
            } catch {
                completionHandler(nil, [], false, error)
                progress.completedUnitCount = 1
            }
        }
        return progress
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let serial = self.serial
        let path = ItemID.decode(identifier)
        Task {
            do {
                try await ADBService.shared.remove(serial: serial, path: path)
                completionHandler(nil)
                progress.completedUnitCount = 1
            } catch {
                completionHandler(error)
                progress.completedUnitCount = 1
            }
        }
        return progress
    }
}

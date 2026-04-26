import FileProvider
import UniformTypeIdentifiers
import MandroidCore

final class FileProviderItem: NSObject, NSFileProviderItem {
    private let file: AndroidFile?
    private let _identifier: NSFileProviderItemIdentifier
    private let _parent: NSFileProviderItemIdentifier
    private let _filename: String
    private let _isDir: Bool
    private let _size: Int64
    private let _mtime: Date?

    init(file: AndroidFile, parentPath: String) {
        self.file = file
        self._identifier = ItemID.encode(path: file.path)
        self._parent = parentPath == FileProviderExtension.rootPath
            ? .rootContainer
            : ItemID.encode(path: parentPath)
        self._filename = file.name
        self._isDir = file.isDirectory
        self._size = file.size
        self._mtime = file.modificationDate
    }

    /// Synthetic root item — represents the device's storage root.
    init(rootDisplayName: String) {
        self.file = nil
        self._identifier = .rootContainer
        self._parent = .rootContainer
        self._filename = rootDisplayName
        self._isDir = true
        self._size = 0
        self._mtime = nil
    }

    var itemIdentifier: NSFileProviderItemIdentifier { _identifier }
    var parentItemIdentifier: NSFileProviderItemIdentifier { _parent }
    var filename: String { _filename }
    var documentSize: NSNumber? { _isDir ? nil : NSNumber(value: _size) }
    var contentModificationDate: Date? { _mtime }
    var creationDate: Date? { _mtime }

    var contentType: UTType {
        if _isDir { return .folder }
        return UTType(filenameExtension: (_filename as NSString).pathExtension) ?? .data
    }

    var capabilities: NSFileProviderItemCapabilities {
        if _isDir {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsDeleting, .allowsRenaming]
        } else {
            return [.allowsReading, .allowsWriting, .allowsDeleting, .allowsRenaming]
        }
    }

    var itemVersion: NSFileProviderItemVersion {
        // Content version: mtime+size encodes "did the bytes change".
        // Metadata version: same, since we have no separate metadata stream.
        let content = "\(_size)-\(Int(_mtime?.timeIntervalSince1970 ?? 0))".data(using: .utf8) ?? Data()
        return NSFileProviderItemVersion(contentVersion: content, metadataVersion: content)
    }
}

/// Translates between Android absolute paths and `NSFileProviderItemIdentifier`.
/// We use the path itself as the stable identifier — it's unique per domain
/// (one domain == one device) and survives extension restarts.
enum ItemID {
    static func encode(path: String) -> NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(path)
    }

    /// Returns a clean device-side path for the identifier.
    ///
    /// Defensive unescape: Finder's File Provider cache can hold identifiers
    /// from previous app versions whose names came from a non-PTY toybox `ls`
    /// (i.e., `\<space>` for space, `\\` for backslash). After we taught the
    /// parser to unescape, fresh items get clean identifiers; but old cached
    /// ones still arrive here with literal backslashes, and `ls` on the
    /// device would say "No such file or directory" for those — surfacing
    /// the directory as empty. Unescaping before send-off makes legacy
    /// identifiers resolve correctly.
    static func decode(_ identifier: NSFileProviderItemIdentifier) -> String {
        if identifier == .rootContainer { return FileProviderExtension.rootPath }
        return unescape(identifier.rawValue)
    }

    private static func unescape(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var iter = s.makeIterator()
        while let c = iter.next() {
            if c == "\\", let next = iter.next() {
                out.append(next)
            } else {
                out.append(c)
            }
        }
        return out
    }
}

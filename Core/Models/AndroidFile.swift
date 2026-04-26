import Foundation

public struct AndroidFile: Sendable, Hashable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let size: Int64
    public let modificationDate: Date?
    public let permissions: String

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        isSymlink: Bool,
        size: Int64,
        modificationDate: Date?,
        permissions: String
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
    }
}

public enum LSParser {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    /// Parses a single line of `ls -la` output (Android toybox/coreutils flavor).
    /// Example: `-rw-rw---- 1 root sdcard_rw 12345 2025-01-02 10:15 file.txt`
    public static func parseLine(_ line: String, parentPath: String) -> AndroidFile? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("total "),
              !trimmed.hasPrefix("ls:") else { return nil }

        let columns = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard columns.count >= 8 else { return nil }

        let permissions = columns[0]
        guard let typeChar = permissions.first else { return nil }
        let isDirectory = typeChar == "d"
        let isSymlink = typeChar == "l"

        // Permissions, links, owner, group, size, date, time, name…
        guard let size = Int64(columns[4]) else { return nil }

        let date = dateFormatter.date(from: "\(columns[5]) \(columns[6])")

        // Name may contain spaces; reassemble from index 7. For symlinks, drop "-> target".
        // toybox `ls` without a PTY (our case — adb's shell: service is non-PTY)
        // backslash-escapes spaces and other special characters. Unescape after
        // stripping the symlink target so the arrow itself isn't perturbed.
        var nameParts = columns[7...].joined(separator: " ")
        if isSymlink, let arrow = nameParts.range(of: " -> ") {
            nameParts = String(nameParts[..<arrow.lowerBound])
        }
        let name = unescape(nameParts)
        guard name != "." && name != ".." else { return nil }

        let fullPath = parentPath.hasSuffix("/")
            ? parentPath + name
            : parentPath + "/" + name

        return AndroidFile(
            name: name,
            path: fullPath,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            size: size,
            modificationDate: date,
            permissions: permissions
        )
    }

    public static func parse(_ output: String, parentPath: String) -> [AndroidFile] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseLine(String($0), parentPath: parentPath) }
    }

    /// Reverses toybox's backslash-escaping of spaces / special chars in
    /// filenames (`AR\ Emoji\ camera` → `AR Emoji camera`, `\\` → `\`).
    /// Unknown escapes degrade to "drop the backslash" — wrong for `\n`/`\t`
    /// inside a filename, but those are vanishingly rare in practice.
    private static func unescape(_ s: String) -> String {
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

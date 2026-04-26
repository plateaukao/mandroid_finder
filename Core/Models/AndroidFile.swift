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
        var nameParts = columns[7...].joined(separator: " ")
        if isSymlink, let arrow = nameParts.range(of: " -> ") {
            nameParts = String(nameParts[..<arrow.lowerBound])
        }
        let name = nameParts
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
}

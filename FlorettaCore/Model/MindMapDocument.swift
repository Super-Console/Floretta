import Foundation

/// A mind map. `roots` is ordered and may contain more than one center (floating topics).
public struct MindMapDocument: Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var roots: [MindMapNode]

    public init(
        title: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        roots: [MindMapNode] = [],
        formatVersion: Int = MindMapDocument.currentFormatVersion
    ) {
        self.formatVersion = formatVersion
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.roots = roots
    }
}

extension MindMapDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case title
        case createdAt
        case modifiedAt
        case roots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .formatVersion)
        guard version == Self.currentFormatVersion else {
            throw FlorettaCodecError.unsupportedVersion(
                found: version,
                supported: Self.currentFormatVersion
            )
        }
        let title = try container.decode(String.self, forKey: .title)
        let createdAt = try FlorettaTimestamp.date(
            from: try container.decode(String.self, forKey: .createdAt)
        )
        let modifiedAt = try FlorettaTimestamp.date(
            from: try container.decode(String.self, forKey: .modifiedAt)
        )
        let roots = try container.decode([MindMapNode].self, forKey: .roots)
        try FlorettaTree.validate(roots)
        self.formatVersion = version
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.roots = roots
    }

    public func encode(to encoder: Encoder) throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw FlorettaCodecError.unsupportedVersion(
                found: formatVersion,
                supported: Self.currentFormatVersion
            )
        }
        try FlorettaTree.validate(roots)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(title, forKey: .title)
        try container.encode(FlorettaTimestamp.string(from: createdAt), forKey: .createdAt)
        try container.encode(FlorettaTimestamp.string(from: modifiedAt), forKey: .modifiedAt)
        try container.encode(roots, forKey: .roots)
    }
}

/// JSON has no pointers, and `MindMapNode.children` is a value array, so a real pointer
/// cycle cannot be stored. Reusing an ancestor's id is the cyclic case this format can
/// express; any other repeated id is a duplicate. Both are rejected.
enum FlorettaTree {
    static func validate(_ roots: [MindMapNode]) throws {
        var seen: Set<UUID> = []
        var stack: [UUID] = []
        for root in roots {
            try visit(root, seen: &seen, stack: &stack)
        }
    }

    private static func visit(
        _ node: MindMapNode,
        seen: inout Set<UUID>,
        stack: inout [UUID]
    ) throws {
        if stack.contains(node.id) {
            throw FlorettaCodecError.cyclicID(node.id)
        }
        if !seen.insert(node.id).inserted {
            throw FlorettaCodecError.duplicateID(node.id)
        }
        stack.append(node.id)
        for child in node.children {
            try visit(child, seen: &seen, stack: &stack)
        }
        stack.removeLast()
    }
}

public enum FlorettaTimestamp {
    public static func string(from date: Date) -> String {
        let whole = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded())
        return formatter(fractional: false).string(from: whole)
    }

    public static func date(from string: String) throws -> Date {
        if let date = formatter(fractional: true).date(from: string) {
            return date
        }
        if let date = formatter(fractional: false).date(from: string) {
            return date
        }
        throw FlorettaCodecError.corrupt(
            "Unreadable timestamp \"\(string)\". Use ISO-8601 UTC, for example 2026-11-09T08:00:00Z."
        )
    }

    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var options: ISO8601DateFormatter.Options = [.withInternetDateTime]
        if fractional {
            options.insert(.withFractionalSeconds)
        }
        formatter.formatOptions = options
        return formatter
    }
}

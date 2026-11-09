import CoreFoundation
import Foundation

public enum FlorettaCodecError: Error, Equatable, Sendable {
    case corrupt(String)
    case unsupportedVersion(found: Int, supported: Int)
    case duplicateID(UUID)
    case cyclicID(UUID)

    public static func wrongJSONType(at place: String) -> FlorettaCodecError {
        .corrupt("Wrong JSON type at \(place).")
    }
}

extension FlorettaCodecError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .corrupt(let message):
            return message
        case .unsupportedVersion(let found, let supported):
            return "Unsupported .floretta format version \(found). This build reads version \(supported)."
        case .duplicateID(let id):
            return "Duplicate node id \(id.uuidString). Each id must appear once in the tree."
        case .cyclicID(let id):
            return "Cyclic node id \(id.uuidString). A node repeats an ancestor. .floretta stores a tree, not a graph, and JSON has no pointers, so a repeated ancestor id is rejected."
        }
    }
}

/// Pretty-printed UTF-8 JSON for a single `.floretta` file.
/// Key order is `JSONEncoder.OutputFormatting.sortedKeys` (alphabetical, stable).
public enum FlorettaCodec {
    public static let fileExtension = "floretta"

    public static func encode(_ document: MindMapDocument) throws -> Data {
        guard document.formatVersion == MindMapDocument.currentFormatVersion else {
            throw FlorettaCodecError.unsupportedVersion(
                found: document.formatVersion,
                supported: MindMapDocument.currentFormatVersion
            )
        }
        try FlorettaTree.validate(document.roots)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(document)
        } catch {
            throw rethrowCodec(error, writing: true)
        }
    }

    public static func decode(_ data: Data) throws -> MindMapDocument {
        if data.isEmpty {
            throw FlorettaCodecError.corrupt("File is empty.")
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw FlorettaCodecError.corrupt("File is not valid UTF-8.")
        }
        try preflightJSONTypes(data)
        do {
            return try JSONDecoder().decode(MindMapDocument.self, from: data)
        } catch {
            throw rethrowCodec(error, writing: false)
        }
    }

    /// JSONDecoder on the current SDK can report a mistyped value, including
    /// `formatVersion`, as `DecodingError.dataCorrupted` with an empty coding path.
    /// That used to be worded as "not a .floretta JSON document", which is only for
    /// syntax failures. Check JSON kinds first so a wrong type stays distinguishable.
    private static func preflightJSONTypes(_ data: Data) throws {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw FlorettaCodecError.corrupt("File is not a .floretta JSON document.")
        }
        guard let object = value as? [String: Any] else {
            throw FlorettaCodecError.wrongJSONType(at: "the root")
        }
        try expect(object, key: "formatVersion", at: "formatVersion") { isJSONInteger($0) }
        try expect(object, key: "title", at: "title") { isJSONString($0) }
        try expect(object, key: "createdAt", at: "createdAt") { isJSONString($0) }
        try expect(object, key: "modifiedAt", at: "modifiedAt") { isJSONString($0) }
        if let frontMatter = object["markdownFrontMatter"], !(frontMatter is NSNull) {
            try expect(object, key: "markdownFrontMatter", at: "markdownFrontMatter") { isJSONString($0) }
        }
        if let roots = object["roots"] {
            guard let array = roots as? [Any] else {
                throw FlorettaCodecError.wrongJSONType(at: "roots")
            }
            for (index, root) in array.enumerated() {
                try preflightNode(root, at: "roots[\(index)]")
            }
        }
    }

    private static func preflightNode(_ value: Any, at path: String) throws {
        guard let object = value as? [String: Any] else {
            throw FlorettaCodecError.wrongJSONType(at: path)
        }
        try expect(object, key: "id", at: "\(path).id") { isJSONString($0) }
        try expect(object, key: "text", at: "\(path).text") { isJSONString($0) }
        try expect(object, key: "note", at: "\(path).note") { isJSONString($0) }
        try expect(object, key: "collapsed", at: "\(path).collapsed") { isJSONBool($0) }
        if let style = object["style"], !(style is NSNull) {
            guard let styleObject = style as? [String: Any] else {
                throw FlorettaCodecError.wrongJSONType(at: "\(path).style")
            }
            try expect(styleObject, key: "colorHex", at: "\(path).style.colorHex") { isJSONString($0) }
        }
        if let position = object["position"], !(position is NSNull) {
            guard let point = position as? [String: Any] else {
                throw FlorettaCodecError.wrongJSONType(at: "\(path).position")
            }
            try expect(point, key: "x", at: "\(path).position.x") { isJSONNumber($0) }
            try expect(point, key: "y", at: "\(path).position.y") { isJSONNumber($0) }
        }
        if let link = object["link"], !(link is NSNull) {
            try expect(object, key: "link", at: "\(path).link") { isJSONString($0) }
        }
        if let side = object["side"], !(side is NSNull) {
            try expect(object, key: "side", at: "\(path).side") { isJSONString($0) }
        }
        if let attachments = object["attachments"], !(attachments is NSNull) {
            guard let array = attachments as? [Any] else {
                throw FlorettaCodecError.wrongJSONType(at: "\(path).attachments")
            }
            for (index, item) in array.enumerated() {
                guard let attachment = item as? [String: Any] else {
                    throw FlorettaCodecError.wrongJSONType(at: "\(path).attachments[\(index)]")
                }
                let place = "\(path).attachments[\(index)]"
                try expect(attachment, key: "sha256", at: "\(place).sha256") { isJSONString($0) }
                try expect(attachment, key: "fileExtension", at: "\(place).fileExtension") { isJSONString($0) }
                try expect(attachment, key: "byteCount", at: "\(place).byteCount") { isJSONInteger($0) }
                try expect(attachment, key: "filename", at: "\(place).filename") { isJSONString($0) }
            }
        }
        if let heading = object["isMarkdownSectionHeading"], !(heading is NSNull) {
            try expect(object, key: "isMarkdownSectionHeading", at: "\(path).isMarkdownSectionHeading") {
                isJSONBool($0)
            }
        }
        if let children = object["children"] {
            guard let array = children as? [Any] else {
                throw FlorettaCodecError.wrongJSONType(at: "\(path).children")
            }
            for (index, child) in array.enumerated() {
                try preflightNode(child, at: "\(path).children[\(index)]")
            }
        }
    }

    private static func expect(
        _ object: [String: Any],
        key: String,
        at path: String,
        _ predicate: (Any) -> Bool
    ) throws {
        guard let value = object[key] else { return }
        if predicate(value) { return }
        throw FlorettaCodecError.wrongJSONType(at: path)
    }

    private static func isJSONString(_ value: Any) -> Bool {
        value is String
    }

    private static func isJSONBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func isJSONNumber(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }

    private static func isJSONInteger(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return false }
        let double = number.doubleValue
        guard double.isFinite, double == double.rounded() else { return false }
        return double >= Double(Int.min) && double <= Double(Int.max)
    }

    private static func rethrowCodec(_ error: Error, writing: Bool) -> FlorettaCodecError {
        let unwrapped = mostSpecific(error)
        if let codec = unwrapped as? FlorettaCodecError {
            return codec
        }
        if writing {
            return .corrupt("Could not write .floretta file: \(unwrapped.localizedDescription)")
        }
        return .corrupt(describe(unwrapped))
    }

    /// Prefer a type mismatch or missing key over an empty-path `dataCorrupted`
    /// wrapper. That wrapper is what a mistyped field was being reported as.
    private static func mostSpecific(_ error: Error, depth: Int = 0) -> Error {
        if error is FlorettaCodecError || depth > 8 {
            return error
        }
        guard let decoding = error as? DecodingError else {
            return error
        }
        switch decoding {
        case .typeMismatch, .keyNotFound, .valueNotFound:
            return decoding
        case .dataCorrupted(let context):
            if let underlying = context.underlyingError {
                let next = mostSpecific(underlying, depth: depth + 1)
                if next is FlorettaCodecError {
                    return next
                }
                if prefers(next, overEmptyPathCorruption: context.codingPath.isEmpty) {
                    return next
                }
            }
            return decoding
        @unknown default:
            return decoding
        }
    }

    private static func prefers(_ error: Error, overEmptyPathCorruption emptyPath: Bool) -> Bool {
        guard let decoding = error as? DecodingError else { return false }
        switch decoding {
        case .typeMismatch, .keyNotFound, .valueNotFound:
            return true
        case .dataCorrupted(let context):
            return emptyPath && !context.codingPath.isEmpty
        @unknown default:
            return false
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return "Could not read .floretta file: \(error.localizedDescription)"
        }
        switch decoding {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            if path.isEmpty {
                return "Missing \"\(key.stringValue)\"."
            }
            return "Missing \"\(key.stringValue)\" (\(path))."
        case .typeMismatch(_, let context):
            return "Wrong JSON type at \(place(context.codingPath))."
        case .valueNotFound(_, let context):
            return "Missing value at \(place(context.codingPath))."
        case .dataCorrupted(let context):
            if looksLikeWrongJSONType(context) {
                return "Wrong JSON type at \(place(context.codingPath))."
            }
            if context.codingPath.isEmpty {
                return "File is not a .floretta JSON document."
            }
            return "Corrupt JSON at \(place(context.codingPath))."
        @unknown default:
            return "Could not read .floretta file."
        }
    }

    private static func place(_ path: [any CodingKey]) -> String {
        let joined = path.map(\.stringValue).joined(separator: ".")
        return joined.isEmpty ? "the root" : joined
    }

    private static func looksLikeWrongJSONType(_ context: DecodingError.Context) -> Bool {
        let text = (context.debugDescription + " " + String(describing: context.underlyingError)).lowercased()
        return text.contains("type mismatch")
            || text.contains("expected to decode")
            || text.contains("does not fit")
            || text.contains("wrong json type")
    }
}

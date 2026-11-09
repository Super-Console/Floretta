import Foundation

enum FlorettaCodecError: Error, Equatable, Sendable {
    case corrupt(String)
    case unsupportedVersion(found: Int, supported: Int)
    case duplicateID(UUID)
    case cyclicID(UUID)
}

extension FlorettaCodecError: LocalizedError {
    var errorDescription: String? {
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
enum FlorettaCodec {
    static let fileExtension = "floretta"

    static func encode(_ document: MindMapDocument) throws -> Data {
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

    static func decode(_ data: Data) throws -> MindMapDocument {
        if data.isEmpty {
            throw FlorettaCodecError.corrupt("File is empty.")
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw FlorettaCodecError.corrupt("File is not valid UTF-8.")
        }
        do {
            return try JSONDecoder().decode(MindMapDocument.self, from: data)
        } catch {
            throw rethrowCodec(error, writing: false)
        }
    }

    private static func rethrowCodec(_ error: Error, writing: Bool) -> FlorettaCodecError {
        let unwrapped = unwrap(error)
        if let codec = unwrapped as? FlorettaCodecError {
            return codec
        }
        if writing {
            return .corrupt("Could not write .floretta file: \(unwrapped.localizedDescription)")
        }
        return .corrupt(describe(unwrapped))
    }

    /// JSONEncoder/JSONDecoder sometimes wrap an error thrown from Codable.
    private static func unwrap(_ error: Error, depth: Int = 0) -> Error {
        if error is FlorettaCodecError || depth > 8 {
            return error
        }
        if let underlying = underlying(error) {
            let next = unwrap(underlying, depth: depth + 1)
            if next is FlorettaCodecError {
                return next
            }
        }
        return error
    }

    private static func underlying(_ error: Error) -> Error? {
        switch error {
        case DecodingError.keyNotFound(_, let context):
            return context.underlyingError
        case DecodingError.typeMismatch(_, let context):
            return context.underlyingError
        case DecodingError.valueNotFound(_, let context):
            return context.underlyingError
        case DecodingError.dataCorrupted(let context):
            return context.underlyingError
        case EncodingError.invalidValue(_, let context):
            return context.underlyingError
        default:
            return nil
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
}

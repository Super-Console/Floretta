import CoreFoundation
import Foundation

/// One JSON value kept so an XMind field can be written back as it arrived.
/// Object key order is not significant; unchanged export writes the original bytes.
public enum XMindJSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([XMindJSONValue])
    case object(XMindJSONObject)

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var objectValue: XMindJSONObject? {
        if case .object(let value) = self { return value }
        return nil
    }

    public func doubleValue() -> Double? {
        guard case .number(let token) = self else { return nil }
        return Double(token)
    }

    public func int64Value() -> Int64? {
        guard let double = doubleValue(), double.isFinite, double == double.rounded() else { return nil }
        guard double >= Double(Int64.min), double <= Double(Int64.max) else { return nil }
        return Int64(double)
    }
}

public struct XMindJSONObject: Equatable, Sendable {
    public private(set) var keys: [String]
    private var storage: [String: XMindJSONValue]

    public init(_ pairs: [(String, XMindJSONValue)] = []) {
        var keys: [String] = []
        var storage: [String: XMindJSONValue] = [:]
        for (key, value) in pairs {
            if storage[key] == nil {
                keys.append(key)
            }
            storage[key] = value
        }
        self.keys = keys
        self.storage = storage
    }

    public var isEmpty: Bool { keys.isEmpty }

    public subscript(key: String) -> XMindJSONValue? {
        get { storage[key] }
        set {
            if let newValue {
                if storage[key] == nil {
                    keys.append(key)
                }
                storage[key] = newValue
            } else if storage[key] != nil {
                storage.removeValue(forKey: key)
                keys.removeAll { $0 == key }
            }
        }
    }
}

enum XMindJSON {
    static func object(from any: Any) throws -> XMindJSONObject {
        guard case .object(let object) = try value(from: any) else {
            throw FlorettaXMindError.corrupt("content.json value is not an object.")
        }
        return object
    }

    static func value(from any: Any) throws -> XMindJSONValue {
        if any is NSNull { return .null }
        if let string = any as? String { return .string(string) }
        if let number = any as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(token(from: number))
        }
        if let array = any as? [Any] {
            return .array(try array.map { try value(from: $0) })
        }
        if let object = any as? [String: Any] {
            let pairs = try object.keys.sorted().map { key -> (String, XMindJSONValue) in
                (key, try value(from: object[key]!))
            }
            return .object(XMindJSONObject(pairs))
        }
        throw FlorettaXMindError.corrupt("content.json has an unsupported JSON value.")
    }

    static func write(_ value: XMindJSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let flag):
            return flag ? "true" : "false"
        case .number(let token):
            return token
        case .string(let string):
            return quoted(string)
        case .array(let items):
            return "[" + items.map(write).joined(separator: ",") + "]"
        case .object(let object):
            let body = object.keys.sorted().map { key in
                quoted(key) + ":" + write(object[key]!)
            }.joined(separator: ",")
            return "{" + body + "}"
        }
    }

    static func token(for value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func token(from number: NSNumber) -> String {
        token(for: number.doubleValue)
    }

    private static func quoted(_ string: String) -> String {
        var text = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"":
                text.append("\\\"")
            case "\\":
                text.append("\\\\")
            case "\n":
                text.append("\\n")
            case "\r":
                text.append("\\r")
            case "\t":
                text.append("\\t")
            case "\u{0008}":
                text.append("\\b")
            case "\u{000C}":
                text.append("\\f")
            default:
                if scalar.value < 0x20 {
                    text.append(String(format: "\\u%04x", scalar.value))
                } else {
                    text.append(String(scalar))
                }
            }
        }
        text.append("\"")
        return text
    }
}

extension XMindJSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int64.self) {
            self = .number(String(value))
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(XMindJSON.token(for: value))
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([XMindJSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode(XMindJSONObject.self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable XMind JSON value.")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let token):
            if let integer = Int64(token) {
                try container.encode(integer)
            } else if let number = Double(token) {
                try container.encode(number)
            } else {
                throw EncodingError.invalidValue(token, EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "XMind number token is not a JSON number."
                ))
            }
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

extension XMindJSONObject: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: XMindCodingKey.self)
        let pairs = try container.allKeys
            .sorted { $0.stringValue < $1.stringValue }
            .map { key in
                (key.stringValue, try container.decode(XMindJSONValue.self, forKey: key))
            }
        self.init(pairs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: XMindCodingKey.self)
        for key in keys {
            guard let value = self[key] else { continue }
            try container.encode(value, forKey: XMindCodingKey(key))
        }
    }
}

struct XMindCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.init(String(intValue))
        self.intValue = intValue
    }
}

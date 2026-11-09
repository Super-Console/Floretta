import Foundation

public enum DocumentContainerKind: String, Equatable, Sendable {
    case legacyJSON
    case zip
}

public enum DocumentContainerError: Error, Equatable, Sendable {
    case readOnlyLegacy
    case refusesToOverwriteLegacy
    case missingEntry(String)
    case corrupt(String)
    case overLimit(String)
    case document(FlorettaCodecError)
}

extension DocumentContainerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .readOnlyLegacy:
            return "The plain JSON .floretta format is read-only. Save As a new file to write the ZIP container."
        case .refusesToOverwriteLegacy:
            return "Refusing to overwrite a plain JSON .floretta file. Save As a new path."
        case .missingEntry(let name):
            return "Missing \(name)."
        case .corrupt(let message):
            return message
        case .overLimit(let message):
            return message
        case .document(let error):
            return error.localizedDescription
        }
    }
}

public struct FlorettaMetadata: Equatable, Sendable {
    public static let currentContainerVersion = 1

    public var containerVersion: Int
    public var createdAt: Date
    public var modifiedAt: Date
    public var appVersion: String
    public var defaultView: String

    public init(
        document: MindMapDocument,
        appVersion: String = "1.0",
        defaultView: String = "canvas",
        containerVersion: Int = FlorettaMetadata.currentContainerVersion
    ) {
        self.containerVersion = containerVersion
        createdAt = document.createdAt
        modifiedAt = document.modifiedAt
        self.appVersion = appVersion
        self.defaultView = defaultView
    }
}

extension FlorettaMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case containerVersion
        case createdAt
        case modifiedAt
        case appVersion
        case defaultView
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .containerVersion)
        guard version == Self.currentContainerVersion else {
            throw DocumentContainerError.corrupt("Unsupported container version \(version).")
        }
        containerVersion = version
        createdAt = try FlorettaTimestamp.date(from: try container.decode(String.self, forKey: .createdAt))
        modifiedAt = try FlorettaTimestamp.date(from: try container.decode(String.self, forKey: .modifiedAt))
        appVersion = try container.decode(String.self, forKey: .appVersion)
        defaultView = try container.decode(String.self, forKey: .defaultView)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(containerVersion, forKey: .containerVersion)
        try container.encode(FlorettaTimestamp.string(from: createdAt), forKey: .createdAt)
        try container.encode(FlorettaTimestamp.string(from: modifiedAt), forKey: .modifiedAt)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(defaultView, forKey: .defaultView)
    }
}

public struct FlorettaAsset: Equatable, Sendable {
    public var sha256: String
    public var fileExtension: String
    public var data: Data

    public init(sha256: String, fileExtension: String, data: Data) {
        self.sha256 = sha256
        self.fileExtension = fileExtension
        self.data = data
    }

    public var relativePath: String { "assets/\(sha256).\(fileExtension)" }
}

public struct FlorettaPackage: Equatable, Sendable {
    public var document: MindMapDocument
    public var metadata: FlorettaMetadata
    public var assets: [FlorettaAsset]

    public init(document: MindMapDocument, metadata: FlorettaMetadata? = nil, assets: [FlorettaAsset] = []) {
        self.document = document
        self.metadata = metadata ?? FlorettaMetadata(document: document)
        self.assets = assets
    }

    /// Same bytes are stored once. The returned path is `assets/<sha256>.<ext>`.
    @discardableResult
    public mutating func addAsset(data: Data, fileExtension: String) -> String {
        let hash = sha256Hex(data)
        if let existing = assets.first(where: { $0.sha256 == hash }) {
            return existing.relativePath
        }
        let asset = FlorettaAsset(
            sha256: hash,
            fileExtension: Self.normalizeExtension(fileExtension),
            data: data
        )
        assets.append(asset)
        assets.sort { $0.sha256 < $1.sha256 }
        return asset.relativePath
    }

    private static func normalizeExtension(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let filtered = trimmed.filter { $0.isLetter || $0.isNumber }
        if filtered.isEmpty { return "bin" }
        return String(filtered.prefix(8))
    }
}

public protocol DocumentContainer: Sendable {
    func read(data: Data) throws -> FlorettaPackage
    func write(_ package: FlorettaPackage) throws -> Data
}

public struct LegacyJSONContainer: DocumentContainer {
    public init() {}

    public func read(data: Data) throws -> FlorettaPackage {
        do {
            let document = try FlorettaCodec.decode(data)
            return FlorettaPackage(document: document)
        } catch let error as FlorettaCodecError {
            throw DocumentContainerError.document(error)
        } catch {
            throw DocumentContainerError.corrupt("Could not read legacy JSON.")
        }
    }

    public func write(_ package: FlorettaPackage) throws -> Data {
        throw DocumentContainerError.readOnlyLegacy
    }
}

public struct LoadedFloretta: Equatable, Sendable {
    public var package: FlorettaPackage
    public var kind: DocumentContainerKind

    public init(package: FlorettaPackage, kind: DocumentContainerKind) {
        self.package = package
        self.kind = kind
    }
}

public enum FlorettaDocumentFile {
    public static func read(from url: URL, limits: ZipLimits = .standard, fileAccess: any FileAccessPort) throws -> LoadedFloretta {
        try read(data: try fileAccess.read(from: url), limits: limits)
    }

    public static func read(data: Data, limits: ZipLimits = .standard) throws -> LoadedFloretta {
        if isZip(data) {
            return LoadedFloretta(package: try ZipContainer(limits: limits).read(data: data), kind: .zip)
        }
        return LoadedFloretta(package: try LegacyJSONContainer().read(data: data), kind: .legacyJSON)
    }

    /// Writes a ZIP. An existing plain JSON file at `url` is left untouched.
    /// Bytes go through `fileAccess` so security scopes and coordination stay outside Core.
    public static func save(
        _ package: FlorettaPackage,
        to url: URL,
        limits: ZipLimits = .standard,
        fileAccess: any FileAccessPort
    ) throws {
        if fileAccess.fileExists(at: url) {
            let existing = try fileAccess.read(from: url)
            if !isZip(existing) {
                throw DocumentContainerError.refusesToOverwriteLegacy
            }
        }
        let data = try ZipContainer(limits: limits).write(package)
        try fileAccess.write(data, to: url)
    }

    public static func isZip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4b
    }
}

public func sha256Hex(_ data: Data) -> String {
    SHA256Hash.digest(data).map { String(format: "%02x", $0) }.joined()
}

import Foundation

public enum AutosaveLoadFailure: Error, Equatable, Sendable {
    case noCopy
    case unreadable(String)
}

/// Temporary recovery copy. The user's document is never opened for writing here.
/// Bytes go through `FileAccessPort`; the support-directory lookup uses Foundation.
public struct AutosaveStore {
    public static let recoveryFileName = "recovery.floretta"

    public let directory: URL
    public let fileAccess: any FileAccessPort

    public var recoveryURL: URL {
        directory.appendingPathComponent(Self.recoveryFileName, isDirectory: false)
    }

    public init(directory: URL, fileAccess: any FileAccessPort) {
        self.directory = directory
        self.fileAccess = fileAccess
    }

    public static func inApplicationSupport(fileAccess: any FileAccessPort) throws -> AutosaveStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("Floretta", isDirectory: true)
            .appendingPathComponent("Autosave", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AutosaveStore(directory: directory, fileAccess: fileAccess)
    }

    public func write(_ document: MindMapDocument) throws {
        let data = try FlorettaCodec.encode(document)
        try fileAccess.write(data, to: recoveryURL)
    }

    public func removeRecoveryCopy() throws {
        guard fileAccess.fileExists(at: recoveryURL) else { return }
        try fileAccess.remove(at: recoveryURL)
    }

    /// Reads the copy left behind by an abnormal quit. Corrupt bytes become `.unreadable`.
    public func loadRecoveryCopy() -> Result<MindMapDocument, AutosaveLoadFailure> {
        let url = recoveryURL
        guard fileAccess.fileExists(at: url) else {
            return .failure(.noCopy)
        }
        do {
            let data = try fileAccess.read(from: url)
            return .success(try FlorettaCodec.decode(data))
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }
}

import FlorettaCore
import Foundation

enum AutosaveLoadFailure: Error, Equatable, Sendable {
    case noCopy
    case unreadable(String)
}

/// Temporary recovery copy under Application Support.
/// The user's document is never opened for writing here. The copy is replaced
/// by writing a new file and then `replaceItemAt` / `moveItem`, not by truncating it.
struct AutosaveStore: Sendable {
    static let recoveryFileName = "recovery.floretta"

    let directory: URL

    var recoveryURL: URL {
        directory.appendingPathComponent(Self.recoveryFileName, isDirectory: false)
    }

    static func inApplicationSupport() throws -> AutosaveStore {
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
        return AutosaveStore(directory: directory)
    }

    func write(_ document: MindMapDocument) throws {
        let data = try FlorettaCodec.encode(document)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).partial", isDirectory: false)
        do {
            try data.write(to: tempURL, options: [])
            let destination = recoveryURL
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    func removeRecoveryCopy() throws {
        let fileManager = FileManager.default
        let url = recoveryURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Reads the copy left behind by an abnormal quit. Corrupt bytes become `.unreadable`.
    func loadRecoveryCopy() -> Result<MindMapDocument, AutosaveLoadFailure> {
        let url = recoveryURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.noCopy)
        }
        do {
            let data = try Data(contentsOf: url)
            return .success(try FlorettaCodec.decode(data))
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }
}

import Foundation
import FlorettaCore

/// Same Foundation adapter the app target injects. Duplicated here so package
/// tests do not link SwiftUI or the Xcode app target.
struct FoundationFileAccess: FileAccessPort {
    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try AtomicFileBytes.write(data, to: url)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func remove(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

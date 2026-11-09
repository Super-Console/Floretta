import Foundation
import FlorettaCore

/// Same Foundation adapter the app target injects. Duplicated here so package
/// tests do not link SwiftUI or the Xcode app target.
struct FoundationFileAccess: FileAccessPort {
    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(UUID().uuidString).partial")
        do {
            try data.write(to: temp)
            // The replacement file is fully written before the previous file is removed.
            // replaceItemAt on swift-corelibs-foundation deletes the destination and then throws.
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: temp, to: url)
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
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

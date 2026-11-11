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

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey], skipsHiddenFiles: Bool) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: skipsHiddenFiles ? [.skipsHiddenFiles] : [])
    }

    func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory }
    func searchPathDirectory(_ directory: FileManager.SearchPathDirectory, create: Bool) throws -> URL? {
        try FileManager.default.url(for: directory, in: .userDomainMask, appropriateFor: nil, create: create)
    }
    func ubiquityDocumentsDirectory() -> URL? { nil }
}

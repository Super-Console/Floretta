import Foundation

/// File open/save/observe. Security-scoped bookmarks and file coordination
/// live in the platform adapter, not in Core.
public protocol FileAccessPort {
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func fileExists(at url: URL) -> Bool
    /// Deletes the file. Does nothing when the path is already absent.
    func remove(at url: URL) throws
}

/// Clipboard text. AppKit and UIKit adapters sit outside Core.
public protocol PasteboardPort {
    func readText() -> String?
    func writeText(_ text: String)
}

/// Device name and model identifier ("我的 iPhone" / "我的 iPad").
public protocol DeviceInfoPort {
    var deviceName: String { get }
    var modelIdentifier: String { get }
}

/// Timestamps for tests and for identical behavior across platforms.
public protocol ClockPort {
    func now() -> Date
}

/// Result of measuring one run of text. Layout consumes this later.
public struct FontMetrics: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var ascent: Double

    public init(width: Double, height: Double, ascent: Double) {
        self.width = width
        self.height = height
        self.ascent = ascent
    }
}

/// Text measurement. Platform fonts differ, so Core asks a port instead of calling CoreText.
public protocol FontMetricsPort {
    func measure(text: String, fontName: String, fontSize: Double, maxWidth: Double?) -> FontMetrics
}

/// Marks a directory so device backup / iCloud backup skips it.
/// The Apple adapter sets `isExcludedFromBackup`. Core never imports a platform SDK for this.
public protocol BackupExclusionPort {
    func excludeFromBackup(_ url: URL) throws
}

/// Random reads of at most one caller-provided buffer. Implementations must not
/// allocate a buffer the size of the file.
public protocol RandomAccessReader: AnyObject {
    var count: Int64 { get }
    func read(at offset: Int64, into buffer: UnsafeMutableRawBufferPointer) throws -> Int
    func close() throws
}

/// Sequential writes from a caller-provided buffer.
public protocol SequentialByteWriter: AnyObject {
    func write(_ buffer: UnsafeRawBufferPointer) throws
    func close() throws
}

extension SequentialByteWriter {
    public func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard raw.count > 0 else { return }
            try write(raw)
        }
    }
}

/// File-system adapter for streaming insert, open, and export.
/// Security-scoped access stays in the app; Core only sees these calls.
public protocol StreamingFilePort {
    func byteCount(at url: URL) throws -> Int64
    func fileExists(at url: URL) -> Bool
    func isZip(at url: URL) throws -> Bool
    func openReader(at url: URL) throws -> RandomAccessReader
    func openWriter(at url: URL) throws -> SequentialByteWriter
    func makeTemporary(nextTo url: URL) throws -> URL
    func replace(destination: URL, with temporary: URL) throws
    func remove(at url: URL) throws
}

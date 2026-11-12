import Foundation

/// File open/save/observe. Security-scoped bookmarks and file coordination
/// live in the platform adapter, not in Core.
public protocol FileAccessPort {
    func read(from url: URL) throws -> Data
    /// Replaces `url` durably (temp file, fsync, rename). A crash leaves the previous bytes in place.
    func write(_ data: Data, to url: URL) throws
    func fileExists(at url: URL) -> Bool
    /// Deletes the file. Does nothing when the path is already absent.
    func remove(at url: URL) throws
    func createDirectory(at url: URL) throws
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey], skipsHiddenFiles: Bool) throws -> [URL]
    func temporaryDirectory() -> URL
    func searchPathDirectory(_ directory: FileManager.SearchPathDirectory, create: Bool) throws -> URL?
    func ubiquityDocumentsDirectory() -> URL?
}

/// Clipboard text. AppKit and UIKit adapters sit outside Core.
public protocol PasteboardPort {
    func readText() -> String?
    func writeText(_ text: String)
    func readImageFileURL() -> URL?
    func readImageData() -> (data: Data, fileExtension: String)?
}

/// Device name and model identifier ("我的 iPhone" / "我的 iPad").
public protocol DeviceInfoPort {
    var deviceName: String { get }
    var modelIdentifier: String { get }
    var isPhone: Bool { get }
}

/// Timestamps for tests and for identical behavior across platforms.
public protocol ClockPort: Sendable {
    func now() -> Date
}

/// Foundation's clock is platform-neutral and is the default implementation for Core callers.
public struct FoundationClock: ClockPort {
    public init() {}
    public func now() -> Date { Date() }
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
    /// Same as `measure(text:fontName:fontSize:maxWidth:)`, with the typography
    /// the canvas will paint. Default ignores the extra identity and uses `fontName`.
    func measure(
        text: String,
        fontName: String,
        fontSize: Double,
        maxWidth: Double?,
        fontFamilyID: String,
        nodeDesign: String
    ) -> FontMetrics
}

extension FontMetricsPort {
    public func measure(
        text: String,
        fontName: String,
        fontSize: Double,
        maxWidth: Double?,
        fontFamilyID: String,
        nodeDesign: String
    ) -> FontMetrics {
        measure(text: text, fontName: fontName, fontSize: fontSize, maxWidth: maxWidth)
    }
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
    /// Push bytes to stable storage. Saves call this before `rename`.
    func synchronize() throws
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
    /// `AtomicFileBytes.partialURL(for:)` after the parent directory exists.
    /// The name is stable so a crash can be found. Do not delete `url` here.
    func makeTemporary(nextTo url: URL) throws -> URL
    /// fsync `temporary`, then `rename` it over `destination`. Never delete `destination` first.
    func replace(destination: URL, with temporary: URL) throws
    func remove(at url: URL) throws
}

import CoreGraphics
import CoreText
import Darwin
import Foundation
import FlorettaCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Foundation file adapter. Security-scoped bookmarks and `NSFileCoordinator`
/// can replace this later without changing Core.
public struct FoundationFileAccess: FileAccessPort {
    public init() {}

    public func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
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

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func remove(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

public struct SystemClock: ClockPort {
    public init() {}

    public func now() -> Date { Date() }
}

public struct CoreTextFontMetrics: FontMetricsPort {
    public init() {}

    public func measure(text: String, fontName: String, fontSize: Double, maxWidth: Double?) -> FontMetrics {
        let safeSize = max(CGFloat(fontSize), 1)
        let safeWidth = max(CGFloat(maxWidth ?? .greatestFiniteMagnitude), 1)
        let font = CTFontCreateWithName(fontName as CFString, safeSize, nil)
        guard let mutable = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0) else {
            return FontMetrics(width: 72, height: 32, ascent: Double(safeSize))
        }
        let sample = text.isEmpty ? " " : text
        CFAttributedStringReplaceString(mutable, CFRange(location: 0, length: 0), sample as CFString)
        let range = CFRange(location: 0, length: CFAttributedStringGetLength(mutable))
        CFAttributedStringSetAttribute(mutable, range, kCTFontAttributeName, font)
        let framesetter = CTFramesetterCreateWithAttributedString(mutable)
        var fit = CFRange()
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            range,
            nil,
            CGSize(width: safeWidth, height: CGFloat.greatestFiniteMagnitude),
            &fit
        )
        return FontMetrics(width: Double(suggested.width), height: Double(suggested.height), ascent: Double(safeSize))
    }
}

#if os(macOS)
public struct SystemPasteboard: PasteboardPort {
    public init() {}

    public func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    public func writeText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

public struct SystemDeviceInfo: DeviceInfoPort {
    public init() {}

    public var deviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    public var modelIdentifier: String { "Mac" }
}
#else
public struct SystemPasteboard: PasteboardPort {
    public init() {}

    public func readText() -> String? {
        UIPasteboard.general.string
    }

    public func writeText(_ text: String) {
        UIPasteboard.general.string = text
    }
}

public struct SystemDeviceInfo: DeviceInfoPort {
    public init() {}

    public var deviceName: String { UIDevice.current.name }

    public var modelIdentifier: String { UIDevice.current.model }
}
#endif

/// The ports, built by the app target. Core only sees the protocols.
public struct ApplePlatformPorts {
    public var files: any FileAccessPort
    public var pasteboard: any PasteboardPort
    public var device: any DeviceInfoPort
    public var clock: any ClockPort
    public var fonts: any FontMetricsPort
    public var streaming: any StreamingFilePort
    public var backup: any BackupExclusionPort

    public init(
        files: any FileAccessPort,
        pasteboard: any PasteboardPort,
        device: any DeviceInfoPort,
        clock: any ClockPort,
        fonts: any FontMetricsPort,
        streaming: any StreamingFilePort = FoundationStreamingFiles(),
        backup: any BackupExclusionPort = URLBackupExclusion()
    ) {
        self.files = files
        self.pasteboard = pasteboard
        self.device = device
        self.clock = clock
        self.fonts = fonts
        self.streaming = streaming
        self.backup = backup
    }

    public static func current() -> ApplePlatformPorts {
        ApplePlatformPorts(
            files: FoundationFileAccess(),
            pasteboard: SystemPasteboard(),
            device: SystemDeviceInfo(),
            clock: SystemClock(),
            fonts: CoreTextFontMetrics()
        )
    }
}

public struct URLBackupExclusion: BackupExclusionPort {
    public init() {}

    public func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var copy = url
        try copy.setResourceValues(values)
    }
}

/// Chunked file adapter. Reads and writes go through one caller-sized buffer.
public final class FoundationStreamingFiles: StreamingFilePort {
    public init() {}

    public func byteCount(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isZip(at url: URL) throws -> Bool {
        let reader = try POSIXFileReader(url: url)
        defer { try? reader.close() }
        guard reader.count >= 2 else { return false }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: 2, alignment: 1)
        defer { pointer.deallocate() }
        let buffer = UnsafeMutableRawBufferPointer(start: pointer, count: 2)
        let count = try reader.read(at: 0, into: buffer)
        return count == 2 && buffer[0] == 0x50 && buffer[1] == 0x4B
    }

    public func openReader(at url: URL) throws -> RandomAccessReader {
        try POSIXFileReader(url: url)
    }

    public func openWriter(at url: URL) throws -> SequentialByteWriter {
        try POSIXFileWriter(url: url)
    }

    public func makeTemporary(nextTo url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(".\(UUID().uuidString).partial")
    }

    public func replace(destination: URL, with temporary: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
    }

    public func remove(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

private final class POSIXFileReader: RandomAccessReader {
    let count: Int64
    private var fd: Int32

    init(url: URL) throws {
        fd = Darwin.open(url.path, O_RDONLY)
        guard fd >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        let end = lseek(fd, 0, SEEK_END)
        guard end >= 0 else { throw CocoaError(.fileReadUnknown) }
        count = Int64(end)
    }

    func read(at offset: Int64, into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return 0 }
        let count = pread(fd, base, buffer.count, off_t(offset))
        if count < 0 { throw CocoaError(.fileReadUnknown) }
        return count
    }

    func close() throws {
        if fd >= 0 {
            _ = Darwin.close(fd)
            fd = -1
        }
    }
}

private final class POSIXFileWriter: SequentialByteWriter {
    private var fd: Int32

    init(url: URL) throws {
        fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
    }

    func write(_ buffer: UnsafeRawBufferPointer) throws {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return }
        var written = 0
        while written < buffer.count {
            let count = Darwin.write(fd, base.advanced(by: written), buffer.count - written)
            if count < 0 { throw CocoaError(.fileWriteUnknown) }
            written += count
        }
    }

    func close() throws {
        if fd >= 0 {
            _ = Darwin.close(fd)
            fd = -1
        }
    }
}

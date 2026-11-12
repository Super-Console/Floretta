import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
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
        try AtomicFileBytes.write(data, to: url)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func remove(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey], skipsHiddenFiles: Bool) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: skipsHiddenFiles ? [.skipsHiddenFiles] : [])
    }

    public func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory }

    public func searchPathDirectory(_ directory: FileManager.SearchPathDirectory, create: Bool) throws -> URL? {
        try FileManager.default.url(for: directory, in: .userDomainMask, appropriateFor: nil, create: create)
    }

    public func ubiquityDocumentsDirectory() -> URL? {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return root.appendingPathComponent("Documents", isDirectory: true)
    }
}

public struct SystemClock: ClockPort {
    public init() {}

    public func now() -> Date { FoundationClock().now() }
}

/// Shared typography for measurement, the canvas, the editor, and export.
/// Uses the system UI font and the official paragraph line-break strategy.
/// Do not shrink the font or truncate the string to fake a wrap.
enum NodeTextTypography {
    static func measuringFont(name: String, size: CGFloat) -> CTFont {
        let safe = max(size, 1)
        // Layout historically asked for Helvetica. The canvas paints the system font.
        if name.isEmpty || name == "Helvetica" {
            if let font = CTFontCreateUIFontForLanguage(.system, safe, nil) {
                return font
            }
        }
        return CTFontCreateWithName(name as CFString, safe, nil)
    }

    static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        style.lineBreakStrategy = .standard
        return style
    }

    static func paragraphStyle(lineHeight: Double) -> NSParagraphStyle {
        let style = (paragraphStyle() as? NSMutableParagraphStyle)
            ?? (paragraphStyle().mutableCopy() as! NSMutableParagraphStyle)
        style.lineHeightMultiple = CGFloat(min(max(lineHeight, 0.8), 2.5))
        return style
    }

    static func attributed(_ text: String, font: CTFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle(),
        ])
    }

    /// Visible line fragments at `width`, using the same attributes as measurement.
    static func lineStrings(_ text: String, fontName: String = "Helvetica", fontSize: CGFloat, width: CGFloat) -> [String] {
        let font = measuringFont(name: fontName, size: fontSize)
        let attributed = attributed(text, font: font)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let range = CFRange(location: 0, length: attributed.length)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            range,
            nil,
            CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude),
            nil
        )
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: max(width, 1), height: max(suggested.height + 8, 8)),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        let ns = text as NSString
        return lines.map { line in
            let fragment = CTLineGetStringRange(line)
            return ns.substring(with: NSRange(location: fragment.location, length: fragment.length))
        }
    }
}

public struct CoreTextFontMetrics: FontMetricsPort {
    public init() {}

    public func measure(text: String, fontName: String, fontSize: Double, maxWidth: Double?) -> FontMetrics {
        let safeSize = max(CGFloat(fontSize), 1)
        let safeWidth = max(CGFloat(maxWidth ?? .greatestFiniteMagnitude), 1)
        let font = NodeTextTypography.measuringFont(name: fontName, size: safeSize)
        let sample = text.isEmpty ? " " : text
        let attributed = NodeTextTypography.attributed(sample, font: font)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let range = CFRange(location: 0, length: attributed.length)
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
#if !FLORETTA_QUICK_LOOK
public struct SystemPasteboard: PasteboardPort {
    public init() {}

    public func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    public func writeText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func readImageFileURL() -> URL? {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?
            .first(where: { ImageInsertRoute.accepts(filename: $0.lastPathComponent) })
    }

    public func readImageData() -> (data: Data, fileExtension: String)? {
        let types: [(NSPasteboard.PasteboardType, String)] = [(.png, "png"), (NSPasteboard.PasteboardType("public.jpeg"), "jpg"), (.tiff, "tiff"), (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"), (NSPasteboard.PasteboardType("public.heic"), "heic")]
        for (type, ext) in types {
            if let data = NSPasteboard.general.data(forType: type), !data.isEmpty { return (data, ext) }
        }
        return nil
    }
}

public struct SystemDeviceInfo: DeviceInfoPort {
    public init() {}

    public var deviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    public var modelIdentifier: String { "Mac" }
    public var isPhone: Bool { false }
}
#endif
#else
public struct SystemPasteboard: PasteboardPort {
    public init() {}

    public func readText() -> String? {
        UIPasteboard.general.string
    }

    public func writeText(_ text: String) {
        UIPasteboard.general.string = text
    }

    public func readImageFileURL() -> URL? {
        guard let url = UIPasteboard.general.url, ImageInsertRoute.accepts(filename: url.lastPathComponent) else { return nil }
        return url
    }

    public func readImageData() -> (data: Data, fileExtension: String)? {
        let types = ["public.png", "public.jpeg", "public.tiff", "com.compuserve.gif", "public.heic"]
        let extensions = ["png", "jpg", "tiff", "gif", "heic"]
        for (type, ext) in zip(types, extensions) {
            if let data = UIPasteboard.general.data(forPasteboardType: type), !data.isEmpty { return (data, ext) }
        }
        return nil
    }
}

public struct SystemDeviceInfo: DeviceInfoPort {
    public init() {}

    public var deviceName: String { UIDevice.current.name }

    public var modelIdentifier: String { UIDevice.current.model }
    public var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
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

    #if !FLORETTA_QUICK_LOOK
    public static func current() -> ApplePlatformPorts {
        ApplePlatformPorts(
            files: FoundationFileAccess(),
            pasteboard: SystemPasteboard(),
            device: SystemDeviceInfo(),
            clock: SystemClock(),
            fonts: CoreTextFontMetrics()
        )
    }
    #endif
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
        return AtomicFileBytes.partialURL(for: url)
    }

    public func replace(destination: URL, with temporary: URL) throws {
        try AtomicFileBytes.commit(temporary: temporary, replacing: destination)
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

/// Apple thumbnail adapter. Reads the spill file URL and downsamples with ImageIO.
/// The source attachment is not passed in as `Data`.
public struct ImageIOThumbnailDecoder: ThumbnailDecodingPort {
    public init() {}

    public func downsample(spill: URL, longestEdge: Int) throws -> Data {
        let edge = longestEdge > 0 ? longestEdge : StreamingBudget.thumbnailLongestEdge
        guard let source = CGImageSourceCreateWithURL(spill as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }

    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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

    func synchronize() throws {
        guard fd >= 0 else { return }
        if Darwin.fsync(fd) != 0 { throw CocoaError(.fileWriteUnknown) }
    }

    func close() throws {
        if fd >= 0 {
            _ = Darwin.close(fd)
            fd = -1
        }
    }
}

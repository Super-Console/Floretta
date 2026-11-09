import CoreGraphics
import CoreText
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

/// The five ports, built by the app target. Core only sees the protocols.
public struct ApplePlatformPorts {
    public var files: any FileAccessPort
    public var pasteboard: any PasteboardPort
    public var device: any DeviceInfoPort
    public var clock: any ClockPort
    public var fonts: any FontMetricsPort

    public init(
        files: any FileAccessPort,
        pasteboard: any PasteboardPort,
        device: any DeviceInfoPort,
        clock: any ClockPort,
        fonts: any FontMetricsPort
    ) {
        self.files = files
        self.pasteboard = pasteboard
        self.device = device
        self.clock = clock
        self.fonts = fonts
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

import Foundation

/// File open/save/observe. Security-scoped bookmarks and file coordination
/// live in the platform adapter, not in Core.
public protocol FileAccessPort {
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func fileExists(at url: URL) -> Bool
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

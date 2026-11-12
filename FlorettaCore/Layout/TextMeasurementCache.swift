import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Sizes node text once per text + font size + max width.
/// The font port supplies the raw line box. Padding stays here so every platform
/// adds the same chrome around the measured text.
public final class TextMeasurementCache: @unchecked Sendable {
    public struct Key: Hashable, Sendable {
        public var text: String
        public var fontSize: CGFloat
        public var maxWidth: CGFloat
        public var fontFamilyID: String
        public var nodeDesign: String

        public init(
            text: String,
            fontSize: CGFloat,
            maxWidth: CGFloat,
            fontFamilyID: String = "",
            nodeDesign: String = "default"
        ) {
            self.text = text
            self.fontSize = fontSize
            self.maxWidth = maxWidth
            self.fontFamilyID = fontFamilyID
            self.nodeDesign = nodeDesign
        }
    }

    private let metrics: any FontMetricsPort
    private let lock = NSLock()
    private var store: [Key: CGSize] = [:]
    public private(set) var missCount = 0

    public init(metrics: any FontMetricsPort = EstimatedFontMetrics()) {
        self.metrics = metrics
    }

    public func size(
        text: String,
        fontSize: CGFloat,
        maxWidth: CGFloat,
        fontFamilyID: String = "",
        nodeDesign: String = "default"
    ) -> CGSize {
        let key = Key(
            text: text,
            fontSize: fontSize,
            maxWidth: maxWidth,
            fontFamilyID: fontFamilyID,
            nodeDesign: nodeDesign
        )
        lock.lock()
        if let cached = store[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let measured = measure(
            text: text,
            fontSize: fontSize,
            maxWidth: maxWidth,
            fontFamilyID: fontFamilyID,
            nodeDesign: nodeDesign
        )
        lock.lock()
        if store[key] == nil {
            store[key] = measured
            missCount += 1
        }
        let result = store[key] ?? measured
        lock.unlock()
        return result
    }

    private func measure(
        text: String,
        fontSize: CGFloat,
        maxWidth: CGFloat,
        fontFamilyID: String,
        nodeDesign: String
    ) -> CGSize {
        let safeSize = max(fontSize, 1)
        let safeWidth = max(maxWidth, 1)
        let sample = text.isEmpty ? " " : text
        // An empty family id keeps the historical Helvetica → system UI path
        // for Core tests and un-themed layout. The canvas passes the painted
        // family so node width matches ThemeFontCascade glyphs.
        let raw = metrics.measure(
            text: sample,
            fontName: "Helvetica",
            fontSize: Double(safeSize),
            maxWidth: Double(safeWidth),
            fontFamilyID: fontFamilyID,
            nodeDesign: nodeDesign
        )
        let width = min(safeWidth + 24, max(72, ceil(raw.width) + 24))
        let height = max(32, ceil(raw.height) + 16)
        return CGSize(width: width, height: height)
    }
}

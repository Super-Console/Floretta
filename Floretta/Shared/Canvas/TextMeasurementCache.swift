import CoreText
import Foundation

/// Sizes node text once per text + font size + max width.
final class TextMeasurementCache: @unchecked Sendable {
    struct Key: Hashable, Sendable {
        var text: String
        var fontSize: CGFloat
        var maxWidth: CGFloat
    }

    private let lock = NSLock()
    private var store: [Key: CGSize] = [:]
    private(set) var missCount = 0

    func size(text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        let key = Key(text: text, fontSize: fontSize, maxWidth: maxWidth)
        lock.lock()
        if let cached = store[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let measured = Self.measure(text: text, fontSize: fontSize, maxWidth: maxWidth)
        lock.lock()
        if store[key] == nil {
            store[key] = measured
            missCount += 1
        }
        let result = store[key] ?? measured
        lock.unlock()
        return result
    }

    private static func measure(text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        let safeSize = max(fontSize, 1)
        let safeWidth = max(maxWidth, 1)
        let font = CTFontCreateWithName("Helvetica" as CFString, safeSize, nil)
        let sample = text.isEmpty ? " " : text
        guard let mutable = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0) else {
            return CGSize(width: 72, height: 32)
        }
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
        let width = min(safeWidth + 24, max(72, ceil(suggested.width) + 24))
        let height = max(32, ceil(suggested.height) + 16)
        return CGSize(width: width, height: height)
    }
}

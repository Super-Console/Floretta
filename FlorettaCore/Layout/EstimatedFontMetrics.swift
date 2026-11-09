import Foundation

/// Deterministic stand-in used when a platform font port is not injected.
/// Longer strings measure wider, so layout tests do not need CoreText.
public struct EstimatedFontMetrics: FontMetricsPort {
    public init() {}

    public func measure(text: String, fontName: String, fontSize: Double, maxWidth: Double?) -> FontMetrics {
        let columns = max(text.count, 1)
        let natural = Double(columns) * fontSize * 0.55
        guard let maxWidth, maxWidth > 0, natural > maxWidth else {
            return FontMetrics(width: natural, height: fontSize * 1.25, ascent: fontSize)
        }
        let lines = (natural / maxWidth).rounded(.up)
        return FontMetrics(width: maxWidth, height: fontSize * 1.25 * lines, ascent: fontSize)
    }
}

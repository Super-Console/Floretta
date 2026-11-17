import Foundation

/// Tracks the time spent in non-empty marked-text ranges during one input sample.
/// Empty marked ranges do not qualify as IME composition and are ignored.
public struct MarkedTextCompositionTiming: Equatable, Sendable {
    private var activeStart: TimeInterval?
    private var accumulatedDuration: TimeInterval = 0
    public private(set) var maximumMarkedTextLength = 0

    public init() {}

    public var hasNonEmptyMarkedText: Bool {
        maximumMarkedTextLength > 0
    }

    /// Returns a duration only after all observed marked ranges have ended.
    public var duration: TimeInterval? {
        guard hasNonEmptyMarkedText, activeStart == nil else { return nil }
        return accumulatedDuration
    }

    /// Feeds the current UTF-16 length from NSTextInputClient's marked range.
    /// Repeated updates inside one range keep its original start; separate ranges
    /// are summed without counting time between them.
    public mutating func observe(markedTextLength: Int, at timestamp: TimeInterval) {
        guard timestamp.isFinite, timestamp >= 0 else { return }

        if markedTextLength > 0 {
            if activeStart == nil {
                activeStart = timestamp
            }
            maximumMarkedTextLength = max(maximumMarkedTextLength, markedTextLength)
        } else if let start = activeStart, timestamp >= start {
            accumulatedDuration += timestamp - start
            activeStart = nil
        }
    }
}

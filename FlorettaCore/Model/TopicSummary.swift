import Foundation

/// Inclusive indexes into a parent topic's `children`.
/// This is the range XMind already stores as `"(start,end)"` on a summary or boundary.
public struct TopicChildRange: Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public func contains(_ index: Int) -> Bool {
        index >= start && index <= end
    }

    /// The same covered topics after the sibling list changes.
    /// A gap between survivors is filled, because a range has to stay contiguous.
    /// No survivors means the mark should be removed.
    public func realigned(from oldIDs: [UUID], to newIDs: [UUID]) -> TopicChildRange? {
        guard start >= 0, end >= start, end < oldIDs.count else { return nil }
        var indexes: [Int] = []
        indexes.reserveCapacity(end - start + 1)
        for id in oldIDs[start...end] {
            if let index = newIDs.firstIndex(of: id) {
                indexes.append(index)
            }
        }
        guard let newStart = indexes.min(), let newEnd = indexes.max() else { return nil }
        return TopicChildRange(start: newStart, end: newEnd)
    }
}

/// A summary topic covering a contiguous run of one parent's children.
/// The record is the XMind summary (`children.summary`, or `summaries` plus that topic).
/// It is not inserted into `children`, so it does not change `topicCount`.
public struct TopicSummary: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var text: String
    public var rangeStart: Int
    public var rangeEnd: Int

    public init(id: UUID = UUID(), text: String, rangeStart: Int, rangeEnd: Int) {
        self.id = id
        self.text = text
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }

    public var range: TopicChildRange {
        get { TopicChildRange(start: rangeStart, end: rangeEnd) }
        set {
            rangeStart = newValue.start
            rangeEnd = newValue.end
        }
    }
}

/// A visual enclosure around a contiguous run of one parent's children.
/// The record is the XMind `boundaries` entry on that parent.
public struct TopicBoundary: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var title: String
    public var rangeStart: Int
    public var rangeEnd: Int

    public init(id: UUID = UUID(), title: String = "", rangeStart: Int, rangeEnd: Int) {
        self.id = id
        self.title = title
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }

    public var range: TopicChildRange {
        get { TopicChildRange(start: rangeStart, end: rangeEnd) }
        set {
            rangeStart = newValue.start
            rangeEnd = newValue.end
        }
    }
}

extension MindMapNode {
    mutating func realignMarks(previousChildIDs: [UUID]) {
        let current = children.map(\.id)
        summaries = summaries.compactMap { summary in
            guard let range = summary.range.realigned(from: previousChildIDs, to: current) else { return nil }
            var copy = summary
            copy.range = range
            return copy
        }
        boundaries = boundaries.compactMap { boundary in
            guard let range = boundary.range.realigned(from: previousChildIDs, to: current) else { return nil }
            var copy = boundary
            copy.range = range
            return copy
        }
    }
}

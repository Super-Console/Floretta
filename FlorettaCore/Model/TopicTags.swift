import Foundation

/// One string from XMind `topic.labels`. The topic stores the array itself.
/// There is no separate tag catalog.
public enum TopicLabels {
    /// Trims and drops blanks and exact duplicates. Import does not use this;
    /// a file's label strings are kept as written.
    public static func normalized(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(raw.count)
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || !seen.insert(trimmed).inserted { continue }
            result.append(trimmed)
        }
        return result
    }

    public static func inserting(_ label: String, into labels: [String]) -> [String] {
        normalized(labels + [label])
    }

    public static func removing(_ label: String, from labels: [String]) -> [String] {
        labels.filter { $0 != label }
    }
}

/// One XMind `topic.markers` record. `markerId` is the file's id, not a new key.
public struct TopicMarker: Equatable, Sendable, Hashable, Codable {
    public var markerId: String

    public init(markerId: String) {
        self.markerId = markerId
    }
}

public enum TopicMarkerGroup: Equatable, Sendable {
    case priority
    case progress
    case flag
}

/// Priority, progress, and flag ids that XMind writes as `markerId`.
/// Any other id stays on the same `markers` array and is not given a second model.
public enum TopicMarkerCatalog {
    public static let priorityIDs: [String] = (1...9).map { "priority-\($0)" }
    public static let progressIDs: [String] = [
        "task-start", "task-oct", "task-quarter", "task-3oct", "task-half",
        "task-5oct", "task-3quar", "task-7oct", "task-done",
    ]
    public static let flagIDs: [String] = [
        "flag-red", "flag-orange", "flag-yellow", "flag-green",
        "flag-blue", "flag-purple", "flag-gray",
    ]

    public static func group(of markerId: String) -> TopicMarkerGroup? {
        if priorityIDs.contains(markerId) { return .priority }
        if progressIDs.contains(markerId) { return .progress }
        if flagIDs.contains(markerId) { return .flag }
        return nil
    }

    public static func priorityNumber(_ markerId: String) -> Int? {
        guard markerId.hasPrefix("priority-"), let number = Int(markerId.dropFirst("priority-".count)) else {
            return nil
        }
        return (1...9).contains(number) ? number : nil
    }

    /// 0 is not started. 1 is done. Fractions match the XMind task markers.
    public static func progressFraction(_ markerId: String) -> Double? {
        switch markerId {
        case "task-start": return 0
        case "task-oct": return 0.125
        case "task-quarter": return 0.25
        case "task-3oct": return 0.375
        case "task-half": return 0.5
        case "task-5oct": return 0.625
        case "task-3quar": return 0.75
        case "task-7oct": return 0.875
        case "task-done": return 1
        default: return nil
        }
    }

    public static func color(for markerId: String) -> BranchColor? {
        switch markerId {
        case "priority-1", "flag-red":
            return BranchColor(red: 0.86, green: 0.22, blue: 0.20)
        case "priority-2", "flag-orange":
            return BranchColor(red: 0.90, green: 0.48, blue: 0.13)
        case "priority-3", "flag-yellow":
            return BranchColor(red: 0.86, green: 0.68, blue: 0.12)
        case "priority-4", "flag-green":
            return BranchColor(red: 0.18, green: 0.62, blue: 0.32)
        case "priority-5", "flag-blue":
            return BranchColor(red: 0.20, green: 0.45, blue: 0.82)
        case "priority-6", "flag-purple":
            return BranchColor(red: 0.48, green: 0.32, blue: 0.72)
        case "priority-7", "flag-gray":
            return BranchColor(red: 0.45, green: 0.47, blue: 0.50)
        case "priority-8":
            return BranchColor(red: 0.35, green: 0.40, blue: 0.55)
        case "priority-9":
            return BranchColor(red: 0.32, green: 0.34, blue: 0.38)
        default:
            return nil
        }
    }

    /// Replaces the marker in `group` and leaves every other marker id in place.
    /// `nil` clears that group. An id from another group is ignored.
    public static func assign(
        _ markers: [TopicMarker],
        markerID: String?,
        group: TopicMarkerGroup
    ) -> [TopicMarker] {
        let replacement: TopicMarker?
        if let markerID {
            guard Self.group(of: markerID) == group else { return markers }
            replacement = TopicMarker(markerId: markerID)
        } else {
            replacement = nil
        }
        var kept: [TopicMarker] = []
        kept.reserveCapacity(markers.count)
        var inserted = false
        for marker in markers {
            if Self.group(of: marker.markerId) == group {
                if !inserted, let replacement {
                    kept.append(replacement)
                    inserted = true
                }
                continue
            }
            kept.append(marker)
        }
        if !inserted, let replacement {
            kept.append(replacement)
        }
        return kept
    }
}

/// Extra height inside a topic that has labels or markers. Zero when it has neither,
/// so an unmarked topic keeps the layout it had before tags were drawn.
public enum TopicTagLayout {
    public static let rowHeight = 16.0
    public static let gap = 4.0

    public static func bandHeight(labelCount: Int, markerCount: Int) -> Double {
        let rows = (labelCount > 0 ? 1 : 0) + (markerCount > 0 ? 1 : 0)
        guard rows > 0 else { return 0 }
        return gap + Double(rows) * rowHeight
    }
}

/// One chosen label or marker. Off until the user picks one.
/// Matching topics are highlighted; the rest fade. Nothing is hidden or deleted.
public struct TopicTagFilter: Equatable, Sendable {
    public enum Choice: Equatable, Sendable {
        case label(String)
        case marker(String)
    }

    public var choice: Choice?

    public init(choice: Choice? = nil) {
        self.choice = choice
    }

    public var isActive: Bool { choice != nil }

    public func matches(_ node: MindMapNode) -> Bool {
        switch choice {
        case nil:
            return true
        case .label(let label):
            return node.labels.contains(label)
        case .marker(let markerId):
            return node.markers.contains { $0.markerId == markerId }
        }
    }

    /// Empty when the filter is off. Otherwise the first-sheet topics that stay bright.
    public func highlightedIDs(in document: MindMapDocument) -> Set<UUID> {
        guard isActive else { return [] }
        var ids: Set<UUID> = []
        document.walkTopics { node in
            if matches(node) { ids.insert(node.id) }
        }
        return ids
    }
}

/// Labels and marker ids on the first sheet, in the order they first appear.
public enum TopicTagIndex {
    public static func labels(in document: MindMapDocument) -> [String] {
        var seen: Set<String> = []
        var labels: [String] = []
        document.walkTopics { node in
            for label in node.labels where seen.insert(label).inserted {
                labels.append(label)
            }
        }
        return labels
    }

    public static func markerIDs(in document: MindMapDocument) -> [String] {
        var seen: Set<String> = []
        var ids: [String] = []
        document.walkTopics { node in
            for marker in node.markers where seen.insert(marker.markerId).inserted {
                ids.append(marker.markerId)
            }
        }
        return ids
    }

    /// Empty query matches everything. Used by the filter sheet's search field.
    public static func contains(_ query: String, in text: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return true }
        return text.localizedCaseInsensitiveContains(needle)
    }
}

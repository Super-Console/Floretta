#if os(macOS)
import Foundation

/// Custom menu accelerators only. System-owned shortcuts are never reassigned.
public enum MacMenuShortcutCatalog {
    public struct Chord: Hashable, Sendable {
        public var key: String
        public var modifiers: Set<String>

        public init(_ key: String, _ modifiers: Set<String> = ["command"]) {
            self.key = key.lowercased()
            self.modifiers = modifiers
        }
    }

    public static let custom: [Chord] = [
        Chord("return"), Chord("return", ["command", "shift"]),
        Chord("0"), Chord("+"), Chord("-"), Chord("="), Chord("b"), Chord("i")
    ]

    public static let reserved: Set<Chord> = [
        Chord("q"), Chord("w"), Chord("h"), Chord("m"),
        Chord("tab", ["command"]), Chord("tab", ["command", "shift"])
    ]

    public static func conflicts(in chords: [Chord]) -> [Chord] {
        var seen = Set<Chord>()
        return chords.filter { reserved.contains($0) || !seen.insert($0).inserted }
    }

    public static func isEnabled(_ id: EditorToolbarCommandID, in context: EditorToolbarContext) -> Bool {
        guard EditorToolbarCatalog.isEnabled(id, in: context) else { return false }
        switch id {
        case .child, .sibling, .image, .attachment:
            return context.hasSelectedTopic
        case .summary, .boundary:
            return context.hasSelectedTopic && context.canEncloseSelection
        default:
            return true
        }
    }
}
#endif

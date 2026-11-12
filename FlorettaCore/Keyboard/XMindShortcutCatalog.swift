import Foundation

/// Canonical XMind-aligned chords. The mapper, menu bar, help sheet, and
/// conflict check all read this table so a new shortcut cannot be added in
/// only one place.
public enum XMindShortcutCatalog {
    public struct Entry: Equatable, Sendable {
        public var title: String
        public var key: KeyToken
        public var modifiers: KeyModifiers
        public var command: MindMapCommand
        /// Bare keys (Space, Enter, Tab, +, -, *, /) stay off the menu key-equivalent
        /// table so a focused text field and IME composition keep them.
        public var registersMenuEquivalent: Bool

        public init(
            title: String,
            key: KeyToken,
            modifiers: KeyModifiers = [],
            command: MindMapCommand,
            registersMenuEquivalent: Bool
        ) {
            self.title = title
            self.key = key
            self.modifiers = modifiers
            self.command = command
            self.registersMenuEquivalent = registersMenuEquivalent
        }

        public var chord: ShortcutChord {
            ShortcutChord(key: key, modifiers: modifiers)
        }

        public var isSingleKey: Bool {
            modifiers.isEmpty || (modifiers == .shift && isShiftedGlyph)
        }

        private var isShiftedGlyph: Bool {
            guard case .character(let character) = key else { return false }
            return character == "+" || character == "*"
        }
    }

    public struct ShortcutChord: Hashable, Sendable {
        public var key: String
        public var modifiers: Int

        public init(key: KeyToken, modifiers: KeyModifiers) {
            self.key = Self.tokenKey(key)
            self.modifiers = modifiers.rawValue
        }

        private static func tokenKey(_ key: KeyToken) -> String {
            switch key {
            case .tab: return "tab"
            case .enter: return "enter"
            case .space: return "space"
            case .escape: return "escape"
            case .delete: return "delete"
            case .backspace: return "backspace"
            case .up: return "up"
            case .down: return "down"
            case .left: return "left"
            case .right: return "right"
            case .f2: return "f2"
            case .f5: return "f5"
            case .character(let character): return String(character).lowercased()
            }
        }
    }

    public static let entries: [Entry] = [
        Entry(title: "编辑主题", key: .space, command: .beginEdit, registersMenuEquivalent: false),
        Entry(title: "编辑主题", key: .f2, command: .beginEdit, registersMenuEquivalent: false),
        Entry(title: "新建同级（后）", key: .enter, command: .createSibling, registersMenuEquivalent: false),
        Entry(title: "新建子级", key: .tab, command: .createChild, registersMenuEquivalent: false),
        Entry(title: "新建同级（前）", key: .enter, modifiers: .shift, command: .createSiblingBefore, registersMenuEquivalent: false),
        Entry(title: "新建父级", key: .enter, modifiers: .command, command: .createParent, registersMenuEquivalent: true),
        Entry(title: "删除主题", key: .delete, command: .deleteSelection, registersMenuEquivalent: false),
        Entry(title: "删除主题", key: .backspace, command: .deleteSelection, registersMenuEquivalent: false),
        Entry(title: "撤销", key: .character("z"), modifiers: .command, command: .undo, registersMenuEquivalent: false),
        Entry(title: "重做", key: .character("z"), modifiers: [.command, .shift], command: .redo, registersMenuEquivalent: false),
        Entry(title: "重做", key: .character("y"), modifiers: .command, command: .redo, registersMenuEquivalent: false),
        Entry(title: "全选主题", key: .character("a"), modifiers: .command, command: .selectAllTopics, registersMenuEquivalent: false),
        Entry(title: "全选同级", key: .character("a"), modifiers: [.command, .shift], command: .selectAllSiblings, registersMenuEquivalent: true),
        Entry(title: "全选子级", key: .character("a"), modifiers: [.command, .option], command: .selectAllChildren, registersMenuEquivalent: true),
        Entry(title: "属性", key: .enter, modifiers: .option, command: .openProperties, registersMenuEquivalent: true),
        Entry(title: "跳到中心主题", key: .character("r"), modifiers: .command, command: .jumpToCentralTopic, registersMenuEquivalent: true),
        Entry(title: "展开分支", key: .character("+"), command: .expandBranch, registersMenuEquivalent: false),
        Entry(title: "收起分支", key: .character("-"), command: .collapseBranch, registersMenuEquivalent: false),
        Entry(title: "展开全部", key: .character("*"), command: .expandAll, registersMenuEquivalent: false),
        Entry(title: "收起全部", key: .character("/"), command: .collapseAll, registersMenuEquivalent: false),
        Entry(title: "上移主题", key: .up, modifiers: .option, command: .moveTopic(.up), registersMenuEquivalent: true),
        Entry(title: "下移主题", key: .down, modifiers: .option, command: .moveTopic(.down), registersMenuEquivalent: true),
        Entry(title: "快捷键一览", key: .character("l"), modifiers: [.command, .shift], command: .showShortcutHelp, registersMenuEquivalent: true),
    ]

    public static var menuEntries: [Entry] {
        entries.filter(\.registersMenuEquivalent)
    }

    public static func conflicts(in entries: [Entry] = entries) -> [Entry] {
        var seen: [ShortcutChord: MindMapCommand] = [:]
        var conflicts: [Entry] = []
        for entry in entries {
            if let existing = seen[entry.chord], existing != entry.command {
                conflicts.append(entry)
            } else {
                seen[entry.chord] = entry.command
            }
        }
        return conflicts
    }

    public static func command(for event: KeyEvent) -> MindMapCommand? {
        for entry in entries where entry.modifiers == event.modifiers && tokensMatch(entry.key, event.key) {
            return entry.command
        }
        return nil
    }

    public static func display(_ key: KeyToken, _ modifiers: KeyModifiers) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyGlyph(key))
        return parts.joined()
    }

    private static func tokensMatch(_ lhs: KeyToken, _ rhs: KeyToken) -> Bool {
        switch (lhs, rhs) {
        case (.character(let a), .character(let b)):
            return String(a).lowercased() == String(b).lowercased()
        default:
            return lhs == rhs
        }
    }

    private static func keyGlyph(_ key: KeyToken) -> String {
        switch key {
        case .tab: return "⇥"
        case .enter: return "↩"
        case .space: return "Space"
        case .escape: return "Esc"
        case .delete: return "⌦"
        case .backspace: return "⌫"
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .f2: return "F2"
        case .f5: return "F5"
        case .character(let character):
            if character == "+" { return "+" }
            if character == "-" { return "-" }
            if character == "*" { return "*" }
            if character == "/" { return "/" }
            return String(character).uppercased()
        }
    }
}

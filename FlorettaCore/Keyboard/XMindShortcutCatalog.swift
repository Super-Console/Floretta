import Foundation

/// The one table of rebindable keyboard commands.
///
/// The mapper, the macOS menu equivalents, the iPad hardware `UIKeyCommand`
/// list, the 快捷键一览 sheet, and the 设置 ▸ 快捷键 page all read this table, so
/// a chord cannot be added, renamed, or defaulted in only one place.
///
/// Every row states the mode it applies in. Enter is two commands: `commitEdit`
/// leaves the text field (edit mode) and `createSibling` makes a topic (command
/// mode), so the same key pressed twice yields exactly one new topic.
public enum ShortcutGroup: String, CaseIterable, Sendable, Identifiable {
    case structure
    case editing
    case history
    case selection
    case branch
    case view
    case help

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .structure: "创建结构"
        case .editing: "编辑与删除"
        case .history: "撤销与重做"
        case .selection: "选择与查找"
        case .branch: "分支与移动"
        case .view: "视图"
        case .help: "帮助"
        }
    }
}

/// Stable identity of one bindable command. The raw value is the storage key in
/// `AppSettings`, so renaming a case would drop a user's binding.
public enum ShortcutCommandID: String, CaseIterable, Codable, Sendable, Hashable {
    case createSibling
    case createChild
    case createSiblingBefore
    case createParent
    case beginEdit
    case commitEdit
    case insertNewline
    case deleteSelection
    case openProperties
    case undo
    case redo
    case selectAllTopics
    case selectAllSiblings
    case selectAllChildren
    case find
    case expandBranch
    case collapseBranch
    case expandAll
    case collapseAll
    case moveTopicUp
    case moveTopicDown
    case jumpToCentralTopic
    case toggleOutline
    case toggleImmersive
    case showShortcutHelp
}

public enum XMindShortcutCatalog {
    /// One rebindable row: title, scope, command, and the chord it ships with.
    public struct Command: Equatable, Sendable, Identifiable {
        public var id: ShortcutCommandID
        public var title: String
        public var group: ShortcutGroup
        public var command: MindMapCommand
        /// Which key handler owns the chord. ↩ and ⌘↩ are used by both modes —
        /// the same chord in two scopes is not a clash, so the conflict check
        /// only compares rows inside one mode.
        public var mode: KeyboardMode
        /// nil means 未绑定: the command has no key until the user picks one.
        public var defaultChord: ShortcutChord?
        /// Extra fixed chords. ⇧↩ is a caret-level line break in every Mac text
        /// field, so 框内换行 keeps it even when its main chord is rebound.
        public var alternateChords: [ShortcutChord]
        /// The menu item shows the current chord. Bare keys (+ - * / Space
        /// Entry Tab) never register: they would swallow typing in every text
        /// field of the app. `Entry.showsInMenu` is that guard.
        public var showsInMenu: Bool

        public init(
            id: ShortcutCommandID,
            title: String,
            group: ShortcutGroup,
            command: MindMapCommand,
            mode: KeyboardMode = .command,
            defaultChord: ShortcutChord?,
            alternateChords: [ShortcutChord] = [],
            showsInMenu: Bool = true
        ) {
            self.id = id
            self.title = title
            self.group = group
            self.command = command
            self.mode = mode
            self.defaultChord = defaultChord
            self.alternateChords = alternateChords
            self.showsInMenu = showsInMenu
        }

        public var chords: [ShortcutChord] {
            (defaultChord.map { [$0] } ?? []) + alternateChords
        }
    }

    /// One resolved key → command row. `ShortcutBindings.entries()` builds these
    /// from the chords in force; the shipped table is `ShortcutBindings.catalogDefaults`.
    public struct Entry: Equatable, Sendable {
        public var id: ShortcutCommandID
        public var title: String
        public var key: KeyToken
        public var modifiers: KeyModifiers
        public var command: MindMapCommand
        public var mode: KeyboardMode
        /// Bare keys (Space, Enter, Tab, +, -, *, /) stay off the menu key-equivalent
        /// table so a focused text field and IME composition keep them.
        public var registersMenuEquivalent: Bool

        public init(
            id: ShortcutCommandID = .createSibling,
            title: String,
            key: KeyToken,
            modifiers: KeyModifiers = [],
            command: MindMapCommand,
            mode: KeyboardMode = .command,
            registersMenuEquivalent: Bool
        ) {
            self.id = id
            self.title = title
            self.key = key
            self.modifiers = modifiers
            self.command = command
            self.mode = mode
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

        /// The menu may carry this row only when it is not a bare key.
        public var showsInMenu: Bool {
            registersMenuEquivalent && !isSingleKey
        }
    }

    public struct ShortcutChord: Hashable, Sendable {
        public var key: String
        public var modifiers: Int

        public init(key: KeyToken, modifiers: KeyModifiers) {
            self.key = Self.tokenKey(key)
            self.modifiers = modifiers.rawValue
        }

        /// Storage form: "<modifier bits>:<key>", e.g. "2:z" for ⌘Z. Unknown
        /// keys are refused so a hand-edited default cannot smuggle in a token
        /// the mapper cannot resolve.
        public init?(storageValue: String) {
            let parts = storageValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let bits = Int(parts[0]) else { return nil }
            let key = String(parts[1])
            guard !key.isEmpty, Self.token(for: key) != nil else { return nil }
            self.key = key
            self.modifiers = bits
        }

        public var storageValue: String {
            "\(modifiers):\(key)"
        }

        public var keyModifiers: KeyModifiers {
            KeyModifiers(rawValue: modifiers)
        }

        public var keyToken: KeyToken? {
            Self.token(for: key)
        }

        /// "⌘⇧Z" in the UI. An unknown key falls back to the raw token.
        public var displayText: String {
            guard let token = keyToken else { return key }
            return XMindShortcutCatalog.display(token, keyModifiers)
        }

        static func tokenKey(_ key: KeyToken) -> String {
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

        static func token(for key: String) -> KeyToken? {
            switch key {
            case "tab": return .tab
            case "enter": return .enter
            case "space": return .space
            case "escape": return .escape
            case "delete": return .delete
            case "backspace": return .backspace
            case "up": return .up
            case "down": return .down
            case "left": return .left
            case "right": return .right
            case "f2": return .f2
            case "f5": return .f5
            default:
                guard key.count == 1, let character = key.first else { return nil }
                return .character(character)
            }
        }
    }

    /// The shipped chord table. Order is the mapper's tie-break when two rows
    /// in one mode share a chord (the conflict check warns before that happens).
    public static let commands: [Command] = [
        // 创建结构
        Command(id: .createSibling, title: "新建同级", group: .structure,
                command: .createSibling,
                defaultChord: ShortcutChord(key: .enter, modifiers: [])),
        Command(id: .createChild, title: "新建子级", group: .structure,
                command: .createChild,
                defaultChord: ShortcutChord(key: .tab, modifiers: [])),
        Command(id: .createSiblingBefore, title: "新建同级（前）", group: .structure,
                command: .createSiblingBefore,
                defaultChord: ShortcutChord(key: .enter, modifiers: .shift)),
        Command(id: .createParent, title: "新建父级", group: .structure,
                command: .createParent,
                defaultChord: ShortcutChord(key: .enter, modifiers: .command)),

        // 编辑与删除
        Command(id: .beginEdit, title: "编辑主题", group: .editing,
                command: .beginEdit,
                defaultChord: ShortcutChord(key: .space, modifiers: []),
                alternateChords: [ShortcutChord(key: .f2, modifiers: [])]),
        Command(id: .commitEdit, title: "结束编辑", group: .editing,
                command: .commitEdit, mode: .edit,
                defaultChord: ShortcutChord(key: .enter, modifiers: [])),
        Command(id: .insertNewline, title: "框内换行", group: .editing,
                command: .insertNewline, mode: .edit,
                defaultChord: ShortcutChord(key: .enter, modifiers: .command),
                alternateChords: [ShortcutChord(key: .enter, modifiers: .shift)],
                showsInMenu: false),
        Command(id: .deleteSelection, title: "删除主题", group: .editing,
                command: .deleteSelection,
                defaultChord: ShortcutChord(key: .backspace, modifiers: []),
                alternateChords: [ShortcutChord(key: .delete, modifiers: [])],
                showsInMenu: false),
        Command(id: .openProperties, title: "主题属性", group: .editing,
                command: .openProperties,
                defaultChord: ShortcutChord(key: .enter, modifiers: .option)),

        // 撤销与重做
        Command(id: .undo, title: "撤销", group: .history,
                command: .undo,
                defaultChord: ShortcutChord(key: .character("z"), modifiers: .command),
                showsInMenu: false),
        Command(id: .redo, title: "重做", group: .history,
                command: .redo,
                defaultChord: ShortcutChord(key: .character("z"), modifiers: [.command, .shift]),
                alternateChords: [ShortcutChord(key: .character("y"), modifiers: .command)],
                showsInMenu: false),

        // 选择与查找
        Command(id: .selectAllTopics, title: "全选主题", group: .selection,
                command: .selectAllTopics,
                defaultChord: ShortcutChord(key: .character("a"), modifiers: .command),
                showsInMenu: false),
        Command(id: .selectAllSiblings, title: "全选同级", group: .selection,
                command: .selectAllSiblings,
                defaultChord: ShortcutChord(key: .character("a"), modifiers: [.command, .shift])),
        Command(id: .selectAllChildren, title: "全选子级", group: .selection,
                command: .selectAllChildren,
                defaultChord: ShortcutChord(key: .character("a"), modifiers: [.command, .option])),
        Command(id: .find, title: "查找", group: .selection,
                command: .find,
                defaultChord: ShortcutChord(key: .character("f"), modifiers: .command)),

        // 分支与移动
        Command(id: .expandBranch, title: "展开分支", group: .branch,
                command: .expandBranch,
                defaultChord: ShortcutChord(key: .character("+"), modifiers: [])),
        Command(id: .collapseBranch, title: "收起分支", group: .branch,
                command: .collapseBranch,
                defaultChord: ShortcutChord(key: .character("-"), modifiers: [])),
        Command(id: .expandAll, title: "展开全部", group: .branch,
                command: .expandAll,
                defaultChord: ShortcutChord(key: .character("*"), modifiers: [])),
        Command(id: .collapseAll, title: "收起全部", group: .branch,
                command: .collapseAll,
                defaultChord: ShortcutChord(key: .character("/"), modifiers: [])),
        Command(id: .moveTopicUp, title: "上移主题", group: .branch,
                command: .moveTopic(.up),
                defaultChord: ShortcutChord(key: .up, modifiers: .option)),
        Command(id: .moveTopicDown, title: "下移主题", group: .branch,
                command: .moveTopic(.down),
                defaultChord: ShortcutChord(key: .down, modifiers: .option)),
        Command(id: .jumpToCentralTopic, title: "跳到中心主题", group: .branch,
                command: .jumpToCentralTopic,
                defaultChord: ShortcutChord(key: .character("r"), modifiers: .command)),

        // 视图: the two toolbar commands ship unbound; binding them is additive.
        Command(id: .toggleOutline, title: "大纲", group: .view,
                command: .toggleOutline, defaultChord: nil),
        Command(id: .toggleImmersive, title: "沉浸", group: .view,
                command: .toggleImmersive, defaultChord: nil),

        // 帮助
        Command(id: .showShortcutHelp, title: "快捷键一览", group: .help,
                command: .showShortcutHelp,
                defaultChord: ShortcutChord(key: .character("l"), modifiers: [.command, .shift])),
    ]

    public static func command(_ id: ShortcutCommandID) -> Command? {
        commands.first { $0.id == id }
    }

    public static func commands(in group: ShortcutGroup) -> [Command] {
        commands.filter { $0.group == group }
    }

    /// The table at its shipped defaults, one entry per chord.
    public static var entries: [Entry] {
        ShortcutBindings.catalogDefaults.entries()
    }

    public static var menuEntries: [Entry] {
        entries.filter(\.showsInMenu)
    }

    /// Two rows in the same mode on one chord. Different modes may share a
    /// chord: ↩ commits in a text field and creates a topic on the canvas.
    public static func conflicts(in entries: [Entry] = entries) -> [Entry] {
        var seen: [ModeChord: MindMapCommand] = [:]
        var conflicts: [Entry] = []
        for entry in entries {
            let key = ModeChord(mode: entry.mode, chord: entry.chord)
            if let existing = seen[key], existing != entry.command {
                conflicts.append(entry)
            } else {
                seen[key] = entry.command
            }
        }
        return conflicts
    }

    public static func command(for event: KeyEvent) -> MindMapCommand? {
        KeyboardCommandMapper.map(event)
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

    /// A key and a mode, which is the scope a chord is unique in.
    struct ModeChord: Hashable {
        var mode: KeyboardMode
        var chord: ShortcutChord
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

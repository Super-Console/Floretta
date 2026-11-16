import Foundation

public enum KeyboardMode: Hashable, Sendable {
    case command
    case edit
}

/// Canvas arrows use laid-out frames. Outline arrows walk the visible tree.
/// Both surfaces use the same `KeyboardCommandMapper` commands.
public enum KeyboardSurface: Equatable, Sendable {
    case canvas
    case outline
}

public struct KeyModifiers: OptionSet, Equatable, Sendable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let command = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

public enum KeyToken: Equatable, Sendable {
    case tab
    case enter
    case space
    case escape
    case delete
    case backspace
    case up
    case down
    case left
    case right
    case f2
    case f5
    case character(Character)
}

public struct KeyEvent: Equatable, Sendable {
    public var key: KeyToken
    public var modifiers: KeyModifiers
    public var mode: KeyboardMode
    public var isComposing: Bool

    public init(key: KeyToken, modifiers: KeyModifiers, mode: KeyboardMode, isComposing: Bool) {
        self.key = key
        self.modifiers = modifiers
        self.mode = mode
        self.isComposing = isComposing
    }
}

public enum TopicMove: Equatable, Sendable {
    case up
    case down
}

public enum MindMapCommand: Equatable, Sendable {
    case createChild
    case createSibling
    case createSiblingBefore
    case createParent
    case insertNewline
    case beginEdit
    case commitEdit
    case cancelEdit
    case deleteSelection
    case moveSelection(SelectionMove)
    case undo
    case redo
    case toggleCollapse
    case expandBranch
    case collapseBranch
    case expandAll
    case collapseAll
    case moveTopic(TopicMove)
    case selectAllTopics
    case selectAllSiblings
    case selectAllChildren
    case openProperties
    case jumpToCentralTopic
    case showShortcutHelp
    /// Toolbar commands that can also carry a chord. The canvas does not change
    /// them; the editor routes them to the same action the menu item runs.
    case toggleOutline
    case toggleImmersive
    case find
}

/// Pure key → command map, resolved against the chords in force.
///
/// Command mode owns structure keys. Edit mode owns the text field: ↩ ends the
/// edit, ⇧↩ and ⌘↩ put a line break in the topic text, Esc cancels. Because ↩
/// means "leave the field" in one mode and "new sibling" in the other, the same
/// key pressed twice yields exactly one new topic.
///
/// Whenever a text field is focused (edit mode) or IME composition is active
/// (`isComposing`), every command-mode shortcut (Space, ⇧↩, Tab, +, -, *, /) is
/// suppressed, and only the edit-mode rows plus Escape resolve.
///
/// Delete choice: in command mode, Backspace, forward Delete, and ⌘Backspace all
/// delete the selected node. macOS prints "delete" on the large Backspace key; a
/// full keyboard also has forward Delete. Mapping both means either keyboard
/// removes the node. Edit mode does not map those keys, so the text view deletes
/// characters. ⌘Backspace is the taskbook chord.
public enum KeyboardCommandMapper {
    public static func map(
        _ event: KeyEvent,
        bindings: ShortcutBindings = .catalogDefaults
    ) -> MindMapCommand? {
        if event.isComposing {
            return nil
        }
        switch event.mode {
        case .command:
            return mapCommand(event, bindings: bindings)
        case .edit:
            return mapEdit(event, bindings: bindings)
        }
    }

    private static func mapCommand(_ event: KeyEvent, bindings: ShortcutBindings) -> MindMapCommand? {
        if let command = bindings.command(for: event) {
            return command
        }
        if event.modifiers.isEmpty {
            switch event.key {
            case .up: return .moveSelection(.up)
            case .down: return .moveSelection(.down)
            case .left: return .moveSelection(.left)
            case .right: return .moveSelection(.right)
            default: break
            }
        }
        if event.modifiers == .command, event.key == .backspace || event.key == .delete {
            return .deleteSelection
        }
        return nil
    }

    /// Escape stays fixed: it is the system's cancel gesture in every text view.
    /// Everything else comes from the edit-mode rows of the catalog.
    private static func mapEdit(_ event: KeyEvent, bindings: ShortcutBindings) -> MindMapCommand? {
        if event.key == .escape, event.modifiers.isEmpty {
            return .cancelEdit
        }
        return bindings.command(for: event)
    }
}

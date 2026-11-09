import Foundation

public enum KeyboardMode: Equatable, Sendable {
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

public enum MindMapCommand: Equatable, Sendable {
    case createChild
    case createSibling
    case insertNewline
    case beginEdit
    case commitEdit
    case cancelEdit
    case deleteSelection
    case moveSelection(SelectionMove)
    case undo
    case redo
    case toggleCollapse
}

/// Pure key → command map. The canvas calls this; it does not look at the tree.
///
/// Command mode owns structure keys. Edit mode keeps Tab, Space, arrows, Delete, and ⌘Z
/// from creating or deleting nodes. Enter in edit mode commits and returns to command mode
/// (it does not create a sibling). Shift+Enter inserts a newline. A second Enter, back in
/// command mode, creates the sibling.
///
/// Delete choice: in command mode, Backspace, forward Delete, and ⌘Backspace all delete the
/// selected node. macOS prints "delete" on the large Backspace key; a full keyboard also has
/// forward Delete. Mapping both means either keyboard removes the node. Edit mode does not
/// map those keys, so the text view deletes characters. ⌘Backspace is the taskbook chord.
public enum KeyboardCommandMapper {
    public static func map(_ event: KeyEvent) -> MindMapCommand? {
        if event.isComposing {
            return nil
        }
        switch event.mode {
        case .command:
            return mapCommand(event)
        case .edit:
            return mapEdit(event)
        }
    }

    private static func mapCommand(_ event: KeyEvent) -> MindMapCommand? {
        if event.modifiers.isEmpty {
            switch event.key {
            case .tab: return .createChild
            case .enter: return .createSibling
            case .space: return .beginEdit
            case .delete, .backspace: return .deleteSelection
            case .up: return .moveSelection(.up)
            case .down: return .moveSelection(.down)
            case .left: return .moveSelection(.left)
            case .right: return .moveSelection(.right)
            case .escape, .character: return nil
            }
        }
        if event.modifiers == .command, isZ(event.key) {
            return .undo
        }
        if event.modifiers == [.command, .shift], isZ(event.key) {
            return .redo
        }
        if event.modifiers == .command, event.key == .backspace || event.key == .delete {
            return .deleteSelection
        }
        return nil
    }

    private static func mapEdit(_ event: KeyEvent) -> MindMapCommand? {
        if event.key == .enter, event.modifiers == .shift {
            return .insertNewline
        }
        if event.key == .enter, event.modifiers.isEmpty {
            return .commitEdit
        }
        if event.key == .escape, event.modifiers.isEmpty {
            return .cancelEdit
        }
        return nil
    }

    private static func isZ(_ key: KeyToken) -> Bool {
        guard case .character(let character) = key else { return false }
        return character == "z" || character == "Z"
    }
}

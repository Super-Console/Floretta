import Foundation

/// One removed canvas, kept so the editor can put it back where it was.
///
/// The sheet value is the whole canvas, camera included. `MindMapCanvas` for
/// slot 0 has no stored id of its own (`MindMapDocument` keeps the first sheet
/// in its own fields), so an id minted here is not compared anywhere.
public struct CanvasSheetRemoval: Equatable, Sendable {
    /// Where the sheet sat before it was removed. Put back restores this slot.
    public let index: Int
    /// The sheet itself, with the camera it had when it went away.
    public let canvas: MindMapCanvas
    /// Ordering token. A removal is the newest ⌘Z step only while no content
    /// edit is newer than this value.
    public let clock: Int

    public init(index: Int, canvas: MindMapCanvas, clock: Int) {
        self.index = index
        self.canvas = canvas
        self.clock = clock
    }
}

/// Undo records for canvas-sheet structure changes.
///
/// Content edits keep their own per-sheet stack in `MindMapKeyboardSession`, and
/// that stack is dropped whenever the sheet changes. This value holds the other
/// half: sheets that were removed. It also owns one clock shared by both kinds of
/// step, so ⌘Z undoes the newest step instead of always preferring one stack.
///
/// A removal stays restorable after later edits (`restorableRemoval`), which is
/// what the sheet menu's 「撤销删除画布」 uses. Only `undoableRemoval` /
/// `redoableRemoval` answer "is this the step ⌘Z means right now?".
public struct CanvasSheetHistory: Equatable, Sendable {
    public private(set) var undoable: [CanvasSheetRemoval] = []
    public private(set) var redoable: [CanvasSheetRemoval] = []
    /// Clock value of the newest content edit on the active sheet.
    public private(set) var contentClock = 0
    private var clock = 0
    /// How many removals are kept. A sheet is a whole canvas, so the stack is short.
    public let limit: Int

    public init(limit: Int = 20) {
        self.limit = max(1, limit)
    }

    /// Notes a content edit on the active sheet, so an older sheet removal is not
    /// reported as the step ⌘Z should undo first.
    public mutating func noteContentEdit() {
        clock += 1
        contentClock = clock
    }

    /// Records a removal as a new structural step. Clears redo: a new step
    /// invalidates the steps that were undone before it.
    public mutating func recordRemoval(index: Int, canvas: MindMapCanvas) {
        clock += 1
        undoable.append(CanvasSheetRemoval(index: index, canvas: canvas, clock: clock))
        if undoable.count > limit {
            undoable.removeFirst(undoable.count - limit)
        }
        redoable.removeAll()
    }

    /// The removal ⌘Z should undo now. Nil when a content edit is newer.
    public var undoableRemoval: CanvasSheetRemoval? {
        guard let last = undoable.last, last.clock > contentClock else { return nil }
        return last
    }

    /// The removal ⌘⇧Z should redo now. Nil when a content edit is newer.
    public var redoableRemoval: CanvasSheetRemoval? {
        guard let last = redoable.last, last.clock > contentClock else { return nil }
        return last
    }

    /// The removal that can still be put back from the menu, whatever the clock says.
    public var restorableRemoval: CanvasSheetRemoval? { undoable.last }

    public var canRestore: Bool { !undoable.isEmpty }

    /// Moves the newest removal to the redo stack. Nil when a content edit is newer.
    @discardableResult
    public mutating func popUndo() -> CanvasSheetRemoval? {
        guard undoableRemoval != nil, let last = undoable.popLast() else { return nil }
        redoable.append(last)
        return last
    }

    /// Moves the newest removal back to the undo stack for ⌘⇧Z. The clock is kept,
    /// so redoing and undoing one deletion does not reorder it against content edits.
    @discardableResult
    public mutating func popRedo() -> CanvasSheetRemoval? {
        guard redoableRemoval != nil, let last = redoable.popLast() else { return nil }
        undoable.append(last)
        return last
    }

    /// Moves the newest removal to the redo stack without the clock check.
    /// The menu's 「撤销删除画布」 uses this after later edits.
    @discardableResult
    public mutating func popRestorable() -> CanvasSheetRemoval? {
        guard let last = undoable.popLast() else { return nil }
        redoable.append(last)
        return last
    }

    /// Drops every record. Used when a step inserts a sheet: sheet indexes after the
    /// insertion shift, so a stored index would no longer name the sheet it came from.
    public mutating func clear() {
        undoable.removeAll()
        redoable.removeAll()
    }
}

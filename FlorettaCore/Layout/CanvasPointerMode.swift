import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Which gesture a drag on blank canvas performs.
///
/// XMind ships the same two tools. `select` is the arrow: a drag on empty paper
/// draws a marquee and selects the topics it touches. `pan` is the open hand:
/// the same drag moves the camera, which is what this canvas did before the
/// pointer modes existed. Clicking a topic and dragging it is unaffected in both
/// modes; so are stickies, regions, and the text being edited.
public enum CanvasPointerMode: String, CaseIterable, Equatable, Sendable {
    case select
    case pan

    /// The Mac opens in the pointer: a trackpad pans with a two-finger scroll,
    /// so a one-finger drag is there to select. Touch platforms keep the pan
    /// drag they shipped with, so iPhone and iPad interact exactly as before.
    public static var platformDefault: CanvasPointerMode {
        #if os(macOS)
        return .select
        #else
        return .pan
        #endif
    }

    /// The stored preference, or the platform default when the key is missing or
    /// holds a value this build does not know.
    public static func stored(_ raw: String?) -> CanvasPointerMode {
        guard let raw, let mode = CanvasPointerMode(rawValue: raw) else { return platformDefault }
        return mode
    }

    /// The mode a press actually uses. Holding Space borrows the hand for as long
    /// as the key is down; the preference underneath is untouched.
    public func effective(spaceHeld: Bool) -> CanvasPointerMode {
        spaceHeld ? .pan : self
    }

    /// What the toggle in the status capsule flips to.
    public var toggled: CanvasPointerMode {
        self == .select ? .pan : .select
    }

    /// SF Symbol that names the mode showing now: the arrow for the pointer, the
    /// open hand for panning.
    public var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pan: return "hand.raised"
        }
    }
}

/// Marquee geometry. Pure: canvas points in, topic ids out. Nothing here reads
/// the camera, so the view converts its two screen corners to canvas points
/// once and the same math runs at any zoom.
public enum CanvasMarquee {
    /// The rectangle two opposite corners describe. Never negative, never Null:
    /// dragging up and to the left makes the same rect as down and to the right.
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else { return .zero }
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// Topics whose frame touches `rect`: fully inside, or crossing one edge.
    /// A zero-width or zero-height rect selects nothing, which is what a drag
    /// that has not moved yet must report.
    public static func intersectingIDs(_ rect: CGRect, in frames: [NodeFrame]) -> Set<UUID> {
        guard rect.width > 0, rect.height > 0 else { return [] }
        var ids: Set<UUID> = []
        for frame in frames where frame.rect.intersects(rect) {
            ids.insert(frame.id)
        }
        return ids
    }

    /// The selection a marquee reports. With Shift (`additive`) the hit set
    /// merges into the selection the drag started from; without it the marquee
    /// owns the selection outright, so shrinking the rectangle drops nodes.
    public static func selection(
        _ rect: CGRect,
        in frames: [NodeFrame],
        from base: Set<UUID>,
        additive: Bool
    ) -> Set<UUID> {
        let hits = intersectingIDs(rect, in: frames)
        return additive ? base.union(hits) : hits
    }
}

/// One marquee drag in flight. `start` and `current` are canvas coordinates,
/// the same space as `NodeFrame.rect`, so zoom and pan need no extra work while
/// the drag runs.
public struct CanvasMarqueeState: Equatable, Sendable {
    public var start: CGPoint
    public var current: CGPoint
    /// The selection as it was when the drag began. Escape restores exactly this.
    public let baseSelection: Set<UUID>
    /// Shift is down: hits merge with `baseSelection` instead of replacing it.
    public var additive: Bool

    public init(start: CGPoint, baseSelection: Set<UUID> = [], additive: Bool = false) {
        self.start = start
        self.current = start
        self.baseSelection = baseSelection
        self.additive = additive
    }

    public var rect: CGRect {
        CanvasMarquee.rect(from: start, to: current)
    }

    public mutating func extend(to point: CGPoint) {
        current = point
    }

    /// Live selection while the drag runs. Recomputed from `baseSelection`, so
    /// growing and shrinking the rectangle is idempotent.
    public func selection(in frames: [NodeFrame]) -> Set<UUID> {
        CanvasMarquee.selection(rect, in: frames, from: baseSelection, additive: additive)
    }

    /// Escape: put back what was selected before the drag.
    public var cancelledSelection: Set<UUID> {
        baseSelection
    }
}

/// What the pointer came down on.
public enum CanvasPressTarget: Equatable, Sendable {
    /// Chrome that runs its own interaction: the edit field, a sticky's toolbar,
    /// a region's toolbar.
    case chrome
    /// A topic the placement model can move: a hierarchy root, or a free topic.
    case draggableNode
    /// Blank paper, or a tree child that is not draggable.
    case blank
}

/// What one press is allowed to start.
public enum CanvasDragIntent: Equatable, Sendable {
    case ignore
    case dragNode
    case marquee
    case pan
}

/// One press, one intent. Every branch that could steal the gesture is decided
/// here so the rule is testable without a window: chrome wins, then a draggable
/// topic, then the pointer mode. Editing and documents without stored positions
/// keep panning, which is how the canvas behaved before pointer modes existed.
public enum CanvasPointerRouter {
    public static func intent(
        target: CanvasPressTarget,
        mode: CanvasPointerMode,
        spaceHeld: Bool,
        isEditing: Bool,
        allowsPlacement: Bool
    ) -> CanvasDragIntent {
        if target == .chrome { return .ignore }
        // While text is being edited a drag outside the field is still a pan.
        // A marquee there would move the selection out from under the editor.
        if isEditing { return .pan }
        // Markdown stores no positions, so nothing on it can be dragged or
        // marquee-selected; the canvas keeps panning.
        guard allowsPlacement else { return .pan }
        if target == .draggableNode { return .dragNode }
        return mode.effective(spaceHeld: spaceHeld) == .pan ? .pan : .marquee
    }
}

/// What releasing Space does.
public enum CanvasSpaceReleaseAction: Equatable, Sendable {
    /// A tap: the plain Space shortcut, 编辑主题.
    case edit
    /// A hold, or a press that was spent panning. Do nothing.
    case none

    /// Below this, a press with no drag is a tap on the Space shortcut.
    public static let holdThresholdMilliseconds = 300

    /// The whole rule: a drag swallows the press, otherwise only a quick tap
    /// reaches 编辑主题.
    public static func at(heldMilliseconds: Int, didDrag: Bool) -> CanvasSpaceReleaseAction {
        if didDrag { return .none }
        return heldMilliseconds < holdThresholdMilliseconds ? .edit : .none
    }
}

/// What one Space key event did.
public enum CanvasSpaceKeyResult: Equatable, Sendable {
    /// First key down: the hand is on screen immediately, no threshold wait.
    case begin
    /// Auto-repeat while the key is already held. Not a new press, and the
    /// clock is not restarted.
    case repeatIgnored
    /// Key up, with the decision it made.
    case end(CanvasSpaceReleaseAction)
    /// Key up with no key down of ours: modifiers, focus loss, or a press that
    /// started inside the text editor.
    case strayUp
}

/// Tracks one Space hold.
///
/// Space is two gestures at once: holding it borrows the hand for panning, and
/// tapping it still means 编辑主题. So the key down answers immediately (cursor,
/// hand mode) and the key up decides. Auto-repeat is the same physical press and
/// must not restart the clock or look like a second tap.
public struct CanvasSpaceGesture: Equatable, Sendable {
    public private(set) var startedAt: TimeInterval?
    public private(set) var didDrag = false

    public var isDown: Bool { startedAt != nil }

    public init() {}

    public mutating func keyDown(at time: TimeInterval) -> CanvasSpaceKeyResult {
        guard startedAt == nil else { return .repeatIgnored }
        startedAt = time
        didDrag = false
        return .begin
    }

    /// A drag started while the key is held. That press is spent on panning, so
    /// releasing it must never fall through to 编辑主题.
    public mutating func noteDrag() {
        guard startedAt != nil else { return }
        didDrag = true
    }

    public mutating func keyUp(at time: TimeInterval) -> CanvasSpaceKeyResult {
        guard let start = startedAt else { return .strayUp }
        startedAt = nil
        let elapsed = time - start
        let milliseconds: Int
        if elapsed.isFinite {
            milliseconds = min(Int((max(elapsed, 0) * 1000).rounded()), 60_000)
        } else {
            milliseconds = 0
        }
        let action = CanvasSpaceReleaseAction.at(heldMilliseconds: milliseconds, didDrag: didDrag)
        didDrag = false
        return .end(action)
    }

    /// Focus left, the mode changed, or the canvas went away.
    public mutating func reset() {
        startedAt = nil
        didDrag = false
    }
}

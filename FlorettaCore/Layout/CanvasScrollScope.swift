import Foundation

/// One step of the Mac window's hit test, as the canvas scroll monitor sees it.
///
/// The overlay that listens for trackpad scrolls covers the whole canvas frame,
/// and the inspector column and the outline panel float above that frame. A
/// bounds check therefore cannot tell "pointer on the canvas" from "pointer on a
/// panel drawn over the canvas" — both points land inside the canvas rectangle,
/// which is how the canvas came to eat the inspector's scroll. The window's hit
/// test can tell them apart, but it needs AppKit. This type carries the single
/// fact that decides the gesture — did the hit chain pass through a scroll
/// view — so the decision itself stays AppKit-free and testable without a window.
public enum CanvasScrollHit: Equatable, Sendable {
    /// The chain passed through an `NSScrollView` below the canvas's container:
    /// an inspector `Form`, the outline `List`, a popover's `ScrollView`.
    /// Whatever it is, that container owns the gesture.
    case scrollView
    /// The walk reached the canvas without meeting a scroll container.
    case canvas
    /// A view that scrolls nothing and is not the canvas: chrome, a label, the
    /// glass plate and padding around a panel's list.
    case other
}

/// Who owns a trackpad scroll that lands over the Mac canvas.
public enum CanvasScrollScope {

    /// Whether the canvas consumes the scroll, or lets it through to whatever
    /// is under the pointer.
    ///
    /// A scroll container anywhere in the hit chain wins, even though the
    /// pointer is also inside the canvas rectangle: the event has to reach that
    /// container, so the canvas must not return nil for it. Otherwise the canvas
    /// claims the scroll, but only from inside its own bounds — an empty or
    /// non-canvas chain is not enough, because a panel's glass plate and padding
    /// hit views that scroll nothing while covering canvas pixels.
    public static func shouldConsume(hitChain: [CanvasScrollHit], pointInCanvas: Bool) -> Bool {
        guard pointInCanvas else { return false }
        return !hitChain.contains(.scrollView)
    }
}

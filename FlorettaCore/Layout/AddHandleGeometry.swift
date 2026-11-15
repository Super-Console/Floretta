import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry shared by the canvas add handles, the hover hit test, and the tests
/// that pin both.
///
/// A handle is drawn `spacing` outside the topic box. Reaching it means leaving
/// the box, so a hover test that only accepts the box itself clears
/// `hoveredNodeID` on the first step and the handle disappears before the pointer
/// gets to it. `hoverInflate` is that reach: it has to cover the handle centre
/// plus the drawn radius, otherwise the last pixels of the glyph are dead.
///
/// All values are view points, not canvas units. The canvas divides by the zoom
/// scale when it converts to canvas space.
public enum AddHandleGeometry {
    /// Handle centre, measured from the topic edge.
    public static let spacing: CGFloat = 18
    /// Side of the square a handle glyph is drawn in. The radius is half of this.
    public static let buttonSide: CGFloat = 20
    /// How far past the topic edge the pointer keeps the topic hovered.
    /// `spacing + buttonSide / 2` is 28, so the whole glyph stays inside the region.
    public static let hoverInflate: CGFloat = spacing + buttonSide / 2
    /// How long a miss is held before the hover clears. Long enough to step over
    /// the gap between two handles, short enough to read as "the pointer left".
    public static let hoverGraceMilliseconds: Int = 200

    /// Centre of one handle around `rect`, in whatever space `rect` is in.
    public static func handleCenter(_ direction: CanvasDirection, in rect: CGRect) -> CGPoint {
        switch direction {
        case .up: return CGPoint(x: rect.midX, y: rect.minY - spacing)
        case .down: return CGPoint(x: rect.midX, y: rect.maxY + spacing)
        case .left: return CGPoint(x: rect.minX - spacing, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX + spacing, y: rect.midY)
        }
    }

    /// Canvas-space reach for a view-space `hoverInflate` at `scale`.
    /// Guards a zero or inverted zoom so the region never collapses to nothing.
    public static func canvasInflate(scale: CGFloat) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return hoverInflate }
        return hoverInflate / scale
    }
}

/// Topic lookup for the pointer. Exact boxes win, then the near ring decides.
/// Kept in Core so the geometry is testable without a view.
public enum NodeHitRegion {
    /// Topmost topic whose box contains `point`. When no box does, the nearest
    /// topic whose box grown by `inflate` still contains it. A tie goes to the
    /// later frame, which is the one painted on top.
    public static func nodeID(
        at point: CGPoint,
        inflate: CGFloat,
        in frames: [NodeFrame]
    ) -> UUID? {
        nodeID(at: point, inflate: inflate, in: frames.map { ($0.id, $0.frame) })
    }

    /// Same rule over plain boxes. `rects` are in order, so a later box wins a tie.
    public static func nodeID(
        at point: CGPoint,
        inflate: CGFloat,
        in rects: [(id: UUID, rect: CGRect)]
    ) -> UUID? {
        var exact: UUID?
        for box in rects where box.rect.contains(point) {
            exact = box.id
        }
        if let exact { return exact }
        guard inflate > 0, inflate.isFinite else { return nil }
        var best: (id: UUID, distance: CGFloat)?
        for box in rects {
            let distance = distance(to: box.rect, from: point)
            guard distance <= inflate else { continue }
            // Equal distance keeps the later box: it is the one drawn on top.
            if let current = best, current.distance < distance { continue }
            best = (box.id, distance)
        }
        return best?.id
    }

    /// Zero inside `rect`, otherwise the straight-line gap to the nearest edge.
    public static func distance(to rect: CGRect, from point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

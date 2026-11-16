import XCTest
import FlorettaCore

/// The Mac canvas registers a window-level `scrollWheel` monitor, so it sees
/// every scroll in the window before the view under the pointer. Its overlay
/// covers the canvas frame, and the inspector column and outline panel float
/// above that frame, so a bounds check let the canvas eat the panel's scroll.
/// `CanvasScrollScope` is the decision it makes instead, kept pure so it runs
/// without a window or a real `NSScrollView`.
final class CanvasScrollScopeTests: XCTestCase {

    /// The pointer sits on the inspector's `Form`. The chain reaches the form's
    /// `NSScrollView`; the point is inside the canvas rectangle too, which is
    /// exactly the case that used to be swallowed.
    func testScrollOverAPanelScrollViewIsPassedThrough() {
        XCTAssertFalse(
            CanvasScrollScope.shouldConsume(
                hitChain: [.other, .scrollView, .other],
                pointInCanvas: true
            )
        )
    }

    /// Bare canvas: nothing between the pointer and the canvas scrolls, so the
    /// canvas pans and zooms on the trackpad as before.
    func testScrollOnTheCanvasItselfIsConsumed() {
        XCTAssertTrue(
            CanvasScrollScope.shouldConsume(hitChain: [.canvas], pointInCanvas: true)
        )
    }

    /// Neither the canvas nor a scroll view: the pointer is on window chrome
    /// outside the canvas frame. The canvas keeps its hands off.
    func testScrollOutsideTheCanvasAndOutsideAnyScrollViewIsPassedThrough() {
        XCTAssertFalse(
            CanvasScrollScope.shouldConsume(hitChain: [.other], pointInCanvas: false)
        )
    }
}

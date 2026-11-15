import CoreGraphics
import XCTest
import FlorettaCore

/// Pointer / hand modes on the Mac canvas: marquee geometry, the press router,
/// Space's double duty (borrowed hand vs 编辑主题), and the wiring the views
/// need so the decision is not duplicated in a gesture closure.
final class CanvasPointerModeTests: XCTestCase {

    // MARK: - marquee geometry

    func testMarqueeFullyContainingATopicSelectsIt() {
        let inside = UUID()
        let frames = [frame(id: inside, rect: CGRect(x: 20, y: 20, width: 60, height: 30))]
        let marquee = CGRect(x: 0, y: 0, width: 200, height: 120)

        XCTAssertEqual(CanvasMarquee.intersectingIDs(marquee, in: frames), [inside])
    }

    func testMarqueeCrossingOneEdgeSelectsTheTopic() {
        let crossing = UUID()
        // Marquee's right edge (100) cuts through a topic that starts at 80.
        let frames = [frame(id: crossing, rect: CGRect(x: 80, y: 10, width: 60, height: 30))]

        XCTAssertEqual(
            CanvasMarquee.intersectingIDs(CGRect(x: 0, y: 0, width: 100, height: 60), in: frames),
            [crossing]
        )
    }

    func testMarqueeThatDoesNotReachATopicSelectsNothing() {
        let far = UUID()
        let frames = [frame(id: far, rect: CGRect(x: 400, y: 400, width: 60, height: 30))]

        XCTAssertEqual(
            CanvasMarquee.intersectingIDs(CGRect(x: 0, y: 0, width: 100, height: 100), in: frames),
            []
        )
    }

    func testEmptyMarqueeSelectsNothing() {
        let frame = self.frame(id: UUID(), rect: CGRect(x: 0, y: 0, width: 60, height: 30))
        // A press that has not moved yet: same corner twice.
        let zero = CanvasMarquee.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10))
        XCTAssertEqual(zero.width, 0)
        XCTAssertEqual(zero.height, 0)
        XCTAssertEqual(CanvasMarquee.intersectingIDs(zero, in: [frame]), [])
        XCTAssertEqual(CanvasMarquee.intersectingIDs(.zero, in: [frame]), [])

        var state = CanvasMarqueeState(start: CGPoint(x: 10, y: 10))
        XCTAssertEqual(state.selection(in: [frame]), [])
        state.extend(to: CGPoint(x: 40, y: 40))
        XCTAssertEqual(state.selection(in: [frame]), [frame.id])
    }

    func testMarqueeNormalizesADragUpAndToTheLeft() {
        let id = UUID()
        let frames = [frame(id: id, rect: CGRect(x: 40, y: 40, width: 20, height: 20))]

        let rect = CanvasMarquee.rect(from: CGPoint(x: 120, y: 120), to: CGPoint(x: 10, y: 10))
        XCTAssertEqual(rect, CGRect(x: 10, y: 10, width: 110, height: 110))
        XCTAssertEqual(CanvasMarquee.intersectingIDs(rect, in: frames), [id])
    }

    func testShiftAddsTheMarqueeHitsToTheSelectionAlreadyThere() {
        let kept = UUID()
        let added = UUID()
        let frames = [
            frame(id: kept, rect: CGRect(x: 0, y: 0, width: 20, height: 20)),
            frame(id: added, rect: CGRect(x: 200, y: 0, width: 20, height: 20)),
        ]
        var state = CanvasMarqueeState(
            start: CGPoint(x: 190, y: -10),
            baseSelection: [kept],
            additive: true
        )
        state.extend(to: CGPoint(x: 240, y: 40))

        XCTAssertEqual(state.selection(in: frames), [kept, added])

        // Same rectangle without Shift replaces instead of merging.
        state.additive = false
        XCTAssertEqual(state.selection(in: frames), [added])
    }

    func testEscapeRestoresTheSelectionFromBeforeTheDrag() {
        let before = UUID()
        let swept = UUID()
        let frames = [
            frame(id: before, rect: CGRect(x: 0, y: 0, width: 20, height: 20)),
            frame(id: swept, rect: CGRect(x: 200, y: 0, width: 20, height: 20)),
        ]
        var state = CanvasMarqueeState(start: CGPoint(x: 190, y: -10), baseSelection: [before])
        state.extend(to: CGPoint(x: 240, y: 40))
        XCTAssertEqual(state.selection(in: frames), [swept])
        XCTAssertEqual(state.cancelledSelection, [before])
    }

    // MARK: - press router

    func testSelectModeBlankDragIsAMarqueeAndNeverAPan() {
        XCTAssertEqual(
            CanvasPointerRouter.intent(
                target: .blank,
                mode: .select,
                spaceHeld: false,
                isEditing: false,
                allowsPlacement: true
            ),
            .marquee
        )
    }

    func testPanModeBlankDragStillPans() {
        XCTAssertEqual(
            CanvasPointerRouter.intent(
                target: .blank,
                mode: .pan,
                spaceHeld: false,
                isEditing: false,
                allowsPlacement: true
            ),
            .pan
        )
    }

    func testDraggingATopicStillWorksInBothModes() {
        for mode in CanvasPointerMode.allCases {
            XCTAssertEqual(
                CanvasPointerRouter.intent(
                    target: .draggableNode,
                    mode: mode,
                    spaceHeld: false,
                    isEditing: false,
                    allowsPlacement: true
                ),
                .dragNode,
                "a topic drag belongs to the topic, not to the pointer mode"
            )
        }
    }

    func testEditingAndMarkdownKeepTheOldPan() {
        XCTAssertEqual(
            CanvasPointerRouter.intent(
                target: .blank,
                mode: .select,
                spaceHeld: false,
                isEditing: true,
                allowsPlacement: true
            ),
            .pan,
            "a drag outside the text field must not move the selection under the editor"
        )
        XCTAssertEqual(
            CanvasPointerRouter.intent(
                target: .draggableNode,
                mode: .select,
                spaceHeld: false,
                isEditing: false,
                allowsPlacement: false
            ),
            .pan,
            "markdown stores no positions, so it keeps panning"
        )
    }

    func testChromeKeepsItsOwnGestureInEveryMode() {
        for mode in CanvasPointerMode.allCases {
            XCTAssertEqual(
                CanvasPointerRouter.intent(
                    target: .chrome,
                    mode: mode,
                    spaceHeld: true,
                    isEditing: true,
                    allowsPlacement: true
                ),
                .ignore
            )
        }
    }

    func testHoldingSpaceBorrowsTheHandInSelectMode() {
        XCTAssertEqual(
            CanvasPointerRouter.intent(
                target: .blank,
                mode: .select,
                spaceHeld: true,
                isEditing: false,
                allowsPlacement: true
            ),
            .pan
        )
        XCTAssertEqual(CanvasPointerMode.select.effective(spaceHeld: false), .select)
        XCTAssertEqual(CanvasPointerMode.select.effective(spaceHeld: true), .pan)
        XCTAssertEqual(CanvasPointerMode.pan.effective(spaceHeld: false), .pan)
        XCTAssertEqual(CanvasPointerMode.pan.effective(spaceHeld: true), .pan)
    }

    // MARK: - the stored preference

    func testTheMacOpensAsAPointerAndTouchKeepsPanning() {
        #if os(macOS)
        XCTAssertEqual(CanvasPointerMode.platformDefault, .select)
        #else
        XCTAssertEqual(CanvasPointerMode.platformDefault, .pan)
        #endif
        XCTAssertEqual(CanvasPointerMode.allCases, [.select, .pan])
    }

    func testStoredModeRoundTripsAndFallsBackToThePlatformDefault() {
        XCTAssertEqual(CanvasPointerMode.stored("select"), .select)
        XCTAssertEqual(CanvasPointerMode.stored("pan"), .pan)
        XCTAssertEqual(CanvasPointerMode.stored(nil), .select)
        XCTAssertEqual(CanvasPointerMode.stored(""), .select)
        XCTAssertEqual(CanvasPointerMode.stored("hand"), .select)
        XCTAssertEqual(CanvasPointerMode(rawValue: CanvasPointerMode.pan.rawValue), .pan)
    }

    func testTheToggleFlipsBetweenTheTwoModes() {
        XCTAssertEqual(CanvasPointerMode.select.toggled, .pan)
        XCTAssertEqual(CanvasPointerMode.pan.toggled, .select)
        XCTAssertEqual(CanvasPointerMode.select.toggled.toggled, .select)
    }

    func testTheToggleDrawsTheHandAndTheArrow() {
        XCTAssertEqual(CanvasPointerMode.pan.symbolName, "hand.raised")
        XCTAssertEqual(CanvasPointerMode.select.symbolName, "cursorarrow")
    }

    func testThePreferenceIsPersistedUnderItsOwnKey() throws {
        let settings = try repoFile("Floretta/Shared/Shell/AppSettings.swift")
        XCTAssertTrue(settings.contains("var pointerMode: CanvasPointerMode"))
        XCTAssertTrue(settings.contains("defaults.set(pointerMode.rawValue, forKey: Key.pointerMode)"))
        XCTAssertTrue(settings.contains("static let pointerMode = \"floretta.pointerMode\""))
        XCTAssertTrue(settings.contains("CanvasPointerMode.stored(defaults.string(forKey: Key.pointerMode))"))
    }

    // MARK: - Space: borrowed hand vs 编辑主题

    func testAShortSpaceTapWithoutADragStillEditsTheTopic() {
        var gesture = CanvasSpaceGesture()
        XCTAssertEqual(gesture.keyDown(at: 100), .begin)
        XCTAssertTrue(gesture.isDown, "the hand is on screen before any threshold")
        XCTAssertEqual(gesture.keyUp(at: 100.12), .end(.edit))
        XCTAssertFalse(gesture.isDown)
    }

    func testAHeldSpaceWithoutADragDoesNothing() {
        var gesture = CanvasSpaceGesture()
        XCTAssertEqual(gesture.keyDown(at: 100), .begin)
        XCTAssertEqual(gesture.keyUp(at: 100.9), .end(.none))
    }

    func testASpaceTapSpentPanningNeverOpensTheEditor() {
        var gesture = CanvasSpaceGesture()
        XCTAssertEqual(gesture.keyDown(at: 100), .begin)
        gesture.noteDrag()
        XCTAssertEqual(gesture.keyUp(at: 100.05), .end(.none))
    }

    func testAHeldSpaceSpentPanningNeverOpensTheEditor() {
        var gesture = CanvasSpaceGesture()
        XCTAssertEqual(gesture.keyDown(at: 100), .begin)
        gesture.noteDrag()
        XCTAssertEqual(gesture.keyUp(at: 102.5), .end(.none))
    }

    func testAutoRepeatIsIgnoredAndDoesNotRestartTheClock() {
        var gesture = CanvasSpaceGesture()
        XCTAssertEqual(gesture.keyDown(at: 100), .begin)
        // Hold: the OS repeats key down every ~30 ms.
        for tick in stride(from: 100.03, through: 100.27, by: 0.03) {
            XCTAssertEqual(gesture.keyDown(at: tick), .repeatIgnored)
        }
        // The repeat must not reset the clock: 320 ms after the first press is a
        // hold, not a 50 ms tap.
        XCTAssertEqual(gesture.keyUp(at: 100.32), .end(.none))
    }

    func testTheThresholdIsTheOnlyDifferenceBetweenTapAndHold() {
        XCTAssertEqual(CanvasSpaceReleaseAction.at(heldMilliseconds: 0, didDrag: false), .edit)
        XCTAssertEqual(CanvasSpaceReleaseAction.at(heldMilliseconds: 299, didDrag: false), .edit)
        XCTAssertEqual(CanvasSpaceReleaseAction.at(heldMilliseconds: 300, didDrag: false), .none)
        XCTAssertEqual(CanvasSpaceReleaseAction.at(heldMilliseconds: 299, didDrag: true), .none)
        XCTAssertEqual(CanvasSpaceReleaseAction.at(heldMilliseconds: 5_000, didDrag: true), .none)
        XCTAssertEqual(CanvasSpaceReleaseAction.holdThresholdMilliseconds, 300)
    }

    func testAnUntrackedKeyUpIsNotOurs() {
        var gesture = CanvasSpaceGesture()
        XCTAssertEqual(gesture.keyUp(at: 50), .strayUp)
        XCTAssertEqual(gesture.keyDown(at: 60), .begin)
        gesture.reset()
        XCTAssertEqual(gesture.keyUp(at: 61), .strayUp)
    }

    func testANoteDragWithoutAHoldIsIgnored() {
        var gesture = CanvasSpaceGesture()
        gesture.noteDrag()
        XCTAssertFalse(gesture.isDown)
        XCTAssertFalse(gesture.didDrag)
    }

    // MARK: - wiring

    /// The gesture closure routes the press instead of deciding again, so the
    /// rules tested above are the rules the canvas runs.
    func testTheCanvasRoutesPressesThroughThePointerRouter() throws {
        let canvas = try repoFile("Floretta/Shared/Canvas/InfiniteCanvas.swift")
        XCTAssertTrue(canvas.contains("CanvasPointerRouter.intent("))
        XCTAssertTrue(canvas.contains("case .marquee:"))
        XCTAssertTrue(canvas.contains("case .pan:"))
        XCTAssertTrue(canvas.contains("CanvasMarqueeState("))
        XCTAssertTrue(canvas.contains("state.selection(in: placedFrames())"))
        XCTAssertTrue(canvas.contains("cancelMarquee()"))
        XCTAssertTrue(canvas.contains("CanvasSpaceGesture()"))
        XCTAssertTrue(canvas.contains("spaceGesture.noteDrag()"))
        // The marquee is a hint, not a plate: 1 pt accent outline, 8% fill.
        XCTAssertTrue(canvas.contains("Color.accentColor.opacity(0.08)"))
        XCTAssertTrue(canvas.contains("lineWidth: 1"))
    }

    /// iOS is untouched: no marquee, no pointer work, the old pan drag stays.
    func testIOSKeepsThePanDragItShippedWith() throws {
        let canvas = try repoFile("Floretta/Shared/Canvas/InfiniteCanvas.swift")
        let routing = try slice(
            canvas,
            from: "private var pointerRoutingMode",
            until: "private var shiftIsDown"
        )
        XCTAssertTrue(routing.contains("#if os(macOS)"))
        XCTAssertTrue(routing.contains("return pointerMode"))
        XCTAssertTrue(routing.contains("return .pan"))
        XCTAssertTrue(routing.contains("effective(spaceHeld: spaceHeld)"))
    }

    func testTheStatusCapsuleCarriesTheMacPointerToggle() throws {
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        XCTAssertTrue(bar.contains("@Binding var pointerMode: CanvasPointerMode"))
        XCTAssertTrue(bar.contains("#if os(macOS)"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.pointer\")"))
        XCTAssertTrue(bar.contains("pointerMode.toggled"))
        XCTAssertTrue(bar.contains("pointerMode.symbolName"))
        XCTAssertTrue(bar.contains(".help(Text(verbatim: pointerModeActionLabel))"))
        XCTAssertTrue(bar.contains(".accessibilityLabel(Text(verbatim: pointerModeActionLabel))"))
        XCTAssertTrue(editor.contains("pointerMode: $settings.pointerMode"))
        XCTAssertTrue(editor.contains("pointerMode: settings.pointerMode"))
    }

    // MARK: - fixtures

    private func frame(id: UUID, rect: CGRect) -> NodeFrame {
        NodeFrame(
            id: id,
            text: "框",
            origin: rect.origin,
            size: rect.size,
            depth: 1,
            fontSize: 16,
            isRoot: false,
            fill: .white,
            border: .black,
            textColor: .black,
            cornerRadius: 8
        )
    }

    private func repoFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func slice(_ source: String, from startMark: String, until endMark: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMark))
        let rest = source[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: endMark))
        return String(rest[..<end.lowerBound])
    }
}

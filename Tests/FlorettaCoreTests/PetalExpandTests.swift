import FlorettaCore
import XCTest

final class PetalExpandTests: XCTestCase {
    func testEaseOutBackIsTheDocumentedCurve() {
        XCTAssertEqual(PetalEasing.name, "easeOutBack")
        XCTAssertEqual(PetalEasing.easeOutBack(0), 0, accuracy: 0.000_001)
        XCTAssertEqual(PetalEasing.easeOutBack(1), 1, accuracy: 0.000_001)
        XCTAssertEqual(PetalEasing.easeOutBack(0.5), 1.087_697_5, accuracy: 0.000_1)
        XCTAssertGreaterThan(PetalEasing.easeOutBack(0.58), 1)
        XCTAssertGreaterThan(abs(PetalEasing.easeOutBack(0.25) - 0.25), 0.05)
        XCTAssertLessThan(PetalEasing.easeOutBack(0.58), PetalExpandTiming.maxGrowth)
    }

    func testMapOpenEndsOnTheLayoutAndGrowsAlongTheRay() throws {
        let (document, rootID, childID, _) = sampleTree()
        var passes = 0
        let frames = LayoutEngine().layout(document)
        passes += 1
        var director = PetalExpandDirector(reduceMotion: false)
        director.openMap(frames: frames, now: 0, layoutPassCount: passes)
        XCTAssertEqual(director.kind, .mapOpen)
        XCTAssertTrue(director.isPlaying)
        XCTAssertEqual(director.easingName, "easeOutBack")
        XCTAssertGreaterThan(director.duration, 0)
        XCTAssertLessThan(director.duration, 0.6)

        let root = try XCTUnwrap(frames.first { $0.id == rootID })
        let bud = director.pose(for: root.id, at: 0)
        XCTAssertEqual(bud?.scale ?? 0, CGFloat(PetalExpandTiming.budScale), accuracy: 0.001)
        XCTAssertEqual(bud?.center.x ?? -1, root.frame.midX, accuracy: 0.001)
        XCTAssertEqual(bud?.center.y ?? -1, root.frame.midY, accuracy: 0.001)
        XCTAssertEqual(bud?.cornerCircle ?? 0, 1, accuracy: 0.001)

        let child = try XCTUnwrap(frames.first { $0.id == childID })
        let earlyChild = director.pose(for: childID, at: 0)
        XCTAssertEqual(earlyChild?.draws, false)

        let elapsed = PetalExpandTiming.stepDelay + PetalExpandTiming.petalDuration * 0.4
        let growing = try XCTUnwrap(director.pose(for: childID, at: elapsed))
        XCTAssertGreaterThan(abs(growing.growth - 0.4), 0.05)
        assertOnRay(pose: growing, final: child)
        XCTAssertGreaterThan(distance(growing.center, growing.origin), 1)
        XCTAssertLessThan(
            distance(growing.center, growing.origin),
            distance(CGPoint(x: child.frame.midX, y: child.frame.midY), growing.origin) * PetalExpandTiming.maxGrowth + 0.1
        )

        XCTAssertFalse(director.isActive(at: director.duration))
        for frame in frames {
            XCTAssertEqual(director.presentationRect(of: frame, at: director.duration), frame.frame)
        }
        XCTAssertEqual(sampleLayoutPasses(director: &director, frames: frames, passes: &passes), 0)
        XCTAssertEqual(passes, 1)
        XCTAssertFalse(director.layoutBudgetExceeded)
    }

    func testReduceMotionSkipsToTheLayout() {
        let (document, _, _, _) = sampleTree()
        let frames = LayoutEngine().layout(document)
        var director = PetalExpandDirector(reduceMotion: true)
        director.openMap(frames: frames, now: 0, layoutPassCount: 1)
        XCTAssertFalse(director.isPlaying)
        XCTAssertEqual(director.duration, 0)
        XCTAssertNil(director.kind)
        for frame in frames {
            XCTAssertEqual(director.presentationRect(of: frame, at: 0), frame.frame)
        }

        var playing = PetalExpandDirector(reduceMotion: false)
        playing.openMap(frames: frames, now: 0, layoutPassCount: 1)
        XCTAssertTrue(playing.isPlaying)
        playing.setReduceMotion(true)
        XCTAssertFalse(playing.isPlaying)
        for frame in frames {
            XCTAssertEqual(playing.presentationRect(of: frame, at: 0.05), frame.frame)
        }
    }

    func testExpandAndCollapseFinishOnTheLayout() throws {
        let (open, _, childID, grandID) = sampleTree()
        var folded = open
        folded.mutateNode(childID) { $0.isCollapsed = true }
        let openFrames = LayoutEngine().layout(open)
        let foldedFrames = LayoutEngine().layout(folded)
        XCTAssertNil(foldedFrames.first { $0.id == grandID })
        XCTAssertNotNil(openFrames.first { $0.id == grandID })

        var expand = PetalExpandDirector(reduceMotion: false)
        expand.noteDocumentChange(
            from: CollapseFingerprint.capture(folded),
            to: CollapseFingerprint.capture(open),
            previousFrames: foldedFrames,
            finalFrames: openFrames,
            now: 0,
            layoutPassCount: 1
        )
        XCTAssertEqual(expand.kind, .expand(childID))
        let child = try XCTUnwrap(openFrames.first { $0.id == childID })
        let petal = try XCTUnwrap(expand.pose(for: grandID, at: 0.02))
        XCTAssertEqual(petal.origin.x, child.frame.midX, accuracy: 0.01)
        XCTAssertEqual(petal.origin.y, child.frame.midY, accuracy: 0.01)
        XCTAssertTrue(petal.draws)
        let grand = try XCTUnwrap(openFrames.first { $0.id == grandID })
        assertOnRay(pose: petal, final: grand)
        for frame in openFrames {
            XCTAssertEqual(expand.presentationRect(of: frame, at: expand.duration), frame.frame)
        }

        var collapse = PetalExpandDirector(reduceMotion: false)
        collapse.noteDocumentChange(
            from: CollapseFingerprint.capture(open),
            to: CollapseFingerprint.capture(folded),
            previousFrames: openFrames,
            finalFrames: foldedFrames,
            now: 0,
            layoutPassCount: 1
        )
        XCTAssertEqual(collapse.kind, .collapse(childID))
        let ghosts = collapse.ghosts(at: 0.001)
        XCTAssertEqual(ghosts.map(\.frame.id), [grandID])
        for frame in foldedFrames {
            XCTAssertEqual(collapse.presentationRect(of: frame, at: 0.05), frame.frame)
            XCTAssertEqual(collapse.presentationRect(of: frame, at: collapse.duration), frame.frame)
        }
        XCTAssertTrue(collapse.ghosts(at: collapse.duration).isEmpty)
    }

    func testReduceMotionCollapseIsInstant() {
        let (open, _, childID, grandID) = sampleTree()
        var folded = open
        folded.mutateNode(childID) { $0.isCollapsed = true }
        let openFrames = LayoutEngine().layout(open)
        let foldedFrames = LayoutEngine().layout(folded)
        var director = PetalExpandDirector(reduceMotion: true)
        director.noteDocumentChange(
            from: CollapseFingerprint.capture(open),
            to: CollapseFingerprint.capture(folded),
            previousFrames: openFrames,
            finalFrames: foldedFrames,
            now: 0,
            layoutPassCount: 1
        )
        XCTAssertFalse(director.isPlaying)
        XCTAssertTrue(director.ghosts(at: 0).isEmpty)
        XCTAssertNil(foldedFrames.first { $0.id == grandID })
        for frame in foldedFrames {
            XCTAssertEqual(director.presentationRect(of: frame, at: 0), frame.frame)
        }
    }

    func testTextDragAndInsertDoNotAttachTheEasing() {
        let (document, rootID, childID, _) = sampleTree()
        let frames = LayoutEngine().layout(document)
        let before = CollapseFingerprint.capture(document)

        var typed = document
        typed.mutateNode(rootID) { $0.text = "键入" }
        XCTAssertEqual(CollapseFingerprint.delta(from: before, to: CollapseFingerprint.capture(typed)), .none)
        var director = PetalExpandDirector(reduceMotion: false)
        director.noteDocumentChange(
            from: before,
            to: CollapseFingerprint.capture(typed),
            previousFrames: frames,
            finalFrames: LayoutEngine().layout(typed),
            now: 0,
            layoutPassCount: 1
        )
        XCTAssertFalse(director.isPlaying)
        XCTAssertNil(director.kind)
        XCTAssertEqual(director.duration, 0)

        director.openMap(frames: frames, now: 0, layoutPassCount: 1)
        XCTAssertTrue(director.isPlaying)
        director.noteDocumentChange(
            from: before,
            to: CollapseFingerprint.capture(typed),
            previousFrames: frames,
            finalFrames: LayoutEngine().layout(typed),
            now: 0.05,
            layoutPassCount: 2
        )
        XCTAssertFalse(director.isPlaying)
        XCTAssertEqual(director.peakConcurrent, 1)

        var dragged = document
        dragged.mutateNode(rootID) { $0.position = MindMapPoint(x: 40, y: 12) }
        XCTAssertEqual(CollapseFingerprint.delta(from: before, to: CollapseFingerprint.capture(dragged)), .none)

        var inserted = document
        _ = inserted.mutateNode(childID) { $0.children.append(MindMapNode(text: "新")) }
        XCTAssertEqual(CollapseFingerprint.delta(from: before, to: CollapseFingerprint.capture(inserted)), .unrelated)
        var idle = PetalExpandDirector(reduceMotion: false)
        idle.noteDocumentChange(
            from: before,
            to: CollapseFingerprint.capture(inserted),
            previousFrames: frames,
            finalFrames: LayoutEngine().layout(inserted),
            now: 0,
            layoutPassCount: 1
        )
        XCTAssertFalse(idle.isPlaying)
    }

    func testASecondTransitionReplacesTheFirst() {
        let (open, _, childID, _) = sampleTree()
        var folded = open
        folded.mutateNode(childID) { $0.isCollapsed = true }
        let openFrames = LayoutEngine().layout(open)
        let foldedFrames = LayoutEngine().layout(folded)
        var director = PetalExpandDirector(reduceMotion: false)
        director.openMap(frames: openFrames, now: 0, layoutPassCount: 1)
        XCTAssertEqual(director.kind, .mapOpen)
        director.noteDocumentChange(
            from: CollapseFingerprint.capture(folded),
            to: CollapseFingerprint.capture(open),
            previousFrames: foldedFrames,
            finalFrames: openFrames,
            now: 0.05,
            layoutPassCount: 2
        )
        XCTAssertEqual(director.kind, .expand(childID))
        XCTAssertEqual(director.peakConcurrent, 1)
        XCTAssertLessThanOrEqual(director.peakConcurrent, PetalExpandTiming.maxConcurrent)
        XCTAssertTrue(director.isPlaying)
    }

    func testWideExpandHidesTheTailUntilTheLayout() throws {
        let children = (0..<60).map { MindMapNode(text: "枝\($0)") }
        let document = MindMapDocument(title: "wide", roots: [MindMapNode(text: "根", children: children)])
        let frames = LayoutEngine().layout(document)
        var director = PetalExpandDirector(reduceMotion: false)
        director.openMap(frames: frames, now: 0, layoutPassCount: 1)
        XCTAssertEqual(director.animatedCount, PetalExpandTiming.maxAnimated)
        XCTAssertEqual(director.hiddenCount, frames.count - PetalExpandTiming.maxAnimated)
        let hidden = try XCTUnwrap(frames.first { director.pose(for: $0.id, at: 0.1)?.draws == false })
        XCTAssertEqual(director.presentationRect(of: hidden, at: director.duration), hidden.frame)
    }

    func testExtraLayoutPassesDuringPlaybackAreVisible() {
        let (document, _, _, _) = sampleTree()
        let frames = LayoutEngine().layout(document)
        var director = PetalExpandDirector(reduceMotion: false)
        var passes = 1
        director.openMap(frames: frames, now: 0, layoutPassCount: passes)
        for _ in 0..<4 {
            passes += 1
            let extra = director.layoutExtra(comparedTo: passes)
            if extra != director.layoutPassesDuringPlayback {
                director.noteLayoutExtra(extra)
            }
        }
        XCTAssertEqual(director.layoutPassesDuringPlayback, 4)
        XCTAssertTrue(director.layoutBudgetExceeded)
        XCTAssertEqual(PetalExpandTiming.maxLayoutPassesDuringPlayback, 0)
    }

    func testPoseSamplesStayInsideTheFrameBudget() {
        let document = bushyTree()
        var passes = 0
        let frames = LayoutEngine().layout(document)
        passes += 1
        var director = PetalExpandDirector(reduceMotion: false)
        director.openMap(frames: frames, now: 0, layoutPassCount: passes)
        let cost = director.measurePoseCost(frames: frames, samples: 60)
        XCTAssertEqual(sampleLayoutPasses(director: &director, frames: frames, passes: &passes), 0)
        XCTAssertEqual(passes, 1)
        XCTAssertGreaterThan(cost.checksum, 0)
        XCTAssertLessThan(TimeInterval(cost.nanosecondsPerFrame) / 1_000_000_000, PetalExpandTiming.frameBudget)
        print(
            "PETAL_MEASURE duration_s=\(cost.duration) layout_passes_during_playback=\(director.layoutPassesDuringPlayback) samples=\(cost.samples) nodes=\(cost.nodes) animated=\(director.animatedCount) pose_ns_per_frame=\(cost.nanosecondsPerFrame) easing=\(cost.easing) checksum=\(cost.checksum) frame_budget_s=\(PetalExpandTiming.frameBudget)"
        )
    }

    func testSwappingTheWholeMapOpensInsteadOfEditing() {
        let (first, _, _, _) = sampleTree()
        let second = MindMapDocument(title: "other", roots: [MindMapNode(text: "另一张")])
        XCTAssertEqual(
            CollapseFingerprint.delta(from: CollapseFingerprint.capture(first), to: CollapseFingerprint.capture(second)),
            .mapOpen
        )
    }

    private func sampleLayoutPasses(
        director: inout PetalExpandDirector,
        frames: [NodeFrame],
        passes: inout Int
    ) -> Int {
        let steps = 60
        for step in 0..<steps {
            let time = director.duration * Double(step) / Double(steps)
            for frame in frames {
                _ = director.presentationRect(of: frame, at: time)
                if let link = frame.link, let pose = director.pose(for: frame.id, at: time) {
                    _ = PetalExpandGeometry.grow(link, from: pose.origin, growth: pose.growth)
                }
            }
            let extra = director.layoutExtra(comparedTo: passes)
            if extra != director.layoutPassesDuringPlayback {
                director.noteLayoutExtra(extra)
            }
        }
        return director.layoutPassesDuringPlayback
    }

    private func assertOnRay(pose: PetalPose, final: NodeFrame, file: StaticString = #filePath, line: UInt = #line) {
        let alongX = final.frame.midX - pose.origin.x
        let alongY = final.frame.midY - pose.origin.y
        let poseX = pose.center.x - pose.origin.x
        let poseY = pose.center.y - pose.origin.y
        XCTAssertEqual(alongX * poseY - alongY * poseX, 0, accuracy: 0.01, file: file, line: line)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func sampleTree() -> (MindMapDocument, UUID, UUID, UUID) {
        let rootID = UUID()
        let childID = UUID()
        let grandID = UUID()
        let otherID = UUID()
        let root = MindMapNode(
            id: rootID,
            text: "根",
            children: [
                MindMapNode(id: childID, text: "甲", children: [MindMapNode(id: grandID, text: "孙")]),
                MindMapNode(id: otherID, text: "乙"),
            ]
        )
        return (MindMapDocument(title: "petal", roots: [root]), rootID, childID, grandID)
    }

    private func bushyTree() -> MindMapDocument {
        let children = (0..<8).map { index in
            MindMapNode(
                text: "枝\(index)",
                children: (0..<4).map { MindMapNode(text: "叶\(index)-\($0)") }
            )
        }
        return MindMapDocument(title: "bush", roots: [MindMapNode(text: "根", children: children)])
    }
}

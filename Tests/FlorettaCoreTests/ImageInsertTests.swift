import FlorettaCore
import XCTest

final class ImageInsertTests: XCTestCase {
    func testThreeEntriesShareOneImageProposal() {
        XCTAssertEqual(ImageInsertEntry.allCases.count, 3)
        XCTAssertEqual(
            Set(ImageInsertEntry.allCases.map(\.rawValue)),
            ["filePicker", "dragDrop", "clipboardPaste"]
        )
        let proposals = ImageInsertEntry.allCases.map { entry in
            ImageInsertRoute.proposal(
                ImageInsertPayload(entry: entry, filename: "Photo.PNG", byteCount: 4096),
                currentDocumentByteCount: 100
            )
        }
        XCTAssertEqual(proposals[0], proposals[1])
        XCTAssertEqual(proposals[1], proposals[2])
        XCTAssertEqual(proposals[0]?.fileExtension, "png")
        XCTAssertEqual(proposals[0]?.fileByteCount, 4096)
        XCTAssertTrue(ImageInsertRoute.accepts(filename: "shot.JPEG"))
        XCTAssertNil(
            ImageInsertRoute.proposal(
                ImageInsertPayload(entry: .dragDrop, filename: "archive.dmg", byteCount: 10),
                currentDocumentByteCount: 0
            )
        )
        XCTAssertNil(
            ImageInsertRoute.proposal(
                ImageInsertPayload(entry: .clipboardPaste, filename: "notes.txt", byteCount: 4),
                currentDocumentByteCount: 0
            )
        )
    }

    func testPreferredExtensionKeepsTheImageType() {
        XCTAssertEqual(ImageFileName.preferredExtension(pathExtension: "JPG", typeExtension: "png"), "jpg")
        XCTAssertEqual(ImageFileName.preferredExtension(pathExtension: "", typeExtension: "heic"), "heic")
        XCTAssertEqual(ImageFileName.preferredExtension(pathExtension: "bin", typeExtension: nil), "png")
    }

    func testAspectFitLetterboxesWithoutCropping() {
        let slot = ImageSlotRect(x: 10, y: 4, width: 160, height: 96)
        let wide = ImageAspectFit.fit(pixels: ImagePixelSize(width: 400, height: 200), in: slot)
        XCTAssertEqual(wide.width, 160, accuracy: 0.001)
        XCTAssertEqual(wide.height, 80, accuracy: 0.001)
        XCTAssertEqual(wide.x, 10, accuracy: 0.001)
        XCTAssertEqual(wide.y, 4 + 8, accuracy: 0.001)
        XCTAssertLessThanOrEqual(wide.width, slot.width + 0.001)
        XCTAssertLessThanOrEqual(wide.height, slot.height + 0.001)
        XCTAssertEqual(wide.width / wide.height, 2, accuracy: 0.001)

        let tall = ImageAspectFit.fit(pixels: ImagePixelSize(width: 100, height: 400), in: slot)
        XCTAssertEqual(tall.height, 96, accuracy: 0.001)
        XCTAssertEqual(tall.width, 24, accuracy: 0.001)
        XCTAssertGreaterThan(tall.x, slot.x)
        XCTAssertEqual(tall.width / tall.height, 0.25, accuracy: 0.001)

        let square = ImageAspectFit.fit(pixels: ImagePixelSize(width: 50, height: 50), in: slot)
        XCTAssertEqual(square.height, 96, accuracy: 0.001)
        XCTAssertEqual(square.width, 96, accuracy: 0.001)

        let empty = ImageAspectFit.fit(pixels: ImagePixelSize(width: 0, height: 10), in: slot)
        XCTAssertTrue(empty.isEmpty)
    }

    func testExportEdgeIsThePageSizeAndNotTheThumbnail() {
        let slot = ImageSlot.slot(nodeWidth: 176)
        XCTAssertEqual(slot.width, ImageSlot.maxWidth, accuracy: 0.001)
        let wide = ImagePixelSize(width: 4000, height: 2000)
        let edge = ImageExportResolution.longestEdge(source: wide, slot: slot, scale: 2)
        let fitted = ImageAspectFit.fit(pixels: wide, in: slot)
        XCTAssertEqual(edge, Int((fitted.longestEdge * 2).rounded(.up)))
        XCTAssertGreaterThan(edge, StreamingBudget.thumbnailLongestEdge)
        XCTAssertLessThan(edge, wide.longestEdge)

        let tiny = ImageExportResolution.longestEdge(
            source: ImagePixelSize(width: 80, height: 40),
            slot: slot,
            scale: 3
        )
        XCTAssertEqual(tiny, 80)

        let unknown = ImageExportResolution.longestEdge(
            source: ImagePixelSize(width: 0, height: 0),
            slot: slot,
            scale: 2
        )
        XCTAssertEqual(unknown, Int((slot.longestEdge * 2).rounded(.up)))
        XCTAssertLessThanOrEqual(unknown, 4096)
    }

    func testLayoutReservesTheImageSlotOnlyForPictures() throws {
        let hash = String(repeating: "a", count: 64)
        let image = MindMapDocument(
            title: "i",
            roots: [MindMapNode(
                text: "图",
                attachments: [NodeAttachment(sha256: hash, fileExtension: "png", byteCount: 4, filename: "a.png")]
            )]
        )
        let audio = MindMapDocument(
            title: "a",
            roots: [MindMapNode(
                text: "图",
                attachments: [NodeAttachment(
                    sha256: String(repeating: "b", count: 64),
                    fileExtension: "mp3",
                    byteCount: 4,
                    filename: "a.mp3"
                )]
            )]
        )
        let plain = MindMapDocument(title: "p", roots: [MindMapNode(text: "图")])
        let imageFrame = try XCTUnwrap(LayoutEngine().layout(image).first)
        let audioFrame = try XCTUnwrap(LayoutEngine().layout(audio).first)
        let plainFrame = try XCTUnwrap(LayoutEngine().layout(plain).first)
        XCTAssertEqual(imageFrame.thumbnailHashes, [hash])
        XCTAssertTrue(audioFrame.thumbnailHashes.isEmpty)
        XCTAssertTrue(plainFrame.thumbnailHashes.isEmpty)
        XCTAssertGreaterThanOrEqual(imageFrame.size.height - plainFrame.size.height, ImageSlot.bandHeight(hasImage: true))
        XCTAssertGreaterThan(imageFrame.size.height, audioFrame.size.height)
        XCTAssertGreaterThanOrEqual(imageFrame.size.width, ImageSlot.maxWidth + ImageSlot.horizontalInset * 2)
        let fitted = ImageAspectFit.fit(
            pixels: ImagePixelSize(width: 200, height: 100),
            in: ImageSlot.slot(nodeWidth: Double(imageFrame.size.width))
        )
        XCTAssertFalse(fitted.isEmpty)
        XCTAssertLessThanOrEqual(fitted.width, ImageSlot.maxWidth + 0.001)
        XCTAssertLessThanOrEqual(fitted.height, ImageSlot.maxHeight + 0.001)
        XCTAssertEqual(fitted.width / fitted.height, 2, accuracy: 0.001)
    }

    func testSchedulerDoesNotRunDecodeOnTheCaller() {
        let flag = DecodeFlag()
        let runner = BlockingRunner()
        ImageDecodeScheduler.submit(runner: runner.call) {
            flag.mark()
        }
        XCTAssertFalse(flag.value)
        XCTAssertEqual(runner.count, 1)
        runner.drain()
        XCTAssertTrue(flag.value)
    }

    func testDetachedDecodeLeavesTheCallerThread() {
        let probe = ThreadProbe()
        let done = expectation(description: "decode lane")
        ImageDecodeScheduler.submit(runner: ImageDecodeLane.detached) {
            probe.record()
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertFalse(probe.sameThread)
        XCTAssertFalse(probe.ranOnMain)
    }
}

private final class ThreadProbe: @unchecked Sendable {
    private let caller: Thread
    private let lock = NSLock()
    private var same = true
    private var main = true

    init() {
        caller = Thread.current
    }

    func record() {
        let same = Thread.current == caller
        let main = Thread.isMainThread
        lock.lock()
        self.same = same
        self.main = main
        lock.unlock()
    }

    var sameThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return same
    }

    var ranOnMain: Bool {
        lock.lock()
        defer { lock.unlock() }
        return main
    }
}

private final class DecodeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false
    private(set) var sameThread = true
    private(set) var main = true

    func mark() {
        lock.lock()
        marked = true
        lock.unlock()
    }

    func record(sameThread: Bool, main: Bool) {
        lock.lock()
        marked = true
        self.sameThread = sameThread
        self.main = main
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return marked
    }
}

private final class BlockingRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [@Sendable () -> Void] = []

    func call(_ body: @escaping @Sendable () -> Void) {
        lock.lock()
        bodies.append(body)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return bodies.count
    }

    func drain() {
        lock.lock()
        let copy = bodies
        bodies.removeAll()
        lock.unlock()
        for body in copy { body() }
    }
}

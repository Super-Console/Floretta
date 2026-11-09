import XCTest

final class AutosaveTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories.removeAll()
        super.tearDown()
    }

    func testAutosaveCopyIsWrittenAtomically() throws {
        let store = try makeStore()
        let document = sampleDocument(title: "第一稿")
        try store.write(document)

        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        XCTAssertEqual(Set(names), [AutosaveStore.recoveryFileName])
        switch store.loadRecoveryCopy() {
        case .success(let loaded):
            XCTAssertEqual(loaded, document)
        case .failure(let failure):
            XCTFail("expected a readable copy, got \(failure)")
        }

        let revised = sampleDocument(title: "第二稿")
        try store.write(revised)
        let namesAfterReplace = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        XCTAssertEqual(Set(namesAfterReplace), [AutosaveStore.recoveryFileName])
        guard case .success(let replaced) = store.loadRecoveryCopy() else {
            return XCTFail("replaced copy did not load")
        }
        XCTAssertEqual(replaced, revised)
    }

    func testNormalCleanupRemovesTheCopy() throws {
        let store = try makeStore()
        try store.write(sampleDocument(title: "待清理"))
        try store.removeRecoveryCopy()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.recoveryURL.path))
        guard case .failure(.noCopy) = store.loadRecoveryCopy() else {
            return XCTFail("cleanup left a recoverable copy")
        }
    }

    func testAbnormalExitLeavesACopyTheNextStartCanRead() throws {
        let directory = try makeDirectory()
        let firstProcess = AutosaveStore(directory: directory)
        let document = sampleDocument(title: "崩溃前")
        try firstProcess.write(document)

        let nextLaunch = AutosaveStore(directory: directory)
        switch nextLaunch.loadRecoveryCopy() {
        case .success(let recovered):
            XCTAssertEqual(recovered, document)
        case .failure(let failure):
            XCTFail("next launch could not read the copy: \(failure)")
        }
    }

    func testCorruptCopyDoesNotCrash() throws {
        let store = try makeStore()
        try Data("this is not a mind map".utf8).write(to: store.recoveryURL)
        switch store.loadRecoveryCopy() {
        case .success:
            XCTFail("corrupt copy was treated as a document")
        case .failure(.noCopy):
            XCTFail("corrupt copy was missing")
        case .failure(.unreadable(let message)):
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testTickWritesAndNormalQuitRemoves() throws {
        let store = try makeStore()
        let session = AutosaveSession(store: store)
        let document = sampleDocument(title: "编辑中")
        session.noteEdit(document)
        XCTAssertEqual(session.interval, AutosaveSession.defaultInterval)
        XCTAssertEqual(AutosaveSession.defaultInterval, .seconds(5))
        session.tick()
        guard case .success(let saved) = store.loadRecoveryCopy() else {
            return XCTFail("tick did not write a copy")
        }
        XCTAssertEqual(saved, document)
        session.quitNormally()
        guard case .failure(.noCopy) = store.loadRecoveryCopy() else {
            return XCTFail("normal quit left the copy")
        }
    }

    func testNextLaunchOffersRecovery() throws {
        let store = try makeStore()
        let document = sampleDocument(title: "恢复")
        try store.write(document)
        let presenter = RecoveryPresenter(store: store)
        presenter.checkOnLaunch()
        XCTAssertTrue(presenter.showOffer)
        XCTAssertFalse(presenter.showFailure)
        XCTAssertTrue(presenter.offerMessage.contains("恢复"))
        presenter.restore()
        XCTAssertEqual(presenter.restoredDocument, document)
        XCTAssertFalse(presenter.showOffer)
        guard case .success = store.loadRecoveryCopy() else {
            return XCTFail("restore removed the copy before a normal quit")
        }
    }

    func testCorruptCopyOffersNoCrashAndNoRestore() throws {
        let store = try makeStore()
        try Data("{".utf8).write(to: store.recoveryURL)
        let presenter = RecoveryPresenter(store: store)
        presenter.checkOnLaunch()
        XCTAssertFalse(presenter.showOffer)
        XCTAssertTrue(presenter.showFailure)
        XCTAssertFalse(presenter.failureMessage.isEmpty)
        XCTAssertNil(presenter.restoredDocument)
        presenter.acknowledgeFailure()
        XCTAssertFalse(presenter.showFailure)
    }

    func testApplicationSupportDirectoryIsNotHardCoded() throws {
        let store = try AutosaveStore.inApplicationSupport()
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = store.directory.resolvingSymlinksInPath().path
        let support = base.resolvingSymlinksInPath().path
        XCTAssertTrue(directory.hasPrefix(support))
        XCTAssertTrue(store.recoveryURL.resolvingSymlinksInPath().path.hasPrefix(support))
    }

    private func makeStore() throws -> AutosaveStore {
        AutosaveStore(directory: try makeDirectory())
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlorettaAutosaveTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
        return directory
    }

    private func sampleDocument(title: String) -> MindMapDocument {
        MindMapDocument(
            title: title,
            createdAt: Date(timeIntervalSince1970: 1_762_646_400),
            modifiedAt: Date(timeIntervalSince1970: 1_762_732_800),
            roots: [
                MindMapNode(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    text: "根"
                ),
            ]
        )
    }
}

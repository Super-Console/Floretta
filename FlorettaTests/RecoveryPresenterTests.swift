import FlorettaCore
import XCTest

final class RecoveryPresenterTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories.removeAll()
        super.tearDown()
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

    private func makeStore() throws -> AutosaveStore {
        AutosaveStore(directory: try makeDirectory(), fileAccess: FoundationFileAccess())
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlorettaRecoveryTests", isDirectory: true)
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

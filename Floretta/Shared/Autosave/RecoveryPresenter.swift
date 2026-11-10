import FlorettaCore
import Foundation
import SwiftUI

/// Launch-time recovery offer. Alerts are system SwiftUI controls.
@Observable
final class RecoveryPresenter {
    var showOffer = false
    var showFailure = false
    var offerMessage = "An unsaved mind map was found."
    var failureMessage = ""
    /// Document title inside the recovery prompt. Empty titles stay nil so the chrome does not invent one.
    private(set) var offeredTitle: String?
    private(set) var restoredDocument: MindMapDocument?

    let session: AutosaveSession
    private let quitBox = AutosaveQuitBox()
    private var pending: MindMapDocument?
    private var didCheck = false

    init(store: AutosaveStore? = nil) {
        let resolved = store
            ?? (try? AutosaveStore.inApplicationSupport(fileAccess: FoundationFileAccess()))
            ?? AutosaveStore(
                directory: FileManager.default.temporaryDirectory,
                fileAccess: FoundationFileAccess()
            )
        session = AutosaveSession(store: resolved)
        quitBox.presenter = self
        let box = quitBox
        AutosaveQuitHook.handler = {
            box.quit()
        }
    }

    func checkOnLaunch() {
        guard !didCheck else { return }
        didCheck = true
        switch session.store.loadRecoveryCopy() {
        case .success(let document):
            pending = document
            offeredTitle = document.title.isEmpty ? nil : document.title
            offerMessage = document.title.isEmpty
                ? "An unsaved mind map was found."
                : "Recover \"\(document.title)\"?"
            showOffer = true
        case .failure(.noCopy):
            break
        case .failure(.unreadable(let message)):
            failureMessage = message.isEmpty ? "自动保存读不出来。" : message
            showFailure = true
        }
    }

    func restore() {
        restoredDocument = pending
        pending = nil
        showOffer = false
    }

    func discard() {
        pending = nil
        showOffer = false
        quitNormally()
    }

    func acknowledgeFailure() {
        showFailure = false
        do {
            try session.store.removeRecoveryCopy()
        } catch {
            // Leave the bad copy if it cannot be deleted. The next launch can ask again.
        }
    }

    func quitNormally() {
        session.quitNormally()
    }

    func noteEdit(_ document: MindMapDocument) {
        session.noteEdit(document)
    }
}

final class AutosaveQuitBox: @unchecked Sendable {
    weak var presenter: RecoveryPresenter?

    func quit() {
        presenter?.quitNormally()
    }
}

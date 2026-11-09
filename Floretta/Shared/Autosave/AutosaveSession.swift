import Foundation

/// While a document has unsaved edits, `tick` runs every `interval` (5 seconds).
/// The timer and `tick` share one write path. Normal quit deletes the copy.
final class AutosaveSession: @unchecked Sendable {
    static let defaultInterval: Duration = .seconds(5)

    let store: AutosaveStore
    let interval: Duration

    private let lock = NSLock()
    private var document: MindMapDocument?
    private var hasUnsavedEdits = false
    private var loop: Task<Void, Never>?

    init(store: AutosaveStore, interval: Duration = AutosaveSession.defaultInterval) {
        self.store = store
        self.interval = interval
    }

    func noteEdit(_ document: MindMapDocument) {
        lock.lock()
        self.document = document
        hasUnsavedEdits = true
        lock.unlock()
        startLoopIfNeeded()
    }

    /// One autosave pass. The 5-second loop calls this; tests can call it directly.
    func tick() {
        lock.lock()
        let dirty = hasUnsavedEdits
        let snapshot = document
        lock.unlock()
        guard dirty, let snapshot else { return }
        do {
            try store.write(snapshot)
        } catch {
            return
        }
        lock.lock()
        if document == snapshot {
            hasUnsavedEdits = false
        }
        lock.unlock()
    }

    func quitNormally() {
        lock.lock()
        let task = loop
        loop = nil
        hasUnsavedEdits = false
        document = nil
        lock.unlock()
        task?.cancel()
        do {
            try store.removeRecoveryCopy()
        } catch {
            // Quitting still proceeds if the copy cannot be removed.
        }
    }

    private func startLoopIfNeeded() {
        lock.lock()
        let alreadyRunning = loop != nil
        lock.unlock()
        guard !alreadyRunning else { return }

        let pause = interval
        let task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: pause)
                } catch {
                    break
                }
                if Task.isCancelled { break }
                self?.tick()
            }
        }

        lock.lock()
        if loop == nil {
            loop = task
        } else {
            task.cancel()
        }
        lock.unlock()
    }
}

enum AutosaveQuitHook: Sendable {
    nonisolated(unsafe) static var handler: (@Sendable () -> Void)?

    static func perform() {
        handler?()
    }
}

final class AutosaveQuitBox: @unchecked Sendable {
    weak var presenter: RecoveryPresenter?

    func quit() {
        presenter?.quitNormally()
    }
}

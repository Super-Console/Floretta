import Foundation

/// While a document has unsaved edits, `tick` runs every `interval` (5 seconds).
/// The timer and `tick` share one write path. Normal quit deletes the copy.
public final class AutosaveSession: @unchecked Sendable {
    public static let defaultInterval: Duration = .seconds(5)

    public let store: AutosaveStore
    public let interval: Duration

    private let lock = NSLock()
    private var document: MindMapDocument?
    private var hasUnsavedEdits = false
    private var loop: Task<Void, Never>?

    public init(store: AutosaveStore, interval: Duration = AutosaveSession.defaultInterval) {
        self.store = store
        self.interval = interval
    }

    public func noteEdit(_ document: MindMapDocument) {
        lock.lock()
        self.document = document
        hasUnsavedEdits = true
        lock.unlock()
        startLoopIfNeeded()
    }

    /// One autosave pass. The 5-second loop calls this; tests can call it directly.
    public func tick() {
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

    public func quitNormally() {
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

public enum AutosaveQuitHook: Sendable {
    nonisolated(unsafe) public static var handler: (@Sendable () -> Void)?

    public static func perform() {
        handler?()
    }
}

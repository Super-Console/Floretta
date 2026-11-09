import Darwin
import FlorettaCore
import SwiftUI
#if os(macOS)
import AppKit
import QuickLookUI
#else
import QuickLook
import UIKit
#endif

/// File-system events are `@Sendable` and not main-actor isolated.
/// The hop is only fired on the main queue, then the coordinator runs on the main actor.
private final class PreviewMissingHop: @unchecked Sendable {
    nonisolated(unsafe) weak var owner: (any PreviewMissingTarget)?
    nonisolated(unsafe) var generation = 0

    func fire() {
        let owner = owner
        let generation = generation
        Task { @MainActor in
            guard let owner, owner.watchGeneration == generation else { return }
            owner.reportMissing()
        }
    }
}

@MainActor
private protocol PreviewMissingTarget: AnyObject {
    var watchGeneration: Int { get }
    func reportMissing()
}

#if os(macOS)
struct MacQuickLookBridge: NSViewRepresentable {
    var url: URL?
    var title: String
    var onMissing: () -> Void
    var onClose: () -> Void
    var onUnavailable: () -> Void

    func makeCoordinator() -> MacQuickLookCoordinator { MacQuickLookCoordinator() }

    func makeNSView(context: Context) -> QLKeyView {
        let view = QLKeyView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: QLKeyView, context: Context) {
        let coordinator = context.coordinator
        view.coordinator = coordinator
        coordinator.onMissing = onMissing
        coordinator.onClose = onClose
        coordinator.onUnavailable = onUnavailable
        coordinator.title = title
        coordinator.host = view
        coordinator.schedulePresent(url)
    }
}

@MainActor
final class MacQuickLookCoordinator: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate, PreviewMissingTarget {
    var onMissing: () -> Void = {}
    var onClose: () -> Void = {}
    var onUnavailable: () -> Void = {}
    var title = ""
    weak var host: QLKeyView?
    fileprivate var item: PreviewFileItem?
    fileprivate var reported = false
    private var suppressedURL: URL?
    private var failedURL: URL?
    private var watch = PreviewFileWatch()
    private let missingHop = PreviewMissingHop()
    private(set) var watchGeneration = 0

    func schedulePresent(_ url: URL?) {
        guard needsUpdate(url) else { return }
        Task { @MainActor [weak self] in
            self?.present(url)
        }
    }

    func present(_ url: URL?) {
        guard let url else {
            close()
            return
        }
        if item?.url == url || url == suppressedURL || url == failedURL { return }
        guard let host, host.window != nil else { return }
        retireCurrentFile()
        reported = false
        let next = PreviewFileItem(url: url, title: title)
        item = next
        if !next.isReadable {
            reportMissing()
            return
        }
        host.window?.makeFirstResponder(host)
        guard let panel = QLPreviewPanel.shared() else {
            failedURL = url
            item = nil
            try? FileManager.default.removeItem(at: url)
            onUnavailable()
            return
        }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
        startWatch(url)
    }

    private func needsUpdate(_ url: URL?) -> Bool {
        if let url {
            if url == suppressedURL || url == failedURL { return false }
            return item?.url != url
        }
        suppressedURL = nil
        failedURL = nil
        return item != nil
    }

    private func retireCurrentFile() {
        watchGeneration += 1
        watch.cancel()
        if let previous = item?.url {
            try? FileManager.default.removeItem(at: previous)
        }
    }

    private func startWatch(_ url: URL) {
        watchGeneration += 1
        missingHop.owner = self
        missingHop.generation = watchGeneration
        let hop = missingHop
        watch.start(url: url) {
            hop.fire()
        }
    }

    func close() {
        watch.cancel()
        let closing = item
        suppressedURL = closing?.url ?? suppressedURL
        reported = true
        item = nil
        QLPreviewPanel.shared()?.orderOut(nil)
        if let url = closing?.url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func reportMissing() {
        guard !reported else { return }
        reported = true
        suppressedURL = item?.url
        watchGeneration += 1
        watch.cancel()
        item = nil
        QLPreviewPanel.shared()?.orderOut(nil)
        onMissing()
    }

    func panelEnded() {
        guard !reported else { return }
        reported = true
        suppressedURL = item?.url
        watchGeneration += 1
        watch.cancel()
        let closing = item
        item = nil
        if let url = closing?.url {
            try? FileManager.default.removeItem(at: url)
        }
        onClose()
    }

    /// Deferred so QuickLook is not torn down inside its own data-source callback.
    /// The hop is Sendable; the data-source method does not capture `self` in a queue closure.
    private func scheduleMissing() {
        missingHop.owner = self
        missingHop.generation = watchGeneration
        missingHop.fire()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        item == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        guard let item else {
            scheduleMissing()
            return PreviewFileItem(url: URL(fileURLWithPath: "/dev/null"), title: "")
        }
        if !item.isReadable {
            scheduleMissing()
        }
        return item
    }
}

/// AppKit calls the preview-panel hooks on the main thread.
/// The coordinator lives on the main actor; this pointer is only read there.
final class QLKeyView: NSView, @unchecked Sendable {
    nonisolated(unsafe) weak var coordinator: MacQuickLookCoordinator?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self.coordinator
            panel.delegate = self.coordinator
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
            self.coordinator?.panelEnded()
        }
    }
}
#else
struct IOSQuickLook: UIViewControllerRepresentable {
    var url: URL
    var title: String
    var onMissing: () -> Void
    var onClose: () -> Void

    func makeCoordinator() -> IOSQuickLookCoordinator {
        IOSQuickLookCoordinator(url: url, title: title, onMissing: onMissing, onClose: onClose)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        let navigation = UINavigationController(rootViewController: preview)
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "关闭",
            style: .done,
            target: context.coordinator,
            action: #selector(IOSQuickLookCoordinator.closeTapped)
        )
        context.coordinator.start()
        return navigation
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.onMissing = onMissing
        context.coordinator.onClose = onClose
        context.coordinator.item = PreviewFileItem(url: url, title: title)
        if !context.coordinator.item.isReadable {
            context.coordinator.reportMissing()
        } else if let preview = controller.viewControllers.first as? QLPreviewController {
            preview.reloadData()
        }
    }

    static func dismantleUIViewController(_ controller: UINavigationController, coordinator: IOSQuickLookCoordinator) {
        coordinator.stop()
    }
}

@MainActor
final class IOSQuickLookCoordinator: NSObject, @preconcurrency QLPreviewControllerDataSource, PreviewMissingTarget {
    var item: PreviewFileItem
    var onMissing: () -> Void
    var onClose: () -> Void
    private var watch = PreviewFileWatch()
    private let missingHop = PreviewMissingHop()
    private var reported = false
    private(set) var watchGeneration = 0

    init(url: URL, title: String, onMissing: @escaping () -> Void, onClose: @escaping () -> Void) {
        item = PreviewFileItem(url: url, title: title)
        self.onMissing = onMissing
        self.onClose = onClose
    }

    func start() {
        if !item.isReadable {
            reportMissing()
            return
        }
        watchGeneration += 1
        missingHop.owner = self
        missingHop.generation = watchGeneration
        let hop = missingHop
        watch.start(url: item.url) {
            hop.fire()
        }
    }

    func stop() {
        watch.cancel()
        guard !reported else { return }
        reported = true
        watchGeneration += 1
        try? FileManager.default.removeItem(at: item.url)
    }

    func reportMissing() {
        guard !reported else { return }
        reported = true
        watchGeneration += 1
        watch.cancel()
        onMissing()
    }

    @objc func closeTapped() {
        stop()
        onClose()
    }

    private func scheduleMissing() {
        missingHop.owner = self
        missingHop.generation = watchGeneration
        missingHop.fire()
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        if !item.isReadable {
            scheduleMissing()
        }
        return item
    }
}
#endif

final class PreviewFileItem: NSObject, QLPreviewItem, @unchecked Sendable {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    var previewItemURL: URL? { url }

    var previewItemTitle: String? { title }

    var isReadable: Bool { PreviewFileProbe.urlIfPresent(url) != nil }
}

final class PreviewFileWatch {
    private var source: DispatchSourceFileSystemObject?

    func start(url: URL, onMissing: @escaping @Sendable () -> Void) {
        cancel()
        guard PreviewFileProbe.urlIfPresent(url) != nil else {
            onMissing()
            return
        }
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            onMissing()
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler(handler: onMissing)
        source.setCancelHandler {
            Darwin.close(fd)
        }
        self.source = source
        source.resume()
    }

    func cancel() {
        source?.cancel()
        source = nil
    }
}

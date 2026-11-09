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

#if os(macOS)
struct MacQuickLookBridge: NSViewRepresentable {
    var url: URL?
    var title: String
    var onMissing: () -> Void
    var onClose: () -> Void
    var onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> QLKeyView {
        let view = QLKeyView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: QLKeyView, context: Context) {
        view.coordinator = context.coordinator
        context.coordinator.onMissing = onMissing
        context.coordinator.onClose = onClose
        context.coordinator.onUnavailable = onUnavailable
        context.coordinator.title = title
        guard context.coordinator.needsUpdate(url) else { return }
        let host = view
        let next = url
        DispatchQueue.main.async {
            context.coordinator.present(next, from: host)
        }
    }

    final class Coordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var onMissing: () -> Void = {}
        var onClose: () -> Void = {}
        var onUnavailable: () -> Void = {}
        var title = ""
        fileprivate var item: PreviewFileItem?
        fileprivate var watch = PreviewFileWatch()
        fileprivate var reported = false
        private var suppressedURL: URL?
        private var failedURL: URL?
        private var watchGeneration = 0

        func needsUpdate(_ url: URL?) -> Bool {
            if let url {
                if url == suppressedURL || url == failedURL { return false }
                return item?.url != url
            }
            suppressedURL = nil
            failedURL = nil
            return item != nil
        }

        func present(_ url: URL?, from host: QLKeyView?) {
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

        private func retireCurrentFile() {
            watchGeneration += 1
            watch.cancel()
            if let previous = item?.url {
                try? FileManager.default.removeItem(at: previous)
            }
        }

        private func startWatch(_ url: URL) {
            watchGeneration += 1
            let generation = watchGeneration
            watch.start(url: url) { [weak self] in
                guard let self, self.watchGeneration == generation else { return }
                self.reportMissing()
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
            watch.cancel()
            item = nil
            QLPreviewPanel.shared()?.orderOut(nil)
            onMissing()
        }

        func panelEnded() {
            guard !reported else { return }
            reported = true
            suppressedURL = item?.url
            watch.cancel()
            let closing = item
            item = nil
            if let url = closing?.url {
                try? FileManager.default.removeItem(at: url)
            }
            onClose()
        }

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            item == nil ? 0 : 1
        }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
            guard let item else {
                DispatchQueue.main.async { self.reportMissing() }
                return PreviewFileItem(url: URL(fileURLWithPath: "/dev/null"), title: "")
            }
            if !item.isReadable {
                DispatchQueue.main.async { self.reportMissing() }
            }
            return item
        }
    }
}

final class QLKeyView: NSView {
    weak var coordinator: MacQuickLookBridge.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = coordinator
        panel.delegate = coordinator
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        coordinator?.panelEnded()
    }
}
#else
struct IOSQuickLook: UIViewControllerRepresentable {
    var url: URL
    var title: String
    var onMissing: () -> Void
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, title: title, onMissing: onMissing, onClose: onClose)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        let navigation = UINavigationController(rootViewController: preview)
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "关闭",
            style: .done,
            target: context.coordinator,
            action: #selector(Coordinator.closeTapped)
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
        } else {
            controller.viewControllers.first.flatMap { $0 as? QLPreviewController }?.reloadData()
        }
    }

    static func dismantleUIViewController(_ controller: UINavigationController, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var item: PreviewFileItem
        var onMissing: () -> Void
        var onClose: () -> Void
        private var watch = PreviewFileWatch()
        private var reported = false

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
            watch.start(url: item.url) { [weak self] in
                self?.reportMissing()
            }
        }

        func stop() {
            watch.cancel()
            guard !reported else { return }
            reported = true
            try? FileManager.default.removeItem(at: item.url)
        }

        func reportMissing() {
            guard !reported else { return }
            reported = true
            watch.cancel()
            onMissing()
        }

        @objc func closeTapped() {
            stop()
            onClose()
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            if !item.isReadable {
                DispatchQueue.main.async { self.reportMissing() }
            }
            return item
        }
    }
}
#endif

final class PreviewFileItem: NSObject, QLPreviewItem {
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

    func start(url: URL, onMissing: @escaping () -> Void) {
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
        source.setEventHandler {
            onMissing()
        }
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

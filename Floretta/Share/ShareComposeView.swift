import FlorettaCore
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

private enum ShareMetrics {
    static let indent: CGFloat = 16
}

enum ShareChrome {
    static func text(_ key: String) -> String {
        guard Locale.current.language.languageCode?.identifier == "en" else { return key }
        return english[key] ?? key
    }

    static func confirmation(_ proposal: AttachmentInsertProposal) -> String {
        guard Locale.current.language.languageCode?.identifier == "en" else {
            return proposal.confirmationMessage
        }
        var lines = [
            "File size: \(AttachmentByteFormat.label(proposal.fileByteCount))",
            "Document size after adding: \(AttachmentByteFormat.label(proposal.projectedDocumentByteCount))",
            "The bytes are stored as-is. Nothing is compressed or transcoded.",
        ]
        if proposal.exceedsSoftCap {
            lines.append("This is over the 10GB soft limit.")
        }
        return lines.joined(separator: "\n")
    }

    private static let english: [String: String] = [
        "存入节点": "Save to Topic",
        "取消": "Cancel",
        "存入": "Save",
        "选择导图": "Choose Map",
        "返回": "Back",
        "最近": "Recent",
        "没有最近导图。选择一份 .floretta。": "No recent maps. Choose a .floretta file.",
        "选择要存入的主题": "Choose a topic",
        "正在读取分享内容": "Reading the shared item",
        "正在写入": "Saving",
        "这份导图没有主题。": "This map has no topics.",
        "书签打不开，请重新选择这份导图。": "The bookmark didn't open. Choose the map again.",
    ]
}

enum ShareComposePhase: Equatable {
    case loading
    case chooseDocument
    case chooseTopic
    case saving
    case failed(String)
}

struct OpenedMap: Equatable {
    var url: URL
    var filename: String
    var topics: [ShareTopicChoice]
}

private final class ScopedMapURL {
    let url: URL
    private var started: Bool

    init(url: URL, started: Bool) {
        self.url = url
        self.started = started || url.startAccessingSecurityScopedResource()
    }

    func end() {
        guard started else { return }
        url.stopAccessingSecurityScopedResource()
        started = false
    }
}

@MainActor
@Observable
final class ShareComposeSession {
    var phase: ShareComposePhase = .loading
    var documents: [ShareDocumentEntry] = []
    var opened: OpenedMap?
    var selection: UUID?
    var summary = ""
    var proposal: AttachmentInsertProposal?
    var errorMessage: String?
    var showPicker = false

    @ObservationIgnored private var context: NSExtensionContext?
    @ObservationIgnored private var draft: ShareDraft?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var scope: ScopedMapURL?
    @ObservationIgnored private var finished = false

    var canSave: Bool {
        phase == .chooseTopic && selection != nil && draft != nil
    }

    func start(_ context: NSExtensionContext?) {
        self.context = context
        documents = ShareCatalogStore.load().documents
        let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await load(items) }
    }

    func cancel() {
        guard !finished, phase != .saving else { return }
        finished = true
        cleanup()
        context?.cancelRequest(withError: CocoaError(.userCancelled))
        context = nil
    }

    func backToDocuments() {
        selection = nil
        opened = nil
        proposal = nil
        errorMessage = nil
        scope?.end()
        scope = nil
        phase = .chooseDocument
    }

    func openCatalogEntry(_ entry: ShareDocumentEntry) {
        guard let url = ShareCatalogStore.resolve(entry) else {
            errorMessage = ShareChrome.text("书签打不开，请重新选择这份导图。")
            return
        }
        adopt(url, accessAlreadyStarted: false)
    }

    func adopt(_ url: URL, accessAlreadyStarted: Bool) {
        errorMessage = nil
        scope?.end()
        let scoped = ScopedMapURL(url: url, started: accessAlreadyStarted)
        scope = scoped
        do {
            let files = FoundationStreamingFiles()
            guard try files.isZip(at: scoped.url) else { throw ShareIngressError.notAPackage }
            let reader = try files.openReader(at: scoped.url)
            let openedDocument: MindMapDocument
            do {
                openedDocument = try FlorettaStreamingDocument.open(reader).document
                try reader.close()
            } catch {
                try? reader.close()
                throw error
            }
            let topics = ShareIngress.topics(in: openedDocument)
            opened = OpenedMap(url: scoped.url, filename: scoped.url.lastPathComponent, topics: topics)
            selection = topics.count == 1 ? topics[0].id : nil
            if let draft {
                let bytes = try files.byteCount(at: scoped.url)
                proposal = ShareIngress.proposal(for: draft, currentDocumentByteCount: bytes)
            }
            phase = .chooseTopic
            if topics.isEmpty {
                errorMessage = ShareChrome.text("这份导图没有主题。")
            }
        } catch {
            scope?.end()
            scope = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func confirm() {
        guard canSave, let draft, let opened, let selection else { return }
        phase = .saving
        errorMessage = nil
        let archive = opened.url
        let node = selection
        let file = fileURL
        let clock = SystemClock()
        Task {
            do {
                let result = try await Task.detached {
                    try ShareCommit.commit(
                        draft,
                        onto: node,
                        archive: archive,
                        fileURL: file,
                        files: FoundationStreamingFiles(),
                        snapshots: .standard,
                        clock: clock
                    )
                }.value
                guard !finished else { return }
                ShareCatalogStore.publish(url: archive, document: result.document)
                finish()
            } catch {
                guard !finished else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                phase = .chooseTopic
            }
        }
    }

    private func load(_ items: [NSExtensionItem]) async {
        do {
            let loaded = try await ShareItemLoader.load(items)
            guard !finished else {
                if let url = loaded.fileURL { try? FileManager.default.removeItem(at: url) }
                return
            }
            draft = loaded.draft
            fileURL = loaded.fileURL
            summary = Self.summary(for: loaded.draft)
            phase = .chooseDocument
        } catch {
            guard !finished else { return }
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        cleanup()
        context?.completeRequest(returningItems: nil, completionHandler: nil)
        context = nil
    }

    private func cleanup() {
        scope?.end()
        scope = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    private static func summary(for draft: ShareDraft) -> String {
        switch draft.kind {
        case .webPage(let url, let title):
            return ShareTopicText.webTitle(url: url, title: title)
        case .plainText(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 80 { return String(trimmed.prefix(80)) + "…" }
            return trimmed
        case .file(let filename, let byteCount):
            return "\(filename) · \(AttachmentByteFormat.label(byteCount))"
        }
    }
}

struct ShareComposeView: View {
    @Bindable var session: ShareComposeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            if let proposal = session.proposal, session.phase == .chooseTopic || session.phase == .saving {
                Text(ShareChrome.confirmation(proposal))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            if let errorMessage = session.errorMessage, session.phase != .failed(errorMessage) {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            buttonBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if os(iOS)
        .sheet(isPresented: $session.showPicker) {
            ShareDocumentPicker { url, started in
                session.showPicker = false
                session.adopt(url, accessAlreadyStarted: started)
            } onCancel: {
                session.showPicker = false
            }
        }
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            if session.phase == .chooseTopic {
                Button {
                    session.backToDocuments()
                } label: {
                    Label(ShareChrome.text("返回"), systemImage: "chevron.left")
                }
                .labelStyle(.titleAndIcon)
                .accessibilityLabel(ShareChrome.text("返回"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ShareChrome.text("存入节点"))
                    .font(.headline)
                if !session.summary.isEmpty {
                    Text(session.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .loading, .saving:
            VStack(spacing: 12) {
                ProgressView()
                Text(ShareChrome.text(session.phase == .loading ? "正在读取分享内容" : "正在写入"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Text(message)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
        case .chooseDocument:
            documentList
        case .chooseTopic:
            topicList
        }
    }

    private var documentList: some View {
        List {
            if session.documents.isEmpty {
                Text(ShareChrome.text("没有最近导图。选择一份 .floretta。"))
                    .foregroundStyle(.secondary)
            } else {
                Section(ShareChrome.text("最近")) {
                    ForEach(session.documents) { entry in
                        Button {
                            session.openCatalogEntry(entry)
                        } label: {
                            Label(entry.filename, systemImage: "doc")
                        }
                        .accessibilityLabel(entry.filename)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .listStyle(.inset)
        #endif
    }

    private var topicList: some View {
        List {
            if let opened = session.opened {
                Section(opened.filename) {
                    if opened.topics.isEmpty {
                        Text(ShareChrome.text("这份导图没有主题。"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(opened.topics) { topic in
                        Button {
                            session.selection = topic.id
                        } label: {
                            HStack {
                                Text(topic.title)
                                    .padding(.leading, CGFloat(topic.depth) * ShareMetrics.indent)
                                Spacer(minLength: 0)
                                if session.selection == topic.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .accessibilityLabel(topic.path)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .listStyle(.inset)
        #endif
    }

    private var buttonBar: some View {
        HStack(spacing: 12) {
            Button {
                session.cancel()
            } label: {
                Label(ShareChrome.text("取消"), systemImage: "xmark")
            }
            .disabled(session.phase == .saving)
            .accessibilityLabel(ShareChrome.text("取消"))
            Spacer(minLength: 0)
            Button {
                #if os(macOS)
                pickOnMac()
                #else
                session.showPicker = true
                #endif
            } label: {
                Label(ShareChrome.text("选择导图"), systemImage: "folder")
            }
            .disabled(session.phase == .loading || session.phase == .saving)
            .accessibilityLabel(ShareChrome.text("选择导图"))
            Button {
                session.confirm()
            } label: {
                Label(ShareChrome.text("存入"), systemImage: "checkmark")
            }
            .disabled(!session.canSave)
            .accessibilityLabel(ShareChrome.text("存入"))
        }
        .padding(16)
    }

    #if os(macOS)
    private func pickOnMac() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let type = UTType("net.timhuang.floretta.document") {
            panel.allowedContentTypes = [type]
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let started = url.startAccessingSecurityScopedResource()
            Task { @MainActor in
                session.adopt(url, accessAlreadyStarted: started)
            }
        }
    }
    #endif
}

#if os(iOS)
private struct ShareDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL, Bool) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let type = UTType("net.timhuang.floretta.document") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [type], asCopy: false)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL, Bool) -> Void
        var onCancel: () -> Void

        init(onPick: @escaping (URL, Bool) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let started = url.startAccessingSecurityScopedResource()
            onPick(url, started)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
#endif

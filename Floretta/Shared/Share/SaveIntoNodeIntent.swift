import AppIntents
import FlorettaCore
import Foundation
import UniformTypeIdentifiers

/// Shortcuts action. Safari links, text, and photo files all land on one named topic.
struct SaveIntoNodeIntent: AppIntent {
    static var title: LocalizedStringResource = "存入节点"
    static var description = IntentDescription("把链接、文字或图片存进指定主题。")
    static var openAppWhenRun = false

    @Parameter(title: "导图")
    var document: IntentFile

    @Parameter(title: "主题")
    var node: String

    @Parameter(title: "链接")
    var link: String?

    @Parameter(title: "文字")
    var text: String?

    @Parameter(title: "文件")
    var attachment: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("把内容存入 \(\.$document) 的 \(\.$node)") {
            \.$link
            \.$text
            \.$attachment
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let archive = try await IntentFileSpill.openInPlace(document)
        let archiveAccess = archive.startAccessingSecurityScopedResource()
        defer {
            if archiveAccess { archive.stopAccessingSecurityScopedResource() }
        }

        var fact: ShareFileFact?
        var fileURL: URL?
        var fileAccess = false
        var spill: URL?
        defer {
            if fileAccess, let fileURL { fileURL.stopAccessingSecurityScopedResource() }
            if let spill { try? FileManager.default.removeItem(at: spill) }
        }
        if let attachment {
            let located = try await IntentFileSpill.read(attachment)
            fileAccess = located.url.startAccessingSecurityScopedResource()
            let count = try FoundationStreamingFiles().byteCount(at: located.url)
            if located.deleteWhenDone {
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("floretta-share-\(UUID().uuidString)", isDirectory: false)
                try FileManager.default.copyItem(at: located.url, to: copy)
                if fileAccess {
                    located.url.stopAccessingSecurityScopedResource()
                    fileAccess = false
                }
                spill = copy
                fileURL = copy
            } else {
                fileURL = located.url
            }
            let name = attachment.filename.isEmpty ? located.url.lastPathComponent : attachment.filename
            fact = ShareFileFact(filename: name, byteCount: count, isDirectory: false)
        }

        let draft = try ShareDraftBuilder.make(
            origin: .shortcuts,
            url: link,
            title: nil,
            text: text,
            file: fact
        )
        let result = try await LibraryModel.shared.saveShared(
            draft: draft,
            onto: node,
            archive: archive,
            fileURL: fileURL
        )
        var name = ""
        if let child = result.childID, let title = result.document.node(child)?.text, !title.isEmpty {
            name = title
        } else {
            name = result.document.node(result.nodeID)?.text ?? ""
        }
        if name.isEmpty { name = "未命名" }
        let dialog = "已存入「\(name)」。"
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// Phrases the Shortcuts app shows. Each one names Floretta.
struct FlorettaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveIntoNodeIntent(),
            phrases: [
                "用 \(.applicationName) 存入节点",
                "存进 \(.applicationName) 的节点",
            ],
            shortTitle: "存入节点",
            systemImageName: "square.and.arrow.down"
        )
    }
}

enum IntentFileSpill {
    struct Located {
        var url: URL
        var deleteWhenDone: Bool
    }

    /// The user's file, not a copy. Writing a copy would not change the map they picked.
    static func openInPlace(_ file: IntentFile) async throws -> URL {
        if let url = file.fileURL { return url }
        let type = file.type ?? UTType(filenameExtension: "floretta") ?? .data
        let located = try await file.file(contentType: type, destinationDirectory: nil)
        guard located.openedInPlace else { throw ShareIngressError.notWritableCopy }
        return located.fileURL
    }

    /// Prefer the original URL so a photo is not transcoded. `.data` is never read.
    static func read(_ file: IntentFile) async throws -> Located {
        if let url = file.fileURL {
            return Located(url: url, deleteWhenDone: false)
        }
        let type = file.type ?? .data
        let located = try await file.file(contentType: type, destinationDirectory: nil)
        return Located(url: located.fileURL, deleteWhenDone: !located.openedInPlace)
    }
}

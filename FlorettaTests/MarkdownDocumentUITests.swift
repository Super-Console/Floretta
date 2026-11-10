import FlorettaCore
import UniformTypeIdentifiers
import XCTest

@MainActor
final class MarkdownDocumentUITests: XCTestCase {
    func testBannerStaysForMarkdownAndLeavesAfterSwitching() throws {
        XCTAssertFalse(MarkdownModeCopy.canDismiss)
        XCTAssertEqual(MarkdownModeCopy.title, "Markdown 模式")
        XCTAssertEqual(FlorettaL10n.string(MarkdownModeCopy.title, language: .english), "Markdown Mode")
        XCTAssertEqual(
            FlorettaL10n.string(MarkdownModeCopy.explanation, language: .english),
            "This file only saves hierarchy and text. It does not include attachments, colors, relationships, free positions, or collapse state."
        )
        for phrase in ["附件", "颜色", "关系线", "自由位置", "折叠"] {
            XCTAssertTrue(MarkdownModeCopy.explanation.contains(phrase), phrase)
        }

        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("笔记.md")
        try Data("- 根\n".utf8).write(to: url)
        let library = try makeLibrary(directory: directory)
        library.openFile(url)
        let session = try XCTUnwrap(library.editor)
        XCTAssertTrue(session.markdownBannerVisible)
        XCTAssertTrue(session.isMarkdownDocument)
        XCTAssertEqual(session.sourceExtension, "md")

        let upgraded = directory.appendingPathComponent("笔记.\(FlorettaCodec.fileExtension)")
        try MarkdownUpgrade.fileData(for: session.document).write(to: upgraded)
        library.finishMarkdownUpgrade(savedAt: upgraded, choice: .keepMarkdown)
        XCTAssertEqual(library.editor?.url?.path, url.path)
        XCTAssertTrue(library.editor?.markdownBannerVisible == true)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "- 根\n")

        library.finishMarkdownUpgrade(savedAt: upgraded, choice: .openFloretta)
        XCTAssertEqual(library.editor?.sourceExtension, "floretta")
        XCTAssertFalse(library.editor?.markdownBannerVisible == true)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).hasPrefix("- "))
    }

    func testDisabledActionsDoNotMutateAndShareOneReason() throws {
        let session = EditorSession(
            document: MindMapDocument(title: "md", roots: [
                MindMapNode(text: "根", children: [MindMapNode(text: "子")]),
            ]),
            url: URL(fileURLWithPath: "/tmp/笔记.md"),
            sourceExtension: "md",
            viewMode: .map
        )
        let child = try XCTUnwrap(session.document.roots[0].children.first?.id)
        for control in MarkdownBlockedControl.allCases {
            XCTAssertFalse(MarkdownModePolicy.isEnabled(control, markdown: true), control.rawValue)
            XCTAssertTrue(MarkdownModePolicy.isEnabled(control, markdown: false), control.rawValue)
            let reason = MarkdownModePolicy.reason(control)
            XCTAssertTrue(reason.hasPrefix("Markdown 模式无法保存"), reason)
            XCTAssertEqual(FlorettaL10n.string(reason, language: .simplifiedChinese), reason)
            XCTAssertNotEqual(FlorettaL10n.string(reason, language: .english), reason)
        }
        XCTAssertEqual(
            MarkdownModePolicy.reason(.insertAttachment),
            MarkdownModePolicy.reason(.insertImage)
        )
        XCTAssertEqual(MarkdownModePolicy.reason(.nodeColor), MarkdownModePolicy.reason(.themeColor))
        XCTAssertEqual(MarkdownModePolicy.reason(.nodeColor), MarkdownModePolicy.reason(.copyStyle))

        session.linkSelectedTopic(to: child)
        session.addFreeNodeFromToolbar()
        session.addStickyFromToolbar()
        session.addSummaryFromToolbar()
        session.addBoundaryFromToolbar()
        session.setBranchTheme("sea")
        XCTAssertFalse(session.updateSelectedTopicTags { $0.labels = ["甲"] })
        XCTAssertTrue(session.document.relationships.isEmpty)
        XCTAssertTrue(session.document.freeNodes.isEmpty)
        XCTAssertTrue(session.document.stickies.isEmpty)
        XCTAssertEqual(session.document.summaryCount, 0)
        XCTAssertEqual(session.document.boundaryCount, 0)
        XCTAssertNil(session.document.themeID)
        XCTAssertTrue(session.document.roots[0].labels.isEmpty)
        XCTAssertFalse(session.acceptsAttachmentDrop)

        let project = EditorSession(
            document: session.document,
            url: URL(fileURLWithPath: "/tmp/图.floretta"),
            sourceExtension: "floretta",
            viewMode: .map
        )
        project.setBranchTheme("sea")
        XCTAssertEqual(project.document.themeID, "sea")
        XCTAssertTrue(project.acceptsAttachmentDrop)
    }

    func testWarningIsOneNoticeAndSurfacesOnce() throws {
        let notice = MarkdownModePolicy.notice(for: [.normalizedListMarker, .normalizedTabIndent, .normalizedListMarker])
        let text = try XCTUnwrap(notice)
        XCTAssertEqual(text.components(separatedBy: "\n").count, 2)
        XCTAssertTrue(text.contains("无序"))
        XCTAssertTrue(text.contains("Tab"))
        XCTAssertNil(MarkdownModePolicy.notice(for: []))

        var presentation = MarkdownWarningPresentation()
        XCTAssertEqual(presentation.present(notice), notice)
        XCTAssertNil(presentation.present(notice))

        let session = EditorSession(
            document: MindMapDocument(title: "md", roots: [MindMapNode(text: "根")]),
            url: URL(fileURLWithPath: "/tmp/a.md"),
            sourceExtension: "markdown",
            viewMode: .map
        )
        session.installMarkdownWarnings([.normalizedListMarker, .normalizedTabIndent])
        XCTAssertEqual(session.visibleMarkdownWarning, notice)
        session.dismissMarkdownWarning()
        XCTAssertNil(session.visibleMarkdownWarning)
        XCTAssertTrue(session.markdownBannerVisible)
        session.installMarkdownWarnings([.normalizedTabIndent])
        XCTAssertNil(session.visibleMarkdownWarning)
    }

    func testDirtyTracksOnlyPersistableFieldsAndSaveDropsTheRest() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("笔记.md")
        let original = "---\nkeep: yes\n---\n\n- 根\n  - 子\n"
        try Data(original.utf8).write(to: url)
        let library = try makeLibrary(directory: directory)
        library.openFile(url)
        let session = try XCTUnwrap(library.editor)
        XCTAssertNil(library.openError)
        XCTAssertFalse(session.isMarkdownDirty)
        XCTAssertFalse(session.consumeAutosaveEdit(session.document))

        let rootID = session.document.roots[0].id
        XCTAssertTrue(CanvasEditCommands.setFill(hex: "#E23D3D", nodeID: rootID, document: &session.document))
        session.document.relationships.append(
            TopicRelationship(sourceID: rootID, targetID: session.document.roots[0].children[0].id, title: "秘密关系")
        )
        session.document.roots[0].attachments.append(
            NodeAttachment(sha256: String(repeating: "ab", count: 32), fileExtension: "png", byteCount: 4, filename: "secret.png")
        )
        session.document.roots[0].isCollapsed = true
        session.document.roots[0].position = MindMapPoint(x: 12, y: 8)
        XCTAssertFalse(session.isMarkdownDirty)
        XCTAssertFalse(session.consumeAutosaveEdit(session.document))

        session.document.markdownFrontMatter = "---\nkeep: edited\n---"
        XCTAssertTrue(session.isMarkdownDirty)
        XCTAssertTrue(session.consumeAutosaveEdit(session.document))
        XCTAssertFalse(session.consumeAutosaveEdit(session.document))

        session.document.roots[0].text = "改过"
        session.document.roots[0].children[0].note = "备注"
        session.document.roots[0].children[0].link = "https://example.com/a"
        XCTAssertTrue(session.isMarkdownDirty)
        library.saveActiveFile()
        XCTAssertNil(library.openError)
        XCTAssertFalse(session.isMarkdownDirty)
        XCTAssertEqual(library.editor?.url?.path, url.path)
        XCTAssertEqual(library.editor?.sourceExtension, "md")

        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(saved.contains("改过"))
        XCTAssertTrue(saved.contains("备注"))
        XCTAssertTrue(saved.contains("https://example.com/a"))
        XCTAssertTrue(saved.contains("keep: edited"))
        XCTAssertFalse(saved.contains("#E23D3D"))
        XCTAssertFalse(saved.contains("secret.png"))
        XCTAssertFalse(saved.contains("秘密关系"))
        XCTAssertFalse(saved.contains("<!--"))
        XCTAssertFalse(saved.contains(rootID.uuidString))
        XCTAssertEqual(saved, FlorettaMarkdownDocumentCodec.save(session.document))

        let beforeUpgrade = try Data(contentsOf: url)
        session.document.roots[0].style = MindMapNodeStyle(colorHex: "#112233")
        let upgradedData = try MarkdownUpgrade.fileData(for: session.document)
        XCTAssertEqual(try Data(contentsOf: url), beforeUpgrade)
        let upgraded = try FlorettaCodec.decode(upgradedData)
        XCTAssertEqual(upgraded.roots[0].text, "改过")
        XCTAssertEqual(upgraded.roots[0].children[0].note, "备注")
        XCTAssertEqual(upgraded.roots[0].children[0].link, "https://example.com/a")
        XCTAssertEqual(upgraded.markdownFrontMatter, "---\nkeep: edited\n---")
        XCTAssertNil(upgraded.roots[0].style)
        XCTAssertTrue(upgraded.roots[0].attachments.isEmpty)
        XCTAssertFalse(upgraded.roots[0].isCollapsed)
        XCTAssertNil(upgraded.roots[0].position)
        XCTAssertTrue(upgraded.relationships.isEmpty)
        XCTAssertEqual(MarkdownUpgrade.defaultChoice, .keepMarkdown)
        XCTAssertEqual(MarkdownUpgrade.filenameExtension, FlorettaCodec.fileExtension)
        XCTAssertEqual(MarkdownUpgrade.filenameExtension, "floretta")
        XCTAssertNotEqual(MarkdownUpgrade.filenameExtension, "florettra")
        XCTAssertEqual(MarkdownUpgrade.contentType.preferredFilenameExtension, FlorettaCodec.fileExtension)
        XCTAssertTrue(MarkdownUpgrade.replacesOriginal(destination: url, original: url))
        let sibling = directory.appendingPathComponent("升级.floretta")
        XCTAssertFalse(MarkdownUpgrade.replacesOriginal(destination: sibling, original: url))

        try upgradedData.write(to: sibling)
        library.finishMarkdownUpgrade(savedAt: url, choice: .keepMarkdown)
        XCTAssertEqual(library.openError, "不能覆盖原来的 Markdown 文件。")
        XCTAssertEqual(try Data(contentsOf: url), beforeUpgrade)
        library.dismissOpenError()
        library.finishMarkdownUpgrade(savedAt: sibling, choice: .keepMarkdown)
        XCTAssertEqual(library.editor?.url?.path, url.path)
        XCTAssertEqual(try Data(contentsOf: url), beforeUpgrade)
        XCTAssertTrue(library.editor?.markdownBannerVisible == true)
    }

    func testOpenFailureShowsTheCodecLineAndDoesNotBuildATree() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("坏.md")
        let fixture = try fixtureText("reject-h2.md")
        try Data(fixture.utf8).write(to: url)
        let library = try makeLibrary(directory: directory)
        library.openFile(url)
        XCTAssertNil(library.editor)
        let message = try XCTUnwrap(library.openError)
        let lines = fixture.split(separator: "\n", omittingEmptySubsequences: false)
        let lineNumber = try XCTUnwrap(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("##") }) + 1
        XCTAssertTrue(message.contains("第 \(lineNumber) 行"), message)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), fixture)

        let markers = try fixtureText("markers-and-tabs.md")
        let marked = directory.appendingPathComponent("标记.md")
        try Data(markers.utf8).write(to: marked)
        library.openFile(marked)
        let session = try XCTUnwrap(library.editor)
        let warning = try XCTUnwrap(session.visibleMarkdownWarning)
        XCTAssertEqual(warning.components(separatedBy: "\n").count, 2)
        XCTAssertEqual(session.document.roots.count, 3)
        session.dismissMarkdownWarning()
        XCTAssertNil(session.visibleMarkdownWarning)
    }

    func testBytesBeatAMarkdownNameSoCloseDoesNotRewriteThem() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("notes.md")
        let map = MindMapDocument(title: "图", roots: [MindMapNode(text: "根")])
        let xml = try FlorettaOPMLCodec.export(map)
        try xml.write(to: url)
        let library = try makeLibrary(directory: directory)
        library.openFile(url)
        let session = try XCTUnwrap(library.editor)
        XCTAssertFalse(session.isMarkdownDocument)
        XCTAssertFalse(session.markdownBannerVisible)
        XCTAssertEqual(session.document.roots.first?.text, "根")
        session.document.roots[0].text = "改过"
        XCTAssertFalse(library.closeEditor())
        XCTAssertEqual(try Data(contentsOf: url), xml)
    }

    func testHeadingExportStaysOffTheDocumentOpenPath() throws {
        let child = MindMapNode(text: "子", note: "子备注", link: "https://example.com/a")
        let document = MindMapDocument(title: "md", roots: [MindMapNode(text: "根", children: [child])])
        let preset = try SharePayload.bytes(for: "md", document: document)
        let presetText = try XCTUnwrap(String(data: preset, encoding: .utf8))
        XCTAssertTrue(presetText.contains("# 根"))
        XCTAssertTrue(presetText.contains("## 子"))
        let imported = try FlorettaMarkdown.importOutline(preset)
        XCTAssertEqual(imported.roots[0].children[0].link, "https://example.com/a")
        XCTAssertThrowsError(try DocumentOpener.open(data: preset, filename: "大纲.md")) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("第"), message)
        }
        let saved = Data(FlorettaMarkdownDocumentCodec.save(document).utf8)
        let opened = try DocumentOpener.open(data: saved, filename: "文档.md")
        XCTAssertEqual(opened.roots[0].text, "根")
        XCTAssertEqual(opened.roots[0].children[0].note, "子备注")
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("## "))
    }

    private func fixtureText(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/FlorettaCoreTests/Fixtures/MarkdownAsDocument")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeLibrary(directory: URL) throws -> LibraryModel {
        let name = "floretta.md.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return LibraryModel(
            settings: AppSettings(defaults: defaults),
            store: RecentMapsStore(defaults: defaults),
            documentsDirectory: directory
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

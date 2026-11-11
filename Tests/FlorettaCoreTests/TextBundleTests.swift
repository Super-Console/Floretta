import CoreFoundation
import FlorettaCore
import Foundation
import XCTest

final class TextBundleTests: XCTestCase {
    func testSimpleFixtureMatchesCodecAndInfo() throws {
        let document = simpleDocument()
        let package = FlorettaTextBundleCodec.export(document)
        let expected = try loadFixture("simple")
        XCTAssertEqual(dictionary(package), expected)
        XCTAssertEqual(package.textMarkdown, FlorettaMarkdownDocumentCodec.save(document))
        XCTAssertFalse(package.textMarkdown.contains("简单"))
        try assertInfo(package)
        try assertDirectoryRoundTrip(package, extensionName: "textbundle")
        try assertTextpackRoundTrip(package)
    }

    func testNestedFixtureMatchesCodec() throws {
        let document = nestedDocument()
        let package = FlorettaTextBundleCodec.export(document)
        XCTAssertEqual(dictionary(package), try loadFixture("nested"))
        XCTAssertEqual(package.textMarkdown, FlorettaMarkdownDocumentCodec.save(document))
        XCTAssertTrue(package.textMarkdown.contains("# 分区"))
        XCTAssertFalse(package.textMarkdown.contains("##"))
        XCTAssertFalse(package.textMarkdown.contains("嵌套"))
    }

    func testAttachmentFixtureCopiesBytesAndSkipsWhatMarkdownCannotHold() throws {
        let (document, assets) = attachmentDocument()
        let package = FlorettaTextBundleCodec.export(document, assets: assets)
        let expected = try loadFixture("attachments")
        XCTAssertEqual(dictionary(package), expected)
        assertCodecLinesPreserved(document, markdown: package.textMarkdown)

        let text = package.textMarkdown
        XCTAssertEqual(assetLines(in: text).count, 4)
        XCTAssertTrue(text.contains("![photo.png](assets/photo.png)"))
        XCTAssertTrue(text.contains("[notes.pdf](assets/notes.pdf)"))
        XCTAssertTrue(text.contains("![photo.png](assets/photo-b360e170.png)"))
        XCTAssertTrue(text.contains("孙"))
        XCTAssertFalse(text.contains("gone.png"))
        XCTAssertFalse(text.contains("float.gif"))
        XCTAssertFalse(text.contains("sheet.txt"))
        XCTAssertFalse(text.contains("浮动"))
        XCTAssertFalse(text.contains("另页"))
        XCTAssertFalse(text.contains("第二张"))
        XCTAssertFalse(text.contains("便签一"))
        XCTAssertFalse(text.contains("关系甲"))
        XCTAssertFalse(text.contains("附件图"))
        XCTAssertFalse(text.contains("FF00AA"))
        XCTAssertFalse(text.contains("left"))

        XCTAssertEqual(package.data(at: "assets/photo.png"), pngBytes)
        XCTAssertEqual(package.data(at: "assets/notes.pdf"), pdfBytes)
        XCTAssertEqual(package.data(at: "assets/photo-b360e170.png"), png2Bytes)
        XCTAssertNil(package.data(at: "assets/float.gif"))
        XCTAssertNil(package.data(at: "assets/sheet.txt"))
        XCTAssertNil(package.data(at: "assets/gone.png"))

        let fromPackage = FlorettaTextBundleCodec.export(FlorettaPackage(
            document: document,
            assets: assets
        ))
        XCTAssertEqual(fromPackage, package)
        try assertDirectoryRoundTrip(package, extensionName: "textbundle")
        try assertTextpackRoundTrip(package)
    }

    func testAssetNamesStayZipSafeAndKeepTheOriginalLabel() {
        let pngHash = sha256Hex(pngBytes)
        let noteHash = sha256Hex(Data("笔记".utf8))
        let dottedHash = sha256Hex(Data("a..b".utf8))
        let spacedHash = sha256Hex(Data("spaced".utf8))
        let bracketHash = sha256Hex(Data("bracket".utf8))
        let document = MindMapDocument(
            title: "名字",
            roots: [
                MindMapNode(
                    text: "根",
                    attachments: [
                        NodeAttachment(sha256: pngHash, fileExtension: "png", byteCount: Int64(pngBytes.count), filename: "../photo.png"),
                        NodeAttachment(sha256: noteHash, fileExtension: "png", byteCount: 6, filename: "笔记.png"),
                        NodeAttachment(sha256: dottedHash, fileExtension: "png", byteCount: 4, filename: "a..b.png"),
                        NodeAttachment(sha256: spacedHash, fileExtension: "png", byteCount: 6, filename: "a b.png"),
                        NodeAttachment(sha256: bracketHash, fileExtension: "png", byteCount: 7, filename: "weird[name].png"),
                    ]
                ),
            ]
        )
        let assets = [
            FlorettaAsset(sha256: pngHash, fileExtension: "png", data: pngBytes),
            FlorettaAsset(sha256: noteHash, fileExtension: "png", data: Data("笔记".utf8)),
            FlorettaAsset(sha256: dottedHash, fileExtension: "png", data: Data("a..b".utf8)),
            FlorettaAsset(sha256: spacedHash, fileExtension: "png", data: Data("spaced".utf8)),
            FlorettaAsset(sha256: bracketHash, fileExtension: "png", data: Data("bracket".utf8)),
        ]
        let package = FlorettaTextBundleCodec.export(document, assets: assets)
        let text = package.textMarkdown
        XCTAssertTrue(text.contains("![photo.png](assets/photo.png)"))
        XCTAssertTrue(text.contains("![笔记.png](assets/\(noteHash).png)"))
        XCTAssertTrue(text.contains("![a..b.png](assets/\(dottedHash).png)"))
        XCTAssertTrue(text.contains("![a b.png](assets/a-b.png)"))
        XCTAssertTrue(text.contains("![weird\\[name\\].png](assets/weirdname.png)"))
        XCTAssertEqual(package.data(at: "assets/photo.png"), pngBytes)
        XCTAssertEqual(package.data(at: "assets/\(noteHash).png"), Data("笔记".utf8))
        XCTAssertEqual(package.data(at: "assets/\(dottedHash).png"), Data("a..b".utf8))
        XCTAssertEqual(package.data(at: "assets/a-b.png"), Data("spaced".utf8))
        XCTAssertEqual(package.data(at: "assets/weirdname.png"), Data("bracket".utf8))
        XCTAssertNil(package.files.first { $0.path.contains("..") })
        let packed = package.textpack()
        XCTAssertNoThrow(try ZipArchive.read(packed, limits: .standard))
    }

    func testEmptyDocumentStillWritesInfoAndAssetsDirectory() throws {
        let package = FlorettaTextBundleCodec.export(MindMapDocument(title: "空"))
        XCTAssertEqual(package.textMarkdown, "")
        XCTAssertEqual(package.files.map(\.path).sorted(), ["info.json", "text.md"])
        try assertInfo(package)
        let root = try makeBundleDirectory("Empty.textbundle")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try package.writeDirectory(to: root)
        var isDirectory = ObjCBool(false)
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: assets.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: assets.path), [])
        let names = try ZipArchive.entryNames(package.textpack())
        XCTAssertTrue(names.contains("assets/"))
        XCTAssertTrue(names.contains("info.json"))
        XCTAssertTrue(names.contains("text.md"))
    }

    func testDirectoryExportWritesTextInfoAssetsAndPreservesAttachmentHash() throws {
        let (document, assets) = attachmentDocument()
        let package = FlorettaTextBundleCodec.export(document, assets: assets)
        let root = try makeBundleDirectory("WithAssets.textbundle")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        try package.writeDirectory(to: root)
        let markdown = try Data(contentsOf: root.appendingPathComponent("text.md"))
        let info = try Data(contentsOf: root.appendingPathComponent("info.json"))
        let asset = try Data(contentsOf: root.appendingPathComponent("assets/photo.png"))
        let assetNames = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("assets").path)

        XCTAssertEqual(markdown, package.data(at: "text.md"))
        XCTAssertEqual(info, package.data(at: "info.json"))
        XCTAssertEqual(asset, pngBytes)
        XCTAssertEqual(sha256Hex(asset), sha256Hex(pngBytes))
        XCTAssertTrue(String(decoding: markdown, as: UTF8.self).contains("assets/photo.png"))
        XCTAssertTrue(assetNames.contains("photo.png"))
    }

    func testDirectoryExportWithoutAttachmentsCreatesEmptyAssetsFolder() throws {
        let package = FlorettaTextBundleCodec.export(simpleDocument())
        let root = try makeBundleDirectory("NoAssets.textbundle")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        try package.writeDirectory(to: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("text.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("info.json").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("assets").path), [])
    }

    func testAssetLinesFollowNotesWithoutDroppingCodecLines() {
        let hash = sha256Hex(pngBytes)
        let attachment = NodeAttachment(
            sha256: hash,
            fileExtension: "png",
            byteCount: Int64(pngBytes.count),
            filename: "photo.png"
        )
        let document = MindMapDocument(
            title: "对齐",
            roots: [
                MindMapNode(
                    text: "分区",
                    note: "甲\r\n乙",
                    attachments: [attachment],
                    children: [
                        MindMapNode(text: "子", attachments: [attachment]),
                    ],
                    isMarkdownSectionHeading: true
                ),
            ],
            markdownFrontMatter: "---\r\nkeep: yes\r\n---\r\n"
        )
        let package = FlorettaTextBundleCodec.export(document, assets: [
            FlorettaAsset(sha256: hash, fileExtension: "png", data: pngBytes),
        ])
        assertCodecLinesPreserved(document, markdown: package.textMarkdown)
        XCTAssertEqual(
            package.textMarkdown,
            """
            ---
            keep: yes
            ---

            # 分区
            > 甲
            > 乙
            ![photo.png](assets/photo.png)
            - 子
              ![photo.png](assets/photo.png)

            """
        )
        XCTAssertEqual(package.data(at: "assets/photo.png"), pngBytes)
    }

    func testFirstAssetBytesWinForOneHash() {
        let hash = sha256Hex(pngBytes)
        let document = MindMapDocument(
            title: "重复",
            roots: [
                MindMapNode(
                    text: "根",
                    attachments: [
                        NodeAttachment(sha256: hash, fileExtension: "png", byteCount: Int64(pngBytes.count), filename: "photo.png"),
                    ]
                ),
            ]
        )
        let package = FlorettaTextBundleCodec.export(document, assets: [
            FlorettaAsset(sha256: hash, fileExtension: "png", data: pngBytes),
            FlorettaAsset(sha256: hash, fileExtension: "png", data: Data("other".utf8)),
        ])
        XCTAssertEqual(package.data(at: "assets/photo.png"), pngBytes)
    }

    func testFieldCatalogMatchesTheInRepoTable() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/TEXTBUNDLE-FIELDS.md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(TextBundleFieldCatalog.rows.isEmpty)
        var seen: Set<String> = []
        for fixture in TextBundleFieldCatalog.fixtures {
            XCTAssertTrue(markdown.contains(fixture.directory), fixture.directory)
            XCTAssertTrue(seen.insert(fixture.name).inserted)
        }
        XCTAssertEqual(seen, ["simple", "nested", "attachments"])
        for row in TextBundleFieldCatalog.rows {
            let line = "| `\(row.field)` | \(row.disposition.rawValue) |"
            XCTAssertTrue(markdown.contains(line), line)
        }
        XCTAssertTrue(TextBundleFieldCatalog.rows.contains { $0.disposition == .mapped })
        XCTAssertTrue(TextBundleFieldCatalog.rows.contains { $0.disposition == .gap })
        XCTAssertFalse(TextBundleFieldCatalog.rows.contains { $0.disposition.rawValue == "passthrough" })
    }

    func testExportThousandNodesWithinBudget() {
        var roots: [MindMapNode] = []
        roots.reserveCapacity(1_000)
        for index in 0..<1_000 {
            roots.append(MindMapNode(text: "n\(index)"))
        }
        let document = MindMapDocument(title: "宽", roots: roots)
        _ = FlorettaTextBundleCodec.export(document)
        let clock = ContinuousClock()
        let start = clock.now
        let package = FlorettaTextBundleCodec.export(document)
        let elapsed = start.duration(to: clock.now)
        XCTAssertEqual(package.textMarkdown.split(separator: "\n").count, 1_000)
        XCTAssertTrue(package.textMarkdown.contains("- n999"))
        XCTAssertLessThan(elapsed, .milliseconds(1500), "export of 1000 nodes took \(elapsed)")
    }

    private func simpleDocument() -> MindMapDocument {
        MindMapDocument(
            title: "简单",
            roots: [
                MindMapNode(
                    text: "根",
                    note: "备注",
                    children: [
                        MindMapNode(text: "子", link: "https://example.com/a"),
                    ]
                ),
            ]
        )
    }

    private func nestedDocument() -> MindMapDocument {
        MindMapDocument(
            title: "嵌套",
            roots: [
                MindMapNode(
                    text: "分区",
                    children: [
                        MindMapNode(
                            text: "甲",
                            children: [
                                MindMapNode(
                                    text: "甲一",
                                    children: [
                                        MindMapNode(text: "甲一一"),
                                    ]
                                ),
                            ]
                        ),
                        MindMapNode(text: "乙"),
                    ],
                    isMarkdownSectionHeading: true
                ),
            ],
            markdownFrontMatter: "---\nkeep: yes\n---"
        )
    }

    private func attachmentDocument() -> (MindMapDocument, [FlorettaAsset]) {
        let pngHash = sha256Hex(pngBytes)
        let pdfHash = sha256Hex(pdfBytes)
        let png2Hash = sha256Hex(png2Bytes)
        let gif = Data("GIF89a-float".utf8)
        let sheet = Data("sheet-asset".utf8)
        let gifHash = sha256Hex(gif)
        let sheetHash = sha256Hex(sheet)
        let missing = String(repeating: "ab", count: 32)
        let rootID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let childID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let child = MindMapNode(
            id: childID,
            text: "子",
            note: "看图",
            link: "https://example.com/x",
            side: .left,
            attachments: [
                NodeAttachment(sha256: pngHash, fileExtension: "png", byteCount: Int64(pngBytes.count), filename: "photo.png"),
                NodeAttachment(sha256: png2Hash, fileExtension: "png", byteCount: Int64(png2Bytes.count), filename: "photo.png"),
            ],
            children: [
                MindMapNode(text: "孙"),
            ]
        )
        let root = MindMapNode(
            id: rootID,
            text: "根",
            isCollapsed: true,
            style: MindMapNodeStyle(colorHex: "FF00AA"),
            attachments: [
                NodeAttachment(sha256: pngHash, fileExtension: "png", byteCount: Int64(pngBytes.count), filename: "photo.png"),
                NodeAttachment(sha256: missing, fileExtension: "png", byteCount: 4, filename: "gone.png"),
                NodeAttachment(sha256: pdfHash, fileExtension: "pdf", byteCount: Int64(pdfBytes.count), filename: "notes.pdf"),
            ],
            children: [child]
        )
        let document = MindMapDocument(
            title: "附件图",
            roots: [root],
            freeNodes: [
                MindMapNode(
                    text: "浮动",
                    position: MindMapPoint(x: 12, y: 24),
                    attachments: [
                        NodeAttachment(sha256: gifHash, fileExtension: "gif", byteCount: Int64(gif.count), filename: "float.gif"),
                    ]
                ),
            ],
            relationships: [
                TopicRelationship(sourceID: rootID, targetID: childID, title: "关系甲"),
            ],
            stickies: [
                StickyNote(text: "便签一", origin: MindMapPoint(x: 0, y: 0)),
            ],
            markdownFrontMatter: "---\nkind: map\n---",
            additionalCanvases: [
                MindMapCanvas(
                    title: "第二张",
                    roots: [
                        MindMapNode(
                            text: "另页",
                            attachments: [
                                NodeAttachment(sha256: sheetHash, fileExtension: "txt", byteCount: Int64(sheet.count), filename: "sheet.txt"),
                            ]
                        ),
                    ]
                ),
            ]
        )
        let assets = [
            FlorettaAsset(sha256: pngHash, fileExtension: "png", data: pngBytes),
            FlorettaAsset(sha256: pdfHash, fileExtension: "pdf", data: pdfBytes),
            FlorettaAsset(sha256: png2Hash, fileExtension: "png", data: png2Bytes),
            FlorettaAsset(sha256: gifHash, fileExtension: "gif", data: gif),
            FlorettaAsset(sha256: sheetHash, fileExtension: "txt", data: sheet),
        ]
        return (document, assets)
    }

    private var pngBytes: Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])
    }

    private var pdfBytes: Data {
        Data("%PDF-1.1\n".utf8)
    }

    private var png2Bytes: Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x99])
    }

    private func dictionary(_ package: TextBundlePackage) -> [String: Data] {
        Dictionary(uniqueKeysWithValues: package.files.map { ($0.path, $0.data) })
    }

    private func loadFixture(_ name: String) throws -> [String: Data] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/TextBundle")
            .appendingPathComponent(name, isDirectory: true)
        var files: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            XCTFail("missing fixture \(name)")
            return [:]
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            files[relative] = try Data(contentsOf: url)
        }
        return files
    }

    private func assertInfo(_ package: TextBundlePackage) throws {
        let data = try XCTUnwrap(package.data(at: "info.json"))
        XCTAssertEqual(String(data: data, encoding: .utf8), FlorettaTextBundleCodec.infoJSON + "\n")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let version = try XCTUnwrap(object["version"] as? NSNumber)
        XCTAssertNotEqual(CFGetTypeID(version), CFBooleanGetTypeID())
        XCTAssertEqual(version.intValue, 2)
        XCTAssertEqual(object["type"] as? String, FlorettaTextBundleCodec.markdownUTI)
        let transient = try XCTUnwrap(object["transient"] as? NSNumber)
        XCTAssertEqual(CFGetTypeID(transient), CFBooleanGetTypeID())
        XCTAssertFalse(transient.boolValue)
        XCTAssertEqual(object["creatorIdentifier"] as? String, FlorettaTextBundleCodec.creatorIdentifier)
        XCTAssertEqual(object["creatorURL"] as? String, FlorettaTextBundleCodec.creatorURL)
        XCTAssertNil(object["sourceURL"])
        XCTAssertNil(object[FlorettaTextBundleCodec.creatorIdentifier])
        XCTAssertEqual(Set(object.keys), ["version", "type", "transient", "creatorURL", "creatorIdentifier"])
    }

    private func assertDirectoryRoundTrip(_ package: TextBundlePackage, extensionName: String) throws {
        let root = try makeBundleDirectory("Sample.\(extensionName)")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try package.writeDirectory(to: root)
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("assets", isDirectory: true).path,
            isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue)
        for file in package.files {
            let url = root.appendingPathComponent(file.path)
            XCTAssertEqual(try Data(contentsOf: url), file.data, file.path)
        }
    }

    private func assertTextpackRoundTrip(_ package: TextBundlePackage) throws {
        let packed = package.textpack()
        let names = try ZipArchive.entryNames(packed)
        XCTAssertTrue(names.contains("assets/"))
        for file in package.files {
            XCTAssertTrue(names.contains(file.path), file.path)
        }
        let entries = try ZipArchive.read(packed, limits: .standard)
        for file in package.files {
            XCTAssertEqual(entries.first { $0.name == file.path }?.data, file.data, file.path)
        }
    }

    private func makeBundleDirectory(_ name: String) throws -> URL {
        let parent = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("floretta-textbundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return parent.appendingPathComponent(name, isDirectory: true)
    }

    private func assertCodecLinesPreserved(_ document: MindMapDocument, markdown: String) {
        XCTAssertEqual(strippedAssetLines(markdown), lines(FlorettaMarkdownDocumentCodec.save(document)))
    }

    private func strippedAssetLines(_ markdown: String) -> [String] {
        lines(markdown).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isAsset = (trimmed.hasPrefix("![") || trimmed.hasPrefix("[")) && trimmed.contains("](assets/")
            return !isAsset
        }
    }

    private func assetLines(in markdown: String) -> [String] {
        lines(markdown).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return (trimmed.hasPrefix("![") || trimmed.hasPrefix("[")) && trimmed.contains("](assets/")
        }
    }

    private func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n"), parts.last?.isEmpty == true {
            parts.removeLast()
        }
        return parts
    }
}

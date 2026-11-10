import FlorettaCore
import XCTest

final class AIAdaptationTests: XCTestCase {
    private let created = Date(timeIntervalSince1970: 1_700_000_000)

    func testRootPathIsTheSecondChildOfTheFourthRoot() throws {
        let session = try markdownSession(sampleList())
        XCTAssertEqual(try session.get(.text, at: "root/3/1"), "d1")
        XCTAssertEqual(try session.get(.text, at: "root/3/1/0"), "d1a")
        XCTAssertEqual(try session.get(.text, at: "root/0"), "a")
        XCTAssertEqual(FlorettaNodePath.parse("root/3/1")?.description, "root/3/1")
        let id = try session.document.node(at: FlorettaNodePath(indexes: [3, 1])).id
        XCTAssertEqual(session.address(of: id), "root/3/1")
        XCTAssertNotEqual(session.address(of: id), id.uuidString)
        XCTAssertFalse(session.tree().contains(id.uuidString))
    }

    func testPathFailuresAndRecomputeAfterInsertDeleteAndMove() throws {
        var session = try markdownSession(sampleList())
        XCTAssertThrowsError(try session.get(.text, at: "root"))
        XCTAssertThrowsError(try session.get(.text, at: "root/3/9"))
        XCTAssertThrowsError(try session.get(.text, at: "root/4"))
        XCTAssertThrowsError(try session.get(.text, at: "root/3/1/2"))
        XCTAssertThrowsError(try session.get(.text, at: "root/-1"))
        XCTAssertThrowsError(try session.get(.text, at: "root/01"))
        XCTAssertThrowsError(try session.get(.text, at: "3/1"))
        XCTAssertThrowsError(try session.get(.text, at: "ROOT/3/1"))
        XCTAssertNil(FlorettaNodePath.parse("root/"))
        XCTAssertNil(FlorettaNodePath.parse("root//1"))

        let stale = session.document.roots[3].children[1].id
        XCTAssertThrowsError(try session.get(.text, at: stale.uuidString)) { error in
            XCTAssertEqual(
                error as? FlorettaAIError,
                .message("Markdown 模式没有稳定节点 UUID。临时 UUID 不能当作路径。请用 root/3/1，并在插入、删除或移动后重算。")
            )
        }

        let inserted = try session.insertSibling(after: "root/3/0", text: "新")
        XCTAssertEqual(inserted, "root/3/1")
        XCTAssertFalse(inserted.contains("-"))
        XCTAssertEqual(try session.get(.text, at: "root/3/1"), "新")
        XCTAssertEqual(try session.get(.text, at: "root/3/2"), "d1")

        try session.delete(at: "root/0")
        XCTAssertThrowsError(try session.get(.text, at: "root/3/2")) { error in
            XCTAssertTrue(String(describing: error).contains("重算"))
        }
        XCTAssertEqual(try session.get(.text, at: "root/2/2"), "d1")

        var moved = try markdownSession(sampleList())
        let address = try moved.move(from: "root/3/1", to: "root")
        XCTAssertEqual(address, "root/4")
        XCTAssertEqual(try moved.get(.text, at: address), "d1")
        XCTAssertThrowsError(try moved.get(.text, at: "root/3/1"))
        XCTAssertThrowsError(try moved.move(from: "root/0", to: "root/0"))
    }

    func testMarkdownAllowsTextNoteLinkAndRefusesTheRest() throws {
        var session = try markdownSession("- [标题](https://example.com)\n> 一行\n> 两行\n")
        XCTAssertEqual(try session.get(.text, at: "root/0"), "标题")
        XCTAssertEqual(try session.get(.link, at: "root/0"), "https://example.com")
        XCTAssertEqual(try session.get(.note, at: "root/0"), "一行\n两行")

        XCTAssertEqual(try session.set(.text, at: "root/0", value: "改"), "root/0")
        XCTAssertEqual(try session.set(.note, at: "root/0", value: "备注"), "root/0")
        XCTAssertEqual(try session.set(.link, at: "root/0", value: "https://floretta.test/a"), "root/0")
        let child = try session.insertChild(under: "root/0", text: "子")
        XCTAssertEqual(child, "root/0/0")
        let sibling = try session.insertSibling(after: "root/0", text: "弟")
        XCTAssertEqual(sibling, "root/1")
        XCTAssertEqual(try session.get(.text, at: "root/1"), "弟")

        let fields: [(FlorettaAIField, String)] = [
            (.color, FlorettaMarkdownRefusal.color),
            (.style, FlorettaMarkdownRefusal.color),
            (.attachment, FlorettaMarkdownRefusal.attachment),
            (.relationship, FlorettaMarkdownRefusal.relationship),
            (.position, FlorettaMarkdownRefusal.position),
            (.side, FlorettaMarkdownRefusal.side),
            (.isCollapsed, FlorettaMarkdownRefusal.collapsed),
        ]
        for (field, message) in fields {
            XCTAssertThrowsError(try session.get(field, at: "root/0")) { error in
                XCTAssertEqual(error as? FlorettaAIError, .refused(message))
            }
            XCTAssertThrowsError(try session.set(field, at: "root/0", value: "#112233")) { error in
                XCTAssertEqual(error as? FlorettaAIError, .refused(message))
            }
        }
        XCTAssertNil(session.document.roots[0].style)
        XCTAssertTrue(session.document.roots[0].attachments.isEmpty)
        XCTAssertTrue(session.document.relationships.isEmpty)
        XCTAssertNil(session.document.roots[0].position)
        XCTAssertNil(session.document.roots[0].side)
        XCTAssertFalse(session.document.roots[0].isCollapsed)

        let saved = FlorettaMarkdownDocumentCodec.save(session.document)
        XCTAssertFalse(saved.contains(session.document.roots[0].id.uuidString))
        XCTAssertFalse(saved.contains("#112233"))
        let again = try FlorettaMarkdownDocumentCodec.open(saved)
        XCTAssertEqual(again.document.roots[0].text, "改")
        XCTAssertEqual(again.document.roots[0].note, "备注")
        XCTAssertEqual(again.document.roots[0].link, "https://floretta.test/a")
        XCTAssertEqual(again.document.roots[0].children[0].text, "子")
        XCTAssertEqual(again.document.roots[1].text, "弟")
    }

    func testFlorettaUsesUUIDAndCanWriteFieldsMarkdownRefuses() throws {
        var session = FlorettaAISession(document: forest(), mode: .floretta, container: .florettaZip)
        let target = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA5"
        XCTAssertEqual(try session.document.node(at: FlorettaNodePath(indexes: [3, 1])).id.uuidString, target)
        XCTAssertThrowsError(try session.get(.text, at: "root/3/1")) { error in
            XCTAssertTrue(String(describing: error).contains("UUID"))
        }
        XCTAssertEqual(try session.get(.text, at: target), "d1")
        XCTAssertEqual(session.address(of: UUID(uuidString: target)!), target)
        XCTAssertFalse(session.tree().contains("root/"))
        XCTAssertTrue(session.tree().contains(target))

        XCTAssertEqual(try session.set(.text, at: target, value: "改"), target)
        XCTAssertEqual(try session.set(.color, at: target, value: "#112233"), target)
        XCTAssertEqual(try session.set(.style, at: target, value: "aabbcc"), target)
        XCTAssertEqual(try session.set(.position, at: target, value: "1.5,-2"), target)
        XCTAssertEqual(try session.set(.side, at: target, value: "left"), target)
        XCTAssertEqual(try session.set(.isCollapsed, at: target, value: "true"), target)
        let anchor = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA0"
        XCTAssertEqual(try session.set(.relationship, at: anchor, value: target + "\t连线"), anchor)

        let node = try XCTUnwrap(session.document.node(UUID(uuidString: target)!))
        XCTAssertEqual(node.text, "改")
        XCTAssertEqual(node.style?.colorHex, "#112233")
        XCTAssertEqual(node.style?.fillHex, "#AABBCC")
        XCTAssertEqual(node.position, MindMapPoint(x: 1.5, y: -2))
        XCTAssertEqual(node.side, .left)
        XCTAssertTrue(node.isCollapsed)
        XCTAssertEqual(session.document.relationships.count, 1)

        XCTAssertThrowsError(try session.set(.attachment, at: target, value: "x")) { error in
            XCTAssertEqual(
                error as? FlorettaAIError,
                .message("附件字节属于 .floretta 容器，不能当作节点字段写入。")
            )
            XCTAssertNotEqual(
                (error as? FlorettaAIError)?.errorDescription,
                FlorettaMarkdownRefusal.attachment
            )
        }

        let added = try session.insertChild(under: target, text: "子")
        XCTAssertNotEqual(added, "root/3/1/0")
        XCTAssertNotNil(UUID(uuidString: added))
        XCTAssertEqual(try session.get(.text, at: added), "子")
    }

    func testTreeNodeAddAndExportCommands() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("map.md")
        let original = sampleList()
        try FileHandleStreamingFiles().write(Data(original.utf8), to: file)
        let files = FileHandleStreamingFiles()

        let listed = FlorettaCommandLine.run(["floretta", "tree", file.path])
        XCTAssertEqual(listed.exitCode, 0, listed.stderr)
        XCTAssertEqual(listed.stdout, """
        root/0	a
        root/1	b
        root/2	c
        root/3	d
          root/3/0	d0
          root/3/1	d1
            root/3/1/0	d1a
        """ + "\n")
        let shallow = FlorettaCommandLine.run(["floretta", "tree", file.path, "--depth", "1"])
        XCTAssertEqual(shallow.exitCode, 0, shallow.stderr)
        XCTAssertFalse(shallow.stdout.contains("root/3/1"))
        XCTAssertTrue(shallow.stdout.contains("root/3\td"))

        let added = FlorettaCommandLine.run([
            "floretta", "node", "add", file.path,
            "--parent", "root/3/1",
            "--text", "新",
            "--note", "记",
            "--link", "https://example.com/n",
        ])
        XCTAssertEqual(added.exitCode, 0, added.stderr)
        XCTAssertEqual(added.stdout, "root/3/1/1\n")
        let opened = try FlorettaAIProjectFile.open(file, files: files)
        XCTAssertEqual(try opened.get(.text, at: "root/3/1"), "d1")
        XCTAssertEqual(try opened.get(.text, at: "root/3/1/1"), "新")
        XCTAssertEqual(try opened.get(.note, at: "root/3/1/1"), "记")
        XCTAssertEqual(try opened.get(.link, at: "root/3/1/1"), "https://example.com/n")
        XCTAssertEqual(try files.read(from: file), Data(FlorettaMarkdownDocumentCodec.save(opened.document).utf8))

        let beforeExport = try files.read(from: file)
        let exported = FlorettaCommandLine.run(["floretta", "export", file.path])
        XCTAssertEqual(exported.exitCode, 0, exported.stderr)
        XCTAssertEqual(exported.stdout, opened.exportHeadingMarkdown())
        XCTAssertEqual(exported.stdout, FlorettaMarkdown.export(opened.document))
        XCTAssertNotEqual(exported.stdout, FlorettaMarkdownDocumentCodec.save(opened.document))
        XCTAssertTrue(exported.stdout.contains("### "))
        XCTAssertEqual(try files.read(from: file), beforeExport)

        let documentExport = FlorettaCommandLine.run(["floretta", "export", file.path, "--format", "document"])
        XCTAssertEqual(documentExport.exitCode, 0, documentExport.stderr)
        XCTAssertEqual(documentExport.stdout, FlorettaMarkdownDocumentCodec.save(opened.document))
        XCTAssertEqual(try files.read(from: file), beforeExport)

        let refused = FlorettaCommandLine.run([
            "floretta", "node", "set", file.path, "root/3/1",
            "--field", "color", "--value", "#112233",
        ])
        XCTAssertNotEqual(refused.exitCode, 0)
        XCTAssertTrue(refused.stderr.contains(FlorettaMarkdownRefusal.color))
        XCTAssertEqual(try files.read(from: file), beforeExport)

        let sibling = FlorettaCommandLine.run([
            "floretta", "node", "add", file.path, "--after", "root/0", "--text", "插",
        ])
        XCTAssertEqual(sibling.exitCode, 0, sibling.stderr)
        XCTAssertEqual(sibling.stdout, "root/1\n")
        let shifted = try FlorettaAIProjectFile.open(file, files: files)
        XCTAssertEqual(try shifted.get(.text, at: "root/1"), "插")
        XCTAssertEqual(try shifted.get(.text, at: "root/2"), "b")
        XCTAssertThrowsError(try shifted.get(.text, at: "root/3/1/1"))
    }

    func testMarkdownOpenSaveUsesTheDocumentCodecAndFlorettaUsesStreaming() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = FileHandleStreamingFiles()

        let markdown = directory.appendingPathComponent("notes.md")
        let source = "---\nkeep: yes\n---\n\n- 根\n"
        try files.write(Data(source.utf8), to: markdown)
        var session = try FlorettaAIProjectFile.open(markdown, files: files)
        XCTAssertEqual(session.container, .markdown)
        _ = try session.set(.text, at: "root/0", value: "改过")
        try FlorettaAIProjectFile.save(session, to: markdown, files: files)
        let saved = try files.read(from: markdown)
        let reopened = try FlorettaMarkdownDocumentCodec.open(saved)
        XCTAssertEqual(reopened.document.markdownFrontMatter?.contains("keep: yes"), true)
        XCTAssertEqual(reopened.document.roots[0].text, "改过")
        XCTAssertEqual(String(decoding: saved, as: UTF8.self), FlorettaMarkdownDocumentCodec.save(reopened.document))
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("# 改过"))

        let rejected = directory.appendingPathComponent("heading.md")
        try files.write(Data("## 不行\n".utf8), to: rejected)
        XCTAssertThrowsError(try FlorettaAIProjectFile.open(rejected, files: files)) { error in
            XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("第 1 行") == true)
        }

        let project = directory.appendingPathComponent("map.floretta")
        let document = forest()
        try FlorettaStreamingDocument.save(document: document, to: project, files: files)
        let opened = try FlorettaAIProjectFile.open(project, files: files)
        XCTAssertEqual(opened.mode, .floretta)
        XCTAssertEqual(opened.container, .florettaZip)
        let reader = try files.openReader(at: project)
        let streamed = try FlorettaStreamingDocument.open(reader)
        try reader.close()
        XCTAssertEqual(opened.document.roots.map(\.text), streamed.document.roots.map(\.text))
        let id = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA5"
        let edited = FlorettaCommandLine.run([
            "floretta", "node", "set", project.path, id, "--field", "note", "--value", "工程备注",
        ])
        XCTAssertEqual(edited.exitCode, 0, edited.stderr)
        XCTAssertEqual(edited.stdout, id + "\n")
        let after = try FlorettaAIProjectFile.open(project, files: files)
        XCTAssertEqual(try after.get(.note, at: id), "工程备注")
        let pathAttempt = FlorettaCommandLine.run([
            "floretta", "node", "get", project.path, "root/3/1", "--field", "text",
        ])
        XCTAssertNotEqual(pathAttempt.exitCode, 0)
        XCTAssertTrue(pathAttempt.stderr.contains("UUID"))

        let legacy = directory.appendingPathComponent("legacy.floretta")
        let legacyBytes = try FlorettaCodec.encode(document)
        try files.write(legacyBytes, to: legacy)
        let legacyOpened = try FlorettaAIProjectFile.open(legacy, files: files)
        XCTAssertEqual(legacyOpened.container, .florettaLegacy)
        XCTAssertEqual(try legacyOpened.get(.text, at: id), "d1")
        let legacyWrite = FlorettaCommandLine.run([
            "floretta", "node", "set", legacy.path, id, "--field", "text", "--value", "不行",
        ])
        XCTAssertNotEqual(legacyWrite.exitCode, 0)
        XCTAssertTrue(legacyWrite.stderr.contains("plain JSON"))
        XCTAssertEqual(try files.read(from: legacy), legacyBytes)
    }

    func testMCPListsToolsAndRefusesMarkdownColor() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("map.md")
        try FileHandleStreamingFiles().write(Data(sampleList().utf8), to: file)

        let initialize = FlorettaMCP.exchange(Data(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}"#.utf8
        ))
        let initializeText = String(decoding: initialize, as: UTF8.self)
        XCTAssertTrue(initializeText.contains("\"name\":\"floretta\""))
        XCTAssertFalse(initializeText.lowercased().contains("http"))
        XCTAssertFalse(initializeText.lowercased().contains("socket"))

        let listed = try call(method: "tools/list", id: 2, params: [:])
        for name in ["tree", "node_add", "export", "node_get", "node_set", "node_delete", "node_move"] {
            XCTAssertTrue(listed.contains("\"name\":\"\(name)\""), name)
        }

        let added = try call(method: "tools/call", id: 3, params: [
            "name": "node_add",
            "arguments": ["path": file.path, "parent": "root/3/1", "text": "来自 MCP"],
        ])
        XCTAssertTrue(added.contains("root/3/1/1"))
        XCTAssertFalse(added.contains("\"isError\":true"))
        let opened = try FlorettaAIProjectFile.open(file)
        XCTAssertEqual(try opened.get(.text, at: "root/3/1/1"), "来自 MCP")

        let refused = try call(method: "tools/call", id: 4, params: [
            "name": "node_set",
            "arguments": [
                "path": file.path,
                "address": "root/0",
                "field": "style",
                "value": "#112233",
            ],
        ])
        let refusal = try toolPayload(refused)
        XCTAssertTrue(refusal.isError)
        XCTAssertTrue(refusal.text.contains(FlorettaMarkdownRefusal.color))
        let afterRefusal = try FlorettaAIProjectFile.open(file)
        XCTAssertNil(afterRefusal.document.roots[0].style)

        let framedBody = Data(
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"export","arguments":{"path":"\#(file.path)","format":"markdown"}}}"#.utf8
        )
        var framed = Data("Content-Length: \(framedBody.count)\r\n\r\n".utf8)
        framed.append(framedBody)
        let exported = String(decoding: FlorettaMCP.exchange(framed), as: UTF8.self)
        XCTAssertTrue(exported.contains("### "))
        XCTAssertFalse(exported.contains("\"isError\":true"))
        XCTAssertEqual(try Data(contentsOf: file), Data(FlorettaMarkdownDocumentCodec.save(opened.document).utf8))
    }

    func testCommandHelpAndMCPDoesNotServeInsideRun() {
        let help = FlorettaCommandLine.run(["floretta", "help"])
        XCTAssertEqual(help.exitCode, 0)
        XCTAssertTrue(help.stdout.contains("floretta tree"))
        XCTAssertTrue(help.stdout.contains("floretta node add"))
        XCTAssertTrue(help.stdout.contains("floretta export"))
        XCTAssertTrue(help.stdout.contains("不监听网络"))
        let mcp = FlorettaCommandLine.run(["floretta", "mcp"])
        XCTAssertEqual(mcp.exitCode, 0)
        XCTAssertTrue(mcp.servesMCP)
        XCTAssertEqual(mcp.stdout, "")
    }

    private func sampleList() -> String {
        """
        - a
        - b
        - c
        - d
          - d0
          - d1
            - d1a

        """
    }

    private func markdownSession(_ text: String) throws -> FlorettaAISession {
        let opened = try FlorettaMarkdownDocumentCodec.open(text)
        return FlorettaAISession(
            document: opened.document,
            mode: .markdown,
            container: .markdown,
            markdownWarnings: opened.warnings
        )
    }

    private func forest() -> MindMapDocument {
        func node(_ suffix: String, _ text: String, _ children: [MindMapNode] = []) -> MindMapNode {
            MindMapNode(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA\(suffix)")!,
                text: text,
                children: children
            )
        }
        return MindMapDocument(
            title: "工程",
            createdAt: created,
            modifiedAt: created,
            roots: [
                node("0", "a"),
                node("1", "b"),
                node("2", "c"),
                node("3", "d", [
                    node("4", "d0"),
                    node("5", "d1", [
                        node("6", "d1a"),
                    ]),
                ]),
            ]
        )
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("floretta-ai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func toolPayload(_ framed: String) throws -> (isError: Bool, text: String) {
        let data = Data(framed.utf8)
        guard let marker = data.range(of: Data("\r\n\r\n".utf8)) else {
            XCTFail("MCP response has no Content-Length frame")
            return (true, framed)
        }
        let object = try JSONSerialization.jsonObject(with: Data(data[marker.upperBound...])) as? [String: Any]
        let result = object?["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        return (result?["isError"] as? Bool ?? false, content?.first?["text"] as? String ?? "")
    }

    private func call(method: String, id: Int, params: [String: Any]) throws -> String {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return String(decoding: FlorettaMCP.exchange(data), as: UTF8.self)
    }
}

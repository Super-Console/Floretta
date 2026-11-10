import FlorettaCore
import XCTest

/// The inspector's sections stay the ones the document already has, and each
/// control writes through `InspectorStyle` / `InspectorMarkField` rather than
/// view state. The source check locks the system controls around those calls.
final class InspectorStyleTests: XCTestCase {
    private let rootID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let childID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let otherID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    private let linkID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
    private let farLinkID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
    private let summaryID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    private let boundaryID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func testTopicSectionWritesShapeFillAndWidth() throws {
        var document = map()
        XCTAssertEqual(InspectorStyle.shape(of: nil), .rounded)
        XCTAssertEqual(InspectorStyle.fillStyleValue(of: nil), "solid")
        XCTAssertEqual(InspectorStyle.topicWidthValue(of: nil), 120)

        XCTAssertTrue(apply(.shape(.rectangle), to: &document))
        XCTAssertEqual(style(in: document)?.cornerRadius, 2)
        XCTAssertEqual(InspectorStyle.shape(of: style(in: document)), .rectangle)

        XCTAssertTrue(apply(.shape(.none), to: &document))
        XCTAssertEqual(style(in: document)?.cornerRadius, 0)
        XCTAssertEqual(style(in: document)?.borderWidth, 0)
        XCTAssertEqual(style(in: document)?.borderStyle, "none")
        XCTAssertEqual(InspectorStyle.shape(of: style(in: document)), .none)

        XCTAssertTrue(apply(.shape(.capsule), to: &document))
        XCTAssertEqual(style(in: document)?.cornerRadius, 40)
        XCTAssertEqual(style(in: document)?.borderStyle, "none", "A shape change does not invent a border")
        XCTAssertEqual(InspectorStyle.shape(of: style(in: document)), .capsule)

        var borderless = MindMapNodeStyle(colorHex: "#000000", borderWidth: 0, cornerRadius: 8)
        borderless.borderStyle = "none"
        XCTAssertEqual(InspectorStyle.shape(of: borderless), .rounded)

        XCTAssertTrue(apply(.fillStyle(.none), to: &document))
        XCTAssertEqual(style(in: document)?.fillStyle, "none")
        XCTAssertTrue(apply(.fillHex("#E23D3D"), to: &document))
        XCTAssertEqual(style(in: document)?.fillHex, "#E23D3D")
        XCTAssertEqual(style(in: document)?.colorHex, "#E23D3D")
        XCTAssertEqual(style(in: document)?.fillStyle, "solid")
        XCTAssertTrue(apply(.topicWidth(183), to: &document))
        XCTAssertEqual(style(in: document)?.topicWidth, 183)

        let saved = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(saved.node(rootID)?.style?.fillHex, "#E23D3D")
        XCTAssertEqual(saved.node(rootID)?.style?.topicWidth, 183)
        XCTAssertEqual(saved.node(rootID)?.style?.cornerRadius, 40)
        let frame = try XCTUnwrap(LayoutEngine().layout(saved).first { $0.id == rootID })
        let color = try XCTUnwrap(BranchColor(hex: "#E23D3D"))
        XCTAssertEqual(frame.fill.red, color.red, accuracy: 0.001)
        XCTAssertEqual(frame.cornerRadius, 40, accuracy: 0.001)

        var free = document
        let freeID = free.addFreeNode(text: "自由", at: MindMapPoint(x: 4, y: 8))
        XCTAssertTrue(InspectorStyle.apply(.topicWidth(80), nodeID: freeID, document: &free, allowsAppearanceWrites: true))
        XCTAssertEqual(free.node(freeID)?.style?.topicWidth, 80)
    }

    func testBorderSectionWritesStyleWidthAndColor() throws {
        var document = map()
        XCTAssertEqual(InspectorStyle.borderStyleValue(of: nil), "solid")
        XCTAssertEqual(InspectorStyle.borderWidthValue(of: nil), 1.5)
        XCTAssertEqual(InspectorStyle.borderWidthReadout(of: nil), .points(1.5))

        XCTAssertTrue(apply(.borderStyle(.none), to: &document))
        XCTAssertEqual(style(in: document)?.borderStyle, "none")
        XCTAssertEqual(style(in: document)?.borderWidth, 0)
        XCTAssertEqual(InspectorStyle.borderWidthReadout(of: style(in: document)), .none)

        XCTAssertTrue(apply(.borderWidth(3), to: &document))
        XCTAssertEqual(style(in: document)?.borderWidth, 3)
        XCTAssertEqual(style(in: document)?.borderStyle, "solid")
        XCTAssertEqual(InspectorStyle.borderWidthReadout(of: style(in: document)), .points(3))

        XCTAssertTrue(apply(.borderWidth(0), to: &document))
        XCTAssertEqual(style(in: document)?.borderStyle, "none")
        XCTAssertEqual(InspectorStyle.borderWidthReadout(of: style(in: document)), .none)

        XCTAssertTrue(apply(.borderHex("#112233"), to: &document))
        XCTAssertEqual(style(in: document)?.borderHex, "#112233")
        let saved = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(saved.node(rootID)?.style?.borderHex, "#112233")
        XCTAssertEqual(saved.node(rootID)?.style?.borderWidth, 0)
    }

    func testTextSectionWritesFontFlagsSizeAndColor() throws {
        var document = map()
        XCTAssertEqual(InspectorStyle.fontDesignValue(of: nil), "default")
        XCTAssertEqual(InspectorStyle.fontSizeValue(of: nil), 18)
        XCTAssertFalse(InspectorStyle.isOn(.bold, style: nil))

        XCTAssertTrue(apply(.fontDesign(.serif), to: &document))
        XCTAssertTrue(apply(.flag(.bold, true), to: &document))
        XCTAssertTrue(apply(.flag(.italic, true), to: &document))
        XCTAssertTrue(apply(.flag(.strikethrough, true), to: &document))
        XCTAssertTrue(apply(.flag(.underline, false), to: &document))
        XCTAssertTrue(apply(.fontSize(28), to: &document))
        XCTAssertTrue(apply(.textHex("#224466"), to: &document))

        let written = try XCTUnwrap(style(in: document))
        XCTAssertEqual(written.fontDesign, "serif")
        XCTAssertEqual(written.bold, true)
        XCTAssertEqual(written.italic, true)
        XCTAssertEqual(written.strikethrough, true)
        XCTAssertEqual(written.underline, false)
        XCTAssertEqual(written.fontSize, 28)
        XCTAssertEqual(written.textHex, "#224466")

        let saved = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        let frame = try XCTUnwrap(LayoutEngine().layout(saved).first { $0.id == rootID })
        XCTAssertEqual(frame.fontSize, 28, accuracy: 0.001)
        XCTAssertTrue(frame.bold)
        XCTAssertTrue(frame.italic)
        XCTAssertEqual(saved.node(rootID)?.style?.textHex, "#224466")
        XCTAssertEqual(saved.node(rootID)?.style?.fontDesign, "serif")
    }

    func testLinksSectionWritesTheSelectionThroughTheSession() throws {
        var document = map()
        _ = document.linkTopics(from: rootID, to: childID, title: "对照", id: linkID)
        _ = document.linkTopics(from: childID, to: otherID, title: "", id: farLinkID)
        let links = InspectorStyle.links(in: document, nodeID: rootID)
        XCTAssertEqual(links.map(\.id), [linkID])
        XCTAssertEqual(
            InspectorStyle.relationshipLine(links[0], seenFrom: rootID, document: document, missingTopic: "Missing Topic"),
            "子 · 对照"
        )
        let missing = TopicRelationship(id: UUID(), sourceID: rootID, targetID: UUID(), title: "")
        XCTAssertEqual(
            InspectorStyle.relationshipLine(missing, seenFrom: rootID, document: document, missingTopic: "Missing Topic"),
            "Missing Topic"
        )

        var keyboard = MindMapKeyboardSession()
        keyboard.selectedNodeID = rootID
        keyboard.apply(.beginEdit, document: &document, frames: [])
        keyboard.replaceEditingText("改过", document: &document)
        XCTAssertEqual(keyboard.mode, .edit)
        InspectorStyle.selectLink(linkID, document: &document, keyboard: &keyboard)
        XCTAssertEqual(document.node(rootID)?.text, "改过")
        XCTAssertEqual(keyboard.mode, .command)
        XCTAssertEqual(keyboard.selectedRelationshipID, linkID)
        XCTAssertNil(keyboard.selectedNodeID)
        XCTAssertEqual(InspectorStyle.links(in: document, nodeID: otherID).map(\.id), [farLinkID])
    }

    func testMapSectionHostsExistingCounts() throws {
        var document = map()
        document.stickies = [StickyNote(text: "卡", origin: MindMapPoint(x: 1, y: 2))]
        document.roots[0].children[0].attachments = [
            NodeAttachment(sha256: String(repeating: "ab", count: 32), fileExtension: "png", byteCount: 100, filename: "a.png"),
        ]
        _ = document.linkTopics(from: rootID, to: childID, title: "", id: linkID)
        _ = document.addSummary(covering: childID, text: "概要", id: summaryID)
        _ = document.addBoundary(covering: childID, title: "边界", id: boundaryID)

        let referenced = InspectorStyle.mapFacts(document: document, storedAttachmentBytes: 0, archiveByteCount: 4096)
        XCTAssertEqual(referenced.attachmentBytes, 100)
        XCTAssertEqual(referenced.archiveBytes, 4096)
        XCTAssertEqual(referenced.referenceCount, 1)
        XCTAssertEqual(referenced.topicCount, document.topicCount)
        XCTAssertEqual(referenced.stickyCount, 1)
        XCTAssertEqual(referenced.relationshipCount, 1)
        XCTAssertEqual(referenced.summaryCount, 1)
        XCTAssertEqual(referenced.boundaryCount, 1)
        XCTAssertEqual(InspectorStyle.mapValue("附件合计", facts: referenced), AttachmentByteFormat.label(100))
        XCTAssertEqual(InspectorStyle.mapValue("节点", facts: referenced), "\(document.topicCount)")
        XCTAssertEqual(InspectorStyle.mapValue("没有这一行", facts: referenced), "")

        let stored = InspectorStyle.mapFacts(document: document, storedAttachmentBytes: 2048, archiveByteCount: 4096)
        XCTAssertEqual(stored.attachmentBytes, 2048)
        XCTAssertEqual(InspectorStyle.mapRowTitleKeys, ["附件合计", "文档大小", "引用", "节点", "便签", "关系", "概要", "边界"])
        XCTAssertFalse(InspectorStyle.mapValue("文档大小", facts: stored).isEmpty)
    }

    func testPresentationSectionHasNoControls() {
        XCTAssertEqual(InspectorTab.allCases.map(\.titleKey), ["样式", "演说", "导图"])
        XCTAssertTrue(InspectorStyle.presentationControlKeys.isEmpty)
        XCTAssertEqual(InspectorStyle.sections.map(\.titleKey), ["主题", "边框", "文本", "连到"])
        XCTAssertEqual(InspectorTopicShape.allCases.map(\.titleKey), ["矩形", "圆角", "胶囊", "无边框"])
        XCTAssertEqual(InspectorFillStyle.allCases.map(\.rawValue), ["solid", "none"])
        XCTAssertEqual(InspectorBorderStyle.allCases.map(\.rawValue), ["solid", "none"])
        XCTAssertEqual(InspectorFontDesign.allCases.map(\.rawValue), ["default", "serif", "rounded", "monospaced"])
        XCTAssertEqual(InspectorTextFlag.allCases.map(\.mark), ["B", "I", "S", "U"])
        XCTAssertEqual(
            InspectorStyle.choiceTags(known: InspectorFillStyle.allCases.map(\.rawValue), current: "solid"),
            ["solid", "none"]
        )
        XCTAssertEqual(
            InspectorStyle.choiceTags(known: InspectorFontDesign.allCases.map(\.rawValue), current: "NeverMind"),
            ["default", "serif", "rounded", "monospaced", "NeverMind"]
        )
    }

    func testRelationshipSummaryAndBoundaryFieldsWriteThrough() {
        var document = map()
        _ = document.linkTopics(from: rootID, to: childID, title: "旧", id: linkID)
        _ = document.addSummary(covering: childID, text: "旧概要", id: summaryID)
        _ = document.addBoundary(covering: childID, title: "旧边界", id: boundaryID)

        var keyboard = MindMapKeyboardSession()
        keyboard.selectedRelationshipID = linkID
        InspectorMarkField.replace("新标签", kind: .relationship, id: linkID, document: &document, keyboard: &keyboard)
        XCTAssertEqual(document.relationship(linkID)?.title, "新标签")
        XCTAssertEqual(InspectorMarkField.text(.relationship, id: linkID, document: document, keyboard: keyboard), "新标签")
        InspectorMarkField.commit(document: &document, keyboard: &keyboard)
        XCTAssertEqual(keyboard.mode, .command)
        XCTAssertEqual(document.relationship(linkID)?.title, "新标签")

        keyboard.selectedSummaryID = summaryID
        InspectorMarkField.replace("新概要", kind: .summary, id: summaryID, document: &document, keyboard: &keyboard)
        XCTAssertEqual(document.summary(summaryID)?.text, "新概要")
        InspectorMarkField.commit(document: &document, keyboard: &keyboard)

        keyboard.selectedBoundaryID = boundaryID
        InspectorMarkField.replace("新边界", kind: .boundary, id: boundaryID, document: &document, keyboard: &keyboard)
        XCTAssertEqual(document.boundary(boundaryID)?.title, "新边界")
        InspectorMarkField.commit(document: &document, keyboard: &keyboard)
        XCTAssertEqual(document.boundary(boundaryID)?.title, "新边界")
        XCTAssertEqual(InspectorMarkField.text(.boundary, id: nil, document: document, keyboard: keyboard), "")
    }

    func testLockedAppearanceDoesNotWriteAnyStyleSection() {
        var document = map()
        let before = document
        for edit in [
            InspectorStyleEdit.shape(.rectangle),
            .fillStyle(.none),
            .fillHex("#E23D3D"),
            .topicWidth(200),
            .borderStyle(.none),
            .borderWidth(4),
            .borderHex("#FFFFFF"),
            .fontDesign(.monospaced),
            .fontSize(32),
            .textHex("#FFFFFF"),
            .flag(.bold, true),
        ] {
            XCTAssertFalse(InspectorStyle.apply(edit, nodeID: rootID, document: &document, allowsAppearanceWrites: false))
        }
        XCTAssertFalse(InspectorStyle.apply(.fillHex("#E23D3D"), nodeID: UUID(), document: &document, allowsAppearanceWrites: true))
        XCTAssertEqual(document, before)
    }

    func testInspectorHostsExistingSectionsWithNativeControls() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let inspector = try slice(source, from: "private var inspectorBody", until: "struct ExportFile")
        let presentation = try slice(source, from: "private var presentationPage", until: "private var documentInfo")

        XCTAssertTrue(inspector.contains("Form"))
        XCTAssertTrue(inspector.contains("Section"))
        XCTAssertTrue(inspector.contains("InspectorTab.allCases"))
        XCTAssertTrue(inspector.contains(".pickerStyle(.segmented)"))
        XCTAssertTrue(inspector.contains(".pickerStyle(.menu)"))
        XCTAssertTrue(inspector.contains(".formStyle(.grouped)"))
        XCTAssertTrue(inspector.contains(".toggleStyle(.button)"))
        XCTAssertTrue(inspector.contains("ColorPicker"))
        XCTAssertTrue(inspector.contains("Slider"))
        XCTAssertTrue(inspector.contains("Toggle"))
        XCTAssertTrue(inspector.contains("InspectorStyleSection.topic.titleKey"))
        XCTAssertTrue(inspector.contains("InspectorStyleSection.border.titleKey"))
        XCTAssertTrue(inspector.contains("InspectorStyleSection.text.titleKey"))
        XCTAssertTrue(inspector.contains("InspectorStyleSection.links.titleKey"))
        XCTAssertTrue(inspector.contains("InspectorStyle.mapRowTitleKeys"))
        XCTAssertTrue(inspector.contains("InspectorStyle.mapFacts"))
        XCTAssertTrue(inspector.contains("InspectorStyle.apply"))
        XCTAssertTrue(inspector.contains("InspectorStyle.selectLink"))
        XCTAssertTrue(inspector.contains("InspectorMarkField.text"))
        XCTAssertTrue(inspector.contains("InspectorMarkField.replace"))
        XCTAssertTrue(inspector.contains("InspectorMarkField.commit"))
        for edit in [".shape(", ".fillStyle(", ".fillHex(", ".topicWidth(", ".borderStyle(", ".borderWidth(", ".borderHex(", ".fontDesign(", ".fontSize(", ".textHex(", ".flag("] {
            XCTAssertTrue(inspector.contains(edit), edit)
        }
        for identifier in [
            "inspector.tabs",
            "inspector.style",
            "inspector.style.shape",
            "inspector.style.fillStyle",
            "inspector.style.fillColor",
            "inspector.style.topicWidth",
            "inspector.style.borderStyle",
            "inspector.style.borderWidth",
            "inspector.style.borderColor",
            "inspector.style.font",
            "inspector.style.bold",
            "inspector.style.italic",
            "inspector.style.strikethrough",
            "inspector.style.underline",
            "inspector.style.fontSize",
            "inspector.style.textColor",
            "inspector.map",
            "inspector.presentation",
            "relationship.label",
            "summary.text",
            "boundary.title",
        ] {
            XCTAssertTrue(inspector.contains(identifier), identifier)
        }

        XCTAssertTrue(presentation.contains("ContentUnavailableView"))
        XCTAssertFalse(presentation.contains("Slider"))
        XCTAssertFalse(presentation.contains("Toggle"))
        XCTAssertFalse(presentation.contains("ColorPicker"))
        XCTAssertFalse(presentation.contains("Picker"))

        for forbidden in ["glassEffect", "NSGlassEffectView", ".shadow(", "ultraThinMaterial", "RoundedRectangle", "TimelineView", "CADisplayLink", "Canvas("] {
            XCTAssertFalse(inspector.contains(forbidden), forbidden)
        }
    }

    private func map() -> MindMapDocument {
        MindMapDocument(
            title: "图",
            roots: [
                MindMapNode(
                    id: rootID,
                    text: "根",
                    children: [
                        MindMapNode(id: childID, text: "子"),
                        MindMapNode(id: otherID, text: "另"),
                    ]
                ),
            ]
        )
    }

    private func style(in document: MindMapDocument) -> MindMapNodeStyle? {
        document.node(rootID)?.style
    }

    @discardableResult
    private func apply(_ edit: InspectorStyleEdit, to document: inout MindMapDocument) -> Bool {
        InspectorStyle.apply(edit, nodeID: rootID, document: &document, allowsAppearanceWrites: true)
    }

    private func repoFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func slice(_ source: String, from startMark: String, until endMark: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMark))
        let rest = source[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: endMark))
        return String(rest[..<end.lowerBound])
    }
}

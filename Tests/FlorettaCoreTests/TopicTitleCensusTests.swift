import FlorettaCore
import XCTest

final class TopicTitleCensusTests: XCTestCase {
    func testXMindAcceptanceFixture() {
        let document = MindMapDocument(
            title: "思维导图",
            roots: [
                MindMapNode(
                    text: "中心主题",
                    children: [
                        MindMapNode(text: "分支主题 1"),
                        MindMapNode(text: "分支主题 2"),
                        MindMapNode(text: "分支主题 3"),
                        MindMapNode(text: "分支主题 4"),
                    ]
                ),
            ]
        )

        let census = document.titleCensus
        XCTAssertEqual(census.topics, 5)
        XCTAssertEqual(census.words, 24)
        XCTAssertEqual(census.characters, 28)
        XCTAssertEqual(census.topics, document.topicCount)
        XCTAssertEqual(TopicTitleMeasure.measure("中心主题"), TopicTitleMeasure(words: 4, characters: 4))
        XCTAssertEqual(TopicTitleMeasure.measure("分支主题 1"), TopicTitleMeasure(words: 5, characters: 6))
    }

    func testMixedChineseAndEnglishWordAndCharacterCounts() {
        XCTAssertEqual(TopicTitleMeasure.measure("Hello世界"), TopicTitleMeasure(words: 3, characters: 7))
        XCTAssertEqual(TopicTitleMeasure.measure("Hello World"), TopicTitleMeasure(words: 2, characters: 11))
        XCTAssertEqual(TopicTitleMeasure.measure("iPhone15很好"), TopicTitleMeasure(words: 4, characters: 10))
        XCTAssertEqual(TopicTitleMeasure.measure("请发 e-mail 给我"), TopicTitleMeasure(words: 6, characters: 12))
        XCTAssertEqual(TopicTitleMeasure.measure("café"), TopicTitleMeasure(words: 1, characters: 4))
        XCTAssertEqual(TopicTitleMeasure.measure("あい"), TopicTitleMeasure(words: 2, characters: 2))
        XCTAssertEqual(TopicTitleMeasure.measure("Helloあ"), TopicTitleMeasure(words: 2, characters: 6))

        let document = MindMapDocument(
            title: "ignored",
            roots: [MindMapNode(text: "Hello世界", children: [MindMapNode(text: "iPhone15很好")])]
        )
        XCTAssertEqual(document.titleCensus, TopicTitleCensus(topics: 2, words: 7, characters: 17))
    }

    func testEmojiCountsAsOneCharacterAndNotAsAWord() {
        XCTAssertEqual(TopicTitleMeasure.measure("👍"), TopicTitleMeasure(words: 0, characters: 1))
        XCTAssertEqual(TopicTitleMeasure.measure("好👍"), TopicTitleMeasure(words: 1, characters: 2))
        XCTAssertEqual(TopicTitleMeasure.measure("A😀B"), TopicTitleMeasure(words: 2, characters: 3))
        XCTAssertEqual(TopicTitleMeasure.measure("❤️"), TopicTitleMeasure(words: 0, characters: 1))
        XCTAssertEqual(TopicTitleMeasure.measure("👨‍👩‍👧‍👦"), TopicTitleMeasure(words: 0, characters: 1))
        XCTAssertEqual(TopicTitleMeasure.measure("🇨🇳"), TopicTitleMeasure(words: 0, characters: 1))
        XCTAssertEqual(TopicTitleMeasure.measure("1️⃣"), TopicTitleMeasure(words: 0, characters: 1))

        let document = MindMapDocument(
            title: "图",
            roots: [MindMapNode(text: "中心", children: [MindMapNode(text: "好👍")])]
        )
        XCTAssertEqual(document.titleCensus, TopicTitleCensus(topics: 2, words: 3, characters: 4))
    }

    func testDigitRunsPunctuationSpacesAndNewlines() {
        XCTAssertEqual(TopicTitleMeasure.measure("1"), TopicTitleMeasure(words: 1, characters: 1))
        XCTAssertEqual(TopicTitleMeasure.measure("12"), TopicTitleMeasure(words: 1, characters: 2))
        XCTAssertEqual(TopicTitleMeasure.measure("１２"), TopicTitleMeasure(words: 1, characters: 2))
        XCTAssertEqual(TopicTitleMeasure.measure("1 2"), TopicTitleMeasure(words: 2, characters: 3))
        XCTAssertEqual(TopicTitleMeasure.measure("分支主题 12"), TopicTitleMeasure(words: 5, characters: 7))
        XCTAssertEqual(TopicTitleMeasure.measure("分支主题 １"), TopicTitleMeasure(words: 5, characters: 6))
        XCTAssertEqual(TopicTitleMeasure.measure("3.14"), TopicTitleMeasure(words: 2, characters: 4))
        XCTAssertEqual(TopicTitleMeasure.measure("don't"), TopicTitleMeasure(words: 2, characters: 5))
        XCTAssertEqual(TopicTitleMeasure.measure("hello-world"), TopicTitleMeasure(words: 2, characters: 11))
        XCTAssertEqual(TopicTitleMeasure.measure("你好！"), TopicTitleMeasure(words: 2, characters: 3))
        XCTAssertEqual(TopicTitleMeasure.measure("..."), TopicTitleMeasure(words: 0, characters: 3))
        XCTAssertEqual(TopicTitleMeasure.measure(" a "), TopicTitleMeasure(words: 1, characters: 3))
        XCTAssertEqual(TopicTitleMeasure.measure("a\nb"), TopicTitleMeasure(words: 2, characters: 2))
        XCTAssertEqual(TopicTitleMeasure.measure("\n\n"), TopicTitleMeasure(words: 0, characters: 0))
        XCTAssertEqual(TopicTitleMeasure.measure("\r\n"), TopicTitleMeasure(words: 0, characters: 0))
        XCTAssertEqual(TopicTitleMeasure.measure(" \n "), TopicTitleMeasure(words: 0, characters: 2))
        XCTAssertEqual(TopicTitleMeasure.measure("\t"), TopicTitleMeasure(words: 0, characters: 1))
        XCTAssertEqual(TopicTitleMeasure.measure(""), TopicTitleMeasure(words: 0, characters: 0))
        XCTAssertEqual(TopicTitleMeasure.measure("①"), TopicTitleMeasure(words: 0, characters: 1))
    }

    func testCountsTitlesOnly() {
        let child = MindMapNode(text: "丙")
        var parent = MindMapNode(
            text: "乙",
            note: "这是备注不是标题",
            isCollapsed: true,
            attachments: [
                NodeAttachment(sha256: String(repeating: "a", count: 64), fileExtension: "png", byteCount: 8, filename: "附件名.png"),
            ],
            children: [child],
            summaries: [TopicSummary(text: "概要文字", rangeStart: 0, rangeEnd: 0)],
            boundaries: [TopicBoundary(title: "边界标题", rangeStart: 0, rangeEnd: 0)],
            labels: ["标签文字"]
        )
        parent.isCollapsed = true
        let freeChild = MindMapNode(text: "己")
        let free = MindMapNode(text: "丁丁", children: [freeChild])
        let root = MindMapNode(text: "甲", children: [parent])
        let document = MindMapDocument(
            title: "文档标题不计入",
            roots: [root],
            freeNodes: [free],
            relationships: [TopicRelationship(sourceID: root.id, targetID: free.id, title: "关系标签")],
            stickies: [StickyNote(text: "便签内容", origin: MindMapPoint(x: 1, y: 2))],
            additionalCanvases: [
                MindMapCanvas(title: "画布名", roots: [MindMapNode(text: "戊")]),
            ]
        )

        XCTAssertEqual(document.titleCensus, TopicTitleCensus(topics: 6, words: 7, characters: 7))
        XCTAssertEqual(document.titleCensus.topics, document.topicCount)
        XCTAssertTrue(document.node(parent.id)?.isCollapsed == true)
    }

    func testUncommittedEditUpdatesTheCount() {
        let branch = MindMapNode(text: "分支主题 1")
        let root = MindMapNode(text: "中心主题", children: [branch])
        var document = MindMapDocument(title: "图", roots: [root])
        let before = document.titleCensus
        XCTAssertEqual(before, TopicTitleCensus(topics: 2, words: 9, characters: 10))

        var keyboard = MindMapKeyboardSession()
        keyboard.selectedNodeID = branch.id
        keyboard.apply(.beginEdit, document: &document, frames: [])
        XCTAssertEqual(keyboard.mode, .edit)
        keyboard.replaceEditingText("分支主题 12", document: &document)
        XCTAssertEqual(keyboard.mode, .edit)
        XCTAssertEqual(document.titleCensus.words, before.words)
        XCTAssertEqual(document.titleCensus.characters, before.characters + 1)
        XCTAssertEqual(document.titleCensus.topics, before.topics)

        keyboard.replaceEditingText("分支主题 12啊", document: &document)
        XCTAssertEqual(keyboard.mode, .edit)
        XCTAssertEqual(document.titleCensus.words, before.words + 1)
        XCTAssertEqual(document.titleCensus.characters, before.characters + 2)
        XCTAssertNotEqual(document.roots[0].children[0].text, branch.text)
    }

    func testCacheSkipsUnchangedSheetsAndRemeasuresOneTitle() {
        let extraNodes = (0..<40).map { MindMapNode(text: "额外\($0)") }
        var document = MindMapDocument(
            title: "图",
            roots: [
                MindMapNode(text: "中心主题", children: [MindMapNode(text: "分支主题 1")]),
            ],
            additionalCanvases: [MindMapCanvas(title: "第二张", roots: extraNodes)]
        )
        var cache = TopicTitleCensusCache()
        let first = cache.update(document)
        XCTAssertEqual(first, document.titleCensus)
        XCTAssertEqual(first.topics, 42)
        XCTAssertGreaterThan(cache.remeasuredActiveTitles, 0)
        XCTAssertEqual(cache.recountedExtraSheets, 1)

        let second = cache.update(document)
        XCTAssertEqual(second, first)
        XCTAssertEqual(cache.remeasuredActiveTitles, 0)
        XCTAssertEqual(cache.recountedExtraSheets, 0)

        document.roots[0].children[0].text = "分支主题 12啊"
        let edited = cache.update(document)
        XCTAssertEqual(edited.words, first.words + 1)
        XCTAssertEqual(edited.characters, first.characters + 2)
        XCTAssertEqual(edited.topics, first.topics)
        XCTAssertEqual(cache.remeasuredActiveTitles, 1)
        XCTAssertEqual(cache.recountedExtraSheets, 0)
        XCTAssertEqual(edited, document.titleCensus)

        document.additionalCanvases[0].roots[0].text = "改过的额外"
        let sheetEdited = cache.update(document)
        XCTAssertEqual(cache.recountedExtraSheets, 1)
        XCTAssertEqual(cache.remeasuredActiveTitles, 0)
        XCTAssertEqual(sheetEdited, document.titleCensus)
        XCTAssertNotEqual(sheetEdited.words, edited.words)
    }
}

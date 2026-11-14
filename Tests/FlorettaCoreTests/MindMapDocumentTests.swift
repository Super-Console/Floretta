import FlorettaCore
import XCTest

final class MindMapDocumentTests: XCTestCase {
    private let rootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let childID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let secondChildID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let grandchildID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let floatingID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    private let created = Date(timeIntervalSince1970: 1_762_646_400)
    private let modified = Date(timeIntervalSince1970: 1_762_732_800)

    func testTextAlignmentDefaultsToCenterForExistingDocumentsAndPersistsPerNode() throws {
        let legacy = Data(#"{"formatVersion":1,"title":"t","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[{"id":"11111111-1111-1111-1111-111111111111","text":"root","note":"","collapsed":false,"children":[]}]}"#.utf8)
        var document = try FlorettaCodec.decode(legacy)
        XCTAssertEqual(document.roots[0].textAlignment, .center)
        XCTAssertTrue(document.setTextAlignment(.leading, on: rootID))
        let reopened = try FlorettaCodec.decode(FlorettaCodec.encode(document))
        XCTAssertEqual(reopened.roots[0].textAlignment, .leading)
    }

    func testSubtitleDefaultsEmptyAndPersistsOnlyWhenSet() throws {
        let document = MindMapDocument(title: "t", roots: [MindMapNode(text: "root")])
        let oldJSON = try XCTUnwrap(String(data: FlorettaCodec.encode(document), encoding: .utf8))
        XCTAssertFalse(oldJSON.contains("subtitle"))
        let oldOpened = try FlorettaCodec.decode(Data(oldJSON.utf8))
        XCTAssertEqual(oldOpened.roots[0].subtitle, "")
        var edited = oldOpened
        XCTAssertTrue(edited.replaceSubtitle("detail", on: edited.roots[0].id))
        XCTAssertEqual(try FlorettaCodec.decode(FlorettaCodec.encode(edited)).roots[0].subtitle, "detail")
    }

    func testThemeIDRoundTripsWithoutBumpingTheFormat() throws {
        var document = MindMapDocument(
            title: "色",
            createdAt: created,
            modifiedAt: modified,
            roots: [MindMapNode(text: "根")]
        )
        let plain = try XCTUnwrap(String(data: try FlorettaCodec.encode(document), encoding: .utf8))
        XCTAssertFalse(plain.contains("themeID"))
        XCTAssertEqual(document.formatVersion, 1)
        document.themeID = "ink"
        let standard = try XCTUnwrap(String(data: try FlorettaCodec.encode(document), encoding: .utf8))
        XCTAssertFalse(standard.contains("themeID"))
        document.themeID = "grove"
        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(decoded.themeID, "grove")
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.roots[0].text, "根")

        let future = """
        {
          "formatVersion": 1,
          "title": "t",
          "createdAt": "2026-11-09T00:00:00Z",
          "modifiedAt": "2026-11-09T00:00:00Z",
          "roots": [],
          "themeID": "future-theme"
        }
        """
        let kept = try FlorettaCodec.decode(Data(future.utf8))
        XCTAssertEqual(kept.themeID, "future-theme")
        let again = try FlorettaCodec.decode(try FlorettaCodec.encode(kept))
        XCTAssertEqual(again.themeID, "future-theme")

        let blank = future.replacingOccurrences(of: "future-theme", with: "")
        XCTAssertNil(try FlorettaCodec.decode(Data(blank.utf8)).themeID)
        let namedInk = future.replacingOccurrences(of: "future-theme", with: "ink")
        XCTAssertNil(try FlorettaCodec.decode(Data(namedInk.utf8)).themeID)

        assertCorrupt(
            Data(#"{"formatVersion":1,"title":"t","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[],"themeID":1}"#.utf8),
            containing: "themeID"
        )
    }

    func testRoundTripPreservesStructureOrderAndText() throws {
        let document = sampleDocument()
        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.title, "周计划")
        XCTAssertEqual(decoded.roots.map(\.id), [rootID, floatingID])
        XCTAssertEqual(decoded.roots.map(\.text), ["中心 A", "浮动 B"])
        XCTAssertEqual(decoded.roots[0].note, "备注\n第二行")
        XCTAssertTrue(decoded.roots[0].isCollapsed)
        XCTAssertEqual(decoded.roots[0].style, MindMapNodeStyle(colorHex: "#C45C26"))
        XCTAssertEqual(decoded.roots[0].children.map(\.text), ["子 1", "子 2"])
        XCTAssertEqual(decoded.roots[0].children.map(\.id), [childID, secondChildID])
        XCTAssertEqual(decoded.roots[0].children[0].children.map(\.text), ["孙"])
        XCTAssertEqual(decoded.roots[0].children[0].children.map(\.id), [grandchildID])
        XCTAssertNil(decoded.roots[1].style)
        XCTAssertFalse(decoded.roots[1].isCollapsed)
        XCTAssertTrue(decoded.roots[1].children.isEmpty)
    }

    func testEncodedFileIsPrettyUTF8WithStableKeyOrder() throws {
        let data = try FlorettaCodec.encode(sampleDocument())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\n"))
        XCTAssertTrue(json.contains("中心 A"))
        XCTAssertFalse(json.contains("\\u"))
        XCTAssertEqual(data.first, UInt8(ascii: "{"))
        try assertKeyOrder(json, ["createdAt", "formatVersion", "modifiedAt", "roots", "title"])

        let leaf = MindMapDocument(
            title: "leaf",
            createdAt: created,
            modifiedAt: modified,
            roots: [
                MindMapNode(
                    id: rootID,
                    text: "叶子",
                    note: "n",
                    isCollapsed: true,
                    style: MindMapNodeStyle(colorHex: "#C45C26")
                ),
            ]
        )
        let leafJSON = try XCTUnwrap(String(data: try FlorettaCodec.encode(leaf), encoding: .utf8))
        try assertKeyOrder(leafJSON, ["children", "collapsed", "id", "note", "style", "text"])
        XCTAssertTrue(leafJSON.contains("#C45C26"))
    }

    func testEmptyForestRoundTrips() throws {
        let document = MindMapDocument(
            title: "",
            createdAt: created,
            modifiedAt: modified,
            roots: []
        )
        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(decoded, document)
    }

    func testDuplicateIDAcrossRootsThrows() throws {
        let shared = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let document = MindMapDocument(
            title: "dup",
            createdAt: created,
            modifiedAt: modified,
            roots: [
                MindMapNode(id: shared, text: "one"),
                MindMapNode(id: shared, text: "two"),
            ]
        )
        XCTAssertThrowsError(try FlorettaCodec.encode(document)) { error in
            XCTAssertEqual(error as? FlorettaCodecError, .duplicateID(shared))
        }
    }

    func testSiblingDuplicateIDThrows() {
        let json = envelope(
            roots: """
            [{
              "id": "\(rootID.uuidString)",
              "text": "parent",
              "note": "",
              "collapsed": false,
              "children": [
                {"id": "\(childID.uuidString)", "text": "a", "note": "", "collapsed": false, "children": []},
                {"id": "\(childID.uuidString)", "text": "b", "note": "", "collapsed": false, "children": []}
              ]
            }]
            """
        )
        assertDecode(json, equals: .duplicateID(childID))
    }

    func testAncestorIDReuseThrowsAsCycle() {
        let json = envelope(
            roots: """
            [{
              "id": "\(rootID.uuidString)",
              "text": "parent",
              "note": "",
              "collapsed": false,
              "children": [{
                "id": "\(rootID.uuidString)",
                "text": "self",
                "note": "",
                "collapsed": false,
                "children": []
              }]
            }]
            """
        )
        assertDecode(json, equals: .cyclicID(rootID))
    }

    func testGrandchildRepeatingRootThrowsAsCycle() {
        let json = envelope(
            roots: """
            [{
              "id": "\(rootID.uuidString)",
              "text": "root",
              "note": "",
              "collapsed": false,
              "children": [{
                "id": "\(childID.uuidString)",
                "text": "child",
                "note": "",
                "collapsed": false,
                "children": [{
                  "id": "\(rootID.uuidString)",
                  "text": "back to root",
                  "note": "",
                  "collapsed": false,
                  "children": []
                }]
              }]
            }]
            """
        )
        assertDecode(json, equals: .cyclicID(rootID))
    }

    func testGarbageDoesNotCrash() {
        assertCorrupt(Data("hello".utf8), containing: "not a .floretta")
        assertCorrupt(Data("{".utf8), containing: "not a .floretta")
        assertCorrupt(Data(), containing: "empty")
        assertCorrupt(Data([0xFF, 0xFE, 0xFD]), containing: "UTF-8")
        assertCorrupt(Data("[]".utf8), containing: "Wrong JSON type")
        assertCorrupt(
            Data(#"{"formatVersion":1,"title":"t","createdAt":1,"modifiedAt":"2026-11-09T00:00:00Z","roots":[]}"#.utf8),
            containing: "Wrong JSON type"
        )
    }

    func testMissingAndMistypedVersionThrow() {
        assertCorrupt(Data(#"{"title":"x"}"#.utf8), containing: "formatVersion")
        assertCorrupt(Data(#"{"formatVersion":"1"}"#.utf8), containing: "Wrong JSON type")
        assertCorrupt(Data(#"{"formatVersion":1.5}"#.utf8), containing: "Wrong JSON type")
    }

    func testUnsupportedVersionThrows() {
        assertDecode(
            #"{"formatVersion":0}"#,
            equals: .unsupportedVersion(found: 0, supported: 1)
        )
        assertDecode(
            #"{"formatVersion":2,"title":"future"}"#,
            equals: .unsupportedVersion(found: 2, supported: 1)
        )
    }

    func testEncodingUnsupportedVersionThrows() {
        let document = MindMapDocument(
            title: "old",
            createdAt: created,
            modifiedAt: modified,
            roots: [],
            formatVersion: 99
        )
        XCTAssertThrowsError(try FlorettaCodec.encode(document)) { error in
            XCTAssertEqual(
                error as? FlorettaCodecError,
                .unsupportedVersion(found: 99, supported: 1)
            )
        }
    }

    private func sampleDocument() -> MindMapDocument {
        let grandchild = MindMapNode(id: grandchildID, text: "孙")
        let first = MindMapNode(id: childID, text: "子 1", children: [grandchild])
        let second = MindMapNode(id: secondChildID, text: "子 2", note: "only note")
        let center = MindMapNode(
            id: rootID,
            text: "中心 A",
            note: "备注\n第二行",
            isCollapsed: true,
            style: MindMapNodeStyle(colorHex: "#C45C26"),
            children: [first, second]
        )
        let floating = MindMapNode(id: floatingID, text: "浮动 B")
        return MindMapDocument(
            title: "周计划",
            createdAt: created,
            modifiedAt: modified,
            roots: [center, floating]
        )
    }

    private func assertKeyOrder(_ json: String, _ keys: [String]) throws {
        var lower = json.startIndex
        for key in keys {
            let needle = "\"\(key)\""
            let range = try XCTUnwrap(
                json.range(of: needle, range: lower..<json.endIndex),
                "missing \(needle)"
            )
            lower = range.upperBound
        }
    }

    private func envelope(roots: String) -> String {
        """
        {
          "formatVersion": 1,
          "title": "t",
          "createdAt": "2026-11-09T00:00:00Z",
          "modifiedAt": "2026-11-09T00:00:00Z",
          "roots": \(roots)
        }
        """
    }

    private func assertDecode(_ json: String, equals expected: FlorettaCodecError) {
        XCTAssertThrowsError(try FlorettaCodec.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? FlorettaCodecError, expected)
        }
    }

    private func assertCorrupt(_ data: Data, containing snippet: String) {
        XCTAssertThrowsError(try FlorettaCodec.decode(data)) { error in
            guard case .corrupt(let message) = error as? FlorettaCodecError else {
                return XCTFail("expected corrupt, got \(error)")
            }
            XCTAssertTrue(
                message.localizedCaseInsensitiveContains(snippet),
                "message \(message) does not contain \(snippet)"
            )
        }
    }
}

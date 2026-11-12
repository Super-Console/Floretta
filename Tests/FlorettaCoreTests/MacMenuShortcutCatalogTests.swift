import XCTest
import FlorettaCore

#if os(macOS)
final class MacMenuShortcutCatalogTests: XCTestCase {
    func testXMindShortcutCatalogHasNoConflictingChords() {
        XCTAssertTrue(XMindShortcutCatalog.conflicts().isEmpty)
        XCTAssertTrue(XMindShortcutCatalog.entries.contains(where: { $0.key == .space && $0.command == .beginEdit }))
    }

    func testDeclaredShortcutsAvoidSystemAndDuplicateChords() {
        XCTAssertTrue(MacMenuShortcutCatalog.conflicts(in: MacMenuShortcutCatalog.custom).isEmpty)
    }

    func testConflictDetectorFindsReservedAndDuplicateChords() {
        let chords = [
            MacMenuShortcutCatalog.Chord("q"),
            MacMenuShortcutCatalog.Chord("x"),
            MacMenuShortcutCatalog.Chord("x")
        ]
        XCTAssertEqual(MacMenuShortcutCatalog.conflicts(in: chords).count, 2)
    }

    func testNodeCommandsAreDisabledWithoutASelectedTopic() {
        let context = EditorToolbarContext()
        for id in [EditorToolbarCommandID.child, .sibling, .image, .attachment, .link, .summary, .boundary] {
            XCTAssertFalse(MacMenuShortcutCatalog.isEnabled(id, in: context), id.rawValue)
        }
        XCTAssertTrue(MacMenuShortcutCatalog.isEnabled(.freeNode, in: context))
    }
}
#endif

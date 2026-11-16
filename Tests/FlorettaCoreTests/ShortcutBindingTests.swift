import FlorettaCore
import XCTest

/// The Enter contract and the 设置 ▸ 快捷键 store, without a UI.
///
/// Three behaviours are pinned here:
///   1. ↩ in edit mode ends the edit and creates nothing; the next ↩ on the
///      canvas creates the sibling. Two presses, one topic.
///   2. ⌘↩ and ⇧↩ put a line break in the topic text.
///   3. A rebinding resolves to the new command at once, a clash is reported,
///      and an untouched install keeps every shipped chord.
final class ShortcutBindingTests: XCTestCase {
    // MARK: - Enter semantics

    func testEditModeEnterEndsEditAndTheSecondEnterCreatesOneSibling() {
        let rootID = UUID()
        var document = MindMapDocument(title: "enter", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID

        XCTAssertEqual(press(.space, session: &session, document: &document), .beginEdit)
        XCTAssertEqual(session.mode, .edit)
        session.replaceEditingText("改过", document: &document)

        // First ↩: leave the field. No topic is created.
        XCTAssertEqual(press(.enter, session: &session, document: &document), .commitEdit)
        XCTAssertEqual(session.mode, .command)
        XCTAssertEqual(document.roots.count, 1)
        XCTAssertTrue(document.roots[0].children.isEmpty)
        XCTAssertEqual(document.roots[0].text, "改过")

        // Second ↩: the sibling the user actually asked for.
        XCTAssertEqual(press(.enter, session: &session, document: &document), .createSibling)
        XCTAssertEqual(document.roots.count, 2)
        XCTAssertEqual(document.roots[1].text, MindMapKeyboardSession.newTopicText)
        XCTAssertEqual(session.mode, .edit)
    }

    func testPlainEnterCommitsButNeverCreatesWhileEditing() {
        XCTAssertEqual(map(.enter, mode: .edit), .commitEdit)
        XCTAssertNotEqual(map(.enter, mode: .edit), .createSibling)
        XCTAssertNotEqual(map(.enter, mode: .edit), .createSiblingBefore)
        XCTAssertNil(map(.enter, .option, mode: .edit))
    }

    func testCommandModeEnterStillCreatesASibling() {
        XCTAssertEqual(map(.enter), .createSibling)
        XCTAssertEqual(map(.enter, .shift), .createSiblingBefore)
        XCTAssertEqual(map(.enter, .command), .createParent)
        XCTAssertEqual(map(.tab), .createChild)
    }

    func testCommandEnterAndShiftEnterInsertTheLineBreak() {
        XCTAssertEqual(map(.enter, .command, mode: .edit), .insertNewline)
        XCTAssertEqual(map(.enter, .shift, mode: .edit), .insertNewline)
        XCTAssertNotEqual(map(.enter, .command, mode: .edit), .createParent)

        let rootID = UUID()
        var document = MindMapDocument(title: "nl", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        press(.space, session: &session, document: &document)

        XCTAssertEqual(press(.enter, .command, session: &session, document: &document), .insertNewline)
        XCTAssertEqual(session.mode, .edit)
        XCTAssertEqual(document.roots[0].text, "中心\n")

        XCTAssertEqual(press(.enter, .shift, session: &session, document: &document), .insertNewline)
        XCTAssertEqual(document.roots[0].text, "中心\n\n")
        XCTAssertEqual(session.mode, .edit)
        // Only the plain third press leaves the field.
        XCTAssertEqual(press(.enter, session: &session, document: &document), .commitEdit)
        XCTAssertEqual(session.mode, .command)
        XCTAssertEqual(document.roots.count, 1)
    }

    func testEscapeStillCancelsAndMarkedTextKeepsReturn() {
        let rootID = UUID()
        var document = MindMapDocument(title: "esc", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        press(.space, session: &session, document: &document)
        session.replaceEditingText("临时", document: &document)
        XCTAssertEqual(press(.escape, session: &session, document: &document), .cancelEdit)
        XCTAssertEqual(document.roots[0].text, "中心")

        // An IME owns ↩: it commits the candidate, not the edit.
        XCTAssertNil(map(.enter, mode: .edit, composing: true))
        XCTAssertNil(map(.enter, .command, mode: .edit, composing: true))
    }

    // MARK: - Bindings resolve immediately

    func testRebindingResolvesToTheNewCommandAndDropsTheOldChord() {
        var bindings = ShortcutBindings.catalogDefaults
        bindings.bind(
            XMindShortcutCatalog.ShortcutChord(key: .character("n"), modifiers: [.command, .shift]),
            to: .createSibling
        )
        XCTAssertNil(KeyboardCommandMapper.map(event(.enter), bindings: bindings))
        XCTAssertEqual(
            KeyboardCommandMapper.map(
                event(.character("n"), [.command, .shift]),
                bindings: bindings
            ),
            .createSibling
        )
        XCTAssertEqual(bindings.displayText(for: .createSibling), "⇧⌘N")
    }

    func testSessionUsesTheEditedBindings() {
        let rootID = UUID()
        var document = MindMapDocument(title: "rebind", roots: [MindMapNode(id: rootID, text: "中心")])
        var bindings = ShortcutBindings.catalogDefaults
        bindings.bind(
            XMindShortcutCatalog.ShortcutChord(key: .character("n"), modifiers: [.command, .shift]),
            to: .createChild
        )
        var session = MindMapKeyboardSession()
        session.bindings = bindings
        session.selectedNodeID = rootID

        XCTAssertNil(press(.tab, session: &session, document: &document))
        XCTAssertTrue(document.roots[0].children.isEmpty)
        XCTAssertEqual(
            press(.character("n"), [.command, .shift], session: &session, document: &document),
            .createChild
        )
        XCTAssertEqual(document.roots[0].children.count, 1)
    }

    func testLineBreakCanBeReboundWithoutLosingTheReturnToCommit() {
        var bindings = ShortcutBindings.catalogDefaults
        bindings.bind(
            XMindShortcutCatalog.ShortcutChord(key: .enter, modifiers: .option),
            to: .insertNewline
        )
        XCTAssertEqual(KeyboardCommandMapper.map(event(.enter, .option, mode: .edit), bindings: bindings), .insertNewline)
        // ⌘↩ no longer breaks the line; plain ↩ still leaves the edit.
        XCTAssertNil(KeyboardCommandMapper.map(event(.enter, .command, mode: .edit), bindings: bindings))
        XCTAssertEqual(KeyboardCommandMapper.map(event(.enter, mode: .edit), bindings: bindings), .commitEdit)
    }

    func testModesAreSeparateScopesSoEnterCanMeanBothThings() {
        // ⌘↩ is 新建父级 on the canvas and 框内换行 in the text field.
        XCTAssertEqual(map(.enter, .command), .createParent)
        XCTAssertEqual(map(.enter, .command, mode: .edit), .insertNewline)
        XCTAssertTrue(XMindShortcutCatalog.conflicts().isEmpty)
    }

    // MARK: - Conflicts

    func testConflictDetectionNamesTheOtherCommand() {
        let tab = XMindShortcutCatalog.ShortcutChord(key: .tab, modifiers: [])
        let ids = ShortcutBindings.catalogDefaults.conflictingIDs(for: tab, bindingTo: .createSibling)
        XCTAssertEqual(ids, [.createChild])

        var bindings = ShortcutBindings.catalogDefaults
        XCTAssertTrue(bindings.conflicts().isEmpty)
        bindings.bind(tab, to: .createSibling)
        let conflicts = bindings.conflicts()
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(Set(conflicts.first?.ids ?? []), [.createSibling, .createChild])
        XCTAssertEqual(conflicts.first?.mode, .command)
        XCTAssertTrue(conflicts.first?.summary.contains("⇥") ?? false)
    }

    func testBindingIsNotSilentlyReplacedSoTheEarlierRowWins() {
        let tab = XMindShortcutCatalog.ShortcutChord(key: .tab, modifiers: [])
        var bindings = ShortcutBindings.catalogDefaults
        bindings.bind(tab, to: .createSibling)
        // The clash is visible, and the shipped row still answers for 新建子级.
        XCTAssertEqual(bindings.conflictingIDs(for: tab, bindingTo: .createChild), [.createSibling])
        XCTAssertEqual(KeyboardCommandMapper.map(event(.tab), bindings: bindings), .createSibling)
    }

    func testUnbindingLeavesTheCommandUnreachable() {
        var bindings = ShortcutBindings.catalogDefaults
        bindings.bind(nil, to: .jumpToCentralTopic)
        XCTAssertNil(bindings.chord(for: .jumpToCentralTopic))
        XCTAssertNil(KeyboardCommandMapper.map(event(.character("r"), .command), bindings: bindings))
        XCTAssertEqual(bindings.storage["jumpToCentralTopic"], "")
        XCTAssertEqual(ShortcutBindings.decode(bindings.storage), bindings)
    }

    // MARK: - Shipped defaults

    func testFreshInstallKeepsEveryShippedChord() {
        XCTAssertEqual(ShortcutBindings.catalogDefaults, ShortcutBindings.decode(nil))
        XCTAssertEqual(ShortcutBindings.catalogDefaults, ShortcutBindings.decode([:]))
        XCTAssertTrue(ShortcutBindings.catalogDefaults.isAllDefault)
        XCTAssertTrue(ShortcutBindings.catalogDefaults.conflicts().isEmpty)

        // The pre-settings table, key by key.
        XCTAssertEqual(map(.tab), .createChild)
        XCTAssertEqual(map(.enter), .createSibling)
        XCTAssertEqual(map(.enter, .shift), .createSiblingBefore)
        XCTAssertEqual(map(.enter, .command), .createParent)
        XCTAssertEqual(map(.space), .beginEdit)
        XCTAssertEqual(map(.f2), .beginEdit)
        XCTAssertEqual(map(.delete), .deleteSelection)
        XCTAssertEqual(map(.backspace), .deleteSelection)
        XCTAssertEqual(map(.backspace, .command), .deleteSelection)
        XCTAssertEqual(map(.character("z"), .command), .undo)
        XCTAssertEqual(map(.character("Z"), [.command, .shift]), .redo)
        XCTAssertEqual(map(.character("y"), .command), .redo)
        XCTAssertEqual(map(.character("a"), .command), .selectAllTopics)
        XCTAssertEqual(map(.character("a"), [.command, .shift]), .selectAllSiblings)
        XCTAssertEqual(map(.character("a"), [.command, .option]), .selectAllChildren)
        XCTAssertEqual(map(.enter, .option), .openProperties)
        XCTAssertEqual(map(.character("r"), .command), .jumpToCentralTopic)
        XCTAssertEqual(map(.character("+")), .expandBranch)
        XCTAssertEqual(map(.character("-")), .collapseBranch)
        XCTAssertEqual(map(.character("*")), .expandAll)
        XCTAssertEqual(map(.character("/")), .collapseAll)
        XCTAssertEqual(map(.up, .option), .moveTopic(.up))
        XCTAssertEqual(map(.down, .option), .moveTopic(.down))
        XCTAssertEqual(map(.character("l"), [.command, .shift]), .showShortcutHelp)
        XCTAssertEqual(map(.character("f"), .command), .find)
        // 大纲 / 沉浸 ship unbound: binding them adds a key, never changes one.
        XCTAssertNil(ShortcutBindings.catalogDefaults.chord(for: .toggleOutline))
        XCTAssertNil(ShortcutBindings.catalogDefaults.chord(for: .toggleImmersive))
    }

    func testStorageRoundTripsOnlyTheRowsTheUserChanged() {
        var bindings = ShortcutBindings.catalogDefaults
        XCTAssertTrue(bindings.storage.isEmpty)
        let chord = XMindShortcutCatalog.ShortcutChord(key: .character("k"), modifiers: [.command, .option])
        bindings.bind(chord, to: .beginEdit)
        XCTAssertEqual(bindings.storage, ["beginEdit": chord.storageValue])
        XCTAssertEqual(ShortcutBindings.decode(bindings.storage), bindings)
        XCTAssertFalse(bindings.isDefault(.beginEdit))

        bindings.reset(.beginEdit)
        XCTAssertTrue(bindings.isAllDefault)
        XCTAssertTrue(bindings.storage.isEmpty)
        XCTAssertEqual(bindings.displayText(for: .beginEdit), "Space")
    }

    func testGarbageOrUnknownStorageFallsBackToTheShippedTable() {
        XCTAssertEqual(
            ShortcutBindings.decode(["createChild": "not-a-chord"]),
            .catalogDefaults
        )
        XCTAssertEqual(
            ShortcutBindings.decode(["noSuchCommand": "2:z"]),
            .catalogDefaults
        )
        // A stale default written by an older build is not an override either.
        XCTAssertEqual(
            ShortcutBindings.decode(["createChild": "0:tab"]),
            .catalogDefaults
        )
    }

    // MARK: - Helpers

    private func event(
        _ key: KeyToken,
        _ modifiers: KeyModifiers = [],
        mode: KeyboardMode = .command
    ) -> KeyEvent {
        KeyEvent(key: key, modifiers: modifiers, mode: mode, isComposing: false)
    }

    private func map(
        _ key: KeyToken,
        _ modifiers: KeyModifiers = [],
        mode: KeyboardMode = .command,
        composing: Bool = false
    ) -> MindMapCommand? {
        KeyboardCommandMapper.map(
            KeyEvent(key: key, modifiers: modifiers, mode: mode, isComposing: composing)
        )
    }

    @discardableResult
    private func press(
        _ key: KeyToken,
        _ modifiers: KeyModifiers = [],
        session: inout MindMapKeyboardSession,
        document: inout MindMapDocument,
        composing: Bool? = nil
    ) -> MindMapCommand? {
        let frames = LayoutEngine().layout(document)
        let event = KeyEvent(
            key: key,
            modifiers: modifiers,
            mode: session.mode,
            isComposing: composing ?? session.isComposing
        )
        return session.handle(event, document: &document, frames: frames)
    }
}

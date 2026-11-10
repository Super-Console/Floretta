import XCTest

/// The named chrome surfaces call Apple's glass APIs. This machine cannot
/// render light and dark screenshots; the contract is the source.
final class AppleGlassChromeContractTests: XCTestCase {
    func testOfficialGlassAPIsAndTheVisualEffectFallbackAreDocumented() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        XCTAssertTrue(glass.contains("GlassEffectContainer"))
        XCTAssertTrue(glass.contains("glassEffect(.regular, in:"))
        XCTAssertTrue(glass.contains("NSGlassEffectView"))
        XCTAssertTrue(glass.contains("NSVisualEffectView"))
        XCTAssertTrue(glass.contains(".underWindowBackground"))
        XCTAssertTrue(glass.contains(".sidebar"))
        XCTAssertTrue(glass.contains("blendingMode = .behindWindow"))
        XCTAssertTrue(glass.contains("case swiftUIGlassEffect"))
        XCTAssertTrue(glass.contains("case nsGlassEffectView"))
        XCTAssertTrue(glass.contains("case nsVisualEffectView"))
        XCTAssertTrue(glass.contains("case unpainted"))
    }

    func testGlassFileDoesNotInventABlurWashOrShadow() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        XCTAssertFalse(glass.contains(".blur("))
        XCTAssertFalse(glass.contains("ultraThinMaterial"))
        XCTAssertFalse(glass.contains("regularMaterial"))
        XCTAssertFalse(glass.contains("Color.white"))
        XCTAssertFalse(glass.contains("Color.black"))
        XCTAssertFalse(glass.contains(".shadow("))
        XCTAssertFalse(glass.contains("colorScheme"))
    }

    func testLabelsOnGlassStayLegibleInLightAndDark() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        XCTAssertTrue(glass.contains(".foregroundStyle(.primary)"))
        XCTAssertTrue(glass.contains("light appearance"))
        XCTAssertTrue(glass.contains("dark appearance"))
        XCTAssertTrue(glass.contains("does not paint a white or black wash"))
    }

    func testMacInspectorPanelIsNotReimplementedHere() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        let plate = try slice(glass, from: "var body: some View", until: "private func hosted")
        XCTAssertTrue(plate.contains("role == .inspectorPanel"))
        XCTAssertTrue(plate.contains("role == .toolbarFloatingButton"))
        XCTAssertTrue(plate.contains("content"))
        XCTAssertTrue(glass.contains("inspector.panel.glass"))
        XCTAssertFalse(glass.contains("struct AppleGlassPanel"))
        XCTAssertFalse(glass.contains("editor.inspector.glass"))
        XCTAssertFalse(glass.contains("editor.outline.glass"))
    }

    func testNamedSurfacesUseTheOfficialChrome() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let canvas = try repoFile("Floretta/Shared/Canvas/InfiniteCanvas.swift")
        let home = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")

        XCTAssertTrue(editor.contains(".appleGlassChrome(.inspectorPanel)"))
        XCTAssertTrue(editor.contains("inspector.panel.glass") == false)
        XCTAssertTrue(editor.contains(".appleGlassChrome(.segmentedContainer)"))
        XCTAssertTrue(editor.contains(".pickerStyle(.segmented)"))
        XCTAssertTrue(editor.contains("text(tab.titleKey)"))
        XCTAssertTrue(editor.contains("text(\"演说\")"))
        XCTAssertTrue(editor.contains("accessibilityIdentifier(\"inspector.tabs\")"))
        let tabs = try repoFile("FlorettaCore/Shell/InspectorStyle.swift")
        XCTAssertTrue(tabs.contains("case .style: \"样式\""))
        XCTAssertTrue(tabs.contains("case .presentation: \"演说\""))
        XCTAssertTrue(tabs.contains("case .map: \"导图\""))

        let empty = try slice(editor, from: "systemName: \"paintbrush\"", until: "description:")
        XCTAssertTrue(empty.contains(".appleGlassChrome(.iconButton)"))
        XCTAssertTrue(empty.contains("inspector.empty.brush"))

        let zen = try slice(editor, from: "private var immersiveExit", until: "private var insertMenu")
        XCTAssertTrue(zen.contains(".appleGlassChrome(.iconButton)"))
        XCTAssertTrue(zen.contains("zen.exit"))
        XCTAssertFalse(zen.contains("ultraThinMaterial"))
        XCTAssertFalse(zen.contains(".blur("))

        XCTAssertTrue(editor.contains(".appleGlassChrome(.bottomBarCapsule)"))
        XCTAssertTrue(editor.contains("editor.bottomBar"))
        XCTAssertTrue(editor.contains("TopicStatusBar("))
        XCTAssertTrue(editor.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(editor.contains("\"字数: %lld\""))
        XCTAssertTrue(canvas.contains(".appleGlassChrome(.bottomBarCapsule)"))
        XCTAssertFalse(canvas.contains("ultraThinMaterial"))
        XCTAssertFalse(canvas.contains("Capsule().fill("))

        let principal = try slice(
            editor,
            from: "ToolbarItemGroup(placement: .principal)",
            until: "ToolbarItemGroup(placement: .primaryAction)"
        )
        XCTAssertTrue(principal.contains(".appleGlassChrome(.toolbarFloatingButton)"))
        XCTAssertTrue(principal.contains("toolbarControl(.undo)"))
        XCTAssertTrue(principal.contains("toolbarControl(.redo)"))
        XCTAssertTrue(principal.contains("toolbarControl(.delete)"))

        let primary = try slice(
            editor,
            from: "ToolbarItemGroup(placement: .primaryAction)",
            until: ".toolbarBackground(.hidden, for: .windowToolbar)"
        )
        XCTAssertTrue(primary.contains(".appleGlassChrome(.toolbarFloatingButton)"))
        XCTAssertTrue(primary.contains("toolbarControl(.insert)"))
        XCTAssertTrue(primary.contains("toolbarControl(.zoom)"))

        XCTAssertFalse(home.contains("appleGlassChrome"))
        XCTAssertFalse(editor.contains(".blur("))
    }

    func testBackButtonAndHomeChromeAreLeftAlone() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let leading = try slice(
            editor,
            from: "ToolbarItem(placement: .cancellationAction)",
            until: "ToolbarItemGroup(placement: .principal)"
        )
        XCTAssertTrue(leading.contains("chevron.backward"))
        XCTAssertTrue(leading.contains("basicChain.back"))
        XCTAssertTrue(leading.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(leading.contains("contentShape(Circle())"))
        XCTAssertTrue(leading.contains(".appleGlassChrome(.iconButton)"))
        XCTAssertFalse(leading.contains("ultraThinMaterial"))
    }

    func testInspectorFormsKeepNativeControls() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let style = try slice(editor, from: "private var appearanceForm", until: "private var shape:")
        XCTAssertTrue(style.contains("Slider("))
        XCTAssertTrue(style.contains("ColorPicker("))
        XCTAssertTrue(style.contains("Toggle("))
        XCTAssertTrue(style.contains(".formStyle(.grouped)"))
        XCTAssertTrue(style.contains(".appleGlassInspectorFormPlate()"))
        XCTAssertFalse(style.contains(".blur("))
        XCTAssertFalse(style.contains("glassEffect"))
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

import XCTest

/// The named chrome surfaces call Apple's glass APIs. This machine cannot
/// render light and dark screenshots; the contract is the source.
final class AppleGlassChromeContractTests: XCTestCase {
    func testInspectorModeSwitchKeepsNativePickerInStableTopInset() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let body = try slice(editor, from: "private var inspectorBody", until: "private var inspectorHeader")
        let header = try slice(editor, from: "private var inspectorHeader", until: "private var showsSheetDismissHandle")
        let picker = try slice(editor, from: "private var inspectorTabPicker", until: "@ViewBuilder\n    private var inspectorTabPage")

        XCTAssertTrue(body.contains(".safeAreaInset(edge: .top"))
        XCTAssertTrue(body.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
        XCTAssertTrue(header.contains("inspectorTabPicker"))
        XCTAssertTrue(header.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(header.contains(".frame(minHeight: 64)"), "the shared inspector header reserves height even when the selected page is empty")
        XCTAssertTrue(picker.contains("Picker(text(\"检查器\"), selection: $inspectorTab)"))
        XCTAssertTrue(picker.contains(".pickerStyle(.segmented)"))
        XCTAssertFalse(header.contains("GlassEffectContainer"), "mode changes must not replace the native picker with positioned custom content")
        XCTAssertFalse(body.contains("overlay"), "selected mode is not redrawn as an overlay on the canvas")
    }

    func testMacDocumentTitleAndBackButtonOccupyLeadingNavigationRegion() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let leading = try slice(
            editor,
            from: "private var macToolbarItemsLeading",
            until: "private var macToolbarItemsPrimary"
        )
        let sharedToolbar = try slice(
            editor,
            from: "private var editorToolbar",
            until: ".toolbar(id: \"floretta.editor\")"
        )
        let macToolbar = try slice(editor, from: ".toolbar(id: \"floretta.editor\")", until: ".toolbarBackground(.hidden, for: .windowToolbar)")
        let leadingPosition = try XCTUnwrap(macToolbar.range(of: "macToolbarItemsLeading")).lowerBound
        let actionsPosition = try XCTUnwrap(macToolbar.range(of: "macToolbarItemsPrimary")).lowerBound

        XCTAssertTrue(leading.contains("ToolbarItem(id: \"document.navigation\", placement: .navigation)"), "back and title share the leading navigation slot")
        XCTAssertTrue(leading.contains("Button(action: onClose)"))
        XCTAssertTrue(leading.contains("HStack(spacing: 8)"), "the title and back glyph are one system capsule, not separate items")
        XCTAssertTrue(leading.contains("document.title"))
        XCTAssertFalse(leading.contains(".appleGlassChrome(.floatingPanel)"), "the leading capsule is system glass; the title must not stack a custom plate inside it")
        XCTAssertTrue(sharedToolbar.contains("#if os(iOS)"))
        XCTAssertFalse(sharedToolbar.contains("leadingDocumentChrome"), "the old cancellationAction title/back capsule must not also be installed on macOS")
        XCTAssertLessThan(leadingPosition, actionsPosition)
        XCTAssertTrue(macToolbar.contains("macToolbarItemsPrimary"), "share/zoom/fit/overflow remain in their existing trailing actions group")
    }

    func testMacTitlebarGlassDoesNotExtendTheHomeGridIntoItsBackdrop() throws {
        let content = try repoFile("Floretta/Shared/ContentView.swift")
        let macShell = try slice(content, from: "// One column. 设置 is the standard", until: "#endif")
        let home = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let recents = try slice(home, from: "private var recentBody", until: "private var filtered")
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let activeLightBackend = try slice(glass, from: "static let renderingStyle", until: "/// The three system scenes")
        let fallbackPlate = try slice(glass, from: "static func updateVisualEffectView", until: "#endif\n\n#if os(macOS)")
        let nativePlate = try slice(glass, from: "private func configure(_ view: NSVisualEffectView)", until: "}\n#endif")
        let fadeRoles = try slice(glass, from: "var fadesBottomEdge: Bool", until: "/// Scene used to pick")

        XCTAssertFalse(macShell.contains("backgroundExtensionEffect()"), "Mac must not extend Home detail/grid pixels behind the window titlebar glass")
        XCTAssertFalse(content.contains("backgroundExtensionEffect()"), "the single-column home has no titlebar band to extend into")
        XCTAssertFalse(content.contains("NavigationSplitView"), "the home is one column on macOS and iPad")
        XCTAssertTrue(recents.contains("LazyVGrid"))
        XCTAssertEqual(recents.components(separatedBy: "LazyVGrid").count - 1, 1, "the recents grid must have one rendered instance")
        XCTAssertFalse(recents.contains("appleGlassChrome"), "the grid is rendered once as content, never supplied as a chrome background")
        XCTAssertTrue(activeLightBackend.contains("= .light"))
        XCTAssertTrue(glass.contains(".background(role.lightUnderlayMaterial, in: shape)"))
        XCTAssertTrue(glass.contains(".regular.tint(AppleGlassChromeMetrics.lightTint)"))
        XCTAssertTrue(fallbackPlate.contains("view.blendingMode = role.fallbackBlendingMode"))
        XCTAssertTrue(nativePlate.contains("view.blendingMode = role.nativeBlendingMode"))
        XCTAssertTrue(glass.contains("case .header, .hud: .withinWindow"), "withinWindow exists only on the explicitly selected native header/HUD path")
        XCTAssertTrue(fadeRoles.contains(".toolbarFloatingButton"))
        XCTAssertFalse(try slice(fadeRoles, from: "case .floatingPanel", until: "case .inspectorPanel").contains("toolbarFloatingButton"), "the titlebar glass is excluded from the content-band bottom mask")
        XCTAssertTrue(fadeRoles.contains("case .inspectorPanel, .sidebarColumn, .iconButton, .toolbarFloatingButton"))
        XCTAssertEqual(editor.components(separatedBy: ".toolbarBackground(.hidden, for: .windowToolbar)").count - 1, 1, "the editor hides the system background once; no second material is installed there")
    }

    func testSettingsUsesSystemNavigationAndFormWithoutGlassHeaderBand() throws {
        let home = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let settings = try slice(home, from: "struct SettingsView: View", until: "private func text")

        XCTAssertTrue(settings.contains("NavigationStack"))
        XCTAssertTrue(settings.contains("Form {"))
        XCTAssertFalse(settings.contains("appleGlassChrome"), "Settings uses the system navigation/form header, not a custom glass band sampling content underneath")
    }

    func testSidebarSelectionUsesOnlyTheNativeListSelection() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        let inset = try slice(glass, from: "func sidebarSelectionInset()", until: "private struct GlassBandBottomFadeModifier")
        XCTAssertTrue(inset.contains(".listRowInsets("))
        XCTAssertTrue(inset.contains(".listRowBackground(Color.clear)"))
        XCTAssertFalse(inset.contains("RoundedRectangle"))
        // The editor's outline column still uses the sidebar glass role; the home
        // sidebar it was first written for is gone.
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        XCTAssertTrue(editor.contains(".appleGlassChrome(.sidebarColumn)"))
        XCTAssertFalse(try repoFile("Floretta/Shared/ContentView.swift").contains(".appleGlassChrome(.sidebarColumn)"))
    }

    func testOfficialGlassAPIsAndTheVisualEffectFallbackAreDocumented() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        XCTAssertTrue(glass.contains("GlassEffectContainer"))
        XCTAssertTrue(glass.contains(".glassEffect("))
        XCTAssertTrue(glass.contains(".regular.tint("))
        XCTAssertTrue(glass.contains("AppleGlassChromeMetrics.lightTint"))
        XCTAssertTrue(glass.contains("NSGlassEffectView"))
        XCTAssertTrue(glass.contains("NSVisualEffectView"))
        XCTAssertTrue(glass.contains(".underWindowBackground"))
        XCTAssertTrue(glass.contains(".sidebar"))
        XCTAssertTrue(glass.contains("var fallbackBlendingMode"))
        XCTAssertTrue(glass.contains("floatsOverContent ? .withinWindow : .behindWindow"))
        XCTAssertTrue(glass.contains("case .header, .hud: .withinWindow"))
        XCTAssertTrue(glass.contains("case swiftUIGlassEffect"))
        XCTAssertTrue(glass.contains("case nsGlassEffectView"))
        XCTAssertTrue(glass.contains("case nsVisualEffectView"))
        XCTAssertTrue(glass.contains("case unpainted"))
        XCTAssertTrue(glass.contains("case sidebarColumn"))
        XCTAssertTrue(glass.contains("case floatingPanel"))
    }

    func testGlassFileDoesNotInventABlurWashOrShadow() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        XCTAssertFalse(glass.contains(".blur("))
        XCTAssertFalse(glass.contains("ultraThinMaterial"))
        XCTAssertFalse(glass.contains("regularMaterial"))
        XCTAssertFalse(glass.contains(".shadow("))
        XCTAssertFalse(glass.contains("colorScheme"))

        // Colors and gradients are forbidden when they paint a glass-like
        // background, but are valid inside the dedicated alpha-mask modifier.
        let mask = try slice(
            glass,
            from: "content.mask {",
            until: "private struct AppleGlassChromePlate"
        )
        XCTAssertTrue(mask.contains("Rectangle().fill(Color.black)"))
        XCTAssertTrue(mask.contains("LinearGradient("))
        XCTAssertTrue(mask.contains("colors: [.black, .clear]"))
        let glassPainting = glass.replacingOccurrences(of: mask, with: "")
        XCTAssertFalse(glassPainting.contains("LinearGradient("))
        XCTAssertFalse(glassPainting.contains("RadialGradient("))
        XCTAssertFalse(glassPainting.contains("AngularGradient("))
        XCTAssertFalse(glassPainting.contains(".fill(Color.white"))
        XCTAssertFalse(glassPainting.contains(".fill(Color.black"))
        XCTAssertFalse(glassPainting.contains(".background(Color.white"))
        XCTAssertFalse(glassPainting.contains(".background(Color.black"))
        XCTAssertFalse(glassPainting.contains("Color.white.opacity("))
        XCTAssertFalse(glassPainting.contains("Color.black.opacity("))
    }

    /// A plate over the canvas must blur the canvas; a plate that owns a
    /// column must blur the window backdrop. The split is one role property,
    /// and `.behindWindow` on a floating capsule is the cut-off-bar bug.
    func testFloatingChromeSamplesWindowContentWhileColumnsKeepTheBackdrop() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        let floats = try slice(glass, from: "var floatsOverContent: Bool", until: "var lightUnderlayMaterial")
        XCTAssertTrue(floats.contains("case .bottomBarCapsule, .floatingPanel, .canvasFloatingButton:\n            return true"))
        for column in [".inspectorPanel", ".sidebarColumn"] {
            XCTAssertTrue(floats.contains(column), column)
        }
        XCTAssertTrue(floats.contains("return false"))
        XCTAssertTrue(glass.contains("floatsOverContent ? .thickMaterial : .thinMaterial"))
        XCTAssertTrue(glass.contains("floatsOverContent ? .withinWindow : .behindWindow"))

        // Material level: floating plates are raised, columns are not.
        let materials = try slice(glass, from: "var fallbackMaterial: NSVisualEffectView.Material", until: "var fallbackBlendingMode")
        XCTAssertTrue(materials.contains("case .bottomBarCapsule, .canvasFloatingButton:\n            .hudWindow"))
        XCTAssertTrue(materials.contains("case .floatingPanel:\n            .popover"))
        XCTAssertTrue(materials.contains("case .inspectorPanel, .sidebarColumn:\n            .sidebar"))

        // Both AppKit plates read the mode from the role, never a literal.
        XCTAssertEqual(glass.components(separatedBy: "blendingMode = role.fallbackBlendingMode").count - 1, 2)
        XCTAssertFalse(glass.contains("blendingMode = .behindWindow"))
        XCTAssertFalse(glass.contains("blendingMode = .withinWindow"))
        XCTAssertTrue(try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift").contains(".appleGlassChrome(.bottomBarCapsule)"))
    }

    /// A system toolbar item is already glass. A plate inside it is the
    /// double-capsule bug, so `toolbarFloatingButton` draws nothing on macOS —
    /// it was only a no-op on iOS — and keeps drawing nothing on iOS.
    func testToolbarItemsDrawNoSecondPlateOnEitherPlatform() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")

        let draws = try slice(glass, from: "var drawsPlate: Bool", until: "var floatsOverContent: Bool")
        XCTAssertTrue(
            draws.contains("case .toolbarFloatingButton:\n            return false"),
            "the toolbar item keeps the system capsule, on both platforms"
        )
        XCTAssertFalse(
            draws.contains("case .toolbarFloatingButton:\n            return true"),
            "no platform may paint a second capsule inside a toolbar item"
        )
        XCTAssertTrue(draws.contains("case .inspectorPanel:\n            #if os(macOS)\n            return false"))
        XCTAssertTrue(draws.contains("case .segmentedContainer, .iconButton, .bottomBarCapsule, .sidebarColumn, .floatingPanel, .canvasFloatingButton:\n            return true"))

        // One gate in the plate: no platform branch that can drift apart again.
        let plate = try slice(glass, from: "var body: some View", until: "private func hosted")
        XCTAssertTrue(plate.contains("if role.drawsPlate {"))
        XCTAssertFalse(plate.contains("#if os(macOS)"))
        XCTAssertFalse(plate.contains("role == .toolbarFloatingButton"))
        XCTAssertFalse(plate.contains("role == .inspectorPanel"))

        // The toolbars keep calling the role: the fix is the role, not twelve
        // deleted call sites that would come back one at a time.
        let macItem = try slice(editor, from: "private func macItem(", until: "private var insertMenu")
        XCTAssertTrue(macItem.contains(".appleGlassChrome(.toolbarFloatingButton)"))
        for item in ["private var insertMenu", "private var shareMenu", "private var moreMenu"] {
            let menu = try slice(editor, from: item, until: "\n    }\n")
            XCTAssertTrue(menu.contains(".appleGlassChrome(.toolbarFloatingButton)"), item)
        }

        // A button over the canvas is not a toolbar item: the Zen exit keeps a
        // plate, and the bottom capsules keep theirs.
        let zenExit = try slice(editor, from: ".overlay(alignment: .topTrailing)", until: ".onChange(of: regionDraftToken)")
        XCTAssertTrue(zenExit.contains(".appleGlassChrome(.canvasFloatingButton)"))
        XCTAssertFalse(zenExit.contains(".appleGlassChrome(.toolbarFloatingButton)"))
        XCTAssertTrue(try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift").contains(".appleGlassChrome(.bottomBarCapsule)"))
        XCTAssertTrue(draws.contains(".canvasFloatingButton"))
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
        XCTAssertTrue(plate.contains("role.drawsPlate"))
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
        XCTAssertTrue(editor.contains("accessibilityIdentifier(\"inspector.tabs\")"))
        XCTAssertFalse(editor.contains("text(\"演说\")"), "no 演说 tab ships")
        let tabs = try repoFile("FlorettaCore/Shell/InspectorStyle.swift")
        XCTAssertTrue(tabs.contains("case .style: \"样式\""))
        XCTAssertFalse(tabs.contains("case .presentation: \"演说\""), "no 演说 tab ships")
        XCTAssertTrue(tabs.contains("case .map: \"导图\""))

        let empty = try slice(editor, from: "text(\"选择一个主题\")", until: "accessibilityIdentifier(\"inspector.empty\")")
        XCTAssertTrue(empty.contains(".appleGlassChrome(.iconButton)"))
        XCTAssertTrue(empty.contains("inspector.empty.brush"))
        XCTAssertTrue(empty.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"), "empty content fills the shared page area instead of constraining the header")

        // Zen exit is hidden by default and floats out only after a canvas tap;
        // the immersive canvas must not have a persistent chrome button.
        XCTAssertFalse(editor.contains("private var immersiveExit"))
        let zenExit = try slice(
            editor,
            from: ".overlay(alignment: .topTrailing)",
            until: ".onChange(of: regionDraftToken)"
        )
        XCTAssertTrue(zenExit.contains("if session.zen.isActive && isExitAffordanceRevealed"))
        XCTAssertTrue(zenExit.contains("accessibilityIdentifier(\"zen.exit\")"))
        XCTAssertTrue(zenExit.contains(".appleGlassChrome(.canvasFloatingButton)"))

        XCTAssertTrue(editor.contains(".appleGlassChrome(.bottomBarCapsule)"))
        XCTAssertTrue(editor.contains("editor.bottomBar"))
        XCTAssertTrue(editor.contains("EditorStatusStrip("))
        XCTAssertFalse(editor.contains("TopicStatusBar("))
        XCTAssertTrue(editor.contains(".overlay(alignment: .bottom)"))
        let canvasTabs = try slice(
            editor,
            from: "private var canvasTabBar",
            until: "private var tagFilterBanner"
        )
        XCTAssertTrue(canvasTabs.contains("accessibilityIdentifier(\"canvas.tabs\")"))
        XCTAssertTrue(canvasTabs.contains("EditorStatusBarChrome.controlMinHeight"))
        XCTAssertTrue(canvasTabs.contains("appleGlassChrome(.bottomBarCapsule)"))
        XCTAssertFalse(canvasTabs.contains("floatingPanel"))
        XCTAssertFalse(canvasTabs.contains(".shadow("))
        let status = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        XCTAssertTrue(status.contains("\"字数 %lld\""))
        XCTAssertTrue(status.contains("accessibilityIdentifier(\"statusBar.zoom\")"))
        XCTAssertTrue(status.contains(".appleGlassChrome(.bottomBarCapsule)"))
        XCTAssertFalse(editor.contains("accessibilityIdentifier(\"editor.zoom\")"))
        XCTAssertTrue(canvas.contains(".appleGlassChrome(.bottomBarCapsule)"))
        XCTAssertFalse(canvas.contains("ultraThinMaterial"))
        XCTAssertFalse(canvas.contains("regularMaterial"))
        XCTAssertFalse(canvas.contains("Capsule().fill("))
        let audio = try repoFile("Floretta/Shared/Canvas/CanvasAudioPlaybackBar.swift")
        XCTAssertTrue(audio.contains(".appleGlassChrome(.floatingPanel)"))
        XCTAssertFalse(audio.contains("regularMaterial"))

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
        XCTAssertTrue(primary.contains("accessibilityIdentifier(\"inspector.open\")"))
        XCTAssertFalse(primary.contains("toolbarControl(.zoom)"), "the status capsule owns zoom (TD-003)")
        XCTAssertFalse(primary.contains("toolbarControl(.immersive)"), "full screen lives in the status capsule (TD-003)")
        XCTAssertFalse(primary.contains("toolbarControl(.share)"), "import/export is low frequency; it is in ••• (TD-006)")

        // 2026-11-15: the home page's one plate is the circular 设置 button, which
        // floats in the top-right corner and owns its own glass. The page itself
        // is still painted by `settings.homeBackground.palette`: no content
        // surface is supplied as a glass background, and no column or panel
        // plate is added.
        XCTAssertEqual(home.components(separatedBy: "appleGlassChrome").count - 1, 1)
        XCTAssertTrue(home.contains(".appleGlassChrome(.iconButton)"), "the 设置 button is the only plate on the home page")
        XCTAssertFalse(home.contains(".appleGlassChrome(.sidebarColumn)"))
        XCTAssertFalse(home.contains(".appleGlassChrome(.floatingPanel)"))
        XCTAssertTrue(home.contains("settings.homeBackground.palette"), "the home page paints the semantic background")
        XCTAssertFalse(editor.contains(".blur("))
        XCTAssertFalse(editor.contains("regularMaterial"))
        XCTAssertFalse(editor.contains(".background(.bar)"))
        XCTAssertTrue(editor.contains(".appleGlassChrome(.sidebarColumn)"))
        XCTAssertTrue(editor.contains(".appleGlassChrome(.floatingPanel)"))

        let content = try repoFile("Floretta/Shared/ContentView.swift")
        XCTAssertFalse(content.contains(".appleGlassChrome(.sidebarColumn)"), "the home sidebar column is gone")
        XCTAssertFalse(content.contains(".backgroundExtensionEffect()"))
        XCTAssertFalse(content.contains("regularMaterial"))
        XCTAssertFalse(content.contains("ultraThinMaterial"))
        XCTAssertFalse(content.contains(".blur("))
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

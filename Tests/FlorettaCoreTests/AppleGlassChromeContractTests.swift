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
        XCTAssertTrue(glass.contains("sampleSource == .windowContent ? .withinWindow : .behindWindow"), "the sample layer is decided in one place")
        // No chrome band is masked: a hand-drawn alpha gradient over an
        // official material is the fade the user asked to remove, on both
        // platforms. The plate ends at its shape's edge and the system
        // controls paint themselves.
        XCTAssertFalse(glass.contains("glassBandBottomFade"))
        XCTAssertFalse(glass.contains("fadesBottomEdge"))
        XCTAssertFalse(glass.contains("GlassBandBottomFadeModifier"))
        XCTAssertFalse(glass.contains("LinearGradient"))
        XCTAssertFalse(glass.contains(".mask {"))
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
        let inset = try slice(glass, from: "func sidebarSelectionInset()", until: "private struct AppleGlassChromePlate")
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
        XCTAssertTrue(glass.contains("sampleSource == .windowContent ? .withinWindow : .behindWindow"))
        XCTAssertTrue(glass.contains("case windowContent"))
        XCTAssertTrue(glass.contains("case windowBackdrop"))
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
        // The system material underlay is chosen once, in the role table
        // (`lightUnderlayMaterial`): thin for in-bar controls, regular for a
        // text column over the canvas, thick for a one-line capsule. A second
        // inline material would be a hand-rolled wash.
        XCTAssertEqual(glass.components(separatedBy: "return .regularMaterial").count - 1, 1)
        XCTAssertFalse(glass.contains(".shadow("))
        XCTAssertFalse(glass.contains("colorScheme"))

        // No gradient and no mask may paint the glass, in any form. The one
        // exception this file used to carry — the alpha-mask bottom-edge fade —
        // is gone: the user saw it as a fading bottom bar, and it was a
        // hand-drawn gradient on top of Apple's glass rather than a system
        // control.
        XCTAssertFalse(glass.contains("content.mask {"))
        XCTAssertFalse(glass.contains("LinearGradient("))
        XCTAssertFalse(glass.contains("RadialGradient("))
        XCTAssertFalse(glass.contains("AngularGradient("))
        XCTAssertFalse(glass.contains("Rectangle().fill(Color.black)"))
        XCTAssertFalse(glass.contains(".fill(Color.white"))
        XCTAssertFalse(glass.contains(".fill(Color.black"))
        XCTAssertFalse(glass.contains(".background(Color.white"))
        XCTAssertFalse(glass.contains(".background(Color.black"))
        XCTAssertFalse(glass.contains("Color.white.opacity("))
        XCTAssertFalse(glass.contains("Color.black.opacity("))
    }

    /// **The rule: a plate samples the layer it actually covers.** A panel that
    /// floats beside or over the canvas covers canvas pixels, so it blurs
    /// those. Only a surface that owns the window edge covers nothing but the
    /// window backdrop. `.behindWindow` on a panel sitting on canvas pixels is
    /// the "solid grey plate" bug: it blurs the desktop while the canvas it
    /// covers stays sharp.
    func testEveryPlateSamplesTheLayerItCovers() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        let sources = try slice(glass, from: "var sampleSource: GlassChromeSampleSource", until: "var lightUnderlayMaterial: Material")

        // Panels and capsules that sit on canvas pixels: the outline column is
        // in this list, because it is a panel over the canvas and not a column
        // of the window.
        XCTAssertTrue(sources.contains("case .bottomBarCapsule, .floatingPanel, .canvasFloatingButton, .sidebarColumn:\n            return .windowContent"))
        // The macOS inspector owns the trailing window edge; on iOS the same
        // inspector is presented over the canvas, so the answer is split.
        XCTAssertTrue(sources.contains("case .inspectorPanel:\n            #if os(macOS)\n            return .windowBackdrop"))
        XCTAssertTrue(sources.contains("#else\n            return .windowContent\n            #endif"))
        XCTAssertTrue(sources.contains("case .iconButton, .toolbarFloatingButton:\n            return .windowBackdrop"))

        // One mapping, read by all three styles, so the `.light` A/B style and
        // the `.native` style cannot blur different layers for the same role.
        XCTAssertEqual(
            glass.components(separatedBy: "? .withinWindow : .behindWindow").count - 1,
            1,
            "the blending mode is derived in one place"
        )
        XCTAssertTrue(glass.contains("var fallbackBlendingMode: NSVisualEffectView.BlendingMode { blendingMode }"))
        XCTAssertTrue(glass.contains("var nativeBlendingMode: NSVisualEffectView.BlendingMode { blendingMode }"))
        XCTAssertFalse(glass.contains("case .sidebar: .behindWindow"), "the native scene picks material, not sample layer")

        // Material level follows the same rule: a text column over the canvas
        // gets sidebar-weight diffusion, a one-line capsule the thick one.
        let materials = try slice(glass, from: "var fallbackMaterial: NSVisualEffectView.Material", until: "var blendingMode")
        XCTAssertTrue(materials.contains("case .bottomBarCapsule, .canvasFloatingButton:\n            .hudWindow"))
        XCTAssertTrue(materials.contains("case .floatingPanel:\n            .popover"))
        XCTAssertTrue(materials.contains("case .inspectorPanel, .sidebarColumn:\n            .sidebar"))
        XCTAssertTrue(glass.contains("case .sidebarColumn, .inspectorPanel:\n            return .regularMaterial"))
        XCTAssertFalse(glass.contains("floatsOverContent"), "the old boolean shortcut is gone; `sampleSource` is the only answer")

        // Both AppKit plates read the mode from the role, never a literal.
        XCTAssertEqual(glass.components(separatedBy: "blendingMode = role.fallbackBlendingMode").count - 1, 2)
        XCTAssertFalse(glass.contains("blendingMode = .behindWindow"))
        XCTAssertFalse(glass.contains("blendingMode = .withinWindow"))
        XCTAssertTrue(try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift").contains(".appleGlassChrome(.bottomBarCapsule)"))
    }

    /// The editor outline is the only `sidebarColumn` call site, it is one
    /// plate over the canvas, and the list under it hides its own background so
    /// the plate is what the reader sees.
    func testOutlinePanelIsOneGlassPlateOverTheCanvas() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let outline = try repoFile("Floretta/Shared/Outline/OutlineView.swift")
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")

        let stack = try slice(editor, from: "private var canvasStack", until: "private var bottomBarRow")
        let canvasPosition = try XCTUnwrap(stack.range(of: "InfiniteCanvas(")).lowerBound
        let panelPosition = try XCTUnwrap(stack.range(of: "if showOutline")).lowerBound
        XCTAssertLessThan(canvasPosition, panelPosition, "the outline is drawn above the canvas it covers")

        let panel = try slice(editor, from: "if showOutline, session.zen.chrome.showsSidebar", until: ".overlay(alignment: .top)")
        XCTAssertTrue(panel.contains(".appleGlassChrome(.sidebarColumn)"))
        XCTAssertEqual(
            panel.components(separatedBy: ".appleGlassChrome(").count - 1,
            1,
            "the outline is one plate; a second one on the panel is double glass"
        )
        XCTAssertFalse(panel.contains("glassEffect"), "no second glass layer inside the plate")
        XCTAssertFalse(panel.contains("Material"), "no hand-rolled material beside the plate")

        // Content, not chrome: the list must not paint over the glass, and it
        // must not carry a plate of its own.
        XCTAssertTrue(outline.contains(".listStyle(.sidebar)"))
        XCTAssertTrue(outline.contains(".scrollContentBackground(.hidden)"))
        XCTAssertFalse(outline.contains("appleGlassChrome"))
        XCTAssertTrue(
            glass.contains("case .sidebarColumn:\n            plated(inked(view), shape: RoundedRectangle(cornerRadius: AppleGlassChromeMetrics.sidebarCornerRadius"),
            "the column-shaped panel keeps its rounded continuous plate"
        )

        // The macOS inspector keeps the system column and its opaque rows: this
        // role draws no plate, and the row blocks are untouched by the change.
        XCTAssertTrue(glass.contains("case .inspectorPanel:\n            #if os(macOS)\n            return false"))
        XCTAssertGreaterThanOrEqual(
            editor.components(separatedBy: ".inspectorRowBlock(").count - 1,
            10,
            "the inspector rows stay opaque blocks on top of the panel glass"
        )
    }

    /// A system toolbar item is already glass. A plate inside it is the
    /// double-capsule bug, so `toolbarFloatingButton` draws nothing on macOS —
    /// it was only a no-op on iOS — and keeps drawing nothing on iOS.
    func testToolbarItemsDrawNoSecondPlateOnEitherPlatform() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")

        let draws = try slice(glass, from: "var drawsPlate: Bool", until: "var sampleSource: GlassChromeSampleSource")
        XCTAssertTrue(
            draws.contains("case .toolbarFloatingButton:\n            return false"),
            "the toolbar item keeps the system capsule, on both platforms"
        )
        XCTAssertFalse(
            draws.contains("case .toolbarFloatingButton:\n            return true"),
            "no platform may paint a second capsule inside a toolbar item"
        )
        XCTAssertTrue(draws.contains("case .inspectorPanel:\n            #if os(macOS)\n            return false"))
        XCTAssertTrue(draws.contains("case .iconButton, .bottomBarCapsule, .sidebarColumn, .floatingPanel, .canvasFloatingButton:\n            return true"))

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
        // The 样式 / 导图 switch is the system segmented control and nothing
        // else: no hand-plated capsule, no masked edge.
        XCTAssertFalse(editor.contains(".appleGlassChrome(.segmentedContainer)"))
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
        XCTAssertTrue(
            empty.contains(".frame(maxWidth: .infinity, minHeight: 180)"),
            "the empty state is a row of the style page's one form, so it fills the width and keeps a readable height instead of owning a second scroll view"
        )

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

        // 2026-11-16: 设置 is a system navigation-bar item (left of ⋯), so the
        // home page owns no plate at all: the bar draws the glass. The page
        // itself is still painted by `settings.homeBackground.palette`: no
        // content surface is supplied as a glass background, and no column or
        // panel plate is added.
        XCTAssertEqual(home.components(separatedBy: "appleGlassChrome").count - 1, 0, "the home bar item is system glass; no custom plate is left")
        XCTAssertFalse(home.contains(".appleGlassChrome(.iconButton)"))
        XCTAssertTrue(home.contains("\"home.settings\""))
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

    /// 2026-11-16: the back button carries exactly one plate, and that plate is
    /// the system bar item's own capsule. The `iconButton` plate that used to be
    /// stacked inside it is what the user saw as two layers of Liquid Glass.
    func testBackButtonHasExactlyOnePlatelessSystemCapsule() throws {
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
        XCTAssertFalse(leading.contains(".appleGlassChrome"), "the system capsule must stay the only plate")
        XCTAssertFalse(leading.contains("GlassEffectContainer"), "no second glass layer inside the bar item")
        XCTAssertFalse(leading.contains("ultraThinMaterial"))
    }

    /// Chrome moves with Apple's own motion, and Reduce Motion turns it off.
    /// Every animation in the editor asks `ChromeMotion`, so no call site can
    /// quietly ship a hand-written curve, a long duration, or a canvas
    /// animation.
    func testChromeMotionIsSystemAnimationAndHonoursReduceMotion() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")

        let motion = try slice(glass, from: "enum ChromeMotion", until: "static func resolved")
        XCTAssertTrue(motion.contains(".snappy(duration: 0.24)"), "the panel curve is the system snappy one")
        XCTAssertTrue(motion.contains(".smooth(duration: 0.18)"), "control feedback is the system smooth one")
        XCTAssertFalse(motion.contains(".linear("), "no hand-tuned curve")
        XCTAssertFalse(motion.contains(".timingCurve"), "no hand-tuned curve")
        for duration in [0.24, 0.18] {
            XCTAssertLessThan(duration, 0.35, "chrome animation stays under 0.35 s")
        }
        XCTAssertTrue(
            glass.contains("reduceMotion ? nil : animation"),
            "Reduce Motion is decided in one function, not at each call site"
        )

        // The outline panel arrives from its own edge and fades, and the value
        // that drives it is the panel flag alone, so the canvas does not animate.
        let stack = try slice(editor, from: "private var canvasStack", until: "private var bottomBarRow")
        XCTAssertTrue(stack.contains(".transition(.move(edge: .leading).combined(with: .opacity))"))
        XCTAssertTrue(
            stack.contains(".animation(ChromeMotion.resolved(ChromeMotion.panel, reduceMotion: reduceMotion), value: showOutline)"),
            "one value drives the panel transition"
        )
        XCTAssertFalse(stack.contains("withAnimation"), "no animation wraps a canvas redraw")

        // The inspector page cross-fades; the header stays in its inset.
        let inspector = try slice(editor, from: "private var inspectorBody", until: "private var inspectorHeader")
        XCTAssertTrue(inspector.contains(".transition(.opacity)"))
        XCTAssertTrue(inspector.contains("ChromeMotion.resolved(ChromeMotion.panel, reduceMotion: reduceMotion), value: inspectorTab"))

        // Nothing in this file animates on a literal curve.
        XCTAssertFalse(editor.contains(".animation(.easeIn"), "curves come from ChromeMotion")
        XCTAssertFalse(editor.contains(".animation(.linear("), "curves come from ChromeMotion")
        XCTAssertFalse(editor.contains(".animation(.spring("), "curves come from ChromeMotion")
    }

    func testInspectorFormsKeepNativeControls() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let style = try slice(editor, from: "private var appearanceSections", until: "private var shape:")
        XCTAssertTrue(style.contains("Slider("))
        XCTAssertTrue(style.contains("ColorPicker("))
        XCTAssertTrue(style.contains("Toggle("))
        // These are sections of the style page's one form: a nested form here
        // would be a second scroll view in the same column.
        XCTAssertFalse(style.contains("Form {"), "the node groups are sections, not a second scroll view")
        XCTAssertTrue(style.contains(".inspectorRowBlock()"))
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

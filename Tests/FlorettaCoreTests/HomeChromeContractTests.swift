import XCTest

/// Locks the home chrome to system controls, and locks the 2026-11-15 decision:
/// the home page is one column on macOS and iPad, and the commands that used to
/// sit in its sidebar live in the toolbar (and the macOS 文件 menu).
final class HomeChromeContractTests: XCTestCase {
    func testIPhoneHomeToolbarIsUnchanged() throws {
        let source = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let recent = try slice(source, from: "struct RecentPage", until: "struct NewMapPage")
        let phone = try slice(recent, from: "private var iphoneHomeToolbar", until: "/// iPad:")

        XCTAssertTrue(phone.contains("ToolbarItem(placement: .primaryAction)"))
        XCTAssertTrue(phone.contains("Menu {"))
        XCTAssertTrue(phone.contains("\"home.toolbarMenu\""))
        XCTAssertTrue(phone.contains("\"home.newMap\""))
        XCTAssertTrue(phone.contains("\"home.openFiles\""))
        XCTAssertTrue(phone.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(phone.contains("\"home.templates\""))
        XCTAssertTrue(phone.contains("\"home.open\""))
        XCTAssertTrue(phone.contains("homeSettingsToolbarItem"), "设置 is a bar item on the phone")
        XCTAssertFalse(phone.contains("ToolbarItemGroup"), "the phone keeps one grouped capsule")
        assertNoCustomChrome(phone)

        // 设置 is declared in the bar before the ⋯ menu, so the gear lands
        // immediately left of ⋯ — the slot the user asked for.
        let settings = try XCTUnwrap(phone.range(of: "homeSettingsToolbarItem")?.lowerBound)
        let more = try XCTUnwrap(phone.range(of: "\"home.toolbarMenu\"")?.lowerBound)
        XCTAssertLessThan(settings, more, "设置 must sit left of the ⋯ menu")

        // The old standalone strip above the search field left an empty band
        // under the large title; it is gone, not merely hidden.
        XCTAssertFalse(recent.contains(".safeAreaInset(edge: .top"), "设置 no longer reserves a strip above the search field")
        XCTAssertFalse(recent.contains("private var settingsButton"), "the floating settings button is replaced by the bar item")

        let search = try slice(recent, from: "#if os(iOS)", until: "#else")
        XCTAssertTrue(search.contains(".searchable("))
        XCTAssertTrue(search.contains("placement: .navigationBarDrawer(displayMode: .always)"))
        XCTAssertFalse(recent.contains("TextField"), "home search is a custom text field, not .searchable")
        XCTAssertFalse(source.contains("home.actionCapsule"))
        XCTAssertFalse(source.contains("home.tabCapsule"))
        XCTAssertFalse(source.contains("UltraThinMaterial"))
    }

    func testHomeSidebarIsGoneOnEveryPlatform() throws {
        let source = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        XCTAssertFalse(source.contains("struct HomeSidebar"), "the home sidebar is a list of commands, not navigation")
        XCTAssertFalse(source.contains("HomeSidebarRow"))
        XCTAssertFalse(source.contains("home.sidebar"), "the row identifiers went with the sidebar")
        XCTAssertFalse(source.contains("NavigationSplitView"))

        let appSettings = try repoFile("Floretta/Shared/Shell/AppSettings.swift")
        XCTAssertFalse(appSettings.contains("HomeSidebarRow"))
        XCTAssertFalse(appSettings.contains("HomeLibraryChrome"))
        XCTAssertFalse(appSettings.contains("preferredColumnVisibility"))
    }

    func testOpenCommandsAreOneMenuNotSidebarRows() throws {
        let source = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let recent = try slice(source, from: "/// 打开▾", until: "private func text")

        // 新建 is the primary button; the other three commands are menu items.
        XCTAssertTrue(source.contains("Label(text(\"新建导图\"), systemImage: \"plus\")"))
        XCTAssertTrue(recent.contains("\"home.openFiles\""))
        XCTAssertTrue(recent.contains("\"home.openICloud\""))
        XCTAssertTrue(recent.contains("\"home.browseLocal\""))
        XCTAssertTrue(recent.contains("\"home.open\""))

        let mac = try slice(source, from: "private var macHomeToolbar", until: "#endif")
        XCTAssertTrue(mac.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(mac.contains("openMenu"))
    }

    func testMacOSFileMenuCarriesTheSameThreeCommands() throws {
        let source = try repoFile("Floretta/Shared/FlorettaApp.swift")
        let menu = try slice(source, from: "// The three 打开 commands", until: "private func topicShortcut")

        XCTAssertTrue(menu.contains("requestHomeOpen(.files)"))
        XCTAssertTrue(menu.contains("requestHomeOpen(.iCloud)"))
        XCTAssertTrue(menu.contains("requestHomeOpen(.local)"))
        XCTAssertFalse(source.contains("library.tab = .settings"), "设置 is the Settings scene, not a page in the window")
        XCTAssertFalse(source.contains("CommandGroup(replacing: .appSettings)"))
    }

    func testMacOSWindowIsOneColumnWithNoSidebar() throws {
        let source = try repoFile("Floretta/Shared/ContentView.swift")
        let shell = try slice(source, from: "private var shell", until: "private var homeStack")

        let ios = try slice(shell, from: "#if os(iOS)", until: "#else")
        XCTAssertTrue(ios.contains("homeStack"))
        XCTAssertFalse(ios.contains("TabView"), "the phone lost its tab bar when 设置 stopped being a tab")
        XCTAssertFalse(ios.contains(".tabViewStyle"), "no tab bar style is left to apply")
        XCTAssertFalse(ios.contains(".tabItem"))
        assertNoCustomChrome(ios)

        let mac = try slice(shell, from: "#else", until: "#endif")
        XCTAssertFalse(mac.contains("NavigationSplitView"), "the Mac home is one column")
        XCTAssertFalse(mac.contains("TabView"), "macOS window chrome picked up the iOS tab bar")
        XCTAssertTrue(mac.contains("homeStack"))

        // The document view keeps its own 展开侧栏 control; only the home
        // sidebar is gone.
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        XCTAssertTrue(editor.contains("showInspector.toggle()"))
        XCTAssertTrue(editor.contains("\"inspector.open\""))
    }

    /// 2026-11-15: 设置 is a card the home page pulls up, not a first-level page.
    func testIPhoneHasNoSettingsTabAndOpensSettingsAsASheet() throws {
        let source = try repoFile("Floretta/Shared/ContentView.swift")
        let shell = try slice(source, from: "private var shell", until: "private var homeStack")
        let ios = try slice(shell, from: "#if os(iOS)", until: "#else")

        // A single 首页 tab would draw a bar with nothing to switch to.
        XCTAssertFalse(ios.contains("TabView"))
        XCTAssertFalse(ios.contains("ShellTab"))
        XCTAssertTrue(ios.contains(".sheet(isPresented: $showSettings)"), "设置 opens as a sheet")
        XCTAssertTrue(ios.contains("SettingsView(settings: settings)"))

        // Bottom card: two detents and the system drag indicator.
        XCTAssertTrue(ios.contains(".presentationDetents([.medium, .large])"))
        XCTAssertTrue(ios.contains(".presentationDragIndicator(.visible)"))

        // The tab model went with the bar.
        XCTAssertFalse(source.contains("library.tab"))
        let appSettings = try repoFile("Floretta/Shared/Shell/AppSettings.swift")
        XCTAssertFalse(appSettings.contains("enum ShellTab"), "no tab enum is left to select")
        XCTAssertFalse(appSettings.contains("case settings"))
        let session = try repoFile("Floretta/Shared/Shell/DocumentSession.swift")
        XCTAssertFalse(session.contains("var tab: ShellTab"))
    }

    /// ① 2026-11-16: the 设置 gear is the bar item immediately left of ⋯.
    /// Both are `ToolbarItem(placement: .primaryAction)` values, and toolbar
    /// order is declaration order, so the gear must be declared before the ⋯
    /// menu. This is the contract the user asked for: 右上角、⋯ 的左边。
    func testSettingsGearIsDeclaredLeftOfTheMoreMenu() throws {
        let source = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let recent = try slice(source, from: "struct RecentPage", until: "struct NewMapPage")
        let phone = try slice(recent, from: "private var iphoneHomeToolbar", until: "/// iPad:")

        let gear = try XCTUnwrap(phone.range(of: "homeSettingsToolbarItem")?.lowerBound)
        let more = try XCTUnwrap(phone.range(of: "Image(systemName: \"ellipsis\")")?.lowerBound)
        XCTAssertLessThan(gear, more, "设置 must be left of ⋯")

        // Both live in the same placement, or the bar could split them into two
        // clusters and the gear would not be adjacent to ⋯.
        let settingsItem = try slice(recent, from: "private var homeSettingsToolbarItem", until: "/// System navigation-bar items")
        XCTAssertTrue(settingsItem.contains("ToolbarItem(placement: .primaryAction)"))
        XCTAssertTrue(phone.contains("ToolbarItem(placement: .primaryAction)"))

        // 液态玻璃 comes from the bar, not from a plate drawn here.
        XCTAssertFalse(settingsItem.contains("appleGlassChrome"))
        XCTAssertFalse(settingsItem.contains("Material"))
    }

    /// 设置 is a system navigation-bar item, not a plate drawn by this file.
    /// The bar owns the Liquid Glass capsule (the look the user asked to keep),
    /// and the item is declared before the ⋯ menu so it lands left of it.
    func testHomeSettingsIsABarItemLeftOfTheMoreMenu() throws {
        let source = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let recent = try slice(source, from: "struct RecentPage", until: "struct NewMapPage")
        let item = try slice(recent, from: "private var homeSettingsToolbarItem", until: "/// System navigation-bar items")

        XCTAssertTrue(item.contains("ToolbarItem(placement: .primaryAction)"), "设置 is one system bar item")
        XCTAssertTrue(item.contains("Label(text(\"设置\"), systemImage: \"gearshape\")"), "the entry is the gearshape glyph")
        XCTAssertTrue(item.contains(".accessibilityIdentifier(\"home.settings\")"))
        XCTAssertTrue(item.contains(".accessibilityLabel(text(\"设置\"))"))
        XCTAssertFalse(item.contains(".appleGlassChrome"), "the bar is already glass; a plate inside it is the double-glass bug")
        XCTAssertFalse(item.contains("Circle()"), "no hand-drawn circular plate is left")
        XCTAssertFalse(item.contains(".frame(width: 44"), "the bar item's own platter is the hit target")

        // One declaration, used by both iOS toolbars (phone + iPad).
        XCTAssertEqual(
            recent.components(separatedBy: "homeSettingsToolbarItem").count - 1,
            3,
            "the phone and iPad bars both install the item"
        )
        XCTAssertFalse(recent.contains("TabView"))
    }

    func testSettingsCardHasNoLargeTitle() throws {
        let source = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let card = try slice(source, from: "struct SettingsView: View", until: "#if os(macOS)\n/// The macOS Settings window")

        XCTAssertTrue(card.contains(".navigationBarTitleDisplayMode(.inline)"), "the card carries an inline 设置 header")
        XCTAssertFalse(card.contains(".large"), "设置 is no longer a page, so it has no large title")
        XCTAssertFalse(card.contains("LargeTitle"))
        XCTAssertTrue(card.contains("Form {"))
        XCTAssertTrue(card.contains("Button(text(\"完成\"))"), "a card needs an explicit way out")
        XCTAssertTrue(card.contains("\"settings.done\""))
        for page in ["SettingsGeneralPage", "SettingsExportPage", "SettingsAboutPage"] {
            XCTAssertTrue(card.contains(page), page)
        }
        XCTAssertFalse(card.contains("appleGlassChrome"), "the card keeps the system bar")
    }

    func testMacOSSettingsIsAStandardSettingsSceneWithSystemTabs() throws {
        let app = try repoFile("Floretta/Shared/FlorettaApp.swift")
        XCTAssertTrue(app.contains("Settings {"), "macOS settings is the standard Settings scene")
        XCTAssertTrue(app.contains("MacSettingsScene(settings: settings)"))

        let source = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let scene = try slice(source, from: "struct MacSettingsScene", until: "\n}\n")
        XCTAssertTrue(scene.contains("TabView {"), "the window uses the system TabView")
        XCTAssertTrue(scene.contains("Tab {"), "tabs are system Tab values, not a drawn list")
        XCTAssertFalse(scene.contains("List(selection:"), "no hand-drawn left column")
        XCTAssertFalse(scene.contains("NavigationSplitView"))
        for page in ["SettingsGeneralPage", "SettingsExportPage", "SettingsAboutPage"] {
            XCTAssertTrue(scene.contains(page), page)
        }
    }

    func testSettingsItemsMovedWithoutLoss() throws {
        let source = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let general = try slice(source, from: "struct SettingsGeneralPage", until: "struct SettingsExportPage")
        let export = try slice(source, from: "struct SettingsExportPage", until: "struct SettingsAboutPage")
        let about = try slice(source, from: "struct SettingsAboutPage", until: "private struct NoticeSheet")
        let ios = try slice(source, from: "struct SettingsView", until: "#if os(macOS)\n/// The macOS Settings window")
        let mac = try slice(source, from: "struct MacSettingsScene", until: "\n}\n")

        for item in ["\"settings.language\"", "\"settings.appearance\"", "AppearanceSettingsPanel"] {
            XCTAssertTrue(general.contains(item), item)
        }
        for item in ["新建时默认视图", "PNG 导出倍率", "PNG 背景", "导出包含便签"] {
            XCTAssertTrue(export.contains(item), item)
        }
        for item in ["版本", "NOTICE"] {
            XCTAssertTrue(about.contains(item), item)
        }
        // iOS stacks all three pages in one form; macOS puts one page per tab.
        for page in ["SettingsGeneralPage", "SettingsExportPage", "SettingsAboutPage"] {
            XCTAssertTrue(ios.contains(page), page)
            XCTAssertTrue(mac.contains(page), page)
        }
    }

    /// The recents grid used to be a bare `.buttonStyle(.plain)` button, so a
    /// focused tile drew macOS's system focus effect: a saturated blue rounded
    /// rectangle around the whole card. The card owns its feedback now. This
    /// locks both halves of that decision — the system ring is off, and hover
    /// plus keyboard focus are still drawn — because a tile with no indicator at
    /// all strands keyboard users.
    func testRecentCardDropsTheSystemFocusRingButKeepsItsOwnFeedback() throws {
        let source = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let recents = try slice(source, from: "private var recentBody", until: "private var filtered")
        let card = try slice(source, from: "private struct RecentDocumentCard", until: "struct NewMapPage")

        // The grid renders the card view, not an inline button with a system ring.
        XCTAssertTrue(recents.contains("RecentDocumentCard("), "the grid renders the card view")
        XCTAssertFalse(recents.contains(".buttonStyle(.plain)"), "the plain button moved into RecentDocumentCard")
        XCTAssertTrue(recents.contains("GridItem(.adaptive(minimum: 160), spacing: 16)"))

        // 1. The default focus ring is gone on both platforms.
        XCTAssertTrue(card.contains(".focusEffectDisabled()"), "the system focus ring must be off")

        // 2. Feedback is replaced, not deleted: hover wash + keyboard border.
        XCTAssertTrue(card.contains("@FocusState"), "the card knows when it is keyboard focused")
        XCTAssertTrue(card.contains(".focused($focused)"), "keyboard focus drives the card's own indicator")
        XCTAssertTrue(card.contains(".onHover"), "pointer position is tracked")
        XCTAssertTrue(card.contains("Color.primary.opacity(hovering"), "hover uses an appearance-adaptive wash")
        XCTAssertTrue(card.contains("shape.strokeBorder("), "focus draws a hairline border, not the system ring")
        XCTAssertTrue(card.contains("Color.accentColor.opacity(focused"), "focus follows the system accent colour")
        XCTAssertTrue(card.contains("lineWidth: Self.focusBorder"), "the focus border is a hairline")
        XCTAssertFalse(card.contains(".focusable(false)"), "the tile stays keyboard reachable")
        XCTAssertFalse(card.contains(".buttonStyle(.bordered)"), "no system button chrome comes back")
        XCTAssertFalse(card.contains(".buttonStyle(.borderedProminent)"), "no system button chrome comes back")

        // 3. The feedback is painted without touching layout: a background fill
        //    and an overlay border inside the card's existing 12-point shape.
        XCTAssertTrue(card.contains(".padding(10)"), "the card's padding is unchanged")
        XCTAssertTrue(card.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(card.contains(".font(.caption)"), "the date line keeps its caption style")
        XCTAssertTrue(card.contains(".lineLimit(1)"), "the title still truncates to one line")
        XCTAssertTrue(card.contains(".overlay"), "the focus border is an overlay, so it adds no size")
        XCTAssertTrue(card.contains(".contentShape(shape)"))

        // The border radius is still the one the grid shipped with.
        XCTAssertTrue(card.components(separatedBy: "cornerRadius: 12, style: .continuous").count - 1 == 1)
        // Thumbnail geometry is untouched.
        let thumbnail = try slice(source, from: "private struct RecentDocumentThumbnail", until: "private extension Image")
        XCTAssertTrue(thumbnail.contains(".frame(height: 110)"))
        XCTAssertFalse(thumbnail.contains("focusEffectDisabled"), "the thumbnail is not the focus target")
    }

    private func assertNoCustomChrome(_ source: String, file: StaticString = #filePath, line: UInt = #line) {
        let forbidden = [
            "Capsule(",
            "ultraThinMaterial",
            "UIVisualEffect",
            "visualEffect",
            "home.actionCapsule",
            "home.tabCapsule",
        ]
        for token in forbidden {
            XCTAssertFalse(source.contains(token), token, file: file, line: line)
        }
    }

    private func repoFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func slice(_ source: String, from startMark: String, until endMark: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMark), startMark)
        let rest = source[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: endMark), endMark)
        return String(rest[..<end.lowerBound])
    }
}

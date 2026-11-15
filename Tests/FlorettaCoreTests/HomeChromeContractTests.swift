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
        XCTAssertFalse(phone.contains("ToolbarItemGroup"), "the phone keeps one grouped capsule")
        assertNoCustomChrome(phone)

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
        XCTAssertTrue(ios.contains("TabView(selection: $library.tab)"))
        XCTAssertTrue(ios.contains("Tab(value: ShellTab.home)"))
        XCTAssertTrue(ios.contains("Tab(value: ShellTab.settings)"))
        XCTAssertTrue(ios.contains(".tabViewStyle(.tabBarOnly)"))
        XCTAssertFalse(ios.contains(".tabItem"), "home tabs fell back to the legacy item style")
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

import XCTest

/// Locks the iOS home chrome to system controls. The old home showed a
/// three-icon toolbar group and a hand-drawn Home/Settings capsule. Those
/// slices fail if that group, or a custom capsule/blur, comes back.
final class HomeChromeContractTests: XCTestCase {
    func testIOSHomeToolbarIsASystemMenuNotACustomCapsule() throws {
        let source = try repoFile("Floretta/Shared/Shell/LibraryHome.swift")
        let recent = try slice(source, from: "struct RecentPage", until: "struct HomeSidebar")
        let ios = try slice(recent, from: "private var iosHomeToolbar", until: "private var macHomeToolbar")
        let mac = try slice(source, from: "private var macHomeToolbar", until: "private func text")

        XCTAssertTrue(ios.contains("ToolbarItem(placement: .primaryAction)"))
        XCTAssertTrue(ios.contains("Menu {"))
        XCTAssertTrue(ios.contains("\"home.toolbarMenu\""))
        XCTAssertTrue(ios.contains("\"home.newMap\""))
        XCTAssertTrue(ios.contains("\"home.templates\""))
        XCTAssertTrue(ios.contains("\"home.open\""))
        XCTAssertFalse(ios.contains("ToolbarItemGroup"), "iOS home actions are still one grouped capsule")
        XCTAssertFalse(ios.contains("Image(systemName: \"square.grid.2x2\")"))
        XCTAssertFalse(ios.contains("Image(systemName: \"folder\")"))
        assertNoCustomChrome(ios)

        XCTAssertTrue(mac.contains("ToolbarItemGroup(placement: .primaryAction)"))
        XCTAssertTrue(mac.contains("Image(systemName: \"plus\")"))
        XCTAssertTrue(mac.contains("Image(systemName: \"square.grid.2x2\")"))
        XCTAssertTrue(mac.contains("Image(systemName: \"folder\")"))

        let iosSearch = try slice(recent, from: "#if os(iOS)", until: "#else")
        XCTAssertTrue(iosSearch.contains(".searchable("))
        XCTAssertTrue(iosSearch.contains("placement: .navigationBarDrawer(displayMode: .always)"))
        XCTAssertFalse(recent.contains("TextField"), "home search is a custom text field, not .searchable")
        XCTAssertFalse(source.contains("home.actionCapsule"))
        XCTAssertFalse(source.contains("home.tabCapsule"))
    }

    func testIOSShellUsesSystemTabViewWithoutADrawnBar() throws {
        let source = try repoFile("Floretta/Shared/ContentView.swift")
        let shell = try slice(source, from: "private var shell", until: "The phone shows the recent stack")
        let ios = try slice(shell, from: "#if os(iOS)", until: "#else")
        let mac = try slice(shell, from: "#else", until: "#endif")

        XCTAssertTrue(ios.contains("TabView(selection: $library.tab)"))
        XCTAssertTrue(ios.contains("Tab(value: ShellTab.home)"))
        XCTAssertTrue(ios.contains("Tab(value: ShellTab.settings)"))
        XCTAssertTrue(ios.contains(".tabViewStyle(.tabBarOnly)"))
        XCTAssertFalse(ios.contains(".tabItem"), "home tabs fell back to the legacy item style")
        assertNoCustomChrome(ios)
        XCTAssertFalse(source.contains("home.actionCapsule"))
        XCTAssertFalse(source.contains("home.tabCapsule"))

        XCTAssertTrue(mac.contains("NavigationSplitView"))
        XCTAssertFalse(mac.contains("TabView"), "macOS window chrome picked up the iOS tab bar")
    }

    private func assertNoCustomChrome(_ source: String, file: StaticString = #filePath, line: UInt = #line) {
        let forbidden = [
            "Capsule(",
            "ultraThinMaterial",
            "UIVisualEffect",
            ".background(",
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
        let start = try XCTUnwrap(source.range(of: startMark))
        let rest = source[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: endMark))
        return String(rest[..<end.lowerBound])
    }
}

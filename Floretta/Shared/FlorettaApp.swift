import FlorettaCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Shared entry point. Floretta-macOS and Floretta-iOS each compile this file.
@main
struct FlorettaApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(FlorettaAppDelegate.self) private var appDelegate
    #else
    @UIApplicationDelegateAdaptor(FlorettaAppDelegate.self) private var appDelegate
    #endif

    @State private var recovery: RecoveryPresenter
    @State private var settings: AppSettings
    @State private var library: LibraryModel

    init() {
        ThemeFontCascade.registerBundledFonts()
        let session = AppLaunch.make()
        _recovery = State(initialValue: session.recovery)
        _settings = State(initialValue: session.settings)
        _library = State(initialValue: session.library)
    }

    var body: some Scene {
        let _ = appDelegate
        WindowGroup {
            ContentView(recovery: recovery, settings: settings, library: library)
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            #if os(macOS)
            FlorettaCommands(settings: settings, library: library)
            #else
            EmptyCommands()
            #endif
        }
        // One command set for the whole app.
        //
        // A `Commands` value is installed by every scene that carries it, so
        // attaching `FlorettaCommands` here as well put 插入 / 视图 / 格式 / 导出 /
        // 主题 / 帮助 in the menu bar a second time — the doubled menu list a
        // reader saw: 文件 编辑 显示 插入 视图 格式 导出 主题 帮助, then the same
        // custom menus again. The same-document window is another window of this
        // app, not another app: it reads the focused editor's state through
        // `FocusedValue`, so the primary window group's menu bar serves it too.
        #if os(macOS)
        WindowGroup(id: SameDocumentWindow.sceneID, for: UUID.self) { $windowID in
            SameDocumentWindow(
                windowID: windowID,
                recovery: recovery,
                settings: settings,
                library: library
            )
        }
        .defaultSize(width: 960, height: 680)
        // Standard Settings scene: ⌘, opens this window on its own, outside the
        // document window and outside the Dock.
        Settings {
            MacSettingsScene(settings: settings)
        }
        #endif
    }
}

#if os(macOS)
private struct FlorettaCommands: Commands {
    @Bindable var settings: AppSettings
    @Bindable var library: LibraryModel
    @FocusedValue(\.florettaEditorCommands) private var editorCommands: FlorettaEditorMenuActions?

    /// The menu bar, once.
    ///
    /// Placement follows what a Mac document app does: every command lives in
    /// the menu it belongs to, and nothing is duplicated. 文件 keeps 新建 /
    /// 打开 / 保存 and carries the whole export list in a 导出 ▸ submenu; 显示 is
    /// the system View menu, and our view commands join it through
    /// `CommandGroup(after: .sidebar)` instead of a second top-level menu; 帮助 is
    /// the system Help menu, with the native menu search and app guide actions. 插入 / 格式 / 主题 stay
    /// top-level because that is where XMind and every other Mac outliner put
    /// them, and each owns its own commands only.
    var body: some Commands {
        // 文件
        CommandGroup(replacing: .newItem) {
            Button {
                library.makeNew()
            } label: {
                Label(FlorettaL10n.string("新建", language: settings.language), systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        // The three 打开 commands, in 文件: the three sources the home page used
        // to carry.
        CommandGroup(after: .newItem) {
            Button {
                library.requestHomeOpen(.files)
            } label: {
                Label(FlorettaL10n.string(HomeOpenCommand.files.titleKey, language: settings.language), systemImage: "folder")
            }
            .disabled(library.editor != nil)
            Button {
                library.requestHomeOpen(.iCloud)
            } label: {
                Label(FlorettaL10n.string(HomeOpenCommand.iCloud.titleKey, language: settings.language), systemImage: "icloud")
            }
            .disabled(library.editor != nil)
            Button {
                library.requestHomeOpen(.local)
            } label: {
                Label(FlorettaL10n.string(HomeOpenCommand.local.titleKey, language: settings.language), systemImage: "internaldrive")
            }
            .disabled(library.editor != nil)

            Menu {
                if library.recents.isEmpty {
                    Button(menuText("没有最近打开的文件"), action: {})
                        .disabled(true)
                } else {
                    ForEach(library.recents) { entry in
                        Button(entry.filename) { library.openRecent(entry) }
                    }
                }
            } label: {
                Label(menuText("最近打开"), systemImage: "clock")
            }

            Button {
                _ = library.closeEditor()
            } label: {
                Label(menuText("关闭"), systemImage: "xmark")
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(library.editor == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button {
                library.saveActiveFile()
            } label: {
                Label(FlorettaL10n.string("保存", language: settings.language), systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!library.canSaveActiveFile)
        }
        CommandGroup(after: .saveItem) {
            Button {
                editorCommands?.duplicateDocument?()
            } label: {
                Label(menuText("复制副本"), systemImage: "plus.square.on.square")
            }
            .disabled(editorCommands?.duplicateDocument == nil)

            Button {
                editorCommands?.saveAsDocument?()
            } label: {
                Label(menuText("另存为…"), systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(editorCommands?.saveAsDocument == nil)

            Divider()
            Menu {
                if let editorCommands {
                    ForEach([EditorToolbarCommandID.png, .pdf, .markdownExport, .textBundle, .mm, .opml, .xmind], id: \.self) { id in
                        editorCommand(id, actions: editorCommands)
                    }
                    editorCommand(editorCommands.isMarkdownDocument ? .upgrade : .saveFloretta, actions: editorCommands)
                }
            } label: {
                Label(menuText("导出为…"), systemImage: "square.and.arrow.up")
            }
            .disabled(editorCommands == nil)

            Button {
                editorCommands?.perform[.importFile]?()
            } label: {
                Label(menuText("导入…"), systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(editorCommands?.perform[.importFile] == nil)

            Divider()
            Button {
                editorCommands?.perform[.printMap]?()
            } label: {
                Label(menuText("打印…"), systemImage: "printer")
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(editorCommands?.perform[.printMap] == nil)

            Menu {
                if let editorCommands {
                    ForEach(EditorToolbarCommandID.allCases.filter { EditorToolbarCatalog.command($0).menu == .share }, id: \.self) { id in
                        editorCommand(id, actions: editorCommands)
                    }
                }
            } label: {
                Label(menuText("共享…"), systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(editorCommands == nil)
        }
        if let editorCommands {
            // 编辑 > 查找
            CommandGroup(after: .textEditing) {
                editorCommand(.find, actions: editorCommands)
                Button {
                    editorCommands.findNext?()
                } label: {
                    Label("查找下一个", systemImage: "arrow.down.circle")
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(editorCommands.findNext == nil)

                Button {
                    editorCommands.showReplace?()
                } label: {
                    Label("替换…", systemImage: "text.badge.xmark")
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(editorCommands.showReplace == nil)

                Divider()
                Button {
                    editorCommands.selectAll?()
                } label: {
                    Label("全选主题", systemImage: "selection.pin.in.out")
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(editorCommands.selectAll == nil || editorCommands.isEditingText)

                Button {
                    editorCommands.perform[.delete]?()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(!editorCommands.hasSelectedTopic || editorCommands.perform[.delete] == nil)

                Divider()
                Button {
                    editorCommands.performShortcut?(.toggleOutline)
                } label: {
                    Label("大纲 ⇄ 导图", systemImage: "list.bullet")
                }
                .disabled(editorCommands.performShortcut == nil)
                topicButton("展开全部", command: .expandAll)
                topicButton("收起全部", command: .collapseAll)
                Menu {
                    ForEach(editorCommands.foldLevels, id: \.self) { level in
                        Button("第 \(level) 层") {
                            editorCommands.collapseToLevel?(level)
                        }
                    }
                } label: {
                    Label("折叠到第 N 层", systemImage: "square.stack.3d.down.right")
                }
                .disabled(editorCommands.foldLevels.isEmpty || editorCommands.collapseToLevel == nil)
            }
        }
        // 显示: the system View menu already exists (sidebar + toolbar), so the
        // view commands join it instead of adding a 视图 menu beside 显示.
        SidebarCommands()
        if let editorCommands {
            CommandGroup(after: .sidebar) {
                viewCommands(editorCommands)
            }
            CommandMenu("插入") {
                ForEach([EditorToolbarCommandID.child, .sibling, .freeNode, .sticky, .image, .attachment, .summary, .boundary, .region], id: \.self) { id in
                    editorCommand(id, actions: editorCommands)
                }
                Menu {
                    ForEach(Array(editorCommands.linkTargets.enumerated()), id: \.offset) { _, target in
                        Button {
                            target.action()
                        } label: {
                            Label(target.title, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                    }
                    if editorCommands.linkTargets.isEmpty {
                        Button {} label: {
                            Label("没有其他节点", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        .disabled(true)
                    }
                } label: {
                    Label("关系线", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .disabled(!editorCommands.hasSelectedTopic)

                Button {
                    editorCommands.perform[.tagFilter]?()
                } label: {
                    Label("标记与标签…", systemImage: "tag")
                }
                .disabled(!editorCommands.enabled.contains(.tagFilter) || editorCommands.perform[.tagFilter] == nil)

                Button {
                    editorCommands.showNodeNote?()
                } label: {
                    Label("备注…", systemImage: "note.text")
                }
                .disabled(!editorCommands.hasSelectedTopic || editorCommands.showNodeNote == nil)
            }
            CommandMenu("格式") {
                Menu {
                    ForEach(MindMapTextAlignment.allCases, id: \.self) { alignment in
                        Button {
                            editorCommands.setTextAlignment?(alignment)
                        } label: {
                            Label(textAlignmentTitle(alignment), systemImage: alignmentSymbol(alignment))
                        }
                        .disabled(!editorCommands.hasEditableSelection || editorCommands.setTextAlignment == nil)
                    }
                } label: {
                    Label("文字对齐", systemImage: "text.alignleft")
                }
                Menu {
                    ForEach(InspectorTopicShape.allCases) { shape in
                        Button {
                            editorCommands.setNodeShape?(shape)
                        } label: {
                            Text(verbatim: FlorettaL10n.string(shape.titleKey, language: settings.language))
                        }
                        .disabled(!editorCommands.hasEditableSelection || editorCommands.setNodeShape == nil)
                    }
                } label: {
                    Label("节点形状", systemImage: "square.on.circle")
                }
                Menu {
                    ForEach(BranchLineStyle.allCases) { line in
                        Button {
                            editorCommands.setBranchLine?(line)
                        } label: {
                            Text(verbatim: FlorettaL10n.string(line.titleKey, language: settings.language))
                        }
                        .disabled(editorCommands.setBranchLine == nil)
                    }
                } label: {
                    Label("连线样式", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                Menu {
                    ForEach(InspectorBorderStyle.allCases) { border in
                        Button {
                            editorCommands.setBorderStyle?(border)
                        } label: {
                            Text(verbatim: FlorettaL10n.string(border.titleKey, language: settings.language))
                        }
                        .disabled(!editorCommands.hasEditableSelection || editorCommands.setBorderStyle == nil)
                    }
                } label: {
                    Label("边框", systemImage: "rectangle.dashed")
                }
                Divider()
                editorCommand(.theme, actions: editorCommands)
                Menu {
                    ForEach(InspectorFontDesign.allCases) { font in
                        Button {
                            editorCommands.setFont?(font)
                        } label: {
                            Label(FlorettaL10n.string(font.titleKey, language: settings.language), systemImage: "textformat")
                        }
                        .disabled(!editorCommands.hasEditableSelection)
                    }
                } label: {
                    Label("字体", systemImage: "textformat")
                }
                Menu {
                    ForEach([14.0, 18.0, 24.0, 32.0, 48.0], id: \.self) { size in
                        Button { editorCommands.setFontSize?(size) } label: {
                            Label("\(Int(size)) pt", systemImage: "textformat.size")
                        }
                            .disabled(!editorCommands.hasEditableSelection)
                    }
                } label: {
                    Label("字号", systemImage: "textformat.size")
                }
                Button {
                    editorCommands.toggleTextFlag?(.bold)
                } label: {
                    Label("加粗", systemImage: "bold")
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!editorCommands.hasEditableSelection)
                Button {
                    editorCommands.toggleTextFlag?(.italic)
                } label: {
                    Label("斜体", systemImage: "italic")
                }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(!editorCommands.hasEditableSelection)
            }
            CommandMenu("主题") {
                topicButton("编辑主题", command: .beginEdit)
                topicButton("新建同级（后）", command: .createSibling)
                topicButton("新建子级", command: .createChild)
                topicButton("新建同级（前）", command: .createSiblingBefore)
                topicShortcut(.createParent)
                Divider()
                topicShortcut(.selectAllSiblings)
                topicShortcut(.selectAllChildren)
                topicShortcut(.jumpToCentralTopic)
                topicShortcut(.moveTopic(.up))
                topicShortcut(.moveTopic(.down))
                Divider()
                topicButton("展开分支", command: .expandBranch)
                topicButton("收起分支", command: .collapseBranch)
                topicShortcut(.openProperties)
            }
            // 帮助: the system Help menu, not a second 帮助 beside it. The chord
            // is whatever 设置 ▸ 快捷键 holds, so a rebind shows here at once.
            CommandGroup(replacing: .help) {
                topicButton("快捷键一览", command: .showShortcutHelp)
                Button {
                    editorCommands.showUserGuide?()
                } label: {
                    Label("使用手册", systemImage: "book")
                }
                .disabled(editorCommands.showUserGuide == nil)
                Button {
                    openFeedback()
                } label: {
                    Label("反馈问题…", systemImage: "bubble.left.and.bubble.right")
                }
            }
        }
        // 窗口 > 新建窗口: the menu the system owns for windows.
        CommandGroup(before: .windowList) {
            OpenSameDocumentWindowButton(settings: settings, library: library)
        }
    }

    /// 显示: 适应窗口, 大纲, 模式, 沉浸, 检查器, 全屏, then the zoom family. One group in
    /// the system View menu, so 显示 is the only view menu in the bar.
    @ViewBuilder
    private func viewCommands(_ editorCommands: FlorettaEditorMenuActions) -> some View {
        ForEach([EditorToolbarCommandID.fit, .outline, .mapMode, .focusMode, .immersive], id: \.self) { id in
            editorCommand(id, actions: editorCommands)
        }
        Button {
            editorCommands.perform[EditorToolbarCommandID.style]?()
        } label: {
            Label("显示或隐藏检查器", systemImage: "sidebar.trailing")
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .disabled(!editorCommands.enabled.contains(.style) || editorCommands.perform[.style] == nil)
        Button {
            NSApp.keyWindow?.toggleFullScreen(nil)
        } label: {
            let isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
            Label(isFullScreen ? "退出全屏" : "全屏", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .keyboardShortcut("f", modifiers: [.control, .command])
        .disabled(NSApp.keyWindow == nil)
        if editorCommands.isZenActive {
            Button { editorCommands.exitZen?() } label: {
                Label("退出全屏沉浸", systemImage: "rectangle.compress.diagonal")
            }
            .keyboardShortcut(".", modifiers: .command)
        }
        Divider()
        Button { editorCommands.zoomIn?() } label: { Label("放大", systemImage: "plus.magnifyingglass") }
            .keyboardShortcut("+", modifiers: .command).disabled(editorCommands.zoomIn == nil)
        Button { editorCommands.zoomOut?() } label: { Label("缩小", systemImage: "minus.magnifyingglass") }
            .keyboardShortcut("-", modifiers: .command).disabled(editorCommands.zoomOut == nil)
        Button { editorCommands.zoomActual?() } label: { Label("实际大小", systemImage: "viewfinder") }
            .keyboardShortcut("0", modifiers: .command).disabled(editorCommands.zoomActual == nil)
    }

    #if os(macOS)
    private func topicShortcut(_ command: MindMapCommand) -> some View {
        guard let entry = settings.shortcutBindings.menuEntry(for: command) else {
            return AnyView(EmptyView())
        }
        return AnyView(topicButton(entry.title, command: command, entry: entry))
    }

    private func menuText(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }

    private func textAlignmentTitle(_ alignment: MindMapTextAlignment) -> String {
        switch alignment {
        case .leading: "靠左"
        case .center: "居中"
        case .trailing: "靠右"
        }
    }

    private func alignmentSymbol(_ alignment: MindMapTextAlignment) -> String {
        switch alignment {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }

    private func openFeedback() {
        guard let url = URL(string: "https://github.com/Super-Console/Floretta/issues/new") else { return }
        NSWorkspace.shared.open(url)
    }

    private func topicButton(
        _ title: String,
        command: MindMapCommand,
        entry: XMindShortcutCatalog.Entry? = nil
    ) -> some View {
        let item = Button {
            editorCommands?.performShortcut?(command)
        } label: {
            Label(title, systemImage: "command")
        }
        .disabled(editorCommands?.performShortcut == nil)
        // One source: the chord in force, which is what 设置 ▸ 快捷键 writes.
        // A bare key never registers here, so typing in a text field keeps it.
        let resolvedEntry = entry ?? settings.shortcutBindings.menuEntry(for: command)
        if let resolvedEntry, let shortcut = KeyboardShortcut(entry: resolvedEntry) {
            return AnyView(item.keyboardShortcut(shortcut))
        }
        return AnyView(item)
    }

    @ViewBuilder
    private func editorCommand(_ id: EditorToolbarCommandID, actions: FlorettaEditorMenuActions) -> some View {
        let command = EditorToolbarCatalog.command(id)
        let item = Button {
            actions.perform[id]?()
        } label: {
            Label(command.title, systemImage: command.symbol)
        }
        .disabled(!actions.enabled.contains(id) || actions.perform[id] == nil)
        // 大纲 / 沉浸 / 查找 are bindable too. Their chord comes from the same
        // table; the static fallbacks cover the zoom family.
        if let entry = settings.shortcutBindings.menuEntry(forToolbar: id),
           let shortcut = KeyboardShortcut(entry: entry) {
            item.keyboardShortcut(shortcut)
        } else if let shortcut = actions.shortcuts[id] {
            item.keyboardShortcut(shortcut)
        } else {
            item
        }
    }
    #endif
}

struct FlorettaEditorMenuActions {
    struct LinkTarget {
        var title: String
        var action: () -> Void
    }
    var perform: [EditorToolbarCommandID: () -> Void]
    var enabled: Set<EditorToolbarCommandID>
    var shortcuts: [EditorToolbarCommandID: KeyboardShortcut] = [:]
    var hasSelectedTopic = false
    var hasEditableSelection = false
    var linkTargets: [LinkTarget] = []
    var setFont: ((InspectorFontDesign) -> Void)?
    var setFontSize: ((Double) -> Void)?
    var toggleTextFlag: ((InspectorTextFlag) -> Void)?
    var showShortcutHelp: (() -> Void)?
    var showUserGuide: (() -> Void)?
    var showNodeNote: (() -> Void)?
    var showReplace: (() -> Void)?
    var findNext: (() -> Void)?
    var selectAll: (() -> Void)?
    var foldLevels: [Int] = []
    var collapseToLevel: ((Int) -> Void)?
    var setTextAlignment: ((MindMapTextAlignment) -> Void)?
    var setNodeShape: ((InspectorTopicShape) -> Void)?
    var setBranchLine: ((BranchLineStyle) -> Void)?
    var setBorderStyle: ((InspectorBorderStyle) -> Void)?
    var performShortcut: ((MindMapCommand) -> Void)?
    var zoomIn: (() -> Void)?
    var zoomOut: (() -> Void)?
    var zoomActual: (() -> Void)?
    var isZenActive = false
    var exitZen: (() -> Void)?
    var duplicateDocument: (() -> Void)?
    var saveAsDocument: (() -> Void)?
    var isEditingText = false
    var isMarkdownDocument = false
}

private struct FlorettaEditorMenuActionsKey: FocusedValueKey {
    typealias Value = FlorettaEditorMenuActions
}

extension FocusedValues {
    var florettaEditorCommands: FlorettaEditorMenuActions? {
        get { self[FlorettaEditorMenuActionsKey.self] }
        set { self[FlorettaEditorMenuActionsKey.self] = newValue }
    }
}
#endif

#if os(macOS)
private struct OpenSameDocumentWindowButton: View {
    @Bindable var settings: AppSettings
    @Bindable var library: LibraryModel

    var body: some View {
        Button {
            library.openAnotherWindow()
        } label: {
            Label(FlorettaL10n.string("新建窗口", language: settings.language), systemImage: "macwindow.badge.plus")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(library.editor == nil)
        .help(Text(verbatim: FlorettaL10n.string("再开一个窗口，编辑同一份导图。", language: settings.language)))
    }
}

/// Connects `LibraryModel.openAnotherWindow` to SwiftUI `openWindow`.
/// File open, recent files, and the Window menu all use that one method.
struct SameDocumentWindowInstaller: View {
    var library: LibraryModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onAppear {
                library.sameDocumentWindows = SameDocumentWindowHost(openWindow: openWindow)
            }
    }
}

@MainActor
private final class SameDocumentWindowHost: SameDocumentWindowOpening {
    private let openWindow: OpenWindowAction

    init(openWindow: OpenWindowAction) {
        self.openWindow = openWindow
    }

    func openSameDocumentWindow(_ presentation: SameDocumentWindowPresentation) {
        openWindow(id: presentation.sceneID, value: presentation.windowID)
    }
}
#endif

enum AppLaunch {
    static let uiTestArgument = "-FlorettaUITest"
    /// UI tests pass this so the editor opens with the inspector already up.
    /// The 样式 item sits in the toolbar menu, which a phone may overflow.
    static let openInspectorArgument = "-FlorettaOpenInspector"

    static var opensInspector: Bool {
        ProcessInfo.processInfo.arguments.contains(openInspectorArgument)
    }

    static var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestArgument)
    }

    /// Directory shared with the UI test process. `make()` may rewrite
    /// `FLORETTA_UITEST_DIR` to a writable fallback inside the app container.
    static var uiTestDirectory: URL? {
        guard isUITest, let raw = getenv("FLORETTA_UITEST_DIR") else { return nil }
        let path = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var uiTestExportDirectory: URL? {
        uiTestDirectory?.appendingPathComponent("export", isDirectory: true)
    }

    static var uiTestImportDirectory: URL? {
        uiTestDirectory?.appendingPathComponent("import", isDirectory: true)
    }

    /// File opened or imported when a UI test skips the system document picker.
    /// The environment value may be an absolute path or a fixture filename under `import/`.
    static var uiTestImportFile: URL? {
        guard isUITest else { return nil }
        guard let requested = ProcessInfo.processInfo.environment["FLORETTA_UITEST_IMPORT_FILE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !requested.isEmpty else { return nil }
        let url = URL(fileURLWithPath: requested)
        if FileManager.default.isReadableFile(atPath: url.path) { return url }
        if let directory = uiTestImportDirectory {
            let candidate = directory.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.isReadableFile(atPath: candidate.path) { return candidate }
        }
        return url
    }

    static func presentUITestImporter(open: (URL) -> Void, otherwise present: () -> Void) {
        if let url = uiTestImportFile {
            open(url)
        } else {
            present()
        }
    }

    static let editChromeArgument = "-FlorettaEditChrome"

    struct Session {
        var recovery: RecoveryPresenter
        var settings: AppSettings
        var library: LibraryModel
    }

    /// Prints resolved PostScript names for typography evidence. Off unless
    /// launched with `-FlorettaDumpFonts`.
    static func dumpFontsIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-FlorettaDumpFonts") else { return }
        ThemeFontCascade.registerBundledFonts()
        let families = ["system-serif", "system-sans", "inter"]
        let samples = [("en", "Hello"), ("zh", "汉字"), ("ja", "あいうえお"), ("ko", "한국어")]
        var lines: [String] = []
        for family in families {
            for (lang, text) in samples {
                let ps = ThemeFontCascade.postScriptName(familyID: family, for: text)
                let line = "FONT_RESOLVE family=\(family) lang=\(lang) text=\(text) ps=\(ps)"
                print(line)
                lines.append(line)
            }
        }
        fflush(stdout)
        let payload = lines.joined(separator: "\n") + "\n"
        let data = Data(payload.utf8)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("font-resolve.txt")
        try? data.write(to: tmp)
        if let raw = getenv("FLORETTA_UITEST_DIR") {
            let dir = URL(fileURLWithPath: String(cString: raw), isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appendingPathComponent("font-resolve.txt"))
        }
    }

    @MainActor
    static func make() -> Session {
        dumpFontsIfRequested()
        let arguments = ProcessInfo.processInfo.arguments
        // A key-latency run keeps its documents, autosave, and defaults in a
        // throwaway root too: it must neither prompt for the user's crash
        // recovery nor write autosave next to the user's maps.
        guard arguments.contains(uiTestArgument)
                || KeyLatencyRun.drivesItself
                || KeyLatencyRun.requestedTextSamples != nil
                || KeyLatencyRun.requestedPinyinSamples != nil else {
            let session = Session(recovery: RecoveryPresenter(), settings: .shared, library: .shared)
            if let language = AppLanguage.fromLaunchArguments(arguments) {
                session.settings.language = language
            }
            return session
        }
        let id = UUID().uuidString
        let root = Self.resolveUITestRoot(id: id)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let autosave = root.appendingPathComponent("Autosave", isDirectory: true)
        let imports = root.appendingPathComponent("import", isDirectory: true)
        let exports = root.appendingPathComponent("export", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: autosave, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("UI test directories failed: \(error)")
        }
        let suite = "net.timhuang.floretta.uitest.\(id)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("UI test defaults suite failed")
        }
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.language = AppLanguage.fromLaunchArguments(arguments) ?? .simplifiedChinese
        let library = LibraryModel(
            settings: settings,
            store: RecentMapsStore(defaults: defaults, currentUITestRoot: root),
            documentsDirectory: documents
        )
        do {
            try library.installSmokeFixtures()
            try UITestImportFixtures.install(into: imports)
        } catch {
            preconditionFailure("UI test fixtures failed: \(error)")
        }
        // Do not open a document during App.init(). On macOS, a primary editor
        // already set at that moment prevents SwiftUI from instantiating the
        // WindowGroup content closure, so NSApp.windows stays empty and the
        // AX tree has no window. ContentView opens these after the first frame.
        if arguments.contains(editChromeArgument) {
            LaunchDocumentQueue.pending = .editChromeSample
        } else if KeyLatencyRun.drivesItself
                    || KeyLatencyRun.requestedTextSamples != nil
                    || KeyLatencyRun.requestedPinyinSamples != nil {
            LaunchDocumentQueue.pending = .keyLatencyFixture(nodes: KeyLatencyRun.requestedNodeCount ?? 1)
        } else if let nodeCount = CanvasPerfRun.requestedNodeCount {
            LaunchDocumentQueue.pending = .perfFixture(nodeCount: nodeCount)
        }
        let recovery = RecoveryPresenter(
            store: AutosaveStore(directory: autosave, fileAccess: FoundationFileAccess())
        )

        return Session(recovery: recovery, settings: settings, library: library)
    }

    /// Prefer the directory the UI test created when it is writable from this process.
    /// Fall back to a per-launch folder in the app temporary directory.
    private static func resolveUITestRoot(id: String) -> URL {
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlorettaUITest-\(id)", isDirectory: true)
        guard let requested = ProcessInfo.processInfo.environment["FLORETTA_UITEST_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !requested.isEmpty else {
            return fallback
        }
        let url = URL(fileURLWithPath: requested, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let probe = url.appendingPathComponent(".writable")
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
            return url
        } catch {
            setenv("FLORETTA_UITEST_DIR", fallback.path, 1)
            return fallback
        }
    }
}

/// Mind-map fixtures the UI tests open or import, and then read back from disk.
enum UITestImportFixtures {
    static let florettaFileName = "A24-floretta-fixture.floretta"
    static let florettaTitle = "A24八Floretta"
    static let florettaCenter = "A24八Floretta中心"
    static let mmFileName = "A24-mm-fixture.mm"
    static let mmCenter = "A24八MM中心"
    static let mmChild = "A24八MM子节点"
    static let opmlFileName = "A24-opml-fixture.opml"
    static let opmlTitle = "A24十OPML"
    static let opmlCenter = "A24十OPML中心"
    static let opmlChild = "A24十OPML子节点"

    static func install(into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let floretta = MindMapDocument.newMap(
            title: florettaTitle,
            roots: [MindMapNode(text: florettaCenter)],
            clock: FoundationClock()
        )
        let florettaURL = directory.appendingPathComponent(florettaFileName)
        try ZipContainer().write(FlorettaPackage(document: floretta)).write(to: florettaURL, options: .atomic)

        let mm = """
        <?xml version="1.0" encoding="UTF-8"?>
        <map version="1.0.1">
          <node TEXT="\(mmCenter)" ID="root">
            <node TEXT="\(mmChild)" ID="child"/>
          </node>
        </map>
        """
        try Data(mm.utf8).write(to: directory.appendingPathComponent(mmFileName), options: .atomic)

        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>\(opmlTitle)</title>
          </head>
          <body>
            <outline text="\(opmlCenter)">
              <outline text="\(opmlChild)"/>
            </outline>
          </body>
        </opml>
        """
        try Data(opml.utf8).write(to: directory.appendingPathComponent(opmlFileName), options: .atomic)
    }
}

#if os(macOS)
final class FlorettaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        AutosaveQuitHook.perform()
    }
}
#else
final class FlorettaAppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        AutosaveQuitHook.perform()
    }
}
#endif


#if os(macOS)
extension KeyboardShortcut {
    init?(entry: XMindShortcutCatalog.Entry) {
        // A bare key (Space, ↩, ⇥, + - * /) never becomes a menu equivalent:
        // it would swallow that key in every text field of the app.
        guard !entry.isSingleKey else { return nil }
        let key: KeyEquivalent
        switch entry.key {
        case .enter: key = .return
        case .tab: key = .tab
        case .space: key = .space
        case .escape: key = .escape
        case .up: key = .upArrow
        case .down: key = .downArrow
        case .left: key = .leftArrow
        case .right: key = .rightArrow
        case .delete, .backspace: key = .delete
        case .character(let character): key = KeyEquivalent(character)
        case .f2, .f5:
            return nil
        }
        var modifiers: EventModifiers = []
        if entry.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if entry.modifiers.contains(.command) { modifiers.insert(.command) }
        if entry.modifiers.contains(.option) { modifiers.insert(.option) }
        if entry.modifiers.contains(.control) { modifiers.insert(.control) }
        self.init(key, modifiers: modifiers)
    }
}
#endif

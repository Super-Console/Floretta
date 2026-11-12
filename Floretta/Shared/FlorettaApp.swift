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
        .commands {
            FlorettaCommands(settings: settings, library: library)
        }
        #endif
    }
}

#if os(macOS)
private struct FlorettaCommands: Commands {
    @Bindable var settings: AppSettings
    @Bindable var library: LibraryModel
    @FocusedValue(\.florettaEditorCommands) private var editorCommands: FlorettaEditorMenuActions?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(FlorettaL10n.string("新建", language: settings.language)) {
                library.makeNew()
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {
            Button(FlorettaL10n.string("保存", language: settings.language)) {
                library.saveActiveFile()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!library.canSaveActiveFile)
        }
        if let editorCommands {
            CommandGroup(after: .textEditing) {
                editorCommand(.find, actions: editorCommands)
            }
        }
        SidebarCommands()
        if let editorCommands {
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
                        Button("没有其他节点") {}.disabled(true)
                    }
                } label: {
                    Label("关系线", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .disabled(!editorCommands.hasSelectedTopic)
            }
            CommandMenu("视图") {
                ForEach([EditorToolbarCommandID.fit, .outline, .mapMode, .focusMode, .immersive, .style], id: \.self) { id in
                    editorCommand(id, actions: editorCommands)
                }
                Divider()
                Button("放大") { editorCommands.zoomIn?() }.keyboardShortcut("+", modifiers: .command).disabled(editorCommands.zoomIn == nil)
                Button("缩小") { editorCommands.zoomOut?() }.keyboardShortcut("-", modifiers: .command).disabled(editorCommands.zoomOut == nil)
                Button("实际大小") { editorCommands.zoomActual?() }.keyboardShortcut("=", modifiers: .command).disabled(editorCommands.zoomActual == nil)
            }
            CommandMenu("格式") {
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
                        Button("\(Int(size)) pt") { editorCommands.setFontSize?(size) }
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
            CommandMenu("导出") {
                ForEach([EditorToolbarCommandID.png, .pdf, .markdownExport, .textBundle, .saveFloretta, .xmind], id: \.self) { id in
                    editorCommand(id, actions: editorCommands)
                }
            }
            CommandMenu("主题") {
                topicButton("编辑主题", command: .beginEdit, chord: "Space")
                topicButton("新建同级（后）", command: .createSibling, chord: "↩")
                topicButton("新建子级", command: .createChild, chord: "⇥")
                topicButton("新建同级（前）", command: .createSiblingBefore, chord: "⇧↩")
                topicShortcut(.createParent)
                Divider()
                topicShortcut(.selectAllSiblings)
                topicShortcut(.selectAllChildren)
                topicShortcut(.jumpToCentralTopic)
                topicShortcut(.moveTopic(.up))
                topicShortcut(.moveTopic(.down))
                Divider()
                topicButton("展开分支", command: .expandBranch, chord: "+")
                topicButton("收起分支", command: .collapseBranch, chord: "-")
                topicButton("展开全部", command: .expandAll, chord: "*")
                topicButton("收起全部", command: .collapseAll, chord: "/")
                topicShortcut(.openProperties)
            }
            CommandMenu("帮助") {
                Button {
                    editorCommands.showShortcutHelp?()
                } label: {
                    Label("快捷键一览", systemImage: "keyboard")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
        CommandGroup(before: .windowList) {
            OpenSameDocumentWindowButton(settings: settings, library: library)
        }
        CommandGroup(replacing: .appSettings) {
            Button(FlorettaL10n.string(ShellTab.settings.title, language: settings.language)) {
                library.tab = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(library.editor != nil)
        }
    }

    #if os(macOS)
    private func topicShortcut(_ command: MindMapCommand) -> some View {
        guard let entry = XMindShortcutCatalog.entries.first(where: {
            $0.command == command && $0.registersMenuEquivalent
        }) else {
            return AnyView(EmptyView())
        }
        return AnyView(topicButton(entry.title, command: command, chord: nil, entry: entry))
    }

    private func topicButton(
        _ title: String,
        command: MindMapCommand,
        chord: String? = nil,
        entry: XMindShortcutCatalog.Entry? = nil
    ) -> some View {
        let label = chord == nil ? title : "\(title)    \(chord!)"
        let item = Button(label) {
            editorCommands?.performShortcut?(command)
        }
        .disabled(editorCommands?.performShortcut == nil)
        if let entry, entry.registersMenuEquivalent, let shortcut = KeyboardShortcut(entry: entry) {
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
        if let shortcut = actions.shortcuts[id] {
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
    var performShortcut: ((MindMapCommand) -> Void)?
    var zoomIn: (() -> Void)?
    var zoomOut: (() -> Void)?
    var zoomActual: (() -> Void)?
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
        Button(FlorettaL10n.string("新建窗口", language: settings.language)) {
            library.openAnotherWindow()
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

    @MainActor
    static func make() -> Session {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(uiTestArgument) else {
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
            store: RecentMapsStore(defaults: defaults),
            documentsDirectory: documents
        )
        do {
            try library.installSmokeFixtures()
            try UITestImportFixtures.install(into: imports)
        } catch {
            preconditionFailure("UI test fixtures failed: \(error)")
        }
        if arguments.contains(editChromeArgument) {
            library.openEditChromeSample()
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

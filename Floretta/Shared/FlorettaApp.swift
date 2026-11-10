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
            FlorettaCommands(settings: settings, library: library)
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

private struct FlorettaCommands: Commands {
    @Bindable var settings: AppSettings
    @Bindable var library: LibraryModel

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
        #if os(macOS)
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
        #endif
    }
}

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
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlorettaUITest-\(id)", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let autosave = root.appendingPathComponent("Autosave", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: autosave, withIntermediateDirectories: true)
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

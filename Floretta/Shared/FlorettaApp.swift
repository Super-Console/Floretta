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
            CommandGroup(replacing: .newItem) {
                Button(FlorettaL10n.string("新建", language: settings.language)) {
                    library.makeNew()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            #if os(macOS)
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
}

enum AppLaunch {
    static let uiTestArgument = "-FlorettaUITest"

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

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

    @State private var recovery = RecoveryPresenter()
    @State private var settings = AppSettings.shared
    @State private var library = LibraryModel.shared

    var body: some Scene {
        let _ = appDelegate
        WindowGroup {
            ContentView(recovery: recovery, settings: settings, library: library)
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建") {
                    library.makeNew()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            #if os(macOS)
            CommandGroup(replacing: .appSettings) {
                Button(ShellTab.settings.title) {
                    library.tab = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(library.editor != nil)
            }
            #endif
        }
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

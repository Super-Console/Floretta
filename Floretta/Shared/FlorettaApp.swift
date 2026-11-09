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

    var body: some Scene {
        let _ = appDelegate
        WindowGroup {
            ContentView(recovery: recovery)
        }
        .defaultSize(width: 800, height: 600)
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

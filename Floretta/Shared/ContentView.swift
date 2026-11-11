import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Bindable var recovery: RecoveryPresenter
    @Bindable var settings: AppSettings
    @Bindable var library: LibraryModel

    @State private var page: HomePage = .recent
    @State private var columnVisibility = ShellTab.preferredColumnVisibility
    @State private var searchText = ""
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var showImporter = false
    @State private var browseRoot: URL?
    @State private var browseTitle = LocalDeviceLabel.current.title
    @State private var notice: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        root
            .preferredColorScheme(settings.appearance.colorScheme)
            .onAppear { recovery.checkOnLaunch() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    library.absorbExternalShare()
                }
            }
            .onChange(of: recovery.restoredDocument) { _, restored in
                if let restored {
                    library.openRecovered(restored)
                }
            }
            .alert(Text(verbatim: text("要恢复未保存的导图吗？")), isPresented: $recovery.showOffer) {
                Button(text("恢复")) { recovery.restore() }
                Button(text("丢弃"), role: .destructive) { recovery.discard() }
            } message: {
                Text(verbatim: FlorettaL10n.recoveryMessage(title: recovery.offeredTitle, locale: settings.resolvedLocale))
            }
            .alert(Text(verbatim: text("无法恢复自动保存")), isPresented: $recovery.showFailure) {
                Button(text("好"), role: .cancel) { recovery.acknowledgeFailure() }
            } message: {
                Text(verbatim: FlorettaL10n.present(recovery.failureMessage, locale: settings.resolvedLocale))
            }
            .alert(Text(verbatim: text(library.interruptedTitle)), isPresented: $library.showInterruptedSave) {
                if library.interruptedCanRestore {
                    Button(text("恢复上一版")) { library.restoreInterruptedSave() }
                    Button(text("丢弃未完成的写入"), role: .destructive) { library.discardInterruptedPartial() }
                } else {
                    Button(text("好"), role: .cancel) { library.discardInterruptedPartial() }
                }
            } message: {
                Text(verbatim: FlorettaL10n.present(library.interruptedMessage, locale: settings.resolvedLocale))
            }
            .alert(Text(verbatim: text(library.alertTitle)), isPresented: openErrorPresented) {
                Button(text("好"), role: .cancel) {}
            } message: {
                Text(verbatim: openErrorMessage)
            }
            .alert(Text(verbatim: text("提示")), isPresented: noticePresented) {
                Button(text("好"), role: .cancel) {}
            } message: {
                Text(verbatim: FlorettaL10n.present(notice ?? "", locale: settings.resolvedLocale))
            }
            .environment(\.locale, settings.resolvedLocale)
            #if os(macOS)
            .background {
                SameDocumentWindowInstaller(library: library)
            }
            #endif
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: FlorettaFileTypes.allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { library.openFile(url) }
                case .failure(let error):
                    library.inventoryError = nil
                    library.openError = error.localizedDescription
                }
            }
    }

    @ViewBuilder
    private var root: some View {
        if let editor = library.session(for: .primary) {
            NavigationStack {
                DocumentEditor(
                    session: editor,
                    settings: settings,
                    onClose: dismissEditor,
                    onEdit: { updated in
                        if library.session(for: .primary)?.consumeAutosaveEdit(updated) != false {
                            recovery.noteEdit(updated)
                        }
                    },
                    onImport: { AppLaunch.presentUITestImporter(open: { library.openFile($0) }) { showImporter = true } },
                    onSavedCopy: { library.noteExportedCopy($0) },
                    onMarkdownUpgrade: { url, choice in
                        library.finishMarkdownUpgrade(savedAt: url, choice: choice)
                    },
                    thumbnailCache: library.thumbnailCache
                )
            }
        } else {
            shell
        }
    }

    @ViewBuilder
    private var shell: some View {
        #if os(iOS)
        // System tab bar. `.tabBarOnly` keeps iPhone and iPad on that bar
        // instead of an iPad sidebar. No custom glass, blur, or capsule.
        TabView(selection: $library.tab) {
            Tab(value: ShellTab.home) {
                iosHome
            } label: {
                Label(text(ShellTab.home.title), systemImage: ShellTab.home.systemImage)
            }
            Tab(value: ShellTab.settings) {
                SettingsView(settings: settings)
            } label: {
                Label(text(ShellTab.settings.title), systemImage: ShellTab.settings.systemImage)
            }
        }
        .tabViewStyle(.tabBarOnly)
        #else
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: macSelection) {
                ForEach(ShellTab.destinations, id: \.self) { destination in
                    Label(text(destination.title), systemImage: destination.systemImage)
                        .tag(destination)
                }
            }
            .navigationTitle("Floretta")
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.regularMaterial)
        } detail: {
            switch library.tab {
            case .home:
                homeStack
            case .settings:
                SettingsView(settings: settings)
            }
        }
        #endif
    }

    #if os(iOS)
    /// The phone shows the recent stack directly. `NavigationSplitView` inside
    /// the tab bar collapses to the sidebar, and that list is not inside the
    /// `NavigationStack` that carries `.navigationTitle("最近")`.
    @ViewBuilder
    private var iosHome: some View {
        switch homeChrome {
        case .stack:
            homeStack
        case .split:
            iosLibrary
        }
    }

    private var homeChrome: HomeLibraryChrome {
        // `UserInterfaceSizeClass` is not frozen. Compare the known cases;
        // nil and any future case stay unspecified so an iPhone still uses the stack.
        let width: HomeWidthClass
        if horizontalSizeClass == .compact {
            width = .compact
        } else if horizontalSizeClass == .regular {
            width = .regular
        } else {
            width = .unspecified
        }
        return HomeLibrary.chrome(
            width: width,
            phoneWhenUnspecified: LocalDeviceLabel.currentKind == .iPhone
        )
    }

    private var iosLibrary: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HomeSidebar(
                library: library,
                openFiles: { AppLaunch.presentUITestImporter(open: { library.openFile($0) }) { showImporter = true } },
                openICloud: openICloud,
                browsePad: browsePad
            )
        } detail: {
            homeStack
        }
    }
    #endif

    private var macSelection: Binding<ShellTab?> {
        Binding(
            get: { library.tab },
            set: { if let tab = $0 { library.tab = tab } }
        )
    }

    private var homeStack: some View {
        NavigationStack {
            switch page {
            case .recent:
                RecentPage(
                    library: library,
                    page: $page,
                    searchText: $searchText,
                    openFiles: { AppLaunch.presentUITestImporter(open: { library.openFile($0) }) { showImporter = true } },
                    openICloud: openICloud,
                    browseLocal: browsePad
                )
            case .newMap:
                NewMapPage(
                    onClose: { page = .recent },
                    onCreate: { library.makeTemplate($0) }
                )
            case .browse:
                if let browseRoot {
                    LocalBrowser(
                        title: browseTitle,
                        directory: browseRoot,
                        files: { library.files(in: $0) },
                        openFile: { library.openFile($0) },
                        onClose: { page = .recent }
                    )
                }
            }
        }
        .id(page)
    }

    private var openErrorPresented: Binding<Bool> {
        Binding(
            get: { library.openError != nil },
            set: { if !$0 { library.dismissOpenError() } }
        )
    }

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )
    }

    private func dismissEditor() {
        if library.closeEditor() {
            recovery.quitNormally()
        }
        library.tab = .home
        page = .recent
    }

    private func browsePad() {
        browseRoot = library.documentsRoot
        browseTitle = LocalDeviceLabel.current.title
        page = .browse
    }

    private func openICloud() {
        guard let directory = library.iCloudDocumentsDirectory() else {
            notice = "iCloud 云盘不可用。"
            return
        }
        browseRoot = directory
        browseTitle = "iCloud云盘"
        page = .browse
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }

    private var openErrorMessage: String {
        if let inventory = library.inventoryError {
            return FlorettaL10n.inventoryMessage(inventory, locale: settings.resolvedLocale)
        }
        return FlorettaL10n.present(library.openError ?? "", locale: settings.resolvedLocale)
    }

}

#if os(macOS)
/// A second (or later) window on the document already open in `ContentView`.
struct SameDocumentWindow: View {
    static let sceneID = SameDocumentWindowScene.id

    var windowID: UUID?
    @Bindable var recovery: RecoveryPresenter
    @Bindable var settings: AppSettings
    @Bindable var library: LibraryModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showImporter = false

    var body: some View {
        Group {
            if let windowID, let editor = library.session(for: .auxiliary(windowID)) {
                NavigationStack {
                    DocumentEditor(
                        session: editor,
                        settings: settings,
                        onClose: { closeThisWindow() },
                        onEdit: { updated in
                            if library.session(for: .auxiliary(windowID))?.consumeAutosaveEdit(updated) != false {
                                recovery.noteEdit(updated)
                            }
                        },
                        onImport: { AppLaunch.presentUITestImporter(open: { library.openFile($0) }) { showImporter = true } },
                        onSavedCopy: { library.noteExportedCopy($0) },
                        onMarkdownUpgrade: { url, choice in
                            library.finishMarkdownUpgrade(savedAt: url, choice: choice)
                        },
                        thumbnailCache: library.thumbnailCache
                    )
                }
            } else {
                Color.clear
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .environment(\.locale, settings.resolvedLocale)
        .background {
            SameDocumentWindowInstaller(library: library)
            if let windowID {
                AuxiliaryWindowCloseMonitor {
                    library.closeAuxiliaryWindow(windowID)
                }
                .allowsHitTesting(false)
            }
        }
        .onChange(of: library.auxiliaryWindowIDs) { _, ids in
            guard let windowID, !ids.contains(windowID) else { return }
            dismiss()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                library.absorbExternalShare()
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: FlorettaFileTypes.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { library.openFile(url) }
            case .failure(let error):
                library.inventoryError = nil
                library.openError = error.localizedDescription
            }
        }
    }

    private func closeThisWindow() {
        guard let windowID else { return }
        library.closeAuxiliaryWindow(windowID)
        dismiss()
    }
}

private struct AuxiliaryWindowCloseMonitor: NSViewRepresentable {
    var onClose: () -> Void

    func makeNSView(context: Context) -> AuxiliaryWindowCloseView {
        let view = AuxiliaryWindowCloseView()
        view.onClose = onClose
        return view
    }

    func updateNSView(_ nsView: AuxiliaryWindowCloseView, context: Context) {
        nsView.onClose = onClose
    }
}

private final class AuxiliaryWindowCloseView: NSView, @unchecked Sendable {
    var onClose: (() -> Void)?
    /// Register and remove only from the main actor. deinit must not touch this.
    @MainActor private var token: NSObjectProtocol?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let attached = window != nil
        MainActor.assumeIsolated {
            stop()
            guard attached, let window = self.window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onClose?()
                }
            }
        }
    }

    @MainActor private func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }
    }
}
#endif

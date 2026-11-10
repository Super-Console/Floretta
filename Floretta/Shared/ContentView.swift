import SwiftUI

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

    var body: some View {
        root
            .preferredColorScheme(settings.appearance.colorScheme)
            .environment(\.locale, settings.resolvedLocale)
            .onAppear { recovery.checkOnLaunch() }
            .onChange(of: recovery.restoredDocument) { _, restored in
                if let restored {
                    library.openRecovered(restored)
                }
            }
            .alert("Recover unsaved mind map?", isPresented: $recovery.showOffer) {
                Button("Recover") { recovery.restore() }
                Button("Discard", role: .destructive) { recovery.discard() }
            } message: {
                Text(recovery.offerMessage)
            }
            .alert("Couldn't recover autosave", isPresented: $recovery.showFailure) {
                Button("OK", role: .cancel) { recovery.acknowledgeFailure() }
            } message: {
                Text(recovery.failureMessage)
            }
            .alert(library.interruptedTitle, isPresented: $library.showInterruptedSave) {
                if library.interruptedCanRestore {
                    Button("恢复上一版") { library.restoreInterruptedSave() }
                    Button("丢弃未完成的写入", role: .destructive) { library.discardInterruptedPartial() }
                } else {
                    Button("好", role: .cancel) { library.discardInterruptedPartial() }
                }
            } message: {
                Text(library.interruptedMessage)
            }
            .alert(library.alertTitle, isPresented: openErrorPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(library.openError ?? "")
            }
            .alert("提示", isPresented: noticePresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(notice ?? "")
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
                    library.openError = error.localizedDescription
                }
            }
    }

    @ViewBuilder
    private var root: some View {
        if let editor = library.editor {
            NavigationStack {
                DocumentEditor(
                    session: editor,
                    settings: settings,
                    onClose: dismissEditor,
                    onEdit: { recovery.noteEdit($0) },
                    onImport: { showImporter = true },
                    onSavedCopy: { library.noteExportedCopy($0) },
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
        TabView(selection: $library.tab) {
            iosHome
                .tabItem {
                    Label(ShellTab.home.title, systemImage: ShellTab.home.systemImage)
                }
                .tag(ShellTab.home)
            SettingsView(settings: settings)
                .tabItem {
                    Label(ShellTab.settings.title, systemImage: ShellTab.settings.systemImage)
                }
                .tag(ShellTab.settings)
        }
        .tabViewStyle(.tabBarOnly)
        #else
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: macSelection) {
                ForEach(ShellTab.destinations, id: \.self) { destination in
                    Label(destination.title, systemImage: destination.systemImage)
                        .tag(destination)
                }
            }
            .navigationTitle("Floretta")
            .listStyle(.sidebar)
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
                openFiles: { showImporter = true },
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
                    openFiles: { showImporter = true },
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
            set: { if !$0 { library.openError = nil } }
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

}

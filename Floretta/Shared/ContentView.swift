import SwiftUI

struct ContentView: View {
    @Bindable var recovery: RecoveryPresenter
    @Bindable var settings: AppSettings
    @Bindable var library: LibraryModel

    @State private var page: HomePage = .recent
    @State private var sidebarVisible = false
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var browseRoot: URL?
    @State private var browseTitle = "我的iPad"
    @State private var saveLocationTitle = "我的iPad"
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
            .alert("无法打开", isPresented: openErrorPresented) {
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
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
    }

    @ViewBuilder
    private var root: some View {
        if let editor = library.editor {
            DocumentEditor(
                session: editor,
                settings: settings,
                onClose: dismissEditor,
                onEdit: { recovery.noteEdit($0) }
            )
        } else {
            NavigationSplitView {
                HomeSidebar(
                    library: library,
                    page: $page,
                    openFiles: { showImporter = true },
                    openICloud: openICloud,
                    browsePad: browsePad
                )
            } detail: {
                NavigationStack {
                    switch page {
                    case .recent:
                        RecentPage(
                            library: library,
                            page: $page,
                            sidebarVisible: $sidebarVisible,
                            searchText: $searchText,
                            showSettings: { showSettings = true }
                        )
                    case .newMap:
                        NewMapPage(
                            onClose: { page = .recent },
                            onCreateMindMap: { library.makeNew() },
                            saveLocationTitle: $saveLocationTitle,
                            chooseDocuments: chooseDocuments,
                            chooseICloud: chooseICloudSave
                        )
                    case .browse:
                        if let browseRoot {
                            LocalBrowser(
                                title: browseTitle,
                                directory: browseRoot,
                                files: { library.files(in: $0) },
                                openFile: { library.openFile($0) }
                            )
                        }
                    }
                }
            }
            .navigationSplitViewColumnVisibility(sidebarVisible ? .all : .detailOnly)
        }
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
        page = .recent
    }

    private func browsePad() {
        browseRoot = library.documentsRoot
        browseTitle = "我的iPad"
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

    private func chooseDocuments() {
        library.useDocumentsForNewFiles()
        saveLocationTitle = "我的iPad"
    }

    private func chooseICloudSave() {
        guard library.useICloudForNewFiles() else {
            notice = "iCloud 云盘不可用。"
            return
        }
        saveLocationTitle = "iCloud云盘"
    }
}

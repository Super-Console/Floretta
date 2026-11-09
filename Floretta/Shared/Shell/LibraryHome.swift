import SwiftUI
import UniformTypeIdentifiers

/// Home from the iPad reference: centered title「最近」, not a large title.
struct RecentPage: View {
    @Bindable var library: LibraryModel
    @Binding var page: HomePage
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var searchText: String
    var showSettings: () -> Void

    var body: some View {
        recentBody
            .navigationTitle("最近")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "搜索")
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    if sidebarOpen {
                        Button(action: showSettings) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("设置")
                    }
                    Button {
                        columnVisibility = sidebarOpen ? .detailOnly : .all
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .accessibilityLabel("侧栏")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        library.makeNew()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建导图")
                    Button {
                        columnVisibility = .detailOnly
                        page = .newMap
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel("模板库")
                    Menu {
                        Button("设置", action: showSettings)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多")
                }
            }
    }

    @ViewBuilder
    private var recentBody: some View {
        let items = filtered
        if library.recents.isEmpty {
            ContentUnavailableView {
                Label("这里还没有导图。", systemImage: "pencil.and.ruler")
            } description: {
                Text("现在是创建一个好的时机。")
            } actions: {
                Button("新建导图") { library.makeNew() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        } else if items.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    ForEach(items) { entry in
                        Button {
                            library.openRecent(entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.quaternary)
                                    .frame(height: 110)
                                    .overlay {
                                        Image(systemName: "map")
                                            .foregroundStyle(.secondary)
                                    }
                                Text(entry.filename)
                                    .lineLimit(1)
                                Text(entry.modifiedAt, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private var sidebarOpen: Bool { columnVisibility != .detailOnly }

    private var filtered: [RecentMapEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.recents }
        return library.recents.filter { $0.filename.localizedCaseInsensitiveContains(query) }
    }
}

struct HomeSidebar: View {
    @Bindable var library: LibraryModel
    @Binding var page: HomePage
    var openFiles: () -> Void
    var openICloud: () -> Void
    var browsePad: () -> Void

    var body: some View {
        List {
            Button {
                page = .recent
            } label: {
                Label("最近", systemImage: "clock")
            }
            Button {
                library.makeNew()
            } label: {
                Label("新建导图", systemImage: "plus")
            }
            Section("本地导图") {
                Button(action: openFiles) {
                    Label("从文件应用打开", systemImage: "folder")
                }
                Button(action: openICloud) {
                    Label("从iCloud云盘打开", systemImage: "cloud")
                }
                Button(action: browsePad) {
                    Label(LocalDeviceLabel.current.title, systemImage: LocalDeviceLabel.current.systemImage)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct NewMapPage: View {
    var onClose: () -> Void
    var onCreateMindMap: () -> Void

    @State private var closedNotice: String?

    private let sections = TemplateCatalog.sections

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(sections) { section in
                    sectionView(section)
                }
            }
            .padding()
        }
        .navigationTitle("新建")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("关闭")
            }
            ToolbarItem(placement: .primaryAction) {
                Label(LocalDeviceLabel.current.title, systemImage: LocalDeviceLabel.current.systemImage)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("提示", isPresented: noticePresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(closedNotice ?? "")
        }
    }

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { closedNotice != nil },
            set: { if !$0 { closedNotice = nil } }
        )
    }

    private func sectionView(_ section: TemplateSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(section.title).font(.title3)
                Spacer()
                Button("全部") { closedNotice = TemplateCatalog.seeAllNotice }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(section.cards) { card in
                        cardButton(card)
                    }
                }
            }
        }
    }

    private func cardButton(_ card: TemplateCard) -> some View {
        Button {
            switch card.tap {
            case .createMindMap:
                onCreateMindMap()
            case .laterLayout:
                closedNotice = TemplateCatalog.laterLayoutNotice
            case .comingSoon:
                closedNotice = TemplateCatalog.comingSoonNotice
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                TemplateThumbnail(name: card.name)
                Text(card.name)
                    .font(.callout)
                    .frame(width: TemplateThumbnail.width, alignment: .leading)
                if card.tap != .createMindMap {
                    Text(card.tap == .laterLayout ? "后续版本" : "即将推出")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: TemplateThumbnail.width, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct LocalBrowser: View {
    var title: String
    var directory: URL
    var files: (URL) -> [URL]
    var openFile: (URL) -> Void

    @State private var stack: [URL] = []

    var body: some View {
        let current = stack.last ?? directory
        List(files(current), id: \.path) { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            Button {
                if isDirectory {
                    stack.append(url)
                } else {
                    openFile(url)
                }
            } label: {
                Label(url.lastPathComponent, systemImage: isDirectory ? "folder" : "doc")
            }
        }
        .navigationTitle(title)
        .toolbar {
            if !stack.isEmpty {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { stack.removeLast() }
                }
            }
        }
    }
}

/// Settings from TASKBOOK-004. Pickers write `AppSettings`, which stores UserDefaults.
struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("语言", selection: $settings.language) {
                        Text("跟随系统").tag(AppLanguage.system)
                        Text("简体中文").tag(AppLanguage.simplifiedChinese)
                        Text("English").tag(AppLanguage.english)
                    }
                    Picker("外观", selection: $settings.appearance) {
                        Text("跟随系统").tag(AppAppearance.system)
                        Text("浅色").tag(AppAppearance.light)
                        Text("深色").tag(AppAppearance.dark)
                    }
                }
                Section {
                    Picker("新建时默认视图", selection: $settings.defaultView) {
                        Text("地图模式").tag(DocumentViewMode.map)
                        Text("聚焦模式").tag(DocumentViewMode.focus)
                    }
                    Picker("PNG 导出倍率", selection: $settings.pngScale) {
                        Text("1x").tag(PNGScalePreference.one)
                        Text("2x").tag(PNGScalePreference.two)
                        Text("3x").tag(PNGScalePreference.three)
                    }
                    Picker("PNG 背景", selection: $settings.pngBackground) {
                        Text("白色").tag(PNGBackgroundPreference.white)
                        Text("透明").tag(PNGBackgroundPreference.transparent)
                    }
                }
                Section("关于") {
                    LabeledContent("版本", value: AppInfo.version)
                    NavigationLink("NOTICE 开源致谢") {
                        ScrollView {
                            Text(AppInfo.notice)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding()
                        }
                        .navigationTitle("NOTICE")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
        }
    }
}


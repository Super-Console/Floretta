import SwiftUI
import UniformTypeIdentifiers

/// Home from the iPad reference: centered title「最近」, not a large title.
struct RecentPage: View {
    @Bindable var library: LibraryModel
    @Binding var page: HomePage
    @Binding var searchText: String
    var openFiles: () -> Void
    var openICloud: () -> Void
    var browseLocal: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        recentBody
            .navigationTitle(text(HomeLibrary.navigationTitle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: Text(verbatim: text("搜索")))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        library.makeNew()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(text("新建导图"))
                    .accessibilityIdentifier("home.newMap")
                    Button {
                        page = .newMap
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel(text("模板库"))
                    .accessibilityIdentifier("home.templates")
                    Menu {
                        Button(text("从文件应用打开"), action: openFiles)
                        Button(text("从 iCloud 云盘打开"), action: openICloud)
                        Button(text(LocalDeviceLabel.current.title), action: browseLocal)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel(text("打开"))
                }
            }
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, locale: locale)
    }

    @ViewBuilder
    private var recentBody: some View {
        let items = filtered
        if library.recents.isEmpty {
            ContentUnavailableView {
                Label(text("这里还没有导图。"), systemImage: "pencil.and.ruler")
            } description: {
                Text(verbatim: text("现在是创建一个好的时机。"))
            } actions: {
                Button(text("新建导图")) { library.makeNew() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
            .accessibilityIdentifier("home.recent")
        } else if items.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .accessibilityIdentifier("home.recent")
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
                        .accessibilityLabel(entry.filename)
                        .accessibilityIdentifier("home.recent.row")
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("home.recent")
        }
    }

    private var filtered: [RecentMapEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.recents }
        return library.recents.filter { $0.filename.localizedCaseInsensitiveContains(query) }
    }
}

struct HomeSidebar: View {
    @Bindable var library: LibraryModel
    var openFiles: () -> Void
    var openICloud: () -> Void
    var browsePad: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        let device = LocalDeviceLabel.current
        List {
            ForEach(HomeSidebarRow.leading) { row in
                sidebarButton(row, device: device)
            }
            Section(text("本地导图")) {
                ForEach(HomeSidebarRow.local) { row in
                    sidebarButton(row, device: device)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("home.sidebar")
    }

    private func sidebarButton(_ row: HomeSidebarRow, device: LocalDeviceLabel) -> some View {
        Button {
            perform(row)
        } label: {
            Label(text(row.title(device: device)), systemImage: row.systemImage(device: device))
        }
        .accessibilityIdentifier(row.accessibilityIdentifier)
    }

    private func perform(_ row: HomeSidebarRow) {
        switch row {
        case .newMap:
            library.makeNew()
        case .openFiles:
            openFiles()
        case .openICloud:
            openICloud()
        case .browseLocal:
            browsePad()
        }
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, locale: locale)
    }
}

struct NewMapPage: View {
    var onClose: () -> Void
    var onCreate: (TemplateKind) -> Void
    @Environment(\.locale) private var locale

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
        .navigationTitle(text("模板库"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(text("关闭"))
            }
            ToolbarItem(placement: .primaryAction) {
                Label(text(LocalDeviceLabel.current.title), systemImage: LocalDeviceLabel.current.systemImage)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, locale: locale)
    }

    private func sectionView(_ section: TemplateSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: text(section.title)).font(.title3)
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
            onCreate(card.kind)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                TemplateThumbnail(kind: card.kind)
                Text(verbatim: text(card.name))
                    .font(.callout)
                    .frame(width: TemplateThumbnail.width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text(card.name))
    }
}

struct LocalBrowser: View {
    var title: String
    var directory: URL
    var files: (URL) -> [URL]
    var openFile: (URL) -> Void
    var onClose: () -> Void
    @Environment(\.locale) private var locale

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
        .navigationTitle(FlorettaL10n.string(title, locale: locale))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if stack.isEmpty {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(FlorettaL10n.string("关闭", locale: locale))
                    .accessibilityIdentifier("home.browse.close")
                } else {
                    Button(FlorettaL10n.string("返回", locale: locale)) { stack.removeLast() }
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
                    Picker(text("语言"), selection: $settings.language) {
                        Text(verbatim: text("跟随系统")).tag(AppLanguage.system)
                        Text(verbatim: text("简体中文")).tag(AppLanguage.simplifiedChinese)
                        Text(verbatim: "English").tag(AppLanguage.english)
                    }
                    .accessibilityIdentifier("settings.language")
                    Picker(text("外观"), selection: $settings.appearance) {
                        Text(verbatim: text("跟随系统")).tag(AppAppearance.system)
                        Text(verbatim: text("浅色")).tag(AppAppearance.light)
                        Text(verbatim: text("深色")).tag(AppAppearance.dark)
                    }
                }
                Section {
                    Picker(text("新建时默认视图"), selection: $settings.defaultView) {
                        Text(verbatim: text("地图模式")).tag(DocumentViewMode.map)
                        Text(verbatim: text("聚焦模式")).tag(DocumentViewMode.focus)
                    }
                    Picker(text("PNG 导出倍率"), selection: $settings.pngScale) {
                        Text(verbatim: "1x").tag(PNGScalePreference.one)
                        Text(verbatim: "2x").tag(PNGScalePreference.two)
                        Text(verbatim: "3x").tag(PNGScalePreference.three)
                    }
                    Picker(text("PNG 背景"), selection: $settings.pngBackground) {
                        Text(verbatim: text("白色")).tag(PNGBackgroundPreference.white)
                        Text(verbatim: text("透明")).tag(PNGBackgroundPreference.transparent)
                    }
                    Toggle(text("导出包含便签"), isOn: $settings.exportIncludesStickies)
                        .help(Text(verbatim: text("PNG 和 PDF 可以带上便签。关掉后便签还在导图里，只是不画进图片。")))
                }
                Section(text("关于")) {
                    LabeledContent(text("版本"), value: AppInfo.version)
                    NavigationLink(text("NOTICE 开源致谢")) {
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
            .navigationTitle(text("设置"))
        }
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }
}


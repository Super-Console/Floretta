import SwiftUI
import UniformTypeIdentifiers
import FlorettaCore

/// Project-manager home with the standard large navigation title and system toolbar.
/// One column on every platform: the old 「最近」 sidebar was a list of commands,
/// not destinations, so those commands live in the toolbar's 打开▾ menu (and the
/// macOS 「文件」 menu) instead.
struct RecentPage: View {
    @Bindable var library: LibraryModel
    @Bindable var settings: AppSettings
    @Binding var page: HomePage
    @Binding var searchText: String
    var openFiles: () -> Void
    var openICloud: () -> Void
    var browseLocal: () -> Void
    var openSettings: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    /// Tap counter behind the 设置 gear's symbol feedback. The card itself is a
    /// system sheet, so its slide-up is Apple's animation, not ours.
    @State private var settingsTapPulse = 0
    /// Chrome motion only. 减少动态效果 removes the symbol effect.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        recentBody
            .chromeTypography(language: .system)
            .navigationTitle(text(HomeLibrary.navigationTitle))
            .background(homeSurface(raised: false))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            // 设置 used to reserve its own strip above the search field, which
            // left an empty band under the title. It is a system navigation-bar
            // item now: it sits inside the bar, left of the ⋯ menu, and the bar
            // draws its Liquid Glass capsule. Nothing here paints a plate of its
            // own (a plate inside a bar item is the double-glass bug).
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(verbatim: text("搜索"))
            )
            #else
            .searchable(text: $searchText, prompt: Text(verbatim: text("搜索")))
            #endif
            .toolbar {
                #if os(iOS)
                if compactChrome {
                    iphoneHomeToolbar
                } else {
                    padHomeToolbar
                }
                #else
                macHomeToolbar
                #endif
            }
    }

    #if os(iOS)
    /// The phone keeps the toolbar it shipped with. Only a regular-width iPad
    /// gets the 新建 / 打开▾ arrangement, so iPhone behaviour does not move.
    private var compactChrome: Bool {
        horizontalSizeClass == .compact
    }

    /// The 设置 entry, as one system navigation-bar item.
    ///
    /// It is declared as a `ToolbarItem` so the bar paints the Liquid Glass
    /// capsule and the pressed state, exactly like the ⋯ menu beside it. A
    /// custom plate inside a bar item would be the double-glass bug, so none is
    /// added here. `ToolbarItem` order is declaration order, and this one is
    /// declared after 新建 / 从文件应用打开 and before the ⋯ menu, which puts the
    /// gear immediately left of ⋯.
    @ToolbarContentBuilder
    private var homeSettingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                settingsTapPulse += 1
                openSettings()
            } label: {
                Label(text("设置"), systemImage: "gearshape")
                    // Apple's symbol effect acknowledges the tap before the
                    // system sheet slides over the page. Reduced motion removes it.
                    .symbolEffect(.bounce, options: .nonRepeating, value: settingsTapPulse)
                    .symbolEffectsRemoved(reduceMotion)
            }
            .accessibilityLabel(text("设置"))
            .accessibilityIdentifier("home.settings")
        }
    }

    /// System navigation-bar items. One toolbar button and one menu; the system
    /// draws their glass. No custom capsule, blur, or background.
    @ToolbarContentBuilder
    private var iphoneHomeToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                library.makeNew()
            } label: {
                Label(text("新建导图"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("home.newMap")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: openFiles) {
                Label(text("从文件应用打开"), systemImage: "folder")
            }
            .accessibilityIdentifier("home.openFiles")
        }
        homeSettingsToolbarItem
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    page = .newMap
                } label: {
                    Label(text("模板库"), systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("home.templates")
                Menu {
                    Button(action: openICloud) {
                        Label(text("从 iCloud 云盘打开"), systemImage: "icloud")
                    }
                    Button(action: browseLocal) {
                        Label(text(LocalDeviceLabel.current.title), systemImage: "internaldrive")
                    }
                } label: {
                    Label(text("打开"), systemImage: "folder")
                }
                .accessibilityIdentifier("home.open")
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel(text("更多"))
            .accessibilityIdentifier("home.toolbarMenu")
        }
    }

    /// iPad: 新建, 打开▾, search, card wall. The sidebar rows became this one menu.
    /// 设置 keeps the same bar item the phone uses, so the iPad does not lose the
    /// entry it used to get from the removed top strip.
    @ToolbarContentBuilder
    private var padHomeToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                library.makeNew()
            } label: {
                Label(text("新建导图"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("home.newMap")
        }
        homeSettingsToolbarItem
        ToolbarItem(placement: .primaryAction) {
            openMenu
        }
    }
    #else
    @ToolbarContentBuilder
    private var macHomeToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                library.makeNew()
            } label: {
                Label(text("新建导图"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("home.newMap")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            openMenu
        }
    }
    #endif

    /// 打开▾: the commands the sidebar used to list, plus the template library.
    private var openMenu: some View {
        Menu {
            Button(action: openFiles) {
                Label(text("从文件应用打开"), systemImage: "folder")
            }
            .accessibilityIdentifier("home.openFiles")
            Divider()
            Button(action: openICloud) {
                Label(text("从 iCloud 云盘打开"), systemImage: "icloud")
            }
            .accessibilityIdentifier("home.openICloud")
            Button(action: browseLocal) {
                Label(text(LocalDeviceLabel.current.title), systemImage: "internaldrive")
            }
            .accessibilityIdentifier("home.browseLocal")
            Divider()
            Button {
                page = .newMap
            } label: {
                Label(text("模板库"), systemImage: "square.grid.2x2")
            }
            .accessibilityIdentifier("home.templates")
        } label: {
            Label(text("打开"), systemImage: "folder")
        }
        .accessibilityIdentifier("home.open")
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, locale: locale)
    }

    private var palette: HomePalette {
        settings.homeBackground.palette(for: colorScheme == .dark ? .dark : .light)
    }

    /// Page or card surface. In dark the card is raised by lightness; there is no
    /// border, because an outline in a dark page reads as dirt.
    private func homeSurface(raised: Bool) -> Color {
        let hex = raised ? palette.cardHex : palette.pageHex
        guard let color = BranchColor(hex: hex) else { return .clear }
        return Color(red: color.red, green: color.green, blue: color.blue)
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
                                RecentDocumentThumbnail(entry: entry, library: library)
                                Text(entry.filename)
                                    .lineLimit(1)
                                Text(entry.modifiedAt, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                homeSurface(raised: true),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
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

/// Loads the recent-file image without blocking scrolling. Quick Look's async
/// generator renders the actual package preview; a missing/invalid preview keeps
/// the system map glyph visible instead of leaving a blank tile.
private struct RecentDocumentThumbnail: View {
    let entry: RecentMapEntry
    let library: LibraryModel
    @State private var imageData: Data?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.quaternary)
            if let image = RecentThumbnailFallback.image(imageData) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(systemName: "map")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.recent.thumbnail")
        .task(id: entry.id) {
            imageData = await library.recentThumbnail(for: entry)
        }
    }
}

private extension Image {
    init(platformImage: PlatformThumbnailImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
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

// MARK: - Settings

/// The settings items, in one order, in three pages. The iPhone / iPad 设置 card
/// stacks all three in one form; the macOS Settings window shows one page per
/// system tab. No item is defined twice.
struct SettingsGeneralPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
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
            .accessibilityIdentifier("settings.appearance")
        }
        AppearanceSettingsPanel(settings: settings, identifierPrefix: "settings.appearance", density: .settings)
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }
}

struct SettingsExportPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
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
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }
}

struct SettingsAboutPage: View {
    @Bindable var settings: AppSettings
    @State private var showNotice = false

    var body: some View {
        Section(text("关于")) {
            LabeledContent(text("版本"), value: AppInfo.version)
            #if os(macOS)
            // The Settings window has no navigation stack; the notice opens as a sheet.
            Button(text("NOTICE 开源致谢")) { showNotice = true }
                .accessibilityIdentifier("settings.notice")
                .sheet(isPresented: $showNotice) {
                    NoticeSheet()
                }
            #else
            NavigationLink(text("NOTICE 开源致谢")) {
                NoticeSheet()
            }
            #endif
        }
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }
}

private struct NoticeSheet: View {
    var body: some View {
        ScrollView {
            Text(AppInfo.notice)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("NOTICE")
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 320)
        #endif
    }
}

/// iOS / iPadOS host: 设置 as a card, not a page. The home page's gear pulls it
/// up from the bottom edge, so it carries an inline 设置 header on the card's own
/// bar instead of a large title, and 完成 dismisses the card. The three groups of
/// items are the same three pages the macOS window shows, one after another.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SettingsGeneralPage(settings: settings)
                SettingsExportPage(settings: settings)
                SettingsAboutPage(settings: settings)
            }
            .formStyle(.grouped)
            .navigationTitle(text("设置"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("完成")) { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .chromeTypography(language: settings.language)
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }
}

#if os(macOS)
/// The macOS Settings window: a standard `Settings` scene with the system
/// `TabView`, which draws the top tabs a Mac settings window has. No hand-drawn
/// column, no page inside the main window.
struct MacSettingsScene: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            Tab {
                Form {
                    SettingsGeneralPage(settings: settings)
                }
                .formStyle(.grouped)
            } label: {
                Label(text("通用"), systemImage: "gearshape")
            }
            Tab {
                Form {
                    SettingsExportPage(settings: settings)
                }
                .formStyle(.grouped)
            } label: {
                Label(text("导出"), systemImage: "square.and.arrow.up")
            }
            Tab {
                Form {
                    SettingsAboutPage(settings: settings)
                }
                .formStyle(.grouped)
            } label: {
                Label(text("关于"), systemImage: "info.circle")
            }
        }
        .frame(width: 520, height: 460)
        .preferredColorScheme(settings.appearance.colorScheme)
        .environment(\.locale, settings.resolvedLocale)
        .chromeTypography(language: settings.language)
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }
}
#endif

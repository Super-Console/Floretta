import SwiftUI
import UniformTypeIdentifiers

/// Home from the iPad reference: centered title「最近」, not a large title.
struct RecentPage: View {
    @Bindable var library: LibraryModel
    @Binding var page: HomePage
    @Binding var sidebarVisible: Bool
    @Binding var searchText: String
    var showSettings: () -> Void

    @State private var showCrown = false

    var body: some View {
        recentBody
            .navigationTitle("最近")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "搜索")
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    if sidebarVisible {
                        Button(action: showSettings) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("设置")
                    }
                    Button {
                        sidebarVisible.toggle()
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .accessibilityLabel("侧栏")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        page = .newMap
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建")
                    Button {
                        showCrown = true
                    } label: {
                        Image(systemName: "crown")
                    }
                    .accessibilityLabel("订阅")
                    Button {
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
            .alert("未开放", isPresented: $showCrown) {
                Button("好", role: .cancel) {}
            } message: {
                Text("订阅尚未开放。")
            }
    }

    @ViewBuilder
    private var recentBody: some View {
        let items = filtered
        if library.recents.isEmpty {
            ContentUnavailableView {
                Label("这里还没有导图。", systemImage: "pencil.and.list.clipboard")
            } description: {
                Text("现在是创建一个的好时机。")
            } actions: {
                Button("新建导图") { page = .newMap }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        } else if items.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(items) { entry in
                Button {
                    library.openRecent(entry)
                } label: {
                    LabeledContent(entry.filename) {
                        Text(entry.modifiedAt, format: .dateTime.year().month().day().hour().minute())
                    }
                }
                .buttonStyle(.plain)
            }
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
                page = .newMap
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
                    Label("我的iPad", systemImage: "ipad")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {} label: {
                Label("登录", systemImage: "person.crop.circle")
            }
            .disabled(true)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NewMapPage: View {
    var onClose: () -> Void
    var onCreateMindMap: () -> Void
    @Binding var saveLocationTitle: String
    var chooseDocuments: () -> Void
    var chooseICloud: () -> Void

    @State private var focusedSection: String?
    @State private var closedNotice: String?

    private let sections = TemplateCatalog.sections

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(visibleSections, id: \.title) { section in
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
                Menu {
                    Button("我的iPad", action: chooseDocuments)
                    Button("iCloud云盘", action: chooseICloud)
                } label: {
                    Label(saveLocationTitle, systemImage: "chevron.down")
                }
            }
        }
        .alert("未开放", isPresented: noticePresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(closedNotice ?? "")
        }
    }

    private var visibleSections: [TemplateSection] {
        guard let focusedSection else { return sections }
        return sections.filter { $0.title == focusedSection }
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
                Button(focusedSection == section.title ? "全部" : "全部") {
                    focusedSection = focusedSection == section.title ? nil : section.title
                }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(section.cards) { card in
                        cardButton(card, ai: section.ai)
                    }
                }
            }
        }
    }

    private func cardButton(_ card: TemplateCard, ai: Bool) -> some View {
        Button {
            if card.createsDocument {
                onCreateMindMap()
            } else if ai {
                closedNotice = "未开放"
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(width: 180, height: 120)
                    .overlay {
                        Image(systemName: card.symbol)
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !card.createsDocument && !ai {
                            Text("即将推出")
                                .font(.caption2)
                                .padding(6)
                        }
                    }
                Text(card.name)
                    .font(.callout)
                    .frame(width: 180, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(!card.createsDocument && !ai)
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


import FlorettaCore
import Foundation
import Observation
import SwiftUI

/// One saved `document.json` from `DocumentSnapshots.list`. Oldest first.
struct SnapshotHistoryItem: Equatable, Identifiable, Sendable {
    var generation: Int
    var title: String
    var rootText: String
    var topicCount: Int
    var modifiedAt: Date

    var id: Int { generation }
}

enum SnapshotRevision: Hashable, Sendable {
    case current
    case generation(Int)
}

enum SnapshotChangeKind: Equatable, Sendable {
    case added
    case removed
    case changed
}

enum SnapshotChangeRole: Equatable, Sendable {
    case documentTitle
    case topic
    case freeNode
    case sticky
    case relationship
    case summary
    case boundary
    case note
    case attachments
    case labels
    case childOrder
    case place
}

/// One tree or text difference. User strings stay in `before` / `after`.
/// `beforeKey` / `afterKey` are catalog keys (sticky colors), never node text.
struct SnapshotChange: Equatable, Identifiable, Sendable {
    var id: String
    var kind: SnapshotChangeKind
    var role: SnapshotChangeRole
    var path: String
    var before: String
    var after: String
    var beforeKey: String?
    var afterKey: String?
}

struct SnapshotRollbackResult: Equatable, Sendable {
    var document: MindMapDocument
    var catalog: ZipDirectory
    var byteCount: Int64
}

/// Lists, rolls back, and compares the existing sidecar. It does not invent a
/// second snapshot file and it does not replace `FlorettaStreamingDocument.save`.
@MainActor
@Observable
final class SnapshotHistorySession {
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let files: any StreamingFilePort
    @ObservationIgnored private var stored: [Int: MindMapDocument] = [:]

    private(set) var snapshots: [SnapshotHistoryItem] = []
    private(set) var current: MindMapDocument
    private(set) var loadError: String?

    init(url: URL, live: MindMapDocument, files: any StreamingFilePort) {
        self.url = url
        self.files = files
        self.current = live
        do {
            try reload(live: live)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
        }
    }

    func reload(live: MindMapDocument) throws {
        current = live
        let listed = try DocumentSnapshots.list(documentAt: url)
        var documents: [Int: MindMapDocument] = [:]
        documents.reserveCapacity(listed.count)
        var items: [SnapshotHistoryItem] = []
        items.reserveCapacity(listed.count)
        for snapshot in listed {
            documents[snapshot.generation] = snapshot.document
            items.append(SnapshotHistoryItem(
                generation: snapshot.generation,
                title: snapshot.document.title,
                rootText: snapshot.document.roots.first?.text ?? "",
                topicCount: snapshot.document.topicCount,
                modifiedAt: snapshot.document.modifiedAt
            ))
        }
        stored = documents
        snapshots = items
        loadError = nil
    }

    func document(for revision: SnapshotRevision) -> MindMapDocument? {
        switch revision {
        case .current:
            return current
        case .generation(let generation):
            return stored[generation]
        }
    }

    func diff(from older: SnapshotRevision, to newer: SnapshotRevision) -> [SnapshotChange] {
        guard let left = document(for: older), let right = document(for: newer) else { return [] }
        return SnapshotOutlineDiff.changes(from: left, to: right)
    }

    /// Writes `generation` back through the existing atomic save.
    /// Unsaved `live` edits are saved first, so they become a snapshot.
    /// When the window is already full and `generation` is the oldest file,
    /// the chosen document is held in memory and written with the same save.
    @discardableResult
    func rollback(to generation: Int, live: MindMapDocument) throws -> SnapshotRollbackResult {
        let listed = try DocumentSnapshots.list(documentAt: url)
        guard let chosen = listed.first(where: { $0.generation == generation }) else {
            throw DocumentOpenError.message("找不到这一版。")
        }
        let onDisk = try openedPackage().document
        let keepLimit = min(SnapshotRetention.hardCap, max(listed.count, SnapshotRetention.standard.limit))
        let keep = SnapshotRetention(limit: keepLimit)
        if live != onDisk {
            let dropsTarget = listed.count >= keepLimit && listed.first?.generation == generation
            if dropsTarget {
                _ = try FlorettaStreamingDocument.save(document: live, to: url, files: files, snapshots: keep)
                _ = try FlorettaStreamingDocument.save(document: chosen.document, to: url, files: files, snapshots: keep)
                let opened = try openedPackage()
                try reload(live: opened.document)
                return SnapshotRollbackResult(document: opened.document, catalog: opened.catalog, byteCount: opened.bytes)
            }
            _ = try FlorettaStreamingDocument.save(document: live, to: url, files: files, snapshots: keep)
        }
        _ = try DocumentSnapshots.rollback(documentAt: url, to: generation, files: files, retention: keep)
        let opened = try openedPackage()
        try reload(live: opened.document)
        return SnapshotRollbackResult(document: opened.document, catalog: opened.catalog, byteCount: opened.bytes)
    }

    private func openedPackage() throws -> (document: MindMapDocument, catalog: ZipDirectory, bytes: Int64) {
        let reader = try files.openReader(at: url)
        do {
            let opened = try FlorettaStreamingDocument.open(reader)
            let bytes = reader.count
            try reader.close()
            return (opened.document, opened.directory, bytes)
        } catch {
            try? reader.close()
            throw error
        }
    }
}

enum SnapshotOutlineDiff {
    static func changes(from older: MindMapDocument, to newer: MindMapDocument) -> [SnapshotChange] {
        if older == newer { return [] }
        var changes: [SnapshotChange] = []
        if older.title != newer.title {
            changes.append(SnapshotChange(
                id: "title",
                kind: .changed,
                role: .documentTitle,
                path: "",
                before: older.title,
                after: newer.title
            ))
        }
        let oldTopics = TopicIndex(older)
        let newTopics = TopicIndex(newer)
        changes.append(contentsOf: diffTopics(old: oldTopics, new: newTopics))
        changes.append(contentsOf: diffStickies(old: older.stickies, new: newer.stickies))
        changes.append(contentsOf: diffLinks(old: linkRecords(in: older, topics: oldTopics), new: linkRecords(in: newer, topics: newTopics)))
        return changes
    }

    private struct TopicRecord {
        var id: UUID
        var role: SnapshotChangeRole
        var scope: UUID?
        var parentID: UUID?
        var path: String
        var text: String
        var note: String
        var attachments: [String]
        var labels: [String]
        var childIDs: [UUID]
        var childTexts: [String]
        var summaries: [(id: UUID, text: String)]
        var boundaries: [(id: UUID, title: String)]
    }

    private struct TopicIndex {
        var order: [UUID] = []
        var records: [UUID: TopicRecord] = [:]

        init(_ document: MindMapDocument) {
            absorb(document.roots, role: .topic, scope: nil, parent: nil, prefix: [])
            absorb(document.freeNodes, role: .freeNode, scope: nil, parent: nil, prefix: [])
            for canvas in document.additionalCanvases {
                let prefix = canvas.title.isEmpty ? [] : [canvas.title]
                absorb(canvas.roots, role: .topic, scope: canvas.id, parent: nil, prefix: prefix)
                absorb(canvas.freeNodes, role: .freeNode, scope: canvas.id, parent: nil, prefix: prefix)
            }
        }

        private mutating func absorb(
            _ nodes: [MindMapNode],
            role: SnapshotChangeRole,
            scope: UUID?,
            parent: UUID?,
            prefix: [String]
        ) {
            for node in nodes {
                guard records[node.id] == nil else { continue }
                var parts = prefix
                if !node.text.isEmpty { parts.append(node.text) }
                let record = TopicRecord(
                    id: node.id,
                    role: role,
                    scope: scope,
                    parentID: parent,
                    path: parts.joined(separator: " / "),
                    text: node.text,
                    note: node.note,
                    attachments: node.attachments.map(\.filename),
                    labels: node.labels,
                    childIDs: node.children.map(\.id),
                    childTexts: node.children.map(\.text),
                    summaries: node.summaries.map { (id: $0.id, text: $0.text) },
                    boundaries: node.boundaries.map { (id: $0.id, title: $0.title) }
                )
                records[node.id] = record
                order.append(node.id)
                absorb(node.children, role: role, scope: scope, parent: node.id, prefix: parts)
            }
        }
    }

    private struct LinkRecord {
        var id: UUID
        var line: String
    }

    private static func linkRecords(in document: MindMapDocument, topics: TopicIndex) -> [LinkRecord] {
        var records: [LinkRecord] = []
        func append(_ links: [TopicRelationship]) {
            for link in links {
                let source = topics.records[link.sourceID]?.text ?? ""
                let target = topics.records[link.targetID]?.text ?? ""
                let line = link.title.isEmpty ? "\(source) → \(target)" : "\(source) → \(target) · \(link.title)"
                records.append(LinkRecord(id: link.id, line: line))
            }
        }
        append(document.relationships)
        for canvas in document.additionalCanvases {
            append(canvas.relationships)
        }
        return records
    }

    private static func diffTopics(old: TopicIndex, new: TopicIndex) -> [SnapshotChange] {
        var changes: [SnapshotChange] = []
        for id in new.order {
            guard let newer = new.records[id] else { continue }
            guard let older = old.records[id] else {
                changes.append(contentsOf: appear(newer, kind: .added))
                continue
            }
            changes.append(contentsOf: changedTopic(from: older, to: newer))
        }
        for id in old.order where new.records[id] == nil {
            guard let older = old.records[id] else { continue }
            changes.append(contentsOf: appear(older, kind: .removed))
        }
        return changes
    }

    private static func appear(_ record: TopicRecord, kind: SnapshotChangeKind) -> [SnapshotChange] {
        let before = kind == .removed
        var rows = [row(id: record.id.uuidString, kind: kind, role: record.role, path: record.path, before: before ? record.text : "", after: before ? "" : record.text)]
        if !record.note.isEmpty {
            rows.append(row(id: "\(record.id.uuidString)#note", kind: kind, role: .note, path: record.path, before: before ? record.note : "", after: before ? "" : record.note))
        }
        if !record.attachments.isEmpty {
            let names = record.attachments.joined(separator: "、")
            rows.append(row(id: "\(record.id.uuidString)#files", kind: kind, role: .attachments, path: record.path, before: before ? names : "", after: before ? "" : names))
        }
        if !record.labels.isEmpty {
            let names = record.labels.joined(separator: "、")
            rows.append(row(id: "\(record.id.uuidString)#labels", kind: kind, role: .labels, path: record.path, before: before ? names : "", after: before ? "" : names))
        }
        for summary in record.summaries {
            rows.append(row(id: summary.id.uuidString, kind: kind, role: .summary, path: record.path, before: before ? summary.text : "", after: before ? "" : summary.text))
        }
        for boundary in record.boundaries {
            rows.append(row(id: boundary.id.uuidString, kind: kind, role: .boundary, path: record.path, before: before ? boundary.title : "", after: before ? "" : boundary.title))
        }
        return rows
    }

    private static func changedTopic(from older: TopicRecord, to newer: TopicRecord) -> [SnapshotChange] {
        var rows: [SnapshotChange] = []
        if older.text != newer.text {
            rows.append(row(id: newer.id.uuidString, kind: .changed, role: newer.role, path: newer.path, before: older.text, after: newer.text))
        }
        if older.note != newer.note {
            rows.append(row(id: "\(newer.id.uuidString)#note", kind: .changed, role: .note, path: newer.path, before: older.note, after: newer.note))
        }
        if older.attachments != newer.attachments {
            rows.append(row(id: "\(newer.id.uuidString)#files", kind: .changed, role: .attachments, path: newer.path, before: older.attachments.joined(separator: "、"), after: newer.attachments.joined(separator: "、")))
        }
        if older.labels != newer.labels {
            rows.append(row(id: "\(newer.id.uuidString)#labels", kind: .changed, role: .labels, path: newer.path, before: older.labels.joined(separator: "、"), after: newer.labels.joined(separator: "、")))
        }
        if older.parentID != newer.parentID || older.scope != newer.scope {
            rows.append(row(id: "\(newer.id.uuidString)#place", kind: .changed, role: .place, path: newer.path, before: older.path, after: newer.path))
        }
        if older.childIDs != newer.childIDs, Set(older.childIDs) == Set(newer.childIDs) {
            rows.append(row(id: "\(newer.id.uuidString)#order", kind: .changed, role: .childOrder, path: newer.path, before: older.childTexts.joined(separator: " / "), after: newer.childTexts.joined(separator: " / ")))
        }
        rows.append(contentsOf: diffPairs(old: older.summaries, new: newer.summaries, role: .summary, path: newer.path))
        rows.append(contentsOf: diffPairs(
            old: older.boundaries.map { (id: $0.id, text: $0.title) },
            new: newer.boundaries.map { (id: $0.id, text: $0.title) },
            role: .boundary,
            path: newer.path
        ))
        return rows
    }

    private static func diffPairs(
        old: [(id: UUID, text: String)],
        new: [(id: UUID, text: String)],
        role: SnapshotChangeRole,
        path: String
    ) -> [SnapshotChange] {
        var oldMap: [UUID: String] = [:]
        for item in old { oldMap[item.id] = item.text }
        var newMap: [UUID: String] = [:]
        for item in new { newMap[item.id] = item.text }
        var rows: [SnapshotChange] = []
        for item in new {
            if let previous = oldMap[item.id] {
                if previous != item.text {
                    rows.append(row(id: item.id.uuidString, kind: .changed, role: role, path: path, before: previous, after: item.text))
                }
            } else {
                rows.append(row(id: item.id.uuidString, kind: .added, role: role, path: path, before: "", after: item.text))
            }
        }
        for item in old where newMap[item.id] == nil {
            rows.append(row(id: item.id.uuidString, kind: .removed, role: role, path: path, before: item.text, after: ""))
        }
        return rows
    }

    private static func diffStickies(old: [StickyNote], new: [StickyNote]) -> [SnapshotChange] {
        var oldMap: [UUID: StickyNote] = [:]
        for sticky in old { oldMap[sticky.id] = sticky }
        var newMap: [UUID: StickyNote] = [:]
        for sticky in new { newMap[sticky.id] = sticky }
        var rows: [SnapshotChange] = []
        for sticky in new {
            let color = colorKey(sticky.color)
            if let previous = oldMap[sticky.id] {
                guard previous.text != sticky.text || previous.color != sticky.color else { continue }
                rows.append(SnapshotChange(
                    id: sticky.id.uuidString,
                    kind: .changed,
                    role: .sticky,
                    path: "",
                    before: previous.text,
                    after: sticky.text,
                    beforeKey: colorKey(previous.color),
                    afterKey: color
                ))
            } else {
                rows.append(SnapshotChange(
                    id: sticky.id.uuidString,
                    kind: .added,
                    role: .sticky,
                    path: "",
                    before: "",
                    after: sticky.text,
                    afterKey: color
                ))
            }
        }
        for sticky in old where newMap[sticky.id] == nil {
            rows.append(SnapshotChange(
                id: sticky.id.uuidString,
                kind: .removed,
                role: .sticky,
                path: "",
                before: sticky.text,
                after: "",
                beforeKey: colorKey(sticky.color)
            ))
        }
        return rows
    }

    private static func diffLinks(old: [LinkRecord], new: [LinkRecord]) -> [SnapshotChange] {
        var oldMap: [UUID: String] = [:]
        for link in old { oldMap[link.id] = link.line }
        var newMap: [UUID: String] = [:]
        for link in new { newMap[link.id] = link.line }
        var rows: [SnapshotChange] = []
        for link in new {
            if let previous = oldMap[link.id] {
                if previous != link.line {
                    rows.append(row(id: link.id.uuidString, kind: .changed, role: .relationship, path: "", before: previous, after: link.line))
                }
            } else {
                rows.append(row(id: link.id.uuidString, kind: .added, role: .relationship, path: "", before: "", after: link.line))
            }
        }
        for link in old where newMap[link.id] == nil {
            rows.append(row(id: link.id.uuidString, kind: .removed, role: .relationship, path: "", before: link.line, after: ""))
        }
        return rows
    }

    private static func colorKey(_ color: StickyColor) -> String {
        switch color {
        case .yellow: "黄色"
        case .pink: "粉色"
        case .green: "绿色"
        case .blue: "蓝色"
        case .orange: "橙色"
        }
    }

    private static func row(
        id: String,
        kind: SnapshotChangeKind,
        role: SnapshotChangeRole,
        path: String,
        before: String,
        after: String
    ) -> SnapshotChange {
        SnapshotChange(id: id, kind: kind, role: role, path: path, before: before, after: after)
    }
}

struct SnapshotHistorySheet: View {
    var session: EditorSession
    var text: (String) -> String
    var locale: Locale

    @Environment(\.dismiss) private var dismiss
    @State private var history: SnapshotHistorySession
    @State private var pendingGeneration: Int?
    @State private var rollbackError: String?
    @State private var showCompare = false
    @State private var left: SnapshotRevision = .current
    @State private var right: SnapshotRevision = .current

    init(session: EditorSession, url: URL, text: @escaping (String) -> String, locale: Locale) {
        self.session = session
        self.text = text
        self.locale = locale
        _history = State(initialValue: SnapshotHistorySession(
            url: url,
            live: session.document,
            files: FoundationStreamingFiles()
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if showCompare {
                    comparePage
                } else {
                    historyList
                }
            }
            .navigationTitle(text(showCompare ? "对比" : "版本历史"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if showCompare {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showCompare = false
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel(text("返回"))
                        .accessibilityIdentifier("snapshotHistory.back")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(text("关闭"))
                        .accessibilityIdentifier("snapshotHistory.close")
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(text("关闭"))
                        .accessibilityIdentifier("snapshotHistory.close")
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .presentationDetents([.medium, .large])
        .confirmationDialog(Text(verbatim: pendingTitle), isPresented: pendingPresented, titleVisibility: .visible) {
            Button(text("回滚")) { performRollback() }
                .accessibilityIdentifier("snapshotHistory.confirmRollback")
            Button(text("取消"), role: .cancel) { pendingGeneration = nil }
        } message: {
            Text(verbatim: text("当前这份会先写入历史，再换成所选版本。工具栏的撤销不能退回这次替换。要回到刚才的内容，再从历史里选那一版。"))
        }
        .alert(Text(verbatim: text("无法回滚")), isPresented: rollbackErrorPresented) {
            Button(text("好"), role: .cancel) { rollbackError = nil }
        } message: {
            Text(verbatim: FlorettaL10n.present(rollbackError ?? "", locale: locale))
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if let loadError = history.loadError {
            ContentUnavailableView {
                Label(text("无法读取历史版本"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: FlorettaL10n.present(loadError, locale: locale))
            }
        } else {
            Form {
                Section(text("当前")) {
                    currentRow
                }
                Section {
                    if history.snapshots.isEmpty {
                        Text(verbatim: text("还没有历史版本。再保存一次之后，上一版会出现在这里。"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(history.snapshots.reversed())) { item in
                            historyRow(item)
                        }
                    }
                } header: {
                    Text(verbatim: text("历史版本"))
                } footer: {
                    Text(verbatim: text("每一行的对比是和当前比较。进入对比后可以改选任意两版。"))
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("snapshotHistory.list")
        }
    }

    private var currentRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: text("当前"))
            Text(verbatim: preview(title: history.current.title, root: history.current.roots.first?.text ?? ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(verbatim: topicCount(history.current.topicCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("snapshotHistory.current")
    }

    private func historyRow(_ item: SnapshotHistoryItem) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: versionTitle(item.generation))
                Text(verbatim: preview(title: item.title, root: item.rootText))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(verbatim: "\(topicCount(item.topicCount)) · \(stamp(item.modifiedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button {
                left = .generation(item.generation)
                right = .current
                showCompare = true
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(text("对比"))
            .accessibilityHint(text("和当前这份比较"))
            .accessibilityIdentifier("snapshotHistory.compare.\(item.generation)")

            Button {
                pendingGeneration = item.generation
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(text("回滚"))
            .accessibilityHint(text("回滚到这一版"))
            .accessibilityIdentifier("snapshotHistory.rollback.\(item.generation)")
        }
        .accessibilityIdentifier("snapshotHistory.row.\(item.generation)")
    }

    private var comparePage: some View {
        let missing = history.document(for: left) == nil || history.document(for: right) == nil
        let changes = missing ? [] : history.diff(from: left, to: right)
        return Form {
            Section {
                revisionPicker(text("左边"), selection: $left)
                revisionPicker(text("右边"), selection: $right)
            }
            Section {
                if missing {
                    Text(verbatim: text("找不到这一版。"))
                        .foregroundStyle(.secondary)
                } else if changes.isEmpty {
                    Text(verbatim: text("这两份的文字和结构没有差别。"))
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: changeSummary(changes))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(changes) { change in
                        changeRow(change)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("snapshotHistory.compare")
    }

    private func revisionPicker(_ label: String, selection: Binding<SnapshotRevision>) -> some View {
        Picker(label, selection: selection) {
            Text(verbatim: text("当前")).tag(SnapshotRevision.current)
            ForEach(Array(history.snapshots.reversed())) { item in
                Text(verbatim: versionTitle(item.generation)).tag(SnapshotRevision.generation(item.generation))
            }
        }
        .pickerStyle(.menu)
    }

    private func changeRow(_ change: SnapshotChange) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: changeSymbol(change.kind))
                .foregroundStyle(changeTint(change.kind))
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: roleLine(change))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                changeBody(change)
                if change.beforeKey != change.afterKey {
                    if let beforeKey = change.beforeKey, change.kind != .added {
                        Text(verbatim: text(beforeKey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let afterKey = change.afterKey, change.kind != .removed {
                        Text(verbatim: text(afterKey))
                            .font(.caption)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(changeLabel(change))
    }

    @ViewBuilder
    private func changeBody(_ change: SnapshotChange) -> some View {
        if change.before == change.after {
            Text(verbatim: change.after)
        } else if change.kind == .added {
            Text(verbatim: change.after)
        } else if change.kind == .removed {
            Text(verbatim: change.before)
                .strikethrough()
                .foregroundStyle(.secondary)
        } else {
            Text(verbatim: change.before)
                .strikethrough()
                .foregroundStyle(.secondary)
            Text(verbatim: change.after)
        }
    }

    private func changeLabel(_ change: SnapshotChange) -> String {
        let body = change.after.isEmpty ? change.before : change.after
        return "\(text(kindKey(change.kind))) \(roleLine(change)) \(body)"
    }

    private func kindKey(_ kind: SnapshotChangeKind) -> String {
        switch kind {
        case .added: "新增"
        case .removed: "删去"
        case .changed: "修改"
        }
    }

    private func roleLine(_ change: SnapshotChange) -> String {
        let name = text(roleKey(change.role))
        if change.path.isEmpty { return name }
        return "\(name) · \(change.path)"
    }

    private func roleKey(_ role: SnapshotChangeRole) -> String {
        switch role {
        case .documentTitle: "标题"
        case .topic: "主题"
        case .freeNode: "自由节点"
        case .sticky: "便签"
        case .relationship: "关系"
        case .summary: "概要"
        case .boundary: "边界"
        case .note: "备注"
        case .attachments: "附件"
        case .labels: "标签"
        case .childOrder: "子节点顺序"
        case .place: "位置"
        }
    }

    private func changeSymbol(_ kind: SnapshotChangeKind) -> String {
        switch kind {
        case .added: "plus"
        case .removed: "minus"
        case .changed: "pencil"
        }
    }

    private func changeTint(_ kind: SnapshotChangeKind) -> Color {
        switch kind {
        case .added: .green
        case .removed: .red
        case .changed: .orange
        }
    }

    private func changeSummary(_ changes: [SnapshotChange]) -> String {
        let added = changes.filter { $0.kind == .added }.count
        let removed = changes.filter { $0.kind == .removed }.count
        let changed = changes.filter { $0.kind == .changed }.count
        return FlorettaL10n.format(
            "新增 %lld，删去 %lld，修改 %lld",
            locale: locale,
            arguments: [Int64(added), Int64(removed), Int64(changed)]
        )
    }

    private var pendingPresented: Binding<Bool> {
        Binding(
            get: { pendingGeneration != nil },
            set: { if !$0 { pendingGeneration = nil } }
        )
    }

    private var pendingTitle: String {
        guard let pendingGeneration else { return "" }
        return FlorettaL10n.format("回滚到第 %lld 版？", locale: locale, arguments: [Int64(pendingGeneration)])
    }

    private var rollbackErrorPresented: Binding<Bool> {
        Binding(
            get: { rollbackError != nil },
            set: { if !$0 { rollbackError = nil } }
        )
    }

    private func performRollback() {
        guard let generation = pendingGeneration else { return }
        pendingGeneration = nil
        session.prepareToSave()
        do {
            let result = try history.rollback(to: generation, live: session.document)
            session.replaceFromSnapshot(result.document, catalog: result.catalog, bytes: result.byteCount)
            showCompare = false
        } catch {
            rollbackError = (error as? LocalizedError)?.errorDescription ?? "无法回滚"
        }
    }

    private func versionTitle(_ generation: Int) -> String {
        FlorettaL10n.format("第 %lld 版", locale: locale, arguments: [Int64(generation)])
    }

    private func topicCount(_ count: Int) -> String {
        FlorettaL10n.format("%lld 个主题", locale: locale, arguments: [Int64(count)])
    }

    private func preview(title: String, root: String) -> String {
        if title.isEmpty { return root }
        if root.isEmpty || root == title { return title }
        return "\(title) · \(root)"
    }

    private func stamp(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
    }
}

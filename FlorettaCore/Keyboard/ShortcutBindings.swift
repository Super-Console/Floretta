import Foundation

/// The chords in force, resolved over `XMindShortcutCatalog.commands`.
///
/// A value with no overrides is the shipped experience: `catalogDefaults`
/// resolves every row to the chord it ships with, and a command that ships
/// unbound stays unbound. `AppSettings` owns one of these and hands it to the
/// keyboard session, the menu bar, and the iPad key-command list, so a change
/// takes effect on the next key press and the next menu draw.
/// `ShortcutChord` is nested in the catalog; this alias keeps the binding code
/// readable without repeating the parent type on every line.
public typealias ShortcutChord = XMindShortcutCatalog.ShortcutChord

public struct ShortcutBindings: Equatable, Sendable {
    /// Chords the user picked that differ from the shipped table.
    public private(set) var overrides: [ShortcutCommandID: ShortcutChord]
    /// Commands the user explicitly unbound (the shipped table has a default).
    public private(set) var unbound: Set<ShortcutCommandID>
    /// Effective chord → command. Mode is part of the key because ↩ commits in
    /// a text field and creates a topic on the canvas. Rebuilt on every write;
    /// the first row in catalog order wins a clash, which is why the conflict
    /// warning is worth reading.
    private var lookup: [LookupKey: MindMapCommand]

    public init(
        overrides: [ShortcutCommandID: ShortcutChord] = [:],
        unbound: Set<ShortcutCommandID> = []
    ) {
        self.overrides = overrides
        self.unbound = unbound
        self.lookup = Self.makeLookup(overrides: overrides, unbound: unbound)
    }

    /// The shipped experience: every row at its own default, nothing overridden.
    public static let catalogDefaults = ShortcutBindings()

    public static func == (lhs: ShortcutBindings, rhs: ShortcutBindings) -> Bool {
        lhs.overrides == rhs.overrides && lhs.unbound == rhs.unbound
    }

    // MARK: - Reading

    /// The chord bound to `id`, or nil when the command is unbound.
    public func chord(for id: ShortcutCommandID) -> ShortcutChord? {
        guard let command = XMindShortcutCatalog.command(id) else { return nil }
        return Self.chords(for: command, overrides: overrides, unbound: unbound).first
    }

    /// "⌘↩" or 未绑定, for the settings row and the help sheet.
    public func displayText(for id: ShortcutCommandID) -> String {
        chord(for: id)?.displayText ?? "未绑定"
    }

    public func isDefault(_ id: ShortcutCommandID) -> Bool {
        overrides[id] == nil && !unbound.contains(id)
    }

    public var isAllDefault: Bool {
        overrides.isEmpty && unbound.isEmpty
    }

    /// Every bound chord, one entry per chord, in catalog order.
    public func entries(mode: KeyboardMode? = nil) -> [XMindShortcutCatalog.Entry] {
        var entries: [XMindShortcutCatalog.Entry] = []
        for command in XMindShortcutCatalog.commands where mode == nil || command.mode == mode {
            for chord in Self.chords(for: command, overrides: overrides, unbound: unbound) {
                guard let key = chord.keyToken else { continue }
                entries.append(
                    XMindShortcutCatalog.Entry(
                        id: command.id,
                        title: command.title,
                        key: key,
                        modifiers: chord.keyModifiers,
                        command: command.command,
                        mode: command.mode,
                        registersMenuEquivalent: command.showsInMenu
                    )
                )
            }
        }
        return entries
    }

    /// Menu key equivalents: only chords that cannot be typed into a text field.
    public func menuEntries() -> [XMindShortcutCatalog.Entry] {
        entries().filter(\.showsInMenu)
    }

    public func menuEntry(for command: MindMapCommand) -> XMindShortcutCatalog.Entry? {
        menuEntries().first { $0.command == command }
    }

    /// The painter of the four menu-eligible chords for one toolbar command.
    public func menuEntry(forToolbar id: EditorToolbarCommandID) -> XMindShortcutCatalog.Entry? {
        switch id {
        case .outline: return menuEntry(for: .toggleOutline)
        case .immersive: return menuEntry(for: .toggleImmersive)
        case .find: return menuEntry(for: .find)
        default: return nil
        }
    }

    // MARK: - Writing

    /// Rebinds one command. A nil chord unbinds it. The other command that
    /// already holds this chord keeps it: `conflictingIDs(for:bindingTo:)` is
    /// the warning, and it is the caller's job to show it before applying.
    public mutating func bind(_ chord: ShortcutChord?, to id: ShortcutCommandID) {
        guard let command = XMindShortcutCatalog.command(id) else { return }
        overrides[id] = nil
        unbound.remove(id)
        guard let chord else {
            unbound.insert(id)
            lookup = Self.makeLookup(overrides: overrides, unbound: unbound)
            return
        }
        if chord != command.defaultChord {
            overrides[id] = chord
        }
        lookup = Self.makeLookup(overrides: overrides, unbound: unbound)
    }

    public mutating func reset(_ id: ShortcutCommandID) {
        overrides[id] = nil
        unbound.remove(id)
        lookup = Self.makeLookup(overrides: overrides, unbound: unbound)
    }

    public mutating func resetAll() {
        overrides.removeAll()
        unbound.removeAll()
        lookup = Self.makeLookup(overrides: overrides, unbound: unbound)
    }

    // MARK: - Resolution

    /// The chord a key press resolves to, honouring the current bindings.
    public func command(for event: KeyEvent) -> MindMapCommand? {
        guard !event.isComposing else { return nil }
        return lookup[LookupKey(mode: event.mode, chord: chord(for: event))]
    }

    public func chord(for event: KeyEvent) -> ShortcutChord {
        ShortcutChord(key: event.key, modifiers: event.modifiers)
    }

    // MARK: - Conflicts

    /// Other commands in `id`'s own mode that already answer to `chord`. These
    /// chords include the fixed alternates, so binding ⇧↩ in a text field warns
    /// about 框内换行 rather than silently swallowing the line break.
    public func conflictingIDs(for chord: ShortcutChord, bindingTo id: ShortcutCommandID) -> [ShortcutCommandID] {
        guard let subject = XMindShortcutCatalog.command(id) else { return [] }
        var ids: [ShortcutCommandID] = []
        for command in XMindShortcutCatalog.commands where command.id != id && command.mode == subject.mode {
            let chords = Self.chords(for: command, overrides: overrides, unbound: unbound)
            if chords.contains(chord), !ids.contains(command.id) {
                ids.append(command.id)
            }
        }
        return ids
    }

    /// Every chord held by more than one command inside one mode.
    public func conflicts() -> [ShortcutConflict] {
        var holders: [LookupKey: [ShortcutCommandID]] = [:]
        for command in XMindShortcutCatalog.commands {
            for chord in Self.chords(for: command, overrides: overrides, unbound: unbound) {
                let key = LookupKey(mode: command.mode, chord: chord)
                if !(holders[key]?.contains(command.id) ?? false) {
                    holders[key, default: []].append(command.id)
                }
            }
        }
        return holders
            .filter { $0.value.count > 1 }
            .map { key, ids in
                ShortcutConflict(
                    chord: key.chord,
                    mode: key.mode,
                    ids: ids,
                    titles: ids.map { XMindShortcutCatalog.command($0)?.title ?? $0.rawValue }
                )
            }
            .sorted { $0.chord.storageValue < $1.chord.storageValue }
    }

    // MARK: - Storage

    /// `<id>: "<modifier bits>:<key>"`. An empty string means 未绑定. Only rows
    /// the user changed are written, so a later change to a shipped default
    /// still reaches everyone who never touched that row.
    public var storage: [String: String] {
        var storage: [String: String] = [:]
        for (id, chord) in overrides {
            storage[id.rawValue] = chord.storageValue
        }
        for id in unbound {
            storage[id.rawValue] = ""
        }
        return storage
    }

    /// Missing key, empty dictionary, and garbage all fall back to the shipped
    /// table row by row: a fresh install, and a build that drops a command,
    /// both keep today's behaviour.
    public static func decode(_ storage: [String: String]?) -> ShortcutBindings {
        guard let storage, !storage.isEmpty else { return .catalogDefaults }
        var overrides: [ShortcutCommandID: ShortcutChord] = [:]
        var unbound: Set<ShortcutCommandID> = []
        for (rawID, rawChord) in storage {
            guard let id = ShortcutCommandID(rawValue: rawID),
                  let command = XMindShortcutCatalog.command(id) else { continue }
            if rawChord.isEmpty {
                unbound.insert(id)
                continue
            }
            guard let chord = ShortcutChord(storageValue: rawChord), chord != command.defaultChord else {
                continue
            }
            overrides[id] = chord
        }
        guard overrides != ShortcutBindings.catalogDefaults.overrides || !unbound.isEmpty else {
            return .catalogDefaults
        }
        return ShortcutBindings(overrides: overrides, unbound: unbound)
    }

    // MARK: - Private

    /// First row in catalog order wins a shared chord, matching the table the
    /// mapper used before the chords became editable.
    private static func makeLookup(
        overrides: [ShortcutCommandID: ShortcutChord],
        unbound: Set<ShortcutCommandID>
    ) -> [LookupKey: MindMapCommand] {
        var lookup: [LookupKey: MindMapCommand] = [:]
        for command in XMindShortcutCatalog.commands {
            for chord in chords(for: command, overrides: overrides, unbound: unbound) {
                let key = LookupKey(mode: command.mode, chord: chord)
                if lookup[key] == nil {
                    lookup[key] = command.command
                }
            }
        }
        return lookup
    }

    static func chords(
        for command: XMindShortcutCatalog.Command,
        overrides: [ShortcutCommandID: ShortcutChord],
        unbound: Set<ShortcutCommandID>
    ) -> [ShortcutChord] {
        if let override = overrides[command.id] {
            return [override] + command.alternateChords.filter { $0 != override }
        }
        if unbound.contains(command.id) { return [] }
        guard let main = command.defaultChord else { return [] }
        return [main] + command.alternateChords.filter { $0 != main }
    }

    struct LookupKey: Hashable {
        var mode: KeyboardMode
        var chord: ShortcutChord
    }
}

/// Two commands in one mode answering to the same chord. The settings page
/// shows this instead of quietly letting the later row win.
public struct ShortcutConflict: Equatable, Sendable, Identifiable {
    public var chord: XMindShortcutCatalog.ShortcutChord
    public var mode: KeyboardMode
    public var ids: [ShortcutCommandID]
    public var titles: [String]

    public init(
        chord: XMindShortcutCatalog.ShortcutChord,
        mode: KeyboardMode,
        ids: [ShortcutCommandID],
        titles: [String]
    ) {
        self.chord = chord
        self.mode = mode
        self.ids = ids
        self.titles = titles
    }

    public var id: String {
        "\(mode == .edit ? "edit" : "command")|\(chord.storageValue)"
    }

    public var modeTitle: String {
        mode == .edit ? "编辑态" : "命令态"
    }

    public var summary: String {
        "\(modeTitle) \(chord.displayText) 同时绑给 \(titles.joined(separator: "、"))"
    }
}

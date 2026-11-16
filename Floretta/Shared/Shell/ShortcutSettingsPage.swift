import FlorettaCore
import SwiftUI

/// 设置 ▸ 快捷键. One row per command in `XMindShortcutCatalog.commands`, each
/// showing the chord in force and letting the user change it.
///
/// The page reads and writes `AppSettings.shortcutBindings`; the keyboard
/// session, the menu bar, and the iPad key-command list all read the same value,
/// so a pick takes effect on the next key press. Both hosts render this page
/// as-is: the macOS Settings window puts it on its own tab, the iOS card stacks
/// it inside the form.
struct ShortcutSettingsPage: View {
    @Bindable var settings: AppSettings
    /// A pick that would share a chord with another command, held until the
    /// user confirms. Nothing is written before the warning is shown.
    @State private var pending: PendingBinding?

    private struct PendingBinding: Identifiable {
        var id: String { commandID.rawValue }
        var commandID: ShortcutCommandID
        var chord: XMindShortcutCatalog.ShortcutChord
        var conflicts: [ShortcutConflict]
    }

    var body: some View {
        Group {
            ForEach(ShortcutGroup.allCases) { group in
                let commands = XMindShortcutCatalog.commands(in: group)
                if !commands.isEmpty {
                    Section {
                        ForEach(commands) { command in
                            ShortcutSettingRow(
                                settings: settings,
                                command: command,
                                onPick: { chord in pick(chord, for: command) }
                            )
                        }
                    } header: {
                        Text(verbatim: group.title)
                    } footer: {
                        if group == .editing {
                            Text(verbatim: editFooter)
                        }
                    }
                }
            }
            if !settings.shortcutConflicts.isEmpty {
                Section {
                    ForEach(settings.shortcutConflicts) { conflict in
                        Label {
                            Text(verbatim: conflict.summary)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .accessibilityIdentifier("settings.shortcuts.conflict")
                    }
                    Text(verbatim: "同一个键绑给两条命令时，按键只执行列表里靠前的那条。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(verbatim: text("冲突"))
                }
            }
            Section {
                Button {
                    settings.resetShortcuts()
                } label: {
                    Text(verbatim: text("恢复默认快捷键"))
                }
                .disabled(settings.shortcutBindings.isAllDefault)
                .accessibilityIdentifier("settings.shortcuts.resetAll")
            }
        }
        .alert(
            text("快捷键冲突"),
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            presenting: pending
        ) { choice in
            Button(text("取消"), role: .cancel) { pending = nil }
            Button(text("仍然绑定")) {
                settings.bindShortcut(choice.chord, to: choice.commandID)
                pending = nil
            }
        } message: { choice in
            Text(verbatim: conflictMessage(choice))
        }
    }

    /// A clash is a warning, not a silent overwrite: the pick is held here and
    /// only written from the alert's confirm button.
    private func pick(_ chord: XMindShortcutCatalog.ShortcutChord?, for command: XMindShortcutCatalog.Command) {
        let conflicts = settings.previewShortcutConflicts(for: chord, bindingTo: command.id)
        guard let chord, !conflicts.isEmpty else {
            settings.bindShortcut(chord, to: command.id)
            return
        }
        pending = PendingBinding(commandID: command.id, chord: chord, conflicts: conflicts)
    }

    private func conflictMessage(_ choice: PendingBinding) -> String {
        let title = XMindShortcutCatalog.command(choice.commandID)?.title ?? choice.commandID.rawValue
        let others = choice.conflicts.flatMap(\.titles).joined(separator: "、")
        return "\(choice.chord.displayText) 已经绑给 \(others)。仍然把 \(title) 绑到同一个键吗？两条命令中只有先解析到的那条会执行。"
    }

    private var editFooter: String {
        "编辑主题时，↩ 结束编辑（不新建），再按一次 ↩ 新建同级；⇧↩ 和 ⌘↩ 在节点文字里换行。"
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }
}

/// One command row: title, scope, current chord, and a reset arrow once the row
/// differs from the shipped table.
private struct ShortcutSettingRow: View {
    @Bindable var settings: AppSettings
    var command: XMindShortcutCatalog.Command
    var onPick: (XMindShortcutCatalog.ShortcutChord?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: command.title)
                Text(verbatim: command.mode == .edit ? scopeEdit : scopeCommand)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if isConflicted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text(verbatim: "冲突"))
            }
            ShortcutChordMenu(
                chord: settings.shortcutBindings.chord(for: command.id),
                defaultChord: command.defaultChord,
                onPick: onPick
            )
            .accessibilityIdentifier("settings.shortcuts.\(command.id.rawValue)")
            Button {
                settings.shortcutBindings.reset(command.id)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(settings.shortcutBindings.isDefault(command.id))
            .accessibilityLabel(Text(verbatim: "恢复默认"))
            .accessibilityIdentifier("settings.shortcuts.reset.\(command.id.rawValue)")
        }
    }

    private var isConflicted: Bool {
        settings.shortcutConflicts.contains { $0.ids.contains(command.id) }
    }

    private var scopeEdit: String {
        FlorettaL10n.string("编辑态", language: settings.language)
    }

    private var scopeCommand: String {
        FlorettaL10n.string("命令态", language: settings.language)
    }
}

/// Chord editor. Two submenus instead of a key recorder: 修饰键 and 键位, plus
/// 未绑定. A recorder would need a live first responder on both platforms, and
/// this list is the whole vocabulary the mapper understands.
private struct ShortcutChordMenu: View {
    var chord: XMindShortcutCatalog.ShortcutChord?
    var defaultChord: XMindShortcutCatalog.ShortcutChord?
    var onPick: (XMindShortcutCatalog.ShortcutChord?) -> Void

    private static let modifierChoices: [(String, KeyModifiers)] = [
        ("无", []),
        ("⌘", .command),
        ("⇧⌘", [.shift, .command]),
        ("⌥", .option),
        ("⌥⇧", [.option, .shift]),
        ("⌃", .control),
        ("⌃⌘", [.control, .command]),
    ]

    private static let letters: [KeyToken] = "abcdefghijklmnopqrstuvwxyz".map { .character($0) }
    private static let digits: [KeyToken] = "0123456789".map { .character($0) }
    private static let specials: [KeyToken] = [.enter, .tab, .space, .escape, .delete, .backspace, .up, .down, .left, .right, .f2, .f5]
    private static let glyphs: [KeyToken] = [.character("+"), .character("-"), .character("*"), .character("/"), .character("."), .character(",")]

    var body: some View {
        Menu {
            Button {
                onPick(nil)
            } label: {
                Text(verbatim: "未绑定")
            }
            Divider()
            Menu {
                ForEach(Array(Self.modifierChoices.enumerated()), id: \.offset) { _, choice in
                    Button {
                        onPick(make(key: currentKey, modifiers: choice.1))
                    } label: {
                        Text(verbatim: choice.0)
                    }
                }
            } label: {
                Text(verbatim: "修饰键")
            }
            Menu {
                keyButtons(Self.letters)
            } label: {
                Text(verbatim: "字母")
            }
            Menu {
                keyButtons(Self.digits)
            } label: {
                Text(verbatim: "数字")
            }
            Menu {
                keyButtons(Self.specials)
            } label: {
                Text(verbatim: "特殊键")
            }
            Menu {
                keyButtons(Self.glyphs)
            } label: {
                Text(verbatim: "符号")
            }
            if let defaultChord {
                Divider()
                Button {
                    onPick(defaultChord)
                } label: {
                    Text(verbatim: "恢复默认 \(defaultChord.displayText)")
                }
            }
        } label: {
            Text(verbatim: chord?.displayText ?? "未绑定")
                .monospaced()
                .foregroundStyle(chord == nil ? .secondary : .primary)
        }
        .fixedSize()
    }

    @ViewBuilder
    private func keyButtons(_ keys: [KeyToken]) -> some View {
        ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
            Button {
                onPick(make(key: key, modifiers: currentModifiers))
            } label: {
                Text(verbatim: XMindShortcutCatalog.display(key, []))
            }
        }
    }

    private var currentKey: KeyToken {
        chord?.keyToken ?? defaultChord?.keyToken ?? .enter
    }

    private var currentModifiers: KeyModifiers {
        chord?.keyModifiers ?? defaultChord?.keyModifiers ?? []
    }

    private func make(key: KeyToken, modifiers: KeyModifiers) -> XMindShortcutCatalog.ShortcutChord {
        XMindShortcutCatalog.ShortcutChord(key: key, modifiers: modifiers)
    }
}

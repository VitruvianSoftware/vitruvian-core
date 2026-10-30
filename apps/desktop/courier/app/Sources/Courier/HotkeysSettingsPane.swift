// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Keycap badge (`component Key.tsx`) for rendering a single key or modifier symbol (e.g. `⌘`, `⇧`, `E`, `Tab`).
struct KeyView: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            )
    }
}

/// Renders one or more `KeyChord` values as sequences of `KeyView` keycaps separated by `"or"`.
struct ChordBadgesView: View {
    let chords: [KeyChord]
    var isDisabled: Bool = false

    var body: some View {
        if chords.isEmpty {
            Text(String(localized: "Not bound"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ForEach(Array(chords.enumerated()), id: \.offset) { index, chord in
                    if index > 0 {
                        Text(String(localized: "or"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 3) {
                        ForEach(Array(chord.keycapTokens.enumerated()), id: \.offset) { _, token in
                            KeyView(symbol: token)
                        }
                    }
                }
            }
            .opacity(isDisabled ? 0.45 : 1.0)
        }
    }
}

/// Settings ▸ Shortcuts pane (`component HotkeysPrefsSubView.tsx`, `command Hotkeys`):
/// search filter, `"Switch to Texts.app keybindings"` preset, `"Revert all"`, per-row enable toggle,
/// `"Global"` toggle on global-capable shortcuts, `"Record Shortcut"` pill button, and inline conflict message.
struct HotkeysSettingsPane: View {
    @ObservedObject var registry: HotkeyRegistry
    @ObservedObject var lifecycle: SystemLifecycleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(HotkeyRegistry.categories, id: \.self) { category in
                        let items = registry.filteredDefinitions.filter { $0.category == category }
                        if !items.isEmpty {
                            categorySection(title: category, items: items)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(
            ShortcutCaptureMonitor(
                isRecording: registry.recordingHotkeyID != nil && !lifecycle.isLocked,
                isLocked: lifecycle.isLocked,
                onCapture: { chord in
                    guard !lifecycle.isLocked, let id = registry.recordingHotkeyID else { return }
                    _ = registry.record(chord, for: id)
                },
                onCancel: {
                    registry.cancelRecording()
                }
            )
            .frame(width: 0, height: 0)
        )
        .onChange(of: lifecycle.isLocked) { _, locked in
            if locked {
                registry.cancelRecording()
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search hotkeys..."), text: $registry.searchQuery)
                    .textFieldStyle(.plain)
                if !registry.searchQuery.isEmpty {
                    Button {
                        registry.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            Spacer(minLength: 8)

            Button(String(localized: "Switch to Texts.app keybindings")) {
                registry.applyTextsAppPreset()
            }
            .controlSize(.small)
            .disabled(lifecycle.isLocked)

            Button(String(localized: "Revert all")) {
                registry.revertAll()
            }
            .controlSize(.small)
            .disabled(
                lifecycle.isLocked || (
                    registry.overrides.isEmpty &&
                    registry.disabledIDs.isEmpty &&
                    registry.globalIDs.isEmpty
                )
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func categorySection(title: String, items: [HotkeyDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, definition in
                    if index > 0 {
                        Divider()
                    }
                    HotkeyRowView(
                        definition: definition,
                        registry: registry,
                        isLocked: lifecycle.isLocked
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

private struct HotkeyRowView: View {
    let definition: HotkeyDefinition
    @ObservedObject var registry: HotkeyRegistry
    let isLocked: Bool

    private var isEnabled: Bool {
        registry.isEnabled(definition.id)
    }

    private var isRecording: Bool {
        registry.recordingHotkeyID == definition.id && !isLocked
    }

    private var hasCustomization: Bool {
        registry.overrides[definition.id] != nil
            || !registry.isEnabled(definition.id)
            || registry.globalIDs.contains(definition.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { isEnabled },
                        set: { registry.setEnabled($0, for: definition.id) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(isLocked)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(definition.title)
                            .font(.body)
                            .foregroundStyle(isEnabled ? .primary : .secondary)
                        if definition.supportsGlobal {
                            Toggle(
                                String(localized: "Global"),
                                isOn: Binding(
                                    get: { registry.globalIDs.contains(definition.id) },
                                    set: { registry.setGlobal($0, for: definition.id) }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(String(localized: "Works from any app on your Mac"))
                            .disabled(isLocked)
                        }
                    }
                }

                Spacer(minLength: 8)

                ChordBadgesView(
                    chords: registry.configuredChords(for: definition.id),
                    isDisabled: !isEnabled
                )

                if isRecording {
                    HStack(spacing: 6) {
                        Text(String(localized: "Press keys…"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.15))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                            )
                        Button(String(localized: "Cancel")) {
                            registry.cancelRecording()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    Button(String(localized: "Record Shortcut")) {
                        registry.beginRecording(for: definition.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLocked)
                }

                if hasCustomization {
                    Button {
                        registry.revert(id: definition.id)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Revert to default shortcut"))
                    .disabled(isLocked)
                }
            }

            if let conflict = registry.conflictErrors[definition.id] {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(conflict.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Captures key-down events while a shortcut row is in recording mode and the app is unlocked.
private struct ShortcutCaptureMonitor: NSViewRepresentable {
    let isRecording: Bool
    let isLocked: Bool
    let onCapture: (KeyChord) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.update(isRecording: isRecording && !isLocked)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.onCancel = onCancel
        context.coordinator.update(isRecording: isRecording && !isLocked)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        var onCapture: (KeyChord) -> Void
        var onCancel: () -> Void
        private var monitor: Any?

        init(onCapture: @escaping (KeyChord) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func update(isRecording: Bool) {
            if isRecording {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if event.keyCode == 53 && flags.isEmpty { // Escape cancels recording
                        self.onCancel()
                        return nil
                    }
                    if let chord = Self.chord(from: event) {
                        self.onCapture(chord)
                        return nil
                    }
                    return event
                }
            } else {
                stop()
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private static func chord(from event: NSEvent) -> KeyChord? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyName: String
            switch event.keyCode {
            case 36, 76: keyName = "enter"
            case 48: keyName = "tab"
            case 49: keyName = "space"
            case 51, 117: keyName = "backspace"
            case 53: keyName = "escape"
            case 123: keyName = "left"
            case 124: keyName = "right"
            case 125: keyName = "down"
            case 126: keyName = "up"
            default:
                guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
                    return nil
                }
                keyName = chars
            }
            return KeyChord(
                key: keyName,
                command: flags.contains(.command),
                shift: flags.contains(.shift),
                option: flags.contains(.option),
                control: flags.contains(.control)
            )
        }
    }
}

/// Applies the primary shortcut from `HotkeyRegistry` for `id` to a menu item or button.
struct RegistryKeyboardShortcutModifier: ViewModifier {
    let id: String
    @ObservedObject var registry: HotkeyRegistry
    var chordIndex: Int = 0

    func body(content: Content) -> some View {
        let active = registry.chords(for: id)
        if chordIndex < active.count,
           let shortcut = Self.keyboardShortcut(from: active[chordIndex]) {
            content.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            content
        }
    }

    static func keyboardShortcut(from chord: KeyChord) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        let keyEquivalent: KeyEquivalent
        switch chord.key.lowercased() {
        case "": return nil
        case "up", "uparrow": keyEquivalent = .upArrow
        case "down", "downarrow": keyEquivalent = .downArrow
        case "left", "leftarrow": keyEquivalent = .leftArrow
        case "right", "rightarrow": keyEquivalent = .rightArrow
        case "enter", "return": keyEquivalent = .return
        case "tab": keyEquivalent = .tab
        case "escape", "esc": keyEquivalent = .escape
        case "space", " ": keyEquivalent = .space
        case "backspace", "delete": keyEquivalent = .delete
        default:
            guard let char = chord.key.lowercased().first else { return nil }
            keyEquivalent = KeyEquivalent(char)
        }

        var modifiers: EventModifiers = []
        if chord.command { modifiers.insert(.command) }
        if chord.shift { modifiers.insert(.shift) }
        if chord.option { modifiers.insert(.option) }
        if chord.control { modifiers.insert(.control) }
        return (keyEquivalent, modifiers)
    }
}

extension View {
    func registryShortcut(_ id: String, in registry: HotkeyRegistry, chordIndex: Int = 0) -> some View {
        modifier(RegistryKeyboardShortcutModifier(id: id, registry: registry, chordIndex: chordIndex))
    }
}

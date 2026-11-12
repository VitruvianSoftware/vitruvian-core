// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The central editor for every global shortcut belonging to an installed
/// feature. It writes the same preferences as each feature page, so there is
/// still one setting and one registration path for every action.
package struct ShortcutsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var superKey = SuperKeyService.shared
    @ObservedObject private var router = SettingsRouter.shared
    /// Redraw when a tool registers, leaves, or is switched on or off. Each
    /// tool command's row watches its own shortcut.
    @ObservedObject private var registry = ToolRegistry.shared
    @AppStorage(Preferences.keyboardBrightnessShortcutsEnabled) private var keyboardBrightnessShortcutsEnabled: Bool
    /// Keyed by group too: brightness has a row in two groups, and each opens on its own.
    @State private var expandedFeatures: [FeatureGroup: Set<AppFeature>] = [.tools: [.screenshot]]
    @State private var showsAppShortcuts = false

    private var text: ShortcutSettingsStrings { FeatureStrings.shortcuts(l10n.language) }
    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }

    private var availableRoles: [GlobalShortcutRole] {
        GlobalShortcutRole.availableRoles(isAvailable: { $0.isAvailable }).filter {
            !$0.isKeyboardBrightness || BrightnessService.keyboardLightIsSupported
        }
    }

    private var captureRoles: [GlobalShortcutRole] {
        GlobalShortcutRole.captureRoles(in: availableRoles)
    }

    private var visibleGroups: [FeatureGroup] {
        FeatureGroup.allCases.filter { group in
            availableRoles.contains { $0.group == group }
                || (group == .windowsDock && AppFeature.windowLayout.isAvailable)
        }
    }

    package var body: some View {
        Form {
            Section {
                Text(l10n.s.shortcutsPageCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(visibleGroups, id: \.self) { group in
                Section(groupTitle(group)) {
                    ForEach(featuresWithShortcuts(in: group), id: \.self) { feature in
                        if feature == .screenshot {
                            captureGroupRows
                        } else {
                            featureRows(feature, in: group)
                        }
                    }
                }
            }

            // Tools outside the app's own lists, each under its own name.
            // With none asking for a shortcut the list is empty, and an
            // empty `ForEach` puts nothing on the page.
            ForEach(ToolCommandShortcutSection.all(registry: registry, language: l10n.language)) { section in
                Section(section.name) {
                    ForEach(section.commands, id: \.id) { command in
                        ToolCommandShortcutRow(command: command)
                    }
                }
            }

            if AppFeature.commandBar.isAvailable {
                Section {
                    Button {
                        showsAppShortcuts = true
                    } label: {
                        Label(FeatureStrings.commandBar(l10n.language).appCenterTitle,
                              systemImage: "app.badge")
                    }
                    Text(FeatureStrings.commandBar(l10n.language).appCenterCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { revealKeyboardBrightnessShortcuts() }
        .onChange(of: router.requestID) { _, _ in revealKeyboardBrightnessShortcuts() }
        .sheet(isPresented: $showsAppShortcuts) {
            CommandBarAppShortcutsView()
        }
    }

    private func featuresWithShortcuts(in group: FeatureGroup) -> [AppFeature] {
        AppFeature.allCases.filter { feature in
            // The screenshot slot anchors the combined capture group; the
            // other capture tools render inside it instead of on their own.
            if feature == .screenshot { return group == .tools && !captureRoles.isEmpty }
            if GlobalShortcutRole.captureFeatures.contains(feature) { return false }
            if feature == .windowLayout {
                return group == .windowsDock && feature.isAvailable
            }
            return availableRoles.contains { $0.feature == feature && $0.group == group }
        }
    }

    /// One group for every capture tool's shortcut. Rows keep each tool's own
    /// icon; the group carries the shared page's name and symbol.
    @ViewBuilder
    private var captureGroupRows: some View {
        let roles = captureRoles
        disclosureHeader(
            title: FeatureStrings.screenshot(l10n.language).screenCaptureTitle,
            symbolName: AppFeature.screenshot.symbolName,
            isActive: featureHasActiveShortcut(.screenshot, roles: roles),
            count: roles.count,
            isExpanded: expansionBinding(for: .screenshot, in: .tools))
        if expandedFeatures[.tools, default: []].contains(.screenshot) {
            ForEach(roles) { role in
                roleRow(role, showsFeatureContext: false)
                    .disclosureIndent()
            }
        }
    }

    @ViewBuilder
    private func featureRows(_ feature: AppFeature, in group: FeatureGroup) -> some View {
        let roles = availableRoles.filter { $0.feature == feature && $0.group == group }
        switch ShortcutsPageRows(feature: feature, roles: roles) {
        case .radialMenuWheels:
            RadialMenuShortcutsRow(text: text)
        case let .group(count):
            featureHeader(feature, roles: roles, count: count, in: group)
            if expandedFeatures[group, default: []].contains(feature) {
                if feature == .windowLayout {
                    ForEach(WindowLayoutAction.shortcutActions) { action in
                        CentralWindowLayoutShortcutRow(
                            action: action,
                            shortcutsEnabled: UserDefaults.standard[Preferences.windowLayoutShortcutsEnabled],
                            showsSuperKeyAlternative: superKey.isRunning,
                            superKeyModifiers: superKey.modifiers,
                            text: text
                        )
                        .disclosureIndent()
                    }
                    ForEach(roles) { role in
                        roleRow(role, showsFeatureContext: false, reservesClearButtonSpace: true)
                            .disclosureIndent()
                    }
                } else {
                    if feature == .brightness, roles.allSatisfy(\.isKeyboardBrightness) {
                        KeyboardBrightnessShortcutToggle(isEnabled: $keyboardBrightnessShortcutsEnabled)
                            .disclosureIndent()
                    }
                    if feature == .brightness, !roles.contains(where: \.isKeyboardBrightness) {
                        DisplayBrightnessShortcutControls(showsShortcutRows: false)
                            .disclosureIndent()
                    }
                    ForEach(roles) { role in
                        roleRow(role, showsFeatureContext: false)
                            .disclosureIndent()
                    }
                }
            }
        case let .single(role):
            roleRow(role)
        case .nothing:
            EmptyView()
        }
    }

    @ViewBuilder
    private func featureHeader(_ feature: AppFeature, roles: [GlobalShortcutRole],
                               count: Int, in group: FeatureGroup) -> some View {
        let header = disclosureHeader(
            title: featureTitle(feature, roles: roles),
            symbolName: featureSymbol(feature, roles: roles),
            isActive: featureHasActiveShortcut(feature, roles: roles),
            count: count,
            isExpanded: expansionBinding(for: feature, in: group))
        if feature == .brightness, roles.allSatisfy(\.isKeyboardBrightness) {
            header.settingsSectionAnchor(.keyboardBrightnessShortcuts)
        } else {
            header
        }
    }

    private func revealKeyboardBrightnessShortcuts() {
        guard router.destination == FeatureSettingsDestination(
            .shortcuts, sectionAnchor: .keyboardBrightnessShortcuts) else { return }
        expandedFeatures[.mouseKeyboard, default: []].insert(.brightness)
    }

    private func featureTitle(_ feature: AppFeature, roles: [GlobalShortcutRole]) -> String {
        if !roles.isEmpty, roles.allSatisfy(\.isKeyboardBrightness) {
            return FeatureStrings.brightness(l10n.language).keyboardLight
        }
        return feature.hubTitle(l10n.s, hub: hub)
    }

    private func featureSymbol(_ feature: AppFeature, roles: [GlobalShortcutRole]) -> String {
        !roles.isEmpty && roles.allSatisfy(\.isKeyboardBrightness)
            ? "keyboard" : feature.symbolName
    }

    private func disclosureHeader(title: String,
                                  symbolName: String,
                                  isActive: Bool,
                                  count: Int,
                                  isExpanded: Binding<Bool>) -> some View {
        DisclosureHeaderRow(isExpanded: isExpanded) {
            ShortcutRowLabel(
                title: title,
                symbolName: symbolName,
                contextLabel: nil,
                statusText: isActive ? text.active : text.inactive,
                statusIsActive: isActive
            )
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }

    private func roleRow(_ role: GlobalShortcutRole,
                         showsFeatureContext: Bool = true,
                         reservesClearButtonSpace: Bool = false) -> some View {
        let title = role.title(l10n.s)
        let featureTitle = role.feature.hubTitle(l10n.s, hub: hub)
        let active = role.requiredEnableKeys.allSatisfy {
            UserDefaults.standard.bool(forKey: $0)
        }
        return ShortcutPreferenceRow(
            role: role,
            isEnabled: !role.isKeyboardBrightness || keyboardBrightnessShortcutsEnabled,
            label: title,
            symbolName: role.isKeyboardBrightness ? "keyboard" : role.feature.symbolName,
            contextLabel: showsFeatureContext && title != featureTitle ? featureTitle : nil,
            statusText: active ? text.active : text.inactive,
            statusIsActive: active,
            showsSuperKeyAlternative: superKey.isRunning,
            superKeyModifiers: superKey.modifiers,
            includeInactiveConflicts: true,
            reservesClearButtonSpace: reservesClearButtonSpace,
            additionalConflict: { shortcut in
                guard AppFeature.windowLayout.isAvailable else { return nil }
                return WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: nil)
            },
            onChange: {
                FeatureRuntime.shared.sync(role.availabilityFeatures)
            }
        )
    }

    private func expansionBinding(for feature: AppFeature, in group: FeatureGroup) -> Binding<Bool> {
        Self.expansionBinding(for: feature, in: group, expanded: $expandedFeatures)
    }

    /// Whether `feature`'s row is open in `group`. Each group keeps its own
    /// set, so a feature listed in two groups opens and closes in each on its
    /// own. The page passes its state; the tests pass a plain binding
    /// (REFACTOR.md step 4b).
    package static func expansionBinding(for feature: AppFeature, in group: FeatureGroup,
                                         expanded expandedFeatures: Binding<[FeatureGroup: Set<AppFeature>]>) -> Binding<Bool> {
        Binding {
            expandedFeatures.wrappedValue[group, default: []].contains(feature)
        } set: { expanded in
            if expanded {
                expandedFeatures.wrappedValue[group, default: []].insert(feature)
            } else {
                expandedFeatures.wrappedValue[group, default: []].remove(feature)
            }
        }
    }

    private func featureHasActiveShortcut(_ feature: AppFeature,
                                          roles: [GlobalShortcutRole]) -> Bool {
        if feature == .windowLayout,
           UserDefaults.standard[Preferences.windowLayoutShortcutsEnabled],
           WindowLayoutAction.shortcutActions.contains(where: { $0.savedShortcut != nil }) {
            return true
        }
        return roles.contains { role in
            role.requiredEnableKeys.allSatisfy { UserDefaults.standard.bool(forKey: $0) }
        }
    }

    private func groupTitle(_ group: FeatureGroup) -> String {
        switch group {
        case .windowsDock: return hub.groupWindowsDock
        case .mouseKeyboard: return hub.groupMouseKeyboard
        case .clipboardFiles: return hub.groupClipboardFiles
        case .sound: return hub.groupSound
        case .energyDisplay: return hub.groupEnergyDisplay
        case .tools: return hub.groupTools
        case .dynamicIsland: return FeatureStrings.notch(l10n.language).title
        case .monitor: return hub.groupMonitor
        }
    }
}

private struct KeyboardBrightnessShortcutToggle: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(FeatureStrings.brightness(l10n.language).keyboardBrightnessShortcuts,
               isOn: $isEnabled)
            .onChange(of: isEnabled) { _, _ in
                brightness.syncWithPreferences()
            }
        if isEnabled, brightness.keyboardBrightnessShortcutRegistrationFailed {
            Text(l10n.s.shortcutUnavailable)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

/// What one feature puts on the Keyboard Shortcuts page.
package enum ShortcutsPageRows: Equatable {
    /// The radial menu's wheels, listed with a link to their page
    /// (`RadialMenuShortcutsSummary`), never a recorder for its role key.
    case radialMenuWheels
    /// A disclosure header over this many rows.
    case group(count: Int)
    /// One recorder row.
    case single(GlobalShortcutRole)
    case nothing

    /// Window layout counts its layout actions among its rows.
    package init(feature: AppFeature, roles: [GlobalShortcutRole]) {
        let count = feature == .windowLayout
            ? WindowLayoutAction.shortcutActions.count + roles.count
            : roles.count
        if feature == .radialMenu {
            self = .radialMenuWheels
        } else if count > 1 {
            self = .group(count: count)
        } else if let role = roles.first {
            self = .single(role)
        } else {
            self = .nothing
        }
    }
}

/// What the Keyboard Shortcuts page shows for the radial menu. Each wheel
/// answers to the shortcut saved in its own profile, and the radial menu's
/// role key only seeds the first wheel until one is saved. A recorder for that
/// key would then show a combination no wheel uses and change nothing, so the
/// row lists what the wheels answer to and leaves the change to the Radial
/// menu page.
package struct RadialMenuShortcutsSummary: Equatable {
    /// What the wheels answer to.
    package let shortcuts: [GlobalShortcut]
    package let isActive: Bool
    /// Where the row's button goes: the page that owns the wheels.
    package let manageDestination: FeatureSettingsDestination

    package init(defaults: UserDefaults = .standard) {
        let role = GlobalShortcutRole.radialMenu
        shortcuts = RadialMenuSupport.profileShortcuts(defaults: defaults)
        isActive = !shortcuts.isEmpty
            && role.requiredEnableKeys.allSatisfy { defaults.bool(forKey: $0) }
        manageDestination = role.feature.settingsDestination
    }
}

private struct RadialMenuShortcutsRow: View {
    @ObservedObject private var l10n = L10n.shared
    let text: ShortcutSettingsStrings

    var body: some View {
        let role = GlobalShortcutRole.radialMenu
        let summary = RadialMenuShortcutsSummary()
        HStack(alignment: .top, spacing: 8) {
            ShortcutRowLabel(title: role.title(l10n.s),
                             symbolName: role.feature.symbolName,
                             contextLabel: nil,
                             statusText: summary.isActive ? text.active : text.inactive,
                             statusIsActive: summary.isActive)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.shortcuts.isEmpty
                     ? l10n.s.shortcutNone
                     : summary.shortcuts.map(\.displayString).joined(separator: "\n"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                Button(FeatureStrings.radialMenu(l10n.language).manageButton) {
                    SettingsRouter.shared.request(summary.manageDestination,
                                                  sidebarFeature: role.feature)
                }
            }
        }
    }
}

private struct CentralWindowLayoutShortcutRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var superKey = SuperKeyService.shared
    let action: WindowLayoutAction
    let shortcutsEnabled: Bool
    let showsSuperKeyAlternative: Bool
    let superKeyModifiers: GlobalShortcutModifiers
    let text: ShortcutSettingsStrings
    @AppStorage private var rawValue: String
    @State private var errorText: String?
    @State private var isRecording = false
    @State private var pendingTakeOver: GlobalShortcut?

    init(action: WindowLayoutAction,
         shortcutsEnabled: Bool,
         showsSuperKeyAlternative: Bool,
         superKeyModifiers: GlobalShortcutModifiers,
         text: ShortcutSettingsStrings) {
        self.action = action
        self.shortcutsEnabled = shortcutsEnabled
        self.showsSuperKeyAlternative = showsSuperKeyAlternative
        self.superKeyModifiers = superKeyModifiers
        self.text = text
        _rawValue = AppStorage(
            wrappedValue: action.defaultShortcut?.storageValue
                ?? WindowLayoutAction.clearedShortcutStorageValue,
            action.shortcutKey
        )
    }

    private var windowText: WindowLayoutFeatureStrings {
        FeatureStrings.windowLayout(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                ShortcutRowLabel(
                    title: action.title(windowText),
                    symbolName: AppFeature.windowLayout.symbolName,
                    contextLabel: nil,
                    statusText: isActive ? text.active : text.inactive,
                    statusIsActive: isActive
                )
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        ShortcutRecorderButton(
                            shortcut: pendingTakeOver ?? shortcut ?? action.defaultShortcut ?? .windowLayoutLeftDefault,
                            isEnabled: true,
                            waitingTitle: l10n.s.shortcutPressKeys,
                            emptyTitle: pendingTakeOver == nil && shortcut == nil ? l10n.s.shortcutNone : nil,
                            clearAction: clear,
                            notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
                            recordingChanged: { recording in
                                isRecording = recording
                                if recording {
                                    errorText = nil
                                    pendingTakeOver = nil
                                }
                            },
                            invalidAction: { errorText = l10n.s.shortcutInvalid },
                            captureAction: save
                        )
                        .frame(width: 108)
                        Button {
                            clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(shortcut == nil)
                        .help(l10n.s.shortcutClear)
                        .accessibilityLabel(l10n.s.shortcutClear)
                        Button(l10n.s.shortcutReset) {
                            if let refusal = refusal(for: action.defaultShortcut) {
                                errorText = refusal
                                pendingTakeOver = nil
                                return
                            }
                            rawValue = action.defaultShortcut?.storageValue
                                ?? WindowLayoutAction.clearedShortcutStorageValue
                            errorText = nil
                            pendingTakeOver = nil
                            SystemShortcutTakeover.setTakeOver(action.shortcutKey, false)
                            WindowLayoutService.shared.syncWithPreferences()
                        }
                        .disabled(shortcut == action.defaultShortcut)
                    }
                    if let alternative = superKeyAlternative {
                        Text(String(format: text.superKeyAlternativeFormat, alternative))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(alternative)
                    }
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isRecording {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: true))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let pendingTakeOver {
                SystemShortcutTakeOverOffer(
                    shortcut: pendingTakeOver,
                    onAccept: {
                        // The offer may have waited while another row took
                        // the combination.
                        if let refusal = refusal(for: pendingTakeOver) {
                            errorText = refusal
                            self.pendingTakeOver = nil
                            return
                        }
                        rawValue = pendingTakeOver.storageValue
                        SystemShortcutTakeover.setTakeOver(action.shortcutKey, true)
                        self.pendingTakeOver = nil
                        WindowLayoutService.shared.syncWithPreferences()
                    },
                    onDismiss: {
                        self.pendingTakeOver = nil
                        errorText = String(format: l10n.s.shortcutConflictFormat, "macOS")
                    }
                )
            }
        }
        .onChange(of: l10n.language) { _, _ in errorText = nil }
    }

    private var shortcut: GlobalShortcut? {
        WindowLayoutAction.resolvedShortcut(storedValue: rawValue,
                                            defaultShortcut: action.defaultShortcut)
    }

    private var isActive: Bool {
        shortcutsEnabled && shortcut != nil
    }

    private var superKeyAlternative: String? {
        guard showsSuperKeyAlternative, let shortcut else { return nil }
        return shortcut.superKeyAlternative(
            sourceLabel: FeatureStrings.superKey(l10n.language).sourceLabel(superKey.source),
            superKeyModifiers: superKeyModifiers)
    }

    private func clear() {
        rawValue = WindowLayoutAction.clearedShortcutStorageValue
        errorText = nil
        pendingTakeOver = nil
        SystemShortcutTakeover.setTakeOver(action.shortcutKey, false)
        WindowLayoutService.shared.syncWithPreferences()
    }

    /// The message when somebody else holds `shortcut`, or nil when it is
    /// free (or there is none). Recording, Reset and accepting a take-over
    /// all ask it.
    private func refusal(for shortcut: GlobalShortcut?) -> String? {
        guard case .refuse(let holder) = ShortcutConflicts.write(shortcut, holders: [
            { GlobalShortcutRole.conflict(for: $0, excluding: nil, includeInactive: true)?.title(l10n.s) },
            { WindowLayoutService.shared.shortcutConflictTitle($0, excluding: action) },
            { ShortcutConflicts.title(for: $0) },
        ]) else { return nil }
        return String(format: l10n.s.shortcutConflictFormat, holder)
    }

    private func save(_ shortcut: GlobalShortcut) {
        if let refusal = refusal(for: shortcut) {
            errorText = refusal
            return
        }
        // The offer is the last word on a combination: every other check has
        // already passed, so accepting it writes exactly what a save writes.
        switch SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: shortcut,
            conflictsWithMacOS: SystemShortcutTakeover.conflictsWithMacOS(shortcut),
            takenOver: SystemShortcutTakeover.isTakenOver(action.shortcutKey),
            current: GlobalShortcut(storageValue: rawValue)) {
        case .offer:
            pendingTakeOver = shortcut
            errorText = nil
            return
        case .save(let clearTakeOver):
            rawValue = shortcut.storageValue
            errorText = nil
            if clearTakeOver { SystemShortcutTakeover.setTakeOver(action.shortcutKey, false) }
        }
        WindowLayoutService.shared.syncWithPreferences()
    }
}

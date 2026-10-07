// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

package protocol PanelOrderItem: RawRepresentable, CaseIterable, Hashable where RawValue == String {}

/// The major, user-customizable sections of the menu panel. Raw values are the
/// stable identifiers persisted in the saved order and the collapsed set, so
/// renaming a case would orphan a user's stored layout — keep them stable.
package enum PanelSectionID: String, CaseIterable, Identifiable, Hashable {
    case keepAwake, brightness, mixer, system, network, disk, power, fanControl, utilities, controls,
         toggles, wallpaper

    package var id: String { rawValue }

    /// Localized display name, reused from the existing section titles.
    package func title(_ s: Strings) -> String {
        switch self {
        case .keepAwake: return s.keepAwakeTitle
        case .brightness: return FeatureStrings.brightness(L10n.shared.language).pageTitle
        case .mixer: return s.mixerSection
        case .system: return s.systemSection
        case .network: return s.networkSection
        case .disk: return s.diskSection
        case .power: return s.powerSection
        case .fanControl: return FeatureStrings.fanControl(L10n.shared.language).title
        case .utilities: return s.utilitiesSection
        case .controls: return s.quickControlsSection
        case .toggles: return FeatureStrings.quickToggles(L10n.shared.language).pageTitle
        case .wallpaper: return FeatureStrings.wallpaper(L10n.shared.language).pageTitle
        }
    }

    package var symbolName: String {
        switch self {
        case .keepAwake: return "moon.zzz.fill"
        case .brightness: return "display.2"
        case .mixer: return "speaker.wave.2"
        case .system: return "cpu"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        case .fanControl: return "fanblades.fill"
        case .utilities: return "wrench.and.screwdriver.fill"
        case .controls: return "switch.2"
        case .toggles: return "togglepower"
        case .wallpaper: return "photo.on.rectangle"
        }
    }

    /// The UserDefaults key that controls whether this section shows in the panel.
    /// The monitoring blocks reuse their existing `monitorShow*` keys; the rest
    /// get a dedicated `panelShow*` key so every section is hideable.
    package var visibilityKey: String {
        switch self {
        case .keepAwake: return DefaultsKey.panelShowKeepAwake
        case .brightness: return DefaultsKey.panelShowBrightness
        case .mixer: return DefaultsKey.monitorShowMixer
        case .system: return DefaultsKey.monitorShowSystem
        case .network: return DefaultsKey.monitorShowNetwork
        case .disk: return DefaultsKey.monitorShowDisk
        case .power: return DefaultsKey.monitorShowPower
        case .fanControl: return DefaultsKey.panelShowFanControl
        case .utilities: return DefaultsKey.panelShowUtilities
        case .controls: return DefaultsKey.panelShowControls
        case .toggles: return DefaultsKey.panelShowToggles
        case .wallpaper: return DefaultsKey.panelShowWallpaper
        }
    }

    /// Installed sections show by default and remain individually hideable.
    package var shownByDefault: Bool { true }

    /// Hub features that keep this section alive: with all of them off, the
    /// section leaves the panel, the section navigation and the layout
    /// editors, regardless of its visibility key (which is preserved for the
    /// feature's return).
    package var featureGate: [AppFeature] {
        switch self {
        case .keepAwake: return [.keepAwake]
        case .brightness: return [.brightness]
        case .mixer: return [.mixer, .audioPriority]
        case .system: return [.monitorCPU, .monitorGPU, .monitorMemory]
        case .network: return [.monitorNetwork]
        case .disk: return [.monitorDisk]
        case .power: return [.monitorPower]
        case .fanControl: return [.fanControl]
        case .utilities: return [.quickLauncher, .cleaner, .homebrew, .appUpdates, .mediaTools,
                                 .clipboardHistory,
                                 .windowLayout, .uninstaller, .urlCleaner, .cleaningMode, .screenOCR,
                                 .colorPicker, .screenshot, .screenRecorder,
                                 .cameraPreview, .scratchpad, .commandBar, .portManager, .nexusAgent]
        case .controls: return [.scrollInverter, .linearScroll, .focusFollowsMouse, .mouseAcceleration, .mouseNavigation, .mouseButtonShortcuts, .switcher,
                                .finderCutPaste, .autoQuit,
                                .shelf, .windowMaximizer, .dockPreview, .keyboardDebounce, .dockClick, .spacesOrder,
                                .middleClick, .textSnippets, .superKey, .radialMenu, .mouseClickDebounce, .notch]
        case .toggles: return [.quickToggles, .micMute]
        case .wallpaper: return [.wallpaper]
        }
    }

    package var isAvailable: Bool { featureGate.contains(where: \.isAvailable) }
}

/// Persisted panel layout: the order the sections appear in and which ones are
/// collapsed. The order is a comma-joined list of ids; any section missing from
/// a saved order (e.g. one added in a later version) is appended in its canonical
/// position, so a section can never silently disappear. Collapsed sections are a
/// comma-joined set of ids.
package enum PanelLayout {
    private static var defaults: UserDefaults { .standard }

    /// The sections in display order: the user's saved order first, then any not
    /// yet listed, in their canonical order.
    package static var order: [PanelSectionID] {
        let saved = (defaults.string(forKey: DefaultsKey.panelSectionOrder) ?? "")
            .split(separator: ",")
            .compactMap { PanelSectionID(rawValue: String($0)) }
        var seen = Set<PanelSectionID>()
        var result: [PanelSectionID] = []
        for id in saved where seen.insert(id).inserted { result.append(id) }
        for id in PanelSectionID.allCases where seen.insert(id).inserted {
            if id == .disk, let networkIndex = result.firstIndex(of: .network) {
                result.insert(id, at: networkIndex + 1)
            } else if id == .controls, let utilitiesIndex = result.firstIndex(of: .utilities) {
                result.insert(id, at: utilitiesIndex + 1)
            } else if id == .brightness, let keepAwakeIndex = result.firstIndex(of: .keepAwake) {
                // New in 3.1.13: saved orders predate it, so it slots in at
                // its canonical place instead of the end.
                result.insert(id, at: keepAwakeIndex + 1)
            } else {
                result.append(id)
            }
        }
        return result
    }

    package static func setOrder(_ ids: [PanelSectionID]) {
        defaults.set(ids.map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.panelSectionOrder)
    }

    package static func itemOrder<Item: PanelOrderItem>(_ type: Item.Type, key: String) -> [Item] {
        let defaultOrder = type.allCases.map(\.rawValue)
        let raw = defaults.string(forKey: key) ?? ""
        return Defaults.sanitizedPanelItemOrder(raw, defaultOrder: defaultOrder).compactMap(Item.init(rawValue:))
    }

    package static func setItemOrder<Item: PanelOrderItem>(_ ids: [Item], key: String) {
        defaults.set(ids.map(\.rawValue).joined(separator: ","), forKey: key)
    }

    package static func resetItemOrder(key: String) {
        defaults.removeObject(forKey: key)
    }

    package static func isShown(_ id: PanelSectionID) -> Bool {
        defaults.object(forKey: id.visibilityKey) as? Bool ?? id.shownByDefault
    }

    package static func setShown(_ shown: Bool, for id: PanelSectionID) {
        defaults.set(shown, forKey: id.visibilityKey)
    }

    /// Whether the section earns a tab in the panel right now: installed and
    /// shown, and for brightness also switched on, since that tab is enabled
    /// from Settings rather than from an empty panel screen. The one rule the
    /// live panel and its preview in Settings both read.
    package static func isVisibleInPanel(_ id: PanelSectionID) -> Bool {
        guard id.isAvailable, isShown(id) else { return false }
        return id != .brightness || defaults[Preferences.brightnessControlEnabled]
    }

    package static func isCollapsed(_ id: PanelSectionID) -> Bool {
        collapsedSet().contains(id.rawValue)
    }

    package static func setCollapsed(_ collapsed: Bool, for id: PanelSectionID) {
        var set = collapsedSet()
        if collapsed { set.insert(id.rawValue) } else { set.remove(id.rawValue) }
        defaults.set(set.sorted().joined(separator: ","), forKey: DefaultsKey.panelCollapsedSections)
    }

    package static func resetCollapsedSectionsOnce(for version: String) {
        guard defaults.string(forKey: DefaultsKey.panelCollapsedResetVersion) != version else { return }
        defaults.removeObject(forKey: DefaultsKey.panelCollapsedSections)
        defaults.set(version, forKey: DefaultsKey.panelCollapsedResetVersion)
    }

    private static func collapsedSet() -> Set<String> {
        Set((defaults.string(forKey: DefaultsKey.panelCollapsedSections) ?? "")
            .split(separator: ",").map(String.init))
    }
}

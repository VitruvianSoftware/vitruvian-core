// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import UniformTypeIdentifiers
import VitruvianAtriumCore
import VitruvianAtriumDesign

/// Settings backup: writes the exportable preferences to a plist and brings
/// one back in. Importing replaces the current preferences and relaunches, so
/// every service, panel and status item comes back from a clean state instead
/// of chasing 25 live re-syncs.
package enum SettingsBackup {
    /// Shows the save panel and writes the file. nil = user cancelled.
    @MainActor
    @discardableResult
    package static func runExportPanel() -> Bool? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Vitruvian Atrium Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        ScratchpadService.shared.prepareForSettingsBackup()
        return write(to: url)
    }

    /// Writes the backup file; false when it could not be saved.
    package static func write(to url: URL, from defaults: UserDefaults = .standard) -> Bool {
        // object(forKey:) sees through to registered defaults, so the file is
        // a complete snapshot: importing it reproduces this exact setup even
        // where the user never touched a control.
        let payload = SettingsBackupSupport.payload(appVersion: AppInfo.version) {
            defaults.object(forKey: $0)
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: payload,
                                                          format: .xml,
                                                          options: 0)
            let manager = FileManager.default
            let target = url.resolvingSymlinksInPath()
            // attributesOfItem sees a dangling link, too. Never replace the link
            // itself, a read-only Nix target, or a non-regular destination.
            let exists: Bool
            do {
                _ = try manager.attributesOfItem(atPath: url.path)
                exists = true
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                exists = false
            }
            if exists {
                let attributes = try manager.attributesOfItem(atPath: target.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      manager.isWritableFile(atPath: target.path) else { return false }
            }
            let directory = target.deletingLastPathComponent()
            try manager.createDirectory(at: directory,
                                        withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // mkstemp creates a 0600 file on the destination volume before any
            // snippet bytes are written, including in a shared dotfiles folder.
            var template = Array(directory.appendingPathComponent(".vitruvian-XXXXXX").path.utf8CString)
            let descriptor = mkstemp(&template)
            guard descriptor >= 0 else { return false }
            let staged = URL(fileURLWithPath: String(cString: template))
            defer { try? manager.removeItem(at: staged) }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try file.write(contentsOf: data)
            try file.close()
            if exists {
                _ = try manager.replaceItemAt(target, withItemAt: staged)
            } else {
                try MediaSupport.installStagedOutput(staged, at: target, replacingExisting: false)
            }
            return true
        } catch {
            return false
        }
    }

    /// Shows the open panel; nil = user cancelled.
    @MainActor
    package static func runImportPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList, .xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Reads and validates a backup; nil when the file is not one of ours.
    package static func readSettings(at url: URL) -> [String: Any]? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        func read(_ item: URL) -> Data? {
            let target = item.resolvingSymlinksInPath()
            guard (try? target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return try? Data(contentsOf: target)
        }
        var coordinatedData: Data?
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { readURL in
            coordinatedData = read(readURL)
        }
        guard let data = coordinatedData ?? read(url),
              let payload = try? PropertyListSerialization.propertyList(from: data,
                                                                        options: [],
                                                                        format: nil) as? [String: Any]
        else { return nil }
        return SettingsBackupSupport.sanitizedSettings(from: payload)
    }

    /// Clears the exportable keys (unset ones fall back to their registered
    /// defaults), writes the file's values and relaunches.
    @MainActor package static func applyAndRelaunch(settings: [String: Any]) {
        ScratchpadService.shared.prepareForSettingsRestore()
        restore(settings, into: .standard)
        FeatureRuntime.shared.relaunchApp()
    }

    /// Writes the file's values into `defaults`. A backup (`replacingMissing`)
    /// first clears the exportable keys; a declarative settings file only
    /// changes the keys it supplies. Either way it keeps what a backup never
    /// carries: this Mac's recorder preset images, watermark and exception
    /// list paths are read before the clear and put back after the file's
    /// values.
    @MainActor package static func restore(_ settings: [String: Any], into defaults: UserDefaults,
                                           replacingMissing: Bool = true) {
        let localRecorderPresets = defaults[Preferences.recorderEditorPresets]
        let localWatermark = defaults[Preferences.screenshotWatermarkStyle]
        let localWatermarkPresets = defaults[Preferences.screenshotWatermarkPresets]
        // A backup carries only the portable half of an exception list: the
        // path of a program that is not an app is authority on one Mac and is
        // filtered out on export (issue #1009). The clear below covers every
        // exported key, so without carrying that half across by hand, applying
        // a backup would delete those entries outright -- including on the Mac
        // the file was written on, where nothing about them was ever wrong.
        // The thumbnail pause lists take such paths too (issue #3033).
        let carried = (MouseExceptionScope.allCases.map(\.defaultsKey)
                       + SettingsBackupSupport.thumbnailPauseListKeys)
            .reduce(into: [String: [String]]()) { out, key in
                out[key] = SettingsBackupSupport.pathIdentities(in: defaults.stringArray(forKey: key) ?? [])
            }
        let windowLayoutPaths = SettingsBackupSupport.pathIdentities(
            in: defaults[Preferences.windowLayoutIgnoredApps])
        if replacingMissing {
            for key in SettingsBackupSupport.keysToClear(whenImporting: settings) {
                defaults.removeObject(forKey: key)
            }
        } else if settings[DefaultsKey.appVolumes] != nil && settings[DefaultsKey.appVolumesArePositions] == nil {
            // Portable volume values are gains. Let the normal migration convert
            // just the values supplied by this file, even on an upgraded Mac.
            defaults.removeObject(forKey: DefaultsKey.appVolumesArePositions)
        }
        for (key, value) in settings {
            defaults.set(value, forKey: key)
        }
        if let shared = SettingsBackupSupport.sharedSwitcherPauseList(in: settings),
           replacingMissing || defaults.object(forKey: DefaultsKey.switcherPreviewExcludedApps) == nil {
            defaults[Preferences.switcherPreviewExcludedApps] = shared
        }
        if let restored = settings[DefaultsKey.recorderEditorPresets] as? Data {
            defaults[Preferences.recorderEditorPresets] = SettingsBackupSupport.preservingLocalPresetImages(
                restored: restored, local: localRecorderPresets)
        }
        if replacingMissing || settings[DefaultsKey.screenshotWatermarkStyle] != nil {
            defaults[Preferences.screenshotWatermarkStyle] = SettingsBackupSupport.restoredScreenshotWatermark(
                restored: settings[DefaultsKey.screenshotWatermarkStyle] as? String,
                local: localWatermark)
        }
        if replacingMissing || settings[DefaultsKey.screenshotWatermarkPresets] != nil {
            defaults[Preferences.screenshotWatermarkPresets] =
                SettingsBackupSupport.restoredScreenshotWatermarkPresets(
                    restored: settings[DefaultsKey.screenshotWatermarkPresets] as? String,
                    local: localWatermarkPresets)
        }
        for (key, paths) in carried where !paths.isEmpty && (replacingMissing || settings[key] != nil) {
            defaults.set(SettingsBackupSupport.restoredExceptionList(
                restored: defaults.stringArray(forKey: key) ?? [],
                carried: paths), forKey: key)
        }
        if !windowLayoutPaths.isEmpty && (replacingMissing || settings[DefaultsKey.windowLayoutIgnoredApps] != nil) {
            defaults[Preferences.windowLayoutIgnoredApps] = SettingsBackupSupport.restoredExceptionList(
                restored: defaults[Preferences.windowLayoutIgnoredApps],
                carried: windowLayoutPaths)
        }
    }

    /// `--export-settings FILE` and `--import-settings FILE`, for scripts and
    /// dotfiles. Runs before the app starts, so no menu bar item or window
    /// appears.
    @MainActor package static func runCommandAndExit(_ command: SettingsBackupSupport.Command) -> Never {
        switch command {
        case .conflictingFlags:
            failCommand("use exactly one settings backup flag")
        case .missingFile(let flag):
            failCommand("\(flag) needs a file path")
        case .export(let path):
            Defaults.register()
            guard write(to: URL(fileURLWithPath: path)) else { failCommand("could not save \(path)") }
            print("SETTINGS: exported to \(path)")
        case .import(let path):
            // A running app keeps the settings it already loaded and saves some
            // of them again, over the imported ones. The Import button
            // relaunches for the same reason.
            if anotherInstanceIsRunning(Bundle.main.bundleIdentifier ?? "") {
                failCommand("quit the app before importing settings")
            }
            guard let settings = readSettings(at: URL(fileURLWithPath: path)) else {
                failCommand("\(path) is not a valid Vitruvian Atrium backup")
            }
            Defaults.register()
            restore(settings, into: .standard)
            // The process exits next; make sure the writes reach the store.
            UserDefaults.standard.synchronize()
            print("SETTINGS: imported from \(path)")
        }
        exit(EXIT_SUCCESS)
    }

    private static func failCommand(_ message: String) -> Never {
        FileHandle.standardError.write(Data("SETTINGS: \(message)\n".utf8))
        exit(EXIT_FAILURE)
    }

    /// The optional settings file (issue #497).
    package static var configFileURL: URL {
        SettingsBackupSupport.configFileURL(
            environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser,
            isDeveloperBuild: AppInfo.isDeveloperBuild)
    }

    /// A normal app launch overlays only the declared keys, before migrations.
    /// The plist is owned by the user or their dotfiles manager. Returns the
    /// feature availability keys the file declared, which the first-run
    /// preset then leaves alone.
    @MainActor
    package static func applyConfigFileAtLaunch(arguments: [String] = CommandLine.arguments,
                                                bundleID: String? = Bundle.main.bundleIdentifier,
                                                url: URL = configFileURL,
                                                defaults: UserDefaults = .standard,
                                                running: (String) -> Bool = anotherInstanceIsRunning) -> Set<String> {
        guard let bundleID, SettingsBackupSupport.appliesConfigFile(arguments: arguments),
              FileManager.default.fileExists(atPath: url.path), !running(bundleID),
              let imported = readSettings(at: url) else { return [] }
        let settings = SettingsBackupSupport.configOverrides(from: imported) { data in
            (try? JSONDecoder().decode([TextSnippet].self, from: data)) != nil
        }
        guard !settings.isEmpty else { return [] }
        let availability = AppFeature.availabilityDefaults
        let managedFeatures = Set(settings.keys.filter { availability[$0] != nil })
        let local = defaults.dictionaryRepresentation()
        let current = SettingsBackupSupport.payload(appVersion: AppInfo.version) { local[$0] }
        let portable = current[SettingsBackupSupport.settingsKey] as? [String: Any] ?? [:]
        if settings.contains(where: { portable[$0.key] as? NSObject != $0.value as? NSObject }) {
            restore(SettingsBackupSupport.keepingLocalMediaLogos(settings, local: local),
                    into: defaults, replacingMissing: false)
        }
        return managedFeatures
    }

    package static func anotherInstanceIsRunning(_ bundleID: String) -> Bool {
        let pid = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != pid }
    }
}

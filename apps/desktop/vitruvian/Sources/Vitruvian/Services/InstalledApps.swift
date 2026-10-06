// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

/// Small lookups for resolving a bundle identifier to a human name and icon,
/// and for listing apps the user might pick. Shared by the auto-quit exception
/// list and the uninstaller.
package enum InstalledApps {
    package struct InstalledApp: Identifiable, Equatable {
        package let id: String
        package let name: String
        package let bundleID: String?
        package let url: URL
        package let isSystem: Bool
        /// The other names macOS knows this app by. Filled in only where a
        /// search wants them; every other picker leaves them empty rather than
        /// paying Spotlight for a list nobody is going to type into.
        package var alternateNames: [String] = []
        /// What the running process answers to when the row was built from a
        /// process rather than a bundle on disk, so the picker stores exactly
        /// what the taps will compare against.
        package var explicitIdentity: String? = nil

        package var identity: String? {
            explicitIdentity ?? bundleID
        }

        package var icon: NSImage {
            NSWorkspace.shared.icon(forFile: url.path)
        }

        // Spelled out because a memberwise initializer never leaves its module.
        package init(id: String, name: String, bundleID: String?, url: URL, isSystem: Bool, alternateNames: [String] = [], explicitIdentity: String? = nil) {
            self.id = id
            self.name = name
            self.bundleID = bundleID
            self.url = url
            self.isSystem = isSystem
            self.alternateNames = alternateNames
            self.explicitIdentity = explicitIdentity
        }
    }

    package static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// A list entry can also be the path of a program that is not packaged as
    /// an app, which has no bundle identifier to be named by (issue #1009).
    private static func fileURL(forIdentity identity: String) -> URL? {
        guard MouseAppExceptionSupport.isExecutablePathIdentity(identity) else {
            return url(for: identity)
        }
        return URL(fileURLWithPath: identity)
    }

    /// Where a path identity's file sits, spelled from home. Every bundled
    /// Java runtime is displayed as "java" (issue #1009), so the directory is
    /// what tells two of them apart in a list. A bundle identifier names its
    /// app on its own and carries no location.
    package static func location(for identity: String) -> String? {
        guard MouseAppExceptionSupport.isExecutablePathIdentity(identity) else { return nil }
        return ((identity as NSString).deletingLastPathComponent as NSString)
            .abbreviatingWithTildeInPath
    }

    /// The second line an app picker shows under a row's name, and the end
    /// of it that gives way when it does not fit.
    package struct RowCaption: Equatable {
        package enum Cut: Equatable {
            case head
            case middle
        }

        package let text: String
        package let cut: Cut

        // Spelled out because a memberwise initializer never leaves its module.
        package init(text: String, cut: Cut) {
            self.text = text
            self.cut = cut
        }
    }

    /// The caption under a listed identity: where a path identity's file
    /// sits, cut from the head. Sibling runtimes share a long directory prefix
    /// and differ in the middle or the tail, so cutting there would hide the
    /// one component that tells the rows apart. Nil for a bundle identifier,
    /// whose name says it all.
    package static func listCaption(for identity: String) -> RowCaption? {
        location(for: identity).map { RowCaption(text: $0, cut: .head) }
    }

    /// The caption under a picker row: a path identity's location, cut from
    /// the head as in the lists, and otherwise the bundle identifier or the
    /// file, cut in the middle.
    package static func pickerCaption(for app: InstalledApp) -> RowCaption {
        if let caption = app.identity.flatMap(listCaption(for:)) { return caption }
        return RowCaption(text: app.bundleID ?? app.url.path, cut: .middle)
    }

    package static func name(for bundleID: String) -> String {
        guard let url = fileURL(forIdentity: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    package static func icon(for bundleID: String) -> NSImage {
        if let url = fileURL(forIdentity: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    /// Apps that belong to the system wherever their bundle really sits. An
    /// app inside these is never offered for uninstalling, and only shows up
    /// in the pickers that ask for system apps too.
    private static let systemPathPrefixes = ["/System/", "/Library/Apple/"]

    /// Apps the user knows well but that no application folder holds. The file
    /// manager cannot reach them by walking, so they are resolved by identity
    /// instead of by a hardcoded path.
    private static let systemBundleIDsOutsideFolders = ["com.apple.finder"]

    package static func isSystemApplication(at url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return systemPathPrefixes.contains { path.hasPrefix($0) }
    }

    /// Whether `url` sits somewhere under one of the folders installed apps
    /// live in - /Applications or ~/Applications - at any depth, not just
    /// directly inside them. Matches `installedApplications`'s own walk of
    /// these same two roots, which recurses into subfolders (an installer
    /// that drops its app inside a vendor subfolder, such as
    /// /Applications/Vendor/App.app, is exactly what that walk already
    /// treats as installed) - this used to require the app sit directly in
    /// one of the roots, which meant a bundle `installedApplications` would
    /// list could still be refused here.
    package static func isInApplicationsFolder(_ url: URL) -> Bool {
        let containingDirectory = url.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL.path
        let roots = [
            URL(fileURLWithPath: "/Applications").standardizedFileURL.path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
                .standardizedFileURL.path,
        ]
        return roots.contains { containingDirectory == $0 || containingDirectory.hasPrefix($0 + "/") }
    }

    package static func installedApplications(includeSystemApplications: Bool = false,
                                      spotlightPaths: [String] = []) -> [InstalledApp] {
        let fm = FileManager.default
        var roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true),
        ]
        if includeSystemApplications {
            roots.append(URL(fileURLWithPath: "/System/Applications", isDirectory: true))
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for root in roots where fm.fileExists(atPath: root.path) {
            // Hidden entries are deliberately NOT skipped: the browser that
            // ships with macOS lives on the system volume and is exposed in
            // /Applications as a hidden symlink, so skipping them left it out
            // of every picker. Only bundles ending in .app are taken anyway.
            guard let enumerator = fm.enumerator(at: root,
                                                includingPropertiesForKeys: keys,
                                                options: [.skipsPackageDescendants]) else {
                continue
            }
            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                // A link's target decides whether the app is the system's:
                // the path inside the application folder says nothing.
                let resolved = url.resolvingSymlinksInPath()
                let isSystemApp = isSystemApplication(at: url)
                guard includeSystemApplications || !isSystemApp else { continue }
                guard seen.insert(resolved.standardizedFileURL.path).inserted else { continue }
                apps.append(app(at: url, fileManager: fm))
            }
        }

        if includeSystemApplications {
            for bundleID in systemBundleIDsOutsideFolders {
                guard let url = url(for: bundleID),
                      seen.insert(url.resolvingSymlinksInPath().standardizedFileURL.path).inserted else {
                    continue
                }
                apps.append(app(at: url, fileManager: fm))
            }
        }

        for path in applicationScanPaths(folderPaths: [],
                                         spotlightPaths: spotlightPaths,
                                         homeDirectory: NSHomeDirectory()) {
            let url = URL(fileURLWithPath: path)
            guard fm.fileExists(atPath: path),
                  seen.insert(url.standardizedFileURL.path).inserted else { continue }
            apps.append(app(at: url, fileManager: fm))
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Merges the normal Applications folders with shallow Spotlight results
    /// from the user's home. Deep build products, hidden folders, nested apps
    /// and system-owned bundles are not installed apps a person should see.
    package static func applicationScanPaths(folderPaths: [String],
                                     spotlightPaths: [String],
                                     homeDirectory: String) -> [String] {
        let home = URL(fileURLWithPath: homeDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        let homePrefix = home.hasSuffix("/") ? home : home + "/"
        var seen = Set<String>()
        var result: [String] = []

        func append(_ path: String, fromSpotlight: Bool) {
            let url = URL(fileURLWithPath: path)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let normalized = url.path
            guard url.pathExtension.lowercased() == "app",
                  !isSystemApplication(at: url),
                  !normalized.split(separator: "/").dropLast().contains(where: {
                      $0.lowercased().hasSuffix(".app")
                  }) else { return }

            if fromSpotlight {
                guard normalized.hasPrefix(homePrefix) else { return }
                let components = normalized.dropFirst(homePrefix.count).split(separator: "/")
                let folders = components.dropLast()
                guard (1...3).contains(components.count),
                      components.first?.lowercased() != "library",
                      !folders.contains(where: { $0.hasPrefix(".") }) else { return }
            }

            guard seen.insert(normalized).inserted else { return }
            result.append(normalized)
        }

        folderPaths.forEach { append($0, fromSpotlight: false) }
        spotlightPaths.forEach { append($0, fromSpotlight: true) }
        return result
    }

    private static func app(at url: URL, fileManager fm: FileManager) -> InstalledApp {
        var name = fm.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return InstalledApp(id: url.standardizedFileURL.path,
                            name: name,
                            bundleID: Bundle(url: url)?.bundleIdentifier,
                            url: url,
                            isSystem: isSystemApplication(at: url))
    }

    /// A program with no .app bundle (a runtime a game launcher starts, issue #865)
    /// is listed only for lists that store path identities, because a list that
    /// takes only apps would drop the pick silently and show a row that does nothing.
    package static func runningApplication(activationPolicy: NSApplication.ActivationPolicy,
                                   bundleID: String?,
                                   bundleURL: URL?,
                                   executableURL: URL?,
                                   localizedName: String?,
                                   acceptsExecutables: Bool) -> InstalledApp? {
        guard activationPolicy == .regular else { return nil }

        if let bundleID, bundleID.isEmpty { return nil }
        let isAppBundle = bundleURL?.pathExtension.caseInsensitiveCompare("app") == .orderedSame

        if let bundleID, let bundleURL, isAppBundle {
            let name = localizedName ?? FileManager.default.displayName(atPath: bundleURL.path)
            return InstalledApp(id: bundleURL.standardizedFileURL.path,
                                name: name,
                                bundleID: bundleID,
                                url: bundleURL,
                                isSystem: isSystemApplication(at: bundleURL),
                                explicitIdentity: nil)
        }

        guard acceptsExecutables, let executableURL else { return nil }
        guard let identity = MouseAppExceptionSupport.identity(
            bundleID: bundleID,
            executablePath: executableURL.path
        ) else { return nil }

        let isPathIdentity = MouseAppExceptionSupport.isExecutablePathIdentity(identity)
        let url = isPathIdentity ? URL(fileURLWithPath: identity) : executableURL
        let name = localizedName ?? FileManager.default.displayName(atPath: url.path)

        return InstalledApp(id: identity,
                            name: name,
                            bundleID: isPathIdentity ? nil : identity,
                            url: url,
                            isSystem: isSystemApplication(at: url),
                            explicitIdentity: identity)
    }

    package static func runningApplication(_ app: NSRunningApplication,
                                   acceptsExecutables: Bool) -> InstalledApp? {
        runningApplication(activationPolicy: app.activationPolicy,
                           bundleID: app.bundleIdentifier,
                           bundleURL: app.bundleURL,
                           executableURL: app.executableURL,
                           localizedName: app.localizedName,
                           acceptsExecutables: acceptsExecutables)
    }

    package static func deduplicatedAndFiltered(_ apps: [InstalledApp],
                                        excluding excludedIdentities: Set<String>) -> [InstalledApp] {
        var seen = Set<String>()
        return apps.filter { app in
            guard let identity = app.identity,
                  !excludedIdentities.contains(identity),
                  seen.insert(identity).inserted else { return false }
            return true
        }.sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            // Equal display names — three runtimes all named "java" — fall
            // back to the identity so the rows hold one order between renders.
            return byName == .orderedSame
                ? ($0.identity ?? "") < ($1.identity ?? "")
                : byName == .orderedAscending
        }
    }

    package static func installedBundleApplications(excluding excludedBundleIDs: Set<String>,
                                            includeRunningApplications: Bool = false,
                                            acceptsExecutables: Bool = false) -> [InstalledApp] {
        var apps = installedApplications(includeSystemApplications: true)
        if includeRunningApplications {
            apps += NSWorkspace.shared.runningApplications.compactMap { runningApp in
                runningApplication(runningApp, acceptsExecutables: acceptsExecutables)
            }
        }

        return deduplicatedAndFiltered(apps, excluding: excludedBundleIDs)
    }
}

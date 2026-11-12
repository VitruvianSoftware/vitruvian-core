// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import UniformTypeIdentifiers
import VitruvianCore
import VitruvianDesign

@MainActor
package final class URLCleanerService: ObservableObject {
    @Published package private(set) var isRunning = false
    @Published package private(set) var lastCleaned: String?
    /// Names the last automatic clean took out, so Settings can say what the
    /// silent rewrite did rather than only that it is running.
    @Published package private(set) var lastRemoved: [String] = []

    private let services: ToolServices
    /// True while the broker watches the clipboard for this tool.
    private var watching = false

    package init(services: ToolServices) {
        self.services = services
    }

    package func clean(_ text: String) -> URLCleaning.Result? {
        URLCleaning.clean(text, rules: Self.rules(try? services.storage.reader().get()))
    }

    /// Writes on the shared lane and settles the change count on the main
    /// queue, where the watch compares against it. The caller never waits: the
    /// lane can be wedged behind an app that promised pasteboard content and
    /// stopped answering (issue #887).
    package func copy(_ urlString: String) {
        lastCleaned = urlString
        services.clipboard.writeLink(urlString)
    }

    /// The text on the clipboard, for a Paste button: empty when it holds
    /// none. Through the shared lane: a direct read would both race the
    /// clipboard services on AppKit's pasteboard cache and hang the button
    /// (and with it the app) on a promised flavour nobody renders any more.
    package func pasteboardText(_ completion: @escaping @MainActor (String) -> Void) {
        services.clipboard.readText { completion($0 ?? "") }
    }

    /// Starts the automatic clean. The tool host calls this each time it
    /// finds the cleaner installed and switched on, so a second call only
    /// confirms it is running.
    package func start() {
        guard !watching else {
            isRunning = true
            return
        }
        guard case .success(let storage) = services.storage.reader() else { return }
        let rule = Self.rewriteRule(rules: { Self.rules(storage) })
        let refusal = services.clipboard.rewriteLinks(rule: rule) { [weak self] replaced in
            guard let self, self.isRunning else { return }
            self.lastCleaned = replaced.text
            self.lastRemoved = replaced.note
        }
        guard refusal == nil else { return }
        watching = true
        isRunning = true
    }

    package func stop() {
        services.clipboard.stopRewritingLinks()
        watching = false
        isRunning = false
    }

    package func canRun(_ command: CommandID) -> Bool {
        command == Self.cleanClipboard
    }

    /// Cleans the link on the clipboard once and says what it did. Reads
    /// through the shared lane like every other clipboard row: a direct
    /// main-thread read races the lane's readers and freezes the app on a
    /// promised flavour nobody is left to render (issue #887).
    package func run(_ command: CommandID) {
        guard command == Self.cleanClipboard else { return }
        let notify = services.notify
        services.clipboard.readText { [weak self] raw in
            guard let self else { return }
            let s = L10n.shared.s
            guard let raw,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notify.hud(icon: "link", message: s.urlCleanerNoURL)
                return
            }
            let cleaned = self.clean(raw)
            switch URLCleaning.outcome(for: cleaned, input: raw) {
            case .notAURL:
                notify.hud(icon: "link", message: s.urlCleanerNoURL)
            case .unchanged:
                notify.hud(icon: "checkmark.circle", message: s.urlCleanerNoChange)
            case .rewritten:
                cleaned.map { self.copy($0.url) }
                notify.hud(icon: "link", message: s.urlCleanerCleaned)
            case .removed(let names):
                cleaned.map { self.copy($0.url) }
                notify.hud(icon: "link",
                           message: String(format: s.urlCleanerRemovedFormat,
                                           names.joined(separator: ", ")))
            }
        }
    }

    /// What the automatic clean asks of each copy, on the clipboard lane.
    /// `rules` is read there, each time a link is about to be cleaned, so a
    /// rule changed in Settings holds from the next copy.
    nonisolated package static func rewriteRule(rules: @escaping @Sendable () -> URLCleaning.Rules)
        -> ClipboardRewriteRule {
        ClipboardRewriteRule(
            // The types decide before any content is read: a picture or a
            // file is never fetched only to be left alone.
            readsText: { URLCleaning.canRewritePasteboard(types: $0) },
            // The rewrite is for a link something was actually taken out of. A
            // copy with nothing to remove is left exactly as the user put it,
            // because writing to the pasteboard discards whatever else the copy
            // carried, and a link the cleaner did not need to touch is the one
            // most likely to come back spelled differently.
            replacement: { text in
                guard let cleaned = URLCleaning.clean(text, rules: rules()),
                      !cleaned.removed.isEmpty else { return nil }
                return ClipboardReplacement(text: cleaned.url, note: cleaned.removed)
            },
            // The rewrite drops the HTML, which is only right when the HTML adds
            // nothing to the link but formatting.
            dropsMarkup: { URLCleaning.markupAddsOnlyFormatting($0, to: $1) })
    }

    /// The saved rules. With no reader, the built-in rules alone.
    nonisolated private static func rules(_ storage: StorageReader?) -> URLCleaning.Rules {
        URLCleaning.rules(
            globalNames: storage?.value(for: Preferences.urlCleanerCustomParameters),
            siteNames: storage?.value(for: Preferences.urlCleanerSiteParameters),
            disabledNames: storage?.value(for: Preferences.urlCleanerDisabledParameters))
    }
}

extension URLCleanerService: BundledTool {
    /// Cleans the link on the clipboard once. The command bar's "Clean URL"
    /// row runs it. It asks for no surface: the row is the bar's own.
    package static let cleanClipboard: CommandID = {
        guard let id = ToolID(AppFeature.urlCleaner.rawValue),
              let command = CommandID(tool: id, name: "cleanClipboard")
        else { preconditionFailure("the URL cleaner's command is not valid") }
        return command
    }()

    package static let manifest: ToolManifest = {
        let feature = AppFeature.urlCleaner
        guard let clean = CommandDescriptor(id: cleanClipboard, title: feature.rawValue, symbol: feature.symbolName,
                                            surfaces: []),
              let tool = ToolDescriptor(id: cleanClipboard.tool, name: feature.rawValue, symbol: feature.symbolName,
                                        commands: [clean]),
              let storage = CapabilityRequest(.storage, reason: "Remembers whether automatic cleaning is on, and your rules."),
              let read = CapabilityRequest(.clipboardRead, reason: "Reads a link you copied, to clean it."),
              let rewrite = CapabilityRequest(.clipboardRewrite, reason: "Replaces a link you copied with the cleaned link."),
              let write = CapabilityRequest(.clipboardWrite, reason: "Copies a link you cleaned by hand."),
              let say = CapabilityRequest(.notify, reason: "Says what was taken out of a link."),
              let manifest = ToolManifest(
                  tool: tool, group: feature.group, capabilities: [storage, read, rewrite, write, say],
                  preferences: [
                      PreferenceDeclaration(key: DefaultsKey.urlCleanerEnabled, default: .bool(false)),
                      PreferenceDeclaration(key: DefaultsKey.urlCleanerCustomParameters, default: .string("")),
                      PreferenceDeclaration(key: DefaultsKey.urlCleanerSiteParameters, default: .string("")),
                      PreferenceDeclaration(key: DefaultsKey.urlCleanerDisabledParameters, default: .string("")),
                      PreferenceDeclaration(key: DefaultsKey.panelUtilityURLCleaner, default: .bool(true)),
                  ],
                  activation: [.onLaunch, .onCommand, .onShown], enabledBy: DefaultsKey.urlCleanerEnabled)
        else { preconditionFailure("the URL cleaner's manifest is not valid") }
        return manifest
    }()
}

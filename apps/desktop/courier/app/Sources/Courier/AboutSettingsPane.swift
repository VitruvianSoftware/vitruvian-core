// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Settings ▸ About pane (`AboutSettingsPane.swift`):
/// Courier version & build info, `"View Changelog"`, `"Report a Problem…"` (`⌘⇧P`),
/// `"Keyboard Shortcuts"` (`⌘/`), `"Privacy & Security"`, and `"Legal Notices"` (MIT/MPL-2.0/AGPL-3.0 notices for embedded bridges).
struct AboutSettingsPane: View {
    @ObservedObject var lifecycle: SystemLifecycleModel
    var appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.6"
    var buildNumber: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "9"
    var onReportProblem: () -> Void = {}
    var onShowKeyboardShortcuts: () -> Void = {}
    var highlightedSettingID: String? = nil

    @State private var showChangelog: Bool = false
    @State private var showPrivacyDetails: Bool = true
    @State private var showLegalNotices: Bool = false

    public static let embeddedBridgeNotices: [(component: String, license: String, summary: String)] = [
        ("Courier Desktop & Engine", "AGPL-3.0-or-later", "On-device unified messaging application and local Matrix store."),
        ("mautrix-go (bridgev2)", "MPL-2.0", "Matrix bridge framework and local bridge database layer (maunium.net/go/mautrix v0.31.0)."),
        ("mautrix-whatsapp", "AGPL-3.0-or-later", "On-device WhatsApp multi-device connector (go.mau.fi/mautrix-whatsapp v0.2609.0)."),
        ("mautrix-signal", "AGPL-3.0-or-later", "On-device Signal linked-device connector (go.mau.fi/mautrix-signal v0.2609.0)."),
        ("mautrix-telegram", "AGPL-3.0-or-later", "On-device Telegram MTProto connector (go.mau.fi/mautrix-telegram v0.2609.0)."),
        ("mautrix-slack", "AGPL-3.0-or-later", "On-device Slack workspace connector (go.mau.fi/mautrix-slack v0.2609.1)."),
        ("mautrix-gmessages", "AGPL-3.0-or-later", "On-device Google Messages paired-phone connector (go.mau.fi/mautrix-gmessages v0.2609.0)."),
        ("SQLite & FTS5", "Public Domain / MIT", "Embedded relational store and full-text message index."),
    ]

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                headerSection
                actionsSection
                privacySection
                legalNoticesSection
            }
            .formStyle(.grouped)
            .disabled(lifecycle.isLocked)
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                if let targetID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        Section(String(localized: "About Courier")) {
            HStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Courier"))
                        .font(.title3.weight(.semibold))
                    Text(String(localized: "Version \(appVersion) (Protocol \(CourierProtocol.version), Build \(buildNumber))"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "All bridges, message history, and search indexes run locally on this Mac."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .settingAnchor("about.version", highlighted: highlightedSettingID)

            DisclosureGroup(
                SettingsNavigationModel.title(for: "about.changelog"),
                isExpanded: $showChangelog
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "• Milestone 4.6: Two-column Settings window with search, Accounts & Bridges panes, Touch ID App Lock, detached windows, shortcut recorder, and local problem report bundles."))
                        .font(.caption)
                    Text(String(localized: "• Milestone 4.5: Chat Info drawer, Calendar pane, Contacts hover cards, Stickers, GIFs, Voice Notes, Emoji autocomplete, and Media Viewer."))
                        .font(.caption)
                    Text(String(localized: "• Milestone 4.4: Read receipts, typing indicators, Incognito mode, and multi-account support."))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .settingAnchor("about.changelog", highlighted: highlightedSettingID)
        }
    }

    private var actionsSection: some View {
        Section(String(localized: "Diagnostics & Reference")) {
            LabeledContent(SettingsNavigationModel.title(for: "about.reportProblem")) {
                Button(String(localized: "Report a Problem… (⌘⇧P)")) {
                    onReportProblem()
                }
            }
            .settingAnchor("about.reportProblem", highlighted: highlightedSettingID)

            LabeledContent(SettingsNavigationModel.title(for: "about.keyboardShortcuts")) {
                Button(String(localized: "Keyboard Shortcuts (⌘/)")) {
                    onShowKeyboardShortcuts()
                }
            }
            .settingAnchor("about.keyboardShortcuts", highlighted: highlightedSettingID)
        }
    }

    private var privacySection: some View {
        Section(SettingsNavigationModel.title(for: "about.privacy")) {
            DisclosureGroup(
                String(localized: "On-Device Architecture & Data Privacy"),
                isExpanded: $showPrivacyDetails
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "• Direct-to-network: Courier connects directly from this Mac to your linked chat networks without any middleman relay."))
                        .font(.caption)
                    Text(String(localized: "• Local SQLite & media store: Messages, attachments, and search indexes stay in your local Courier data folder."))
                        .font(.caption)
                    Text(String(localized: "• Local diagnostics: Problem report bundles are saved to a file you choose on this Mac and scrubbed of tokens, phone numbers, names, and home folder paths."))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .settingAnchor("about.privacy", highlighted: highlightedSettingID)
        }
    }

    private var legalNoticesSection: some View {
        Section(SettingsNavigationModel.title(for: "about.legalNotices")) {
            DisclosureGroup(
                String(localized: "Open-Source Licenses (MIT / MPL-2.0 / AGPL-3.0)"),
                isExpanded: $showLegalNotices
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.embeddedBridgeNotices, id: \.component) { notice in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(notice.component)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(notice.license)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(notice.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 4)
            }
            .settingAnchor("about.legalNotices", highlighted: highlightedSettingID)
        }
    }
}

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
    /// Updates: nil leaves the section out.
    var updates: UpdateModel? = nil

    @State private var showChangelog: Bool = false
    @State private var showPrivacyDetails: Bool = true
    @State private var showLegalNotices: Bool = false

    init(
        lifecycle: SystemLifecycleModel,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.6",
        buildNumber: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "9",
        onReportProblem: @escaping () -> Void = {},
        onShowKeyboardShortcuts: @escaping () -> Void = {},
        highlightedSettingID: String? = nil,
        showChangelog: Bool = false,
        showPrivacyDetails: Bool = true,
        showLegalNotices: Bool = false,
        updates: UpdateModel? = nil
    ) {
        self.updates = updates
        self.lifecycle = lifecycle
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.onReportProblem = onReportProblem
        self.onShowKeyboardShortcuts = onShowKeyboardShortcuts
        self.highlightedSettingID = highlightedSettingID
        _showChangelog = State(initialValue: showChangelog || highlightedSettingID == "about.changelog")
        _showPrivacyDetails = State(initialValue: showPrivacyDetails || highlightedSettingID == "about.privacy")
        _showLegalNotices = State(initialValue: showLegalNotices || highlightedSettingID == "about.legalNotices")
    }

    /// The release's page for this version, or every Courier release when the version isn't a release's.
    static func releaseNotesURL(version: String) -> URL {
        if let release = SemanticVersion(version) {
            return CourierReleases.releasePageURL(for: release)
        }
        return URL(string: "https://github.com/\(CourierReleases.owner)/\(CourierReleases.repository)/releases?q=courier-v")!
    }

    public static let embeddedBridgeNotices: [(component: String, license: String, summary: String)] = [
        ("Courier Desktop & Engine", "AGPL-3.0-or-later", "On-device unified messaging application and local Matrix store."),
        ("mautrix-go (bridgev2)", "MPL-2.0", "Matrix bridge framework and local bridge database layer (maunium.net/go/mautrix v0.31.0)."),
        ("mautrix-whatsapp", "AGPL-3.0-or-later", "On-device WhatsApp multi-device connector (go.mau.fi/mautrix-whatsapp v0.2609.0)."),
        ("mautrix-signal", "AGPL-3.0-or-later", "On-device Signal linked-device connector (go.mau.fi/mautrix-signal v0.2609.0)."),
        ("mautrix-telegram", "AGPL-3.0-or-later", "On-device Telegram MTProto connector (go.mau.fi/mautrix-telegram v0.2609.0)."),
        ("mautrix-slack", "AGPL-3.0-or-later", "On-device Slack workspace connector (go.mau.fi/mautrix-slack v0.2609.1)."),
        ("mautrix-gmessages", "AGPL-3.0-or-later", "On-device Google Messages paired-phone connector (go.mau.fi/mautrix-gmessages v0.2609.0)."),
        ("mautrix-googlechat", "AGPL-3.0-or-later", "On-device Google Chat connector (github.com/VitruvianSoftware/courier/bridges/googlechat)."),
        ("mautrix-discord", "AGPL-3.0-or-later", "On-device Discord connector (go.mau.fi/mautrix-discord)."),
        ("mautrix-meta", "AGPL-3.0-or-later", "On-device Facebook Messenger and Instagram connector (go.mau.fi/mautrix-meta v0.2609.0)."),
        ("mautrix-twitter", "AGPL-3.0-or-later", "On-device X (Twitter) connector (go.mau.fi/mautrix-twitter v0.2609.0)."),
        ("mautrix-linkedin", "AGPL-3.0-or-later", "On-device LinkedIn Messaging connector (go.mau.fi/mautrix-linkedin v0.2609.0)."),
        ("mautrix-gvoice", "AGPL-3.0-or-later", "On-device Google Voice connector (go.mau.fi/mautrix-gvoice)."),
        ("mautrix-bluesky", "AGPL-3.0-or-later", "On-device Bluesky chat connector (go.mau.fi/mautrix-bluesky)."),
        ("courier-imessage", "AGPL-3.0-or-later", "On-device macOS iMessage connector (github.com/VitruvianSoftware/courier/engine/internal/imessage)."),
        ("SQLite & FTS5", "Public Domain / MIT", "Embedded relational store and full-text message index."),
    ]

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                headerSection
                if let updates {
                    UpdatesSection(updates: updates, highlightedSettingID: highlightedSettingID)
                }
                actionsSection
                privacySection
                legalNoticesSection
            }
            .formStyle(.grouped)
            .disabled(lifecycle.isLocked)
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                // Help ▸ Changelog and Help ▸ Privacy & Security, and a search result, open what they point at even
                // while Settings is already showing About.
                switch targetID {
                case "about.changelog": showChangelog = true
                case "about.privacy": showPrivacyDetails = true
                case "about.legalNotices": showLegalNotices = true
                default: break
                }
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
                    Text(String(localized: "What changed in each version of Courier is in its release notes."))
                        .font(.caption)
                    Link(String(localized: "Release Notes for Courier \(appVersion)"),
                         destination: AboutSettingsPane.releaseNotesURL(version: appVersion))
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

/// Settings ▸ About ▸ Updates: whether a newer Courier is out, and installing it. The check runs at launch and daily
/// (unless turned off here), and Courier ▸ Check for Updates… runs it now.
struct UpdatesSection: View {
    @ObservedObject var updates: UpdateModel
    var highlightedSettingID: String?

    var body: some View {
        Section(SettingsNavigationModel.title(for: "about.updates")) {
            VStack(alignment: .leading, spacing: 8) {
                status
                actions
            }
            .padding(.vertical, 2)
            .settingAnchor("about.updates", highlighted: highlightedSettingID)

            Toggle(String(localized: "Check for updates automatically"), isOn: $updates.checksAutomatically)
            Text(String(localized: "Courier checks GitHub when it opens and once a day. An update is installed only after its checksum, its Developer ID signature and Apple’s notarization check out; Courier then quits and opens again."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updates.phase {
        case .idle:
            Text(String(localized: "Courier hasn’t checked for updates yet."))
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Checking for updates…"))
            }
        case .upToDate:
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Courier \(updates.currentVersion?.description ?? "") is up to date."))
                if let lastChecked = updates.lastChecked {
                    Text(String(localized: "Checked \(lastChecked.formatted(date: .abbreviated, time: .shortened))."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case let .available(version):
            Text(String(localized: "Courier \(version.description) is available. You have \(updates.currentVersion?.description ?? "")."))
                .fontWeight(.medium)
        case let .downloading(version, fraction):
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Downloading Courier \(version.description)…"))
                ProgressView(value: fraction)
            }
        case let .verifying(version):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Checking Courier \(version.description)’s checksum, signature and notarization…"))
            }
        case let .installing(version):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Installing Courier \(version.description). Courier will quit and open again."))
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if case let .available(version) = updates.phase {
                Button(String(localized: "Download and Install")) {
                    Task { await updates.installUpdate() }
                }
                .buttonStyle(.borderedProminent)
                Link(String(localized: "Release Notes"), destination: CourierReleases.releasePageURL(for: version))
            } else {
                Button(String(localized: "Check for Updates")) {
                    Task { await updates.check() }
                }
                .disabled(updates.isBusy)
            }
        }
    }
}

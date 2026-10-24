// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// A banner for an account that needs the person: logged out, refused, stuck on an error, or not started, with the
/// button that fixes it (none, for one that did not start).
struct AccountBannerView: View {
    let banner: AccountBanner
    let act: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if !banner.detail.isEmpty {
                    Text(banner.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let buttonTitle {
                Button(buttonTitle, action: act)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch banner.reason {
        // With two accounts on the network, the one that needs the person is named: "WhatsApp (+1 555 0102)".
        case .loggedOut: String(localized: "You’re logged out of \(name).")
        case .badCredentials: String(localized: "\(name) no longer accepts your sign-in.")
        case .unknownError: String(localized: "\(name) stopped working.")
        case .notStarted: String(localized: "\(name) isn’t running.")
        }
    }

    /// The network, and the account when the banner names one, kept on one line: a phone number never breaks.
    private var name: String { banner.titleName.replacingOccurrences(of: " ", with: "\u{00A0}") }

    private var buttonTitle: String? {
        switch banner.action {
        case .reconnect: String(localized: "Reconnect")
        case nil: nil
        }
    }
}

/// One small item per linked account, with its network's mark, and "Starting…" beside those the engine hasn't
/// started yet, "Reconnecting…" beside those the bridge has lost. A connected account says nothing; the tooltip names
/// the account when its network has more than one. Nothing at all when no account is linked.
struct AccountStatusStrip: View {
    let items: [AccountStatusItem]

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        NetworkBadge(network: item.network, name: item.displayName, size: 14)
                            .opacity(item.isStarting ? 0.55 : 1)
                        if let status = item.statusLabel {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .help(item.tooltip)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.tooltip)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

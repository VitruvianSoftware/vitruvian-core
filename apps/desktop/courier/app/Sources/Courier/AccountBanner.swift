// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// A banner for an account that needs the person: logged out, refused, stuck on an error, or not started, with the
/// button that fixes it.
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
        case .loggedOut: String(localized: "You’re logged out of \(banner.displayName).")
        case .badCredentials: String(localized: "\(banner.displayName) no longer accepts your sign-in.")
        case .unknownError: String(localized: "\(banner.displayName) stopped working.")
        case .notStarted: String(localized: "\(banner.displayName) isn’t running.")
        }
    }

    private var buttonTitle: String? {
        switch banner.action {
        case .reconnect: String(localized: "Reconnect")
        case .setUp: String(localized: "Set up")
        case nil: nil
        }
    }
}

/// One small item per linked account, with its network's mark, and "Reconnecting…" beside the marks of those the
/// bridge has lost. A connected account says nothing. Nothing at all when no account is linked.
struct AccountStatusStrip: View {
    let items: [AccountStatusItem]

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        NetworkBadge(network: item.network, name: item.displayName, size: 14)
                        if item.isReconnecting {
                            Text(String(localized: "Reconnecting…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help(item.isReconnecting ? "\(item.displayName): \(String(localized: "Reconnecting…"))" : item.displayName)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// The inbox pane: the account strip and banners, then the chats, newest first.
struct InboxList: View {
    @ObservedObject var inbox: InboxModel

    var body: some View {
        VStack(spacing: 0) {
            AccountStatusStrip(items: inbox.statusItems)
            ForEach(inbox.banners) { banner in
                AccountBannerView(banner: banner) { inbox.perform(banner) }
            }
            chats
        }
    }

    @ViewBuilder
    private var chats: some View {
        if !inbox.isLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if inbox.rows.isEmpty {
            Text(String(localized: "No chats yet"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { scroll in
                List(selection: selection) {
                    ForEach(inbox.rows, id: \.roomID) { row in
                        InboxRowView(row: row, networkName: inbox.networkName(row.network))
                            .tag(row.roomID)
                    }
                }
                .listStyle(.inset)
                .onChange(of: inbox.selectedRoomID) { _, id in
                    // A key moved the selection, which may be off screen.
                    if let id { scroll.scrollTo(id) }
                }
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { inbox.selectedRoomID }, set: { inbox.select($0) })
    }
}

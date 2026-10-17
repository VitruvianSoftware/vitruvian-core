// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// What was just done, at the bottom of the chat list, with Undo when it can be undone (⌘Z does the same). The
/// model takes it down after a few seconds, or on the next action.
struct ToastView: View {
    @ObservedObject var inbox: InboxModel

    var body: some View {
        ZStack {
            if let toast = inbox.toast {
                HStack(spacing: 12) {
                    Text(toast.message)
                        .font(.callout)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if toast.canUndo {
                        Button(String(localized: "Undo")) { Task { await inbox.undo() } }
                            .buttonStyle(.borderless)
                            .font(.callout.weight(.semibold))
                            .help(String(localized: "Undo (⌘Z)"))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .padding(.bottom, 12)
                .padding(.horizontal, 12)
                .id(toast.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeOut(duration: 0.2), value: inbox.toast)
    }
}

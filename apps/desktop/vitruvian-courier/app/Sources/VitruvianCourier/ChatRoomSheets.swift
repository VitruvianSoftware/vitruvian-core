// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import VitruvianCourierCore
import SwiftUI

/// The Edit Chat / Edit Group and Report as Spam sheets, hosted by the window rather than by the open chat's pane, so
/// they can open for any chat: the inbox's right-click menu opens them for a chat that isn't open, and opening it
/// just for that would send the people in it a read receipt.
struct ChatRoomSheets: ViewModifier {
    @ObservedObject var conversation: ConversationModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $conversation.activeEditGroupDraft) { draft in
                EditGroupSheet(
                    draft: draft,
                    onSave: { updated in
                        Task { _ = await conversation.saveGroupEdit(updated) }
                    },
                    onResetLocalOverride: {
                        Task { _ = await conversation.resetLocalOverride(roomID: draft.roomID, network: draft.network) }
                    },
                    onCancel: {
                        conversation.activeEditGroupDraft = nil
                    }
                )
            }
            .sheet(item: $conversation.activeReportSpamDraft) { draft in
                ReportSpamSheet(
                    draft: draft,
                    onConfirm: { confirmed in
                        Task { _ = await conversation.reportSpam(confirmed) }
                    },
                    onCancel: {
                        conversation.activeReportSpamDraft = nil
                    }
                )
            }
    }
}

extension View {
    func chatRoomSheets(_ conversation: ConversationModel) -> some View {
        modifier(ChatRoomSheets(conversation: conversation))
    }
}

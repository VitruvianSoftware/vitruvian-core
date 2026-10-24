// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// "Also hide that you're typing?", asked once each time turning Incognito on raises it
/// (`ConversationModel.asksToHideTyping`), whichever way it was turned on: Settings, the command bar, anything later.
/// The app gives one presenter for all of them, so the question is never asked twice at once; the answer goes back to
/// the conversation (`answerHideTyping`), true for Hide Typing.
///
/// The presenter is called on the next turn of the main actor, never inside the change that raised the question, so a
/// presenter that waits for its answer (an app-modal alert) can't answer before the question is fully asked. A
/// question withdrawn meanwhile (Incognito turned off again) is not asked; an answer to one withdrawn changes nothing.
@MainActor
public final class HideTypingQuestion {
    /// The question is up and not answered yet.
    public private(set) var isAsking = false

    private let conversation: ConversationModel
    private let present: @MainActor (_ answer: @escaping @MainActor (_ hide: Bool) -> Void) -> Void
    private var subscription: AnyCancellable?

    public init(conversation: ConversationModel,
                present: @escaping @MainActor (_ answer: @escaping @MainActor (_ hide: Bool) -> Void) -> Void) {
        self.conversation = conversation
        self.present = present
        subscription = conversation.$asksToHideTyping.removeDuplicates().sink { [weak self] asks in
            guard asks else { return }
            Task { @MainActor [weak self] in self?.ask() }
        }
    }

    private func ask() {
        guard !isAsking, conversation.asksToHideTyping else { return }
        isAsking = true
        present { [weak self] hide in
            guard let self else { return }
            isAsking = false
            conversation.answerHideTyping(hide)
        }
    }
}

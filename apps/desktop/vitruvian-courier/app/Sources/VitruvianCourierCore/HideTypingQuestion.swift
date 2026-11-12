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
/// presenter that waits for its answer (an app-modal alert) can't answer before the question is fully asked. It
/// returns how to take the question down: Incognito turned off while it is up withdraws it, and the question is taken
/// down then (B11). A question withdrawn before it came up is not asked; an answer to one withdrawn changes nothing,
/// whenever it comes (an alert being taken down may still answer).
@MainActor
public final class HideTypingQuestion {
    /// The question is up and not answered yet.
    public private(set) var isAsking = false

    private let conversation: ConversationModel
    private let present: @MainActor (_ answer: @escaping @MainActor (_ hide: Bool) -> Void) -> (@MainActor () -> Void)
    private var subscription: AnyCancellable?
    /// Takes down the question that is up.
    private var takeDown: (@MainActor () -> Void)?
    /// Counts the questions asked or withdrawn: an answer counts only for the one it was given to, while it is up.
    private var asked = 0

    public init(conversation: ConversationModel,
                present: @escaping @MainActor (_ answer: @escaping @MainActor (_ hide: Bool) -> Void)
                    -> (@MainActor () -> Void)) {
        self.conversation = conversation
        self.present = present
        subscription = conversation.$asksToHideTyping.removeDuplicates().sink { [weak self] asks in
            guard asks else {
                self?.withdraw()
                return
            }
            Task { @MainActor [weak self] in self?.ask() }
        }
    }

    private func ask() {
        guard !isAsking, conversation.asksToHideTyping else { return }
        isAsking = true
        asked += 1
        let question = asked
        let down = present { [weak self] hide in
            guard let self, isAsking, asked == question else { return }
            isAsking = false
            takeDown = nil
            conversation.answerHideTyping(hide)
        }
        // A presenter may answer before it returns (an app-modal alert): then there is nothing to take down.
        if isAsking, asked == question { takeDown = down }
    }

    /// Incognito was turned off, or the question answered: one still up is taken down, and its answer won't count.
    private func withdraw() {
        guard isAsking else { return }
        isAsking = false
        asked += 1
        let down = takeDown
        takeDown = nil
        down?()
    }
}

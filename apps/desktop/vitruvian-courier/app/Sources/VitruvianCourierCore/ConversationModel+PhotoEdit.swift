// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// "Edit with AI…": from a photo in the viewer or a photo message's menu.
extension ConversationModel {
    /// Whether "Edit with AI…" is offered at all: AI is on and the app is unlocked. With AI turned off it is hidden.
    public var isPhotoEditingOffered: Bool {
        !isLocked && (photoEditBackend?.isOffered() ?? false)
    }

    /// Whether `message`'s menu shows "Edit with AI…".
    public func offersPhotoEdit(for message: TimelineMessage) -> Bool {
        isPhotoEditingOffered && PhotoEditSource(message: message) != nil
    }

    /// Whether the viewer shows "Edit with AI…" for `item`.
    public func offersPhotoEdit(for item: CarouselItem) -> Bool {
        isPhotoEditingOffered && PhotoEditSource(item: item) != nil
    }

    /// Opens the sheet for `source`. Its result can only be saved or put in this chat's message box as a draft.
    @discardableResult
    public func editPhotoWithAI(_ source: PhotoEditSource) -> Bool {
        guard isPhotoEditingOffered, let backend = photoEditBackend else { return false }
        photoEdit?.cancel()
        photoEdit = PhotoEditModel(
            source: source,
            backend: backend,
            draftIntoMessage: { [weak self] file, room in
                self?.composer.placeDraft(text: nil, attachment: file, in: room) ?? false
            },
            openAISettings: { [weak self] kind in self?.onOpenPhotoEditingSettings(kind) }
        )
        return true
    }

    public func editPhotoWithAI(messageID: String, from source: MessageSource = .chat) {
        guard let message = self.message(messageID, from: source), let photo = PhotoEditSource(message: message)
        else { return }
        editPhotoWithAI(photo)
    }

    public func closePhotoEdit() {
        photoEdit?.cancel()
        photoEdit = nil
    }
}

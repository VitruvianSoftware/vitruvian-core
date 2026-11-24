// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The inline tools offered when expanding the composer's `+` button, in display order.
public enum ComposerToolKind: String, CaseIterable, Equatable, Hashable, Sendable, Identifiable {
    case attachFile
    case photo
    case gif
    case sticker
    case voiceNote
    case sendLater
    case poll
    case location
    case ai

    public var id: String { rawValue }

    public var accessibilityIdentifier: String {
        "composer.tool.\(rawValue)"
    }
}

/// One visible entry in the composer's expanded tool row.
public struct ComposerToolItem: Equatable, Sendable, Identifiable {
    public let kind: ComposerToolKind
    public let isEnabled: Bool
    public let disabledReason: String?

    public var id: ComposerToolKind { kind }

    public init(kind: ComposerToolKind, isEnabled: Bool, disabledReason: String? = nil) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

/// Sizing rules for the composer's inline tool row: the text field keeps its room and the row (which scrolls
/// sideways) gets only what is left.
public enum ComposerToolRowMetrics {
    /// The width the text itself keeps while the tool row is open, whenever the window allows.
    public static let fieldMinimumWidth: CGFloat = 160
    /// The narrowest the text ever gets (a very narrow pane): below this the row gives way, not the text.
    public static let fieldHardMinimumWidth: CGFloat = 100
    /// The least the open row shows (two buttons) so its tools stay reachable by scrolling.
    public static let minimumRowWidth: CGFloat = 64
    public static let toolButtonWidth: CGFloat = 28
    public static let toolSpacing: CGFloat = 2

    /// The width of `count` tool buttons side by side, before any padding.
    public static func toolsWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * toolButtonWidth + CGFloat(count - 1) * toolSpacing
    }

    /// The width the open tool row may take, in a container `container` wide beside a `plus`-wide button with
    /// `gap`s around the row.
    ///
    /// `fieldMinimum` is the whole field's width when its text is at `fieldHardMinimumWidth`. The row takes all
    /// of `natural` when it fits; otherwise what is left once the text has `fieldMinimumWidth`; and in a very
    /// narrow container it keeps `minimumRowWidth` by squeezing the text down to its hard minimum, never further.
    /// Never negative.
    public static func rowWidth(natural: CGFloat, container: CGFloat, plus: CGFloat, fieldMinimum: CGFloat,
                                gap: CGFloat) -> CGFloat {
        let leftAfterHardMinimum = container - plus - 2 * gap - fieldMinimum
        let leftAfterComfortableMinimum = leftAfterHardMinimum - (fieldMinimumWidth - fieldHardMinimumWidth)
        let floor = min(natural, minimumRowWidth)
        return max(0, min(natural, max(leftAfterComfortableMinimum, min(floor, leftAfterHardMinimum))))
    }
}

/// Motion rules for opening and closing the composer's inline tool row.
public enum ComposerToolRowMotion {
    /// Duration of the slide/rotation or Reduce Motion cross-fade (180 ms, within 160–200 ms).
    public static let duration: TimeInterval = 0.18

    public static func usesSlideAndRotation(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// The text field glides aside only with motion; under Reduce Motion it snaps and the row cross-fades.
    public static func fieldGlides(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    public static func plusRotationDegrees(isOpen: Bool, reduceMotion: Bool) -> Double {
        (!reduceMotion && isOpen) ? 45 : 0
    }
}

/// Visual state of the composer's always-visible circular send button.
public enum ComposerSendButtonAppearance: Equatable, Sendable {
    case disabledNeutral
    case activeAccent

    public enum FillStyle: Equatable, Sendable {
        case quietGray
        case solidAccent
    }

    public enum ArrowStyle: Equatable, Sendable {
        case muted
        case white
    }

    /// Duration of the colour ease between quiet grey and solid accent (0.12 s).
    public static let colorEaseDuration: TimeInterval = 0.12

    public static func forComposer(canSend: Bool) -> Self {
        canSend ? .activeAccent : .disabledNeutral
    }

    public var fillStyle: FillStyle {
        self == .activeAccent ? .solidAccent : .quietGray
    }

    public var arrowStyle: ArrowStyle {
        self == .activeAccent ? .white : .muted
    }

    public var fillOpacity: Double {
        self == .activeAccent ? 1.0 : 0.24
    }

    public static func colorAnimationDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : colorEaseDuration
    }
}

/// What pressing Tab or Shift-Tab does inside the composer's text box.
public enum TabKeyAction: Equatable, Sendable {
    case acceptAutocomplete
    case focusNext
    case focusPrevious
    case insertLiteralTab
}

extension ChatFeatures {
    /// Attach and Photo show unless the network explicitly says it cannot take them: no feature data
    /// (nil) means shown, as it always was for the inline buttons.
    public var supportsFileSendForComposer: Bool {
        fileFeatures?.supported != false
    }

    public var supportsImageSendForComposer: Bool {
        imageFeatures?.supported != false
    }

    public var supportsGIFSendForComposer: Bool {
        source == .none ? (gifFeatures?.supported ?? true) : gif.supported
    }

    public var supportsVoiceSendForComposer: Bool {
        voiceFeatures?.supported != false
    }

    public var supportsPollCreateForComposer: Bool {
        poll != nil
    }

    public var supportsStickerSendForComposer: Bool {
        source == .none ? true : sticker.supported
    }

    public var supportsLocationShareForComposer: Bool {
        locationSupported
    }
}

extension ComposerModel {
    /// Decides how Tab / Shift-Tab / Option-Tab behaves in the composer text box.
    /// Option-Tab inserts a literal tab; Shift-Tab moves focus backward; plain Tab accepts an open
    /// mention/emoji/quick-reply autocomplete suggestion or otherwise moves focus forward.
    public nonisolated static func action(
        forTab modifiers: KeyModifiers,
        isBacktab: Bool = false,
        ignoresFieldEditor: Bool = false,
        hasOpenAutocomplete: Bool = false
    ) -> TabKeyAction {
        if ignoresFieldEditor || modifiers.contains(.option) {
            return .insertLiteralTab
        }
        if isBacktab || modifiers.contains(.shift) {
            return .focusPrevious
        }
        if hasOpenAutocomplete {
            return .acceptAutocomplete
        }
        return .focusNext
    }

    public var sendButtonAppearance: ComposerSendButtonAppearance {
        .forComposer(canSend: canSend)
    }

    /// Why Send Later is unavailable for the current draft when the chat otherwise offers Send Later,
    /// or nil when Send Later can be used (or when the room is locked/unselected).
    public var sendLaterDisabledReason: String? {
        let locked = isLocked || hotkeyDispatcher?.lifecycle.isLocked == true
        guard !locked, roomID != nil else { return nil }
        if !entitlement.isEntitled(.sendLater) {
            return String(localized: "Available with a plan")
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Write a message first")
        }
        if !attachments.isEmpty || pendingGIF != nil {
            return String(localized: "Send Later works with text messages only")
        }
        return nil
    }

    /// Tools shown in the expanded `+` tool row in exact order. Tools unsupported by the active
    /// chat/network are omitted; tools that require prerequisites (like Send Later on an empty draft)
    /// remain visible with `isEnabled == false` and a human-readable `disabledReason`.
    public func toolRowItems(offersSendLater: Bool = true, offersPoll: Bool = true) -> [ComposerToolItem] {
        let locked = isLocked || hotkeyDispatcher?.lifecycle.isLocked == true
        let hasRoom = roomID != nil
        let editing: Bool = {
            if case .editing = mode { return true }
            return false
        }()
        let inThread: Bool = {
            if case .thread = mode { return true }
            return false
        }()

        var items: [ComposerToolItem] = []

        if !editing, features.supportsFileSendForComposer {
            items.append(ComposerToolItem(kind: .attachFile, isEnabled: hasRoom && !locked))
        }
        if !editing, features.supportsImageSendForComposer {
            items.append(ComposerToolItem(kind: .photo, isEnabled: hasRoom && !locked))
        }
        if !editing, features.supportsGIFSendForComposer {
            items.append(ComposerToolItem(kind: .gif, isEnabled: canSendGIF && !locked))
        }
        if !editing, features.supportsStickerSendForComposer {
            items.append(ComposerToolItem(kind: .sticker, isEnabled: canSendSticker && !locked))
        }
        if !editing, features.supportsVoiceSendForComposer {
            items.append(ComposerToolItem(kind: .voiceNote, isEnabled: hasRoom && !locked))
        }
        if !editing, !inThread, offersSendLater, preferences?.showsSendLaterInPlusMenu ?? true {
            let reason = sendLaterDisabledReason
            let enabled = !locked && hasRoom && reason == nil && canSchedule
            items.append(ComposerToolItem(kind: .sendLater, isEnabled: enabled, disabledReason: reason))
        }
        if !editing, !inThread, offersPoll, features.supportsPollCreateForComposer {
            items.append(ComposerToolItem(kind: .poll, isEnabled: hasRoom && !locked))
        }
        if !editing, features.supportsLocationShareForComposer {
            items.append(ComposerToolItem(kind: .location, isEnabled: hasRoom && !locked))
        }
        items.append(ComposerToolItem(kind: .ai, isEnabled: hasRoom && !locked))

        return items
    }
}

// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A poll being written in the "New Poll" window (01 §6): its question, its options and whether people may choose
/// more than one. What it says is wrong is what the engine would refuse (actions.CreatePoll), in Courier's words, so
/// a poll that can't go is never sent.
///
/// The engine trims the question and each option, counts characters as Unicode scalars (Go's runes), allows the
/// question 1 to `maxQuestionLength` of them, wants 2 to the chat's `max_options` options of 1 to its
/// `option_max_length` each, and refuses two options that are the same ignoring case. An empty option row (the
/// "Add an option" row, or one cleared) isn't an option: it is left out of what is sent.
public struct PollDraft: Equatable, Sendable {
    /// The longest question the engine takes, in characters (actions.MaxPollQuestion).
    public static let maxQuestionLength = 300

    public var question = ""
    /// The option rows, as typed; the window starts with two empty ones.
    public var options = ["", ""]
    /// "Allow multiple answers".
    public var multiple = false

    public init() {}

    /// The question as it is sent.
    public var sendableQuestion: String { question.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The options as they are sent: trimmed, without the empty rows, in order.
    public var sendableOptions: [String] {
        options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The rows (indexes into `options`) that repeat an earlier option, ignoring case: each says "This option
    /// already exists".
    public var duplicates: [Int] {
        var seen: [String] = []
        var repeated: [Int] = []
        for (index, option) in options.enumerated() {
            let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.contains(where: { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
                repeated.append(index)
            } else {
                seen.append(trimmed)
            }
        }
        return repeated
    }

    /// As many options as the chat takes are written: the window offers no more ("You have added the maximum number
    /// of options" shows under them). Not a problem: the poll can still be sent.
    public func isAtMaximum(in features: PollFeatures) -> Bool {
        features.maxOptions > 0 && sendableOptions.count >= features.maxOptions
    }

    /// What stops the poll from being sent in a chat with `features`, in the window's order; empty means it can be
    /// sent.
    public func problems(in features: PollFeatures) -> [String] {
        var found: [String] = []
        let question = sendableQuestion
        if question.isEmpty {
            found.append(String(localized: "Ask a question"))
        } else if question.unicodeScalars.count > Self.maxQuestionLength {
            found.append(String(localized: "Questions can be up to \(Self.maxQuestionLength) characters"))
        }
        let options = sendableOptions
        if options.count < 2 {
            found.append(String(localized: "Add at least two options"))
        }
        if !duplicates.isEmpty {
            found.append(String(localized: "This option already exists"))
        }
        if features.maxOptions > 0, options.count > features.maxOptions {
            found.append(String(localized: "You have added the maximum number of options"))
        }
        if features.optionMaxLength > 0, options.contains(where: { $0.unicodeScalars.count > features.optionMaxLength }) {
            found.append(String(localized: "Options can be up to \(features.optionMaxLength) characters"))
        }
        return found
    }
}

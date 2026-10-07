// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The real emoji rows and the real run recorder, over settings in a
/// disposable domain. Typing is recorded; no keyboard events are sent.
enum CommandBarEmojiContract {
    static var typed: [String] = []

    /// The field the recorder reads, and the bar's own close, which wipes it.
    final class Bar {
        var field = CommandBarRunRecorder.Field(mode: .search, query: ":thumb", savedQuery: "",
                                                queryBeforeCompletion: nil, selectedText: "", isVisible: true)
        let defaults: Foundation.UserDefaults
        private(set) lazy var runs = CommandBarRunRecorder(host: .init(
            field: { [unowned self] in self.field },
            hide: { [unowned self] in
                self.closing.append("hide")
                self.field.isVisible = false
                self.field.query = ""
                self.field.savedQuery = ""
                self.field.selectedText = ""
            },
            type: { CommandBarEmojiContract.typed.append($0) },
            defaults: defaults,
            closingForRun: { [unowned self] in self.closing.append("farewell") },
            closedForRun: { [unowned self] in self.closing.append("cheer") }))
        /// What closing the bar for a run did, in order: the companion's
        /// glad farewell, the close, and its hop back in the island.
        var closing: [String] = []

        init(_ defaults: Foundation.UserDefaults) { self.defaults = defaults }
    }

    static func emojiRows(_ defaults: Foundation.UserDefaults, accessible: Bool = true) -> [CommandBarEntry] {
        CommandBarCatalog.emojiEntries(bar: .enUS, defaults: defaults, accessible: accessible,
                                       type: { typed.append($0) })
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.command-bar-emoji"
        let defaults = Foundation.UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            typed = []
        }
        let tones = CommandBarEmoji.SkinTone.allCases
        suite.expect(!CommandBarEmoji.acceptsSkinTone("👪")
                     && tones.allSatisfy { CommandBarEmoji.applying($0, to: "👪") == "👪" },
                     "family stays unchanged instead of offering unsupported skin tones")
        suite.expect(["👍", "☝️", "🤝", "👫", "👬", "👭", "💏", "💑"].allSatisfy {
            CommandBarEmoji.acceptsSkinTone($0)
        }, "excluding family preserves supported single-person and multi-person tones")

        // Exercise actual row construction, not just the helper used for IDs.
        let originalIDs = CommandBarEmoji.emoji.map { "emoji." + $0.identity }
        let thumbID = "emoji.👍"
        defaults.set(CommandBarPreferences.encodePins([thumbID]), forKey: DefaultsKey.commandBarPins)
        let pins = defaults.string(forKey: DefaultsKey.commandBarPins)
        for tone in tones {
            defaults.set(tone.rawValue, forKey: DefaultsKey.commandBarEmojiSkinTone)
            let rows = emojiRows(defaults)
            suite.expect(rows.map(\.id) == originalIDs,
                         "\(tone.rawValue) keeps every stored row identity")
            typed = []
            rows.forEach { $0.run(nil) }
            suite.expect(zip(rows, typed).allSatisfy { $0.title.hasPrefix($1 + "  ") },
                         "\(tone.rawValue) inserts exactly the emoji shown by each row")
            let family = rows.first { $0.id == "emoji.👪" }!
            suite.expect(Bar(defaults).runs.skinToneActions(for: family).isEmpty,
                         "family has no unsupported alternate actions")
            let thumb = rows.first { $0.id == thumbID }!
            let bar = Bar(defaults)
            let actions = bar.runs.skinToneActions(for: thumb)
            suite.expect(actions.count == 5 && Set(actions.map(\.title)).count == 5,
                         "each default offers the other five distinct tones")
            suite.expect(!actions.contains { $0.title == CommandBarEmoji.applying(tone, to: "👍") },
                         "the current default is not duplicated as an alternate")
            for action in actions {
                defaults.removeObject(forKey: DefaultsKey.commandBarUsage)
                defaults.removeObject(forKey: DefaultsKey.commandBarQueryHabits)
                bar.runs.queryHabitStore.forgetAll()
                bar.field.mode = .actions(entryID: thumbID)
                bar.field.savedQuery = ":thumb"
                bar.field.query = ""
                bar.field.isVisible = true
                action.run()
                let usage = CommandBarUsage.decode(defaults.string(forKey: DefaultsKey.commandBarUsage))
                suite.expect(usage[thumbID]?.count == 1 && usage.count == 1,
                             "a one-off tone records exactly one use under the original emoji")
                suite.expect(bar.runs.queryMemory.boost(query: "thumb", id: thumbID) > 0,
                             "a one-off tone learns the search saved before opening actions")
                suite.expect(CommandBarQueryHabits.boost(
                    for: thumbID,
                    preparedQuery: CommandBarQueryHabits.prepare("thumb"),
                    store: bar.runs.queryHabitStore.store, now: Date().timeIntervalSince1970) > 0,
                             "a one-off tone learns searches in memory for the current session")
                suite.expect(defaults.object(forKey: DefaultsKey.commandBarQueryHabits) == nil,
                             "a one-off tone never persists query learning in preferences")
                suite.expect(Bar(defaults).runs.queryHabitStore.store.isEmpty,
                             "a new service starts without the previous session's query learning")
                suite.expect(!bar.field.isVisible && typed.last == action.title,
                             "the one-off action closes the bar and inserts the chosen tone")
                suite.expect(defaults.string(forKey: DefaultsKey.commandBarEmojiSkinTone) == tone.rawValue
                             && defaults.string(forKey: DefaultsKey.commandBarPins) == pins,
                             "one-off insertion preserves the default tone and stored pins")
            }
            // A different preference may change after the one-off insertion.
            defaults.set("emoji", forKey: DefaultsKey.commandBarDisabledSources)
            defaults.set("", forKey: DefaultsKey.commandBarDisabledSources)
            let reopened = emojiRows(defaults).first { $0.id == thumbID }!
            reopened.run(nil)
            suite.expect(typed.last == CommandBarEmoji.applying(tone, to: "👍"),
                         "reopening after another preference change still uses the saved default")
        }

        defaults.removeObject(forKey: DefaultsKey.commandBarUsage)
        let row = emojiRows(defaults).first { $0.id == thumbID }!
        let normal = Bar(defaults)
        normal.field.query = " :thumb "
        normal.field.selectedText = "the selection"
        typed = []
        normal.runs.finish(row, value: nil)
        suite.expect(CommandBarUsage.decode(defaults.string(forKey: DefaultsKey.commandBarUsage))[thumbID]?.count == 1
                     && normal.runs.usage[thumbID]?.count == 1
                     && normal.runs.queryMemory.boost(query: "thumb", id: thumbID) == 1
                     && normal.runs.queryMemoryStep == 1
                     && !normal.field.isVisible && typed == [CommandBarEmoji.applying(.dark, to: "👍")],
                     "normal insertion still records usage and learning once before closing")
        suite.expect(normal.runs.queryWhenRun == " :thumb " && normal.runs.selectionWhenRun == "the selection",
                     "the field and the selection are handed over before closing wipes them")
        suite.expect(normal.closing == ["farewell", "hide", "cheer"],
                     "a command run from the bar sends the companion home smiling, to hop for it")
        normal.runs.forgetRun()
        suite.expect(normal.runs.queryWhenRun.isEmpty && normal.runs.selectionWhenRun.isEmpty,
                     "a new opening starts with nothing handed over")
        let shortcut = Bar(defaults)
        shortcut.field.isVisible = false
        shortcut.runs.finish(row, value: nil)
        suite.expect(shortcut.runs.queryMemory == CommandBarQueryMemory()
                     && CommandBarUsage.decode(defaults.string(forKey: DefaultsKey.commandBarUsage))[thumbID]?.count == 2,
                     "a hidden shortcut counts usage without learning an unseen search")
        let argument = Bar(defaults)
        argument.field.mode = .argument(entryID: thumbID)
        argument.field.savedQuery = "original"
        argument.field.query = "42"
        argument.runs.finish(row, value: 42)
        suite.expect(argument.runs.queryMemory.boost(query: "original", id: thumbID) == 1
                     && argument.runs.queryMemory.boost(query: "42", id: thumbID) == 0,
                     "argument execution keeps learning from the saved search")
        var received: [Int?] = []
        let numbered = CommandBarEntry(id: "test.numbered", title: "Numbered", subtitle: "", icon: .symbol("number"),
                                       run: { received.append($0) })
        argument.runs.finish(numbered, value: 42)
        suite.expect(received == [42], "the row runs once, with the number it was given")
        let completed = Bar(defaults)
        completed.field.query = "thumbs up"
        completed.field.queryBeforeCompletion = "thu"
        completed.runs.finish(row, value: nil)
        suite.expect(completed.runs.queryMemory.boost(query: "thu", id: thumbID) == 1
                     && completed.runs.queryMemory.boost(query: "thumbs up", id: thumbID) == 0,
                     "a completed search learns what was typed, not what completion filled in")
        let transient = CommandBarEntry(id: row.id, title: row.title, subtitle: row.subtitle, icon: row.icon,
                                        countsUsage: false, keepsBarOpen: true, run: row.run)
        let before = defaults.string(forKey: DefaultsKey.commandBarUsage)
        let open = Bar(defaults)
        typed = []
        open.runs.finish(transient, value: nil)
        suite.expect(open.closing.isEmpty, "a command that keeps the bar open sends the companion nowhere")
        suite.expect(open.field.isVisible && open.runs.queryMemoryStep == 0 && open.runs.usage.isEmpty
                     && open.runs.queryHabitStore.store.isEmpty
                     && defaults.string(forKey: DefaultsKey.commandBarUsage) == before && typed.count == 1,
                     "non-learning rows and commands that keep the bar open retain their behavior")
        suite.expect(emojiRows(defaults, accessible: false).allSatisfy {
            if case .needsPermission = $0.trouble { return true } else { return false }
        } && emojiRows(defaults).allSatisfy { $0.trouble == nil },
                     "without Accessibility every emoji row says so")

        let payload = SettingsBackupSupport.payload(appVersion: "test", valueFor: defaults.object(forKey:))
        let restored = SettingsBackupSupport.sanitizedSettings(from: payload)
        suite.expect(restored?[DefaultsKey.commandBarEmojiSkinTone] as? String == "dark",
                     "the chosen tone survives backup export and restore validation")
    }
}

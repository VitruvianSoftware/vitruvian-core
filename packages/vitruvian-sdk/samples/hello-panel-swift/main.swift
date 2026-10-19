// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// A tool that draws, written with the kit. Its page in the island is a
// counter with a button and a field; its page in Settings is one switch.
// The app draws both, from the blocks this program sends. The command
// `addOne` counts too, and sends the open page again.
//
// It also shows a status, the small mark the app draws on the closed
// island, and its island page has a pop-up menu to pick it with. Both are
// newer than protocol 2 itself, so the tool asks the app what it has. An
// app that draws a status's words (3.50 and later) gets a second menu: the
// count, or a count of seconds, beside the mark.

import Foundation
import VitruvianToolKit

/// What the tool knows. One thread reads the link, so one object is enough.
final class Counter {
    var count = 0
    var name = ""
    var byTwo = false
    /// What the tool shows on the closed island.
    var status = StatusState.ok
    /// What it says beside the mark: none, the count, or seconds.
    var words = "none"
    /// When "Seconds" was picked: the app counts from here.
    var since = Date()

    var step: Int { byTwo ? 2 : 1 }

    /// The island page: what it says now.
    func page(_ app: App) -> UITree {
        UITree {
            heading("Counter")
            text("Pressed \(count) times")
            button("add", "Add \(step)", style: .prominent)
            field("name", title: "Your name", value: name, placeholder: "Type it and press Return")
            if !name.isEmpty { text("Hello, \(name)", style: .secondary) }
            statusPicker(app)
            if app.supports(.statusActivity) { wordsPicker() }
        }
    }

    /// What may stand beside the mark, in the second menu.
    static let wordsOptions: [(value: String, title: String)] = [
        ("none", "None"), ("count", "The count"), ("seconds", "Seconds"),
    ]

    /// The words beside the mark, to pick. It starts at None, so the
    /// sample does not take the place of what the person reads there until
    /// they ask.
    func wordsPicker() -> UIBlock {
        let options = Counter.wordsOptions.map { UIChoiceOption(value: $0.value, title: .plain($0.title)) }
        return choice("words", title: "Words on the closed island", value: words, options: options)
    }

    /// What each status is called in the menu, and what it says to VoiceOver.
    static let statuses: [(state: StatusState, title: String, says: String?)] = [
        (.none, "None", nil),
        (.ok, "OK", "The counter is fine"),
        (.busy, "Busy", "The counter is counting"),
        (.attention, "Needs attention", "The counter wants a look"),
        (.failure, "Failed", "The counter failed"),
    ]

    /// The status, to pick: a pop-up menu where the app has one. An app
    /// before 3.48 draws a `choice` as plain words nobody can change, so
    /// there it is a field to type the word in.
    func statusPicker(_ app: App) -> UIBlock {
        guard app.supports(.choice) else {
            return field("status", title: "Status: none, ok, busy, attention or failure", value: status.rawValue)
        }
        let options = Counter.statuses.map { UIChoiceOption(value: $0.state.rawValue, title: .plain($0.title)) }
        return choice("status", title: "Status on the closed island", value: status.rawValue, options: options)
    }

    /// Sets the mark on the closed island. Nothing is sent to an app that
    /// has no status, and the call says so.
    func showStatus(_ app: App) throws {
        let says = Counter.statuses.first { $0.state == status }?.says
        // An app before 3.50 is sent the status without the words.
        try app.status(status, text: says.map(UIText.plain),
                       activity: words == "count" ? .plain("\(count)") : nil,
                       since: words == "seconds" ? since : nil)
    }

    /// The Settings page. An app that has sections draws the switch's help
    /// under it, and lists the heading to jump to; an older one is sent the
    /// same words as a caption after the switch.
    func settings(_ app: App) -> UITree {
        let help: UIText = "The island's counter adds this much each time."
        guard app.supports(.sections) else {
            return UITree {
                toggle("byTwo", "Count by two", isOn: byTwo)
                text(help, style: .caption)
            }
        }
        return UITree {
            heading("Counting", section: true)
            toggle("byTwo", "Count by two", isOn: byTwo, help: help)
        }
    }
}

let tool = Tool(version: "0.1.0")
let counter = Counter()

let island = tool.panel("counter", onOpen: { app, _ in counter.page(app) }, onEvent: { app, panel, event in
    switch event.block {
    case "add"?:
        counter.count += counter.step
        try panel.badge(count: counter.count)
        if counter.words == "count" { try counter.showStatus(app) }
    case "name"?:
        counter.name = event.text ?? counter.name
    case "status"?:
        // A pick is the event `change`, as leaving a field changed is.
        guard let picked = event.text.flatMap(StatusState.init(rawValue:)) else { return .keep }
        counter.status = picked
        try counter.showStatus(app)
    case "words"?:
        guard let picked = event.text, Counter.wordsOptions.contains(where: { $0.value == picked }) else {
            return .keep
        }
        counter.words = picked
        if picked == "seconds" { counter.since = Date() }
        try counter.showStatus(app)
    default:
        return .keep
    }
    return .page(counter.page(app))
})

tool.panel("settings", onOpen: { app, _ in counter.settings(app) }, onEvent: { app, _, event in
    guard event.block == "byTwo", let isOn = event.isOn else { return .keep }
    counter.byTwo = isOn
    return .page(counter.settings(app))
})

tool.command("addOne") { app in
    counter.count += counter.step
    island.render(counter.page(app))
    if counter.words == "count" { try counter.showStatus(app) }
}

// The status goes when the program ends, so it is set each time the program
// starts. The app may refuse any request: the tool carries on without.
tool.onStart = { app in
    do {
        try counter.showStatus(app)
    } catch {
        app.log("no status: \(error)")
    }
}

tool.run()

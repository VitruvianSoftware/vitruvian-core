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

import VitruvianToolKit

/// What the tool knows. One thread reads the link, so one object is enough.
final class Counter {
    var count = 0
    var name = ""
    var byTwo = false

    var step: Int { byTwo ? 2 : 1 }

    /// The island page: what it says now.
    func page() -> UITree {
        UITree {
            heading("Counter")
            text("Pressed \(count) times")
            button("add", "Add \(step)", style: .prominent)
            field("name", title: "Your name", value: name, placeholder: "Type it and press Return")
            if !name.isEmpty { text("Hello, \(name)", style: .secondary) }
        }
    }

    /// The Settings page.
    func settings() -> UITree {
        UITree {
            toggle("byTwo", "Count by two", isOn: byTwo)
            text("The island's counter adds this much each time.", style: .caption)
        }
    }
}

let tool = Tool(version: "0.1.0")
let counter = Counter()

let island = tool.panel("counter", onOpen: { _, _ in counter.page() }, onEvent: { _, panel, event in
    switch event.block {
    case "add"?:
        counter.count += counter.step
        try panel.badge(count: counter.count)
    case "name"?:
        counter.name = event.text ?? counter.name
    default:
        return .keep
    }
    return .page(counter.page())
})

tool.panel("settings", onOpen: { _, _ in counter.settings() }, onEvent: { _, _, event in
    guard event.block == "byTwo", let isOn = event.isOn else { return .keep }
    counter.byTwo = isOn
    return .page(counter.settings())
})

tool.command("addOne") { _ in
    counter.count += counter.step
    island.render(counter.page())
}

tool.run()

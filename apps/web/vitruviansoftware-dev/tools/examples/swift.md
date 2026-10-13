---
layout: tools
title: "An example in Swift"
description: "A tool written with the Swift kit: it says hello, and counts with a preference the person can change in Settings."
permalink: /tools/examples/swift/
source: packages/vitruvian-sdk/samples/hello-swift
---
{%- comment -%}
  Written by tools/sync-site-tools/sync.py from packages/vitruvian-sdk.
  Do not edit it: change the source, then run
    bazel run //tools/sync-site-tools:sync
{%- endcomment -%}
{% raw %}
`vitruvian-tool init <folder> --template swift` starts a new tool from a copy of this one, as a Swift package that depends on the published SDK. Its `build.sh` builds the program into `tool/bin/tool`, and `tool/` is the folder you add to Vitruvian.

This is [`samples/hello-swift`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/hello-swift) of the SDK, as it is. The conformance script runs it in the SDK's tests.

`vitruvian-tool.json`:

```json
{
  "id": "dev.vitruvian.samples.hello-swift",
  "name": { "en": "Hello, in Swift" },
  "description": { "en": "Says hello, and counts one more each time." },
  "version": "0.1.0",
  "protocol": "1",
  "publisher": "VitruvianSoftware",
  "license": "MIT",
  "icon": "swift",
  "uses": ["notify", "storage"],
  "contributes": {
    "commands": [
      {
        "id": "hello",
        "title": { "en": "Say hello from Swift" },
        "icon": "hand.wave",
        "surfaces": ["commandBar", "radial", "quickPanel", "shortcut"]
      },
      {
        "id": "count",
        "title": { "en": "Count one more" },
        "icon": "number",
        "surfaces": ["commandBar"]
      }
    ]
  },
  "preferences": [
    {
      "id": "count",
      "title": { "en": "Counted so far" },
      "type": "integer",
      "default": 0
    },
    {
      "id": "step",
      "title": { "en": "Count by" },
      "type": "string",
      "default": "1",
      "options": [
        { "value": "1", "title": { "en": "One" } },
        { "value": "2", "title": { "en": "Two" } },
        { "value": "5", "title": { "en": "Five" } }
      ]
    }
  ],
  "activation": ["onCommand"],
  "runtime": { "kind": "external", "exec": "bin/tool" }
}
```

`main.swift`:

```swift
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

// A tool written with the kit. It has two commands: `hello` asks the app to
// show a short message, and `count` keeps a number in a preference its
// manifest declares, counting by what another preference says. That one
// has `options`, so the app draws it as a pop-up menu in the tool's detail. `vitruvian-tool init --template swift` starts a new
// tool from this file.

import VitruvianToolKit

let tool = Tool(version: "0.1.0")

tool.command("hello") { app in
    try app.showMessage("Hello from a Swift tool", icon: "hand.wave")
}

tool.command("count") { app in
    // The step is saved as text. The options are how the app draws the
    // setting, not a rule on what is saved: an app before 3.48 draws a text
    // field, so anything may be there. What is no number counts as one.
    let step = Double(try app.value("step").stringValue ?? "") ?? 1
    let next = (try app.value("count").numberValue ?? 0) + step
    try app.setValue(.number(next), for: "count")
    try app.showMessage("Counted to \(Int(next))", icon: "number")
}

tool.run()
```
{% endraw %}

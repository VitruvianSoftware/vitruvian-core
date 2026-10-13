---
layout: tools
title: "An example in Go"
description: "A tool written with the Go kit: it says hello, and counts with a preference the person can change in Settings."
permalink: /tools/examples/go/
source: packages/vitruvian-sdk/samples/hello-go
---
{%- comment -%}
  Written by tools/sync-site-tools/sync.py from packages/vitruvian-sdk.
  Do not edit it: change the source, then run
    bazel run //tools/sync-site-tools:sync
{%- endcomment -%}
{% raw %}
`vitruvian-tool init <folder> --template go` starts a new tool from a copy of this one, as a Go module that requires the published kit. Its `build.sh` builds the program into `tool/bin/tool`, and `tool/` is the folder you add to Vitruvian.

This is [`samples/hello-go`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/hello-go) of the SDK, as it is. The conformance script runs it in the SDK's tests.

`vitruvian-tool.json`:

```json
{
  "id": "dev.vitruvian.samples.hello-go",
  "name": { "en": "Hello, in Go" },
  "description": { "en": "Says hello, and counts one more each time." },
  "version": "0.1.0",
  "protocol": "1",
  "publisher": "VitruvianSoftware",
  "license": "MIT",
  "icon": "chevron.left.forwardslash.chevron.right",
  "uses": ["notify", "storage"],
  "contributes": {
    "commands": [
      {
        "id": "hello",
        "title": { "en": "Say hello from Go" },
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
    }
  ],
  "activation": ["onCommand"],
  "runtime": { "kind": "external", "exec": "bin/tool" }
}
```

`main.go`:

```go
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

// A tool written with the Go kit. It has two commands: `hello` asks the app
// to show a short message, and `count` keeps a number in a preference its
// manifest declares. `vitruvian-tool init --template go` starts a new tool
// from this file.
package main

import (
	"context"
	"fmt"

	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit"
)

func main() {
	tool := toolkit.New("0.1.0")

	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		return app.Notify.HUD("Hello from a Go tool", "hand.wave")
	})

	tool.Command("count", func(ctx context.Context, app *toolkit.App) error {
		saved, err := app.Storage.Get("count")
		if err != nil {
			return err
		}
		next, _ := saved.(float64)
		next++
		if err := app.Storage.Set("count", next); err != nil {
			return err
		}
		return app.Notify.HUD(fmt.Sprintf("Counted to %d", int(next)), "number")
	})

	tool.Run()
}
```
{% endraw %}

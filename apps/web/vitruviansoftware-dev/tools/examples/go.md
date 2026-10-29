---
layout: tools
title: "A tool in Go"
description: "A tool written with the Go kit: it says hello, and counts with a preference the person can change in Settings."
permalink: /tools/examples/go/
source: packages/vitruvian-sdk/samples/hello-go/README.md
---
{%- comment -%}
  Written by tools/sync-site-tools from packages/vitruvian-sdk.
  Do not edit it: change the source, then run
    bazel run //tools/sync-site-tools:sync
{%- endcomment -%}
{% raw %}
A tool with two commands, written with the Go kit: `hello` shows a short
message, and `count` keeps a number in a preference and shows it. It is one
file, with nothing outside Go's standard library.

```sh
vitruvian-tool init ~/hello-go --id com.you.hello-go --name "Hello" --publisher "You" --template go
~/hello-go/build.sh
vitruvian-tool run ~/hello-go/tool --command hello --command count
```

The program, `main.go`:

```go
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

`build.sh` builds the program into `tool/bin/tool`, and `tool/` is the
folder you add in Vitruvian: Settings › Extensions, "Add from Folder…".

## Drawing

[`samples/hello-panel-go`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/hello-panel-go) is a tool of protocol 2, written
with the same kit: a counter the app draws in the island from blocks the
tool sends. The guide's "Drawing" says how. Its page is `ui.Tree` of its
blocks, with package `ui` of the kit:

```go
// page is the island page: what it says now.
func (c *counter) page(app *toolkit.App) toolkit.UITree {
	return ui.Tree(
		ui.Heading("Counter"),
		ui.Text(fmt.Sprintf("Pressed %d times", c.count)),
		ui.Button("add", fmt.Sprintf("Add %d", c.step()), ui.ButtonOptions{Style: ui.Prominent}),
		ui.Field("name", ui.FieldOptions{Title: "Your name", Value: c.name, Placeholder: "Type it and press Return"}),
		ui.If(c.name != "", ui.Text("Hello, "+c.name, ui.TextOptions{Style: ui.Secondary})),
		c.statusPicker(app),
		ui.If(app.Supports(toolkit.FeatureStatusActivity), c.wordsPicker()),
	)
}
```
{% endraw %}

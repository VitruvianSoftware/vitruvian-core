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

// A tool that draws, written with the Go kit. Its page in the island is a
// counter with a button and a field; its page in Settings is one switch.
// The app draws both, from the blocks this program sends. The command
// `addOne` counts too, and sends the open page again.
package main

import (
	"context"
	"fmt"

	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit"
	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit/ui"
)

// counter is what the tool knows. One goroutine reads the link, so one
// value is enough.
type counter struct {
	count int
	name  string
	byTwo bool
}

func (c *counter) step() int {
	if c.byTwo {
		return 2
	}
	return 1
}

// page is the island page: what it says now.
func (c *counter) page() toolkit.UITree {
	return ui.Tree(
		ui.Heading("Counter"),
		ui.Text(fmt.Sprintf("Pressed %d times", c.count)),
		ui.Button("add", fmt.Sprintf("Add %d", c.step()), ui.ButtonOptions{Style: ui.Prominent}),
		ui.Field("name", ui.FieldOptions{Title: "Your name", Value: c.name, Placeholder: "Type it and press Return"}),
		ui.If(c.name != "", ui.Text("Hello, "+c.name, ui.TextOptions{Style: ui.Secondary})),
	)
}

// settings is the Settings page.
func (c *counter) settings() toolkit.UITree {
	return ui.Tree(
		ui.Toggle("byTwo", "Count by two", c.byTwo),
		ui.Text("The island's counter adds this much each time.", ui.TextOptions{Style: ui.Caption}),
	)
}

func main() {
	tool := toolkit.New("0.1.0")
	state := &counter{}

	island := tool.Panel("counter",
		func(app *toolkit.App, panel *toolkit.PanelHandle) (*toolkit.UITree, error) {
			page := state.page()
			return &page, nil
		},
		func(app *toolkit.App, panel *toolkit.PanelHandle, event toolkit.PanelEvent) (toolkit.PanelAnswer, error) {
			switch event.Block {
			case "add":
				state.count += state.step()
				if err := panel.Badge(state.count, false); err != nil {
					return toolkit.Keep(), err
				}
			case "name":
				if text, ok := event.Text(); ok {
					state.name = text
				}
			default:
				return toolkit.Keep(), nil
			}
			return toolkit.Page(state.page()), nil
		})

	tool.Panel("settings",
		func(app *toolkit.App, panel *toolkit.PanelHandle) (*toolkit.UITree, error) {
			page := state.settings()
			return &page, nil
		},
		func(app *toolkit.App, panel *toolkit.PanelHandle, event toolkit.PanelEvent) (toolkit.PanelAnswer, error) {
			isOn, ok := event.IsOn()
			if event.Block != "byTwo" || !ok {
				return toolkit.Keep(), nil
			}
			state.byTwo = isOn
			return toolkit.Page(state.settings()), nil
		})

	tool.Command("addOne", func(ctx context.Context, app *toolkit.App) error {
		state.count += state.step()
		island.Render(state.page())
		return nil
	})

	tool.Run()
}

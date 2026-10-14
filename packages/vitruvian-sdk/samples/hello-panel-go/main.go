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
//
// It also shows a status, the small mark the app draws on the closed
// island, and its island page has a pop-up menu to pick it with. Both are
// newer than protocol 2 itself, so the tool asks the app what it has. An
// app that draws a status's words (3.50 and later) gets a second menu: the
// count, or a count of seconds, beside the mark.
package main

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit"
	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit/ui"
)

// counter is what the tool knows. One goroutine reads the link, so one
// value is enough.
type counter struct {
	count int
	name  string
	byTwo bool
	// status is what the tool shows on the closed island.
	status string
	// words is what it says beside the mark: none, the count, or seconds;
	// since is when "Seconds" was picked, which the app counts from.
	words string
	since time.Time
}

// statuses is what each status is called in the menu, and what it says to
// VoiceOver.
var statuses = []struct{ state, title, says string }{
	{toolkit.StatusNone, "None", ""},
	{toolkit.StatusOK, "OK", "The counter is fine"},
	{toolkit.StatusBusy, "Busy", "The counter is counting"},
	{toolkit.StatusAttention, "Needs attention", "The counter wants a look"},
	{toolkit.StatusFailure, "Failed", "The counter failed"},
}

func (c *counter) step() int {
	if c.byTwo {
		return 2
	}
	return 1
}

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

// words is what may stand beside the mark, in the second menu.
var words = []toolkit.UIChoiceOption{
	{Value: "none", Title: "None"},
	{Value: "count", Title: "The count"},
	{Value: "seconds", Title: "Seconds"},
}

// wordsPicker is the words beside the mark, to pick. It starts at None, so
// the sample does not take the place of what the person reads there until
// they ask.
func (c *counter) wordsPicker() toolkit.UIBlock {
	return ui.Choice("words", c.words, words, ui.ChoiceOptions{Title: "Words on the closed island"})
}

// isWords is whether a word is one of the second menu's.
func isWords(word string) bool {
	for _, option := range words {
		if option.Value == word {
			return true
		}
	}
	return false
}

// statusPicker is the status, to pick: a pop-up menu where the app has one.
// An app before 3.48 draws a choice as plain words nobody can change, so
// there it is a field to type the word in.
func (c *counter) statusPicker(app *toolkit.App) toolkit.UIBlock {
	if !app.Supports(toolkit.FeatureChoice) {
		return ui.Field("status", ui.FieldOptions{Title: "Status: none, ok, busy, attention or failure", Value: c.status})
	}
	options := make([]toolkit.UIChoiceOption, 0, len(statuses))
	for _, status := range statuses {
		options = append(options, toolkit.UIChoiceOption{Value: status.state, Title: status.title})
	}
	return ui.Choice("status", c.status, options, ui.ChoiceOptions{Title: "Status on the closed island"})
}

// showStatus sets the mark on the closed island. Nothing is sent to an app
// that has no status, and the call says so.
func (c *counter) showStatus(app *toolkit.App) (bool, error) {
	options := toolkit.StatusOptions{}
	for _, status := range statuses {
		if status.state == c.status && status.says != "" {
			options.Text = status.says
		}
	}
	// An app before 3.50 is sent the status without the words.
	switch c.words {
	case "count":
		options.Activity = strconv.Itoa(c.count)
	case "seconds":
		options.Since = c.since
	}
	return app.UI.Status(c.status, options)
}

// isStatus is whether a word is one of the five a status may be.
func isStatus(word string) bool {
	for _, status := range statuses {
		if status.state == word {
			return true
		}
	}
	return false
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
	state := &counter{status: toolkit.StatusOK, words: "none"}

	island := tool.Panel("counter",
		func(app *toolkit.App, panel *toolkit.PanelHandle) (*toolkit.UITree, error) {
			page := state.page(app)
			return &page, nil
		},
		func(app *toolkit.App, panel *toolkit.PanelHandle, event toolkit.PanelEvent) (toolkit.PanelAnswer, error) {
			switch event.Block {
			case "add":
				state.count += state.step()
				if err := panel.Badge(state.count, false); err != nil {
					return toolkit.Keep(), err
				}
				if state.words == "count" {
					if _, err := state.showStatus(app); err != nil {
						return toolkit.Keep(), err
					}
				}
			case "name":
				if text, ok := event.Text(); ok {
					state.name = text
				}
			case "status":
				// A pick is the event change, as leaving a field changed is.
				picked, ok := event.Text()
				if !ok || !isStatus(picked) {
					return toolkit.Keep(), nil
				}
				state.status = picked
				if _, err := state.showStatus(app); err != nil {
					return toolkit.Keep(), err
				}
			case "words":
				picked, ok := event.Text()
				if !ok || !isWords(picked) {
					return toolkit.Keep(), nil
				}
				state.words = picked
				if picked == "seconds" {
					state.since = time.Now()
				}
				if _, err := state.showStatus(app); err != nil {
					return toolkit.Keep(), err
				}
			default:
				return toolkit.Keep(), nil
			}
			return toolkit.Page(state.page(app)), nil
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
		island.Render(state.page(app))
		if state.words == "count" {
			_, err := state.showStatus(app)
			return err
		}
		return nil
	})

	// The status goes when the program ends, so it is set each time the
	// program starts. The app may refuse any request: the tool carries on
	// without.
	tool.OnStart = func(app *toolkit.App) {
		if _, err := state.showStatus(app); err != nil {
			app.Log("no status: " + err.Error())
		}
	}

	tool.Run()
}

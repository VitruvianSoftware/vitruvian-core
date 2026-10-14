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

package toolkit_test

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"testing"
	"time"

	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit"
	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit/ui"
)

// A tool that draws: its panels opened, acted in, rendered to and closed,
// and a web panel's calls, against the same link of two buffers. These are
// the Swift kit's PanelTests, one for one.

func (b *bench) open(panel string, id int) *bench {
	return b.app(`{"jsonrpc":"2.0","id":` + strconv.Itoa(id) + `,"method":"ui/open","params":{"panel":"` + panel + `"}}`)
}

func (b *bench) tap(panel, block string, id int) *bench {
	return b.app(`{"jsonrpc":"2.0","id":` + strconv.Itoa(id) + `,"method":"ui/event","params":{"panel":"` + panel +
		`","block":"` + block + `","event":"tap"}}`)
}

func (b *bench) close(panel string) *bench {
	return b.app(`{"jsonrpc":"2.0","method":"ui/close","params":{"panel":"` + panel + `"}}`)
}

func pressed(count int) toolkit.UITree {
	return ui.Tree(ui.Text("Pressed " + strconv.Itoa(count) + " times"))
}

func TestAPanelIsOpenedActedInAndClosed(t *testing.T) {
	b := (&bench{}).helloOffering(`["1","2"]`).open("counter", 2).tap("counter", "add", 3).
		tap("counter", "nothing", 4).close("counter").goodbye()
	tool := b.tool()
	count := 0
	var seen []toolkit.PanelEvent
	handle := tool.Panel("counter",
		func(app *toolkit.App, panel *toolkit.PanelHandle) (*toolkit.UITree, error) {
			page := pressed(count)
			return &page, nil
		},
		func(app *toolkit.App, panel *toolkit.PanelHandle, event toolkit.PanelEvent) (toolkit.PanelAnswer, error) {
			seen = append(seen, event)
			if event.Block != "add" {
				return toolkit.Keep(), nil
			}
			count++
			return toolkit.Page(pressed(count)), nil
		})
	if status := tool.Serve(); status != 0 {
		t.Fatalf("status %d", status)
	}
	same(t, b.lines(t),
		`{"jsonrpc":"2.0","id":"hello","result":{"protocolVersion":"2","toolVersion":"9.9.9"}}`,
		`{"jsonrpc":"2.0","id":2,"result":{"tree":{"blocks":[{"type":"text","text":"Pressed 0 times"}]}}}`,
		`{"jsonrpc":"2.0","id":3,"result":{"tree":{"blocks":[{"type":"text","text":"Pressed 1 times"}]}}}`,
		`{"jsonrpc":"2.0","id":4,"result":{"keep":true}}`)
	wanted := []toolkit.PanelEvent{{Block: "add", Kind: "tap"}, {Block: "nothing", Kind: "tap"}}
	if !reflect.DeepEqual(seen, wanted) {
		t.Errorf("seen %v, wanted %v", seen, wanted)
	}
	if handle.IsOpen() {
		t.Errorf("ui/close closes it")
	}
}

func TestAPageIsSentUnpromptedOnlyWhileThePanelIsOpen(t *testing.T) {
	b := (&bench{}).helloOffering(`["1","2"]`).run("refresh", 2).open("counter", 3).run("refresh", 4).
		close("counter").run("refresh", 5).goodbye()
	tool := b.tool()
	var sent []bool
	panel := tool.Panel("counter", func(app *toolkit.App, panel *toolkit.PanelHandle) (*toolkit.UITree, error) {
		page := ui.Tree(ui.Heading("Counter"))
		return &page, nil
	}, nil)
	tool.Command("refresh", func(ctx context.Context, app *toolkit.App) error {
		sent = append(sent, panel.Render(ui.Tree(ui.Text("Later"))))
		return nil
	})
	tool.Serve()
	if !reflect.DeepEqual(sent, []bool{false, true, false}) {
		t.Errorf("render sends nothing for a panel that is not open: %v", sent)
	}
	var renders []any
	for _, line := range b.lines(t) {
		if message, ok := line.(map[string]any); ok && message["method"] == "ui/render" {
			renders = append(renders, line)
		}
	}
	same(t, renders,
		`{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"counter","tree":{"blocks":[{"type":"text","text":"Later"}]}}}`)
}

func TestWhatIsNotAPanelOfTheToolsIsRefused(t *testing.T) {
	b := (&bench{}).helloOffering(`["1","2"]`).open("nowhere", 2).tap("counter", "add", 3).goodbye()
	tool := b.tool()
	tool.Panel("counter", func(app *toolkit.App, panel *toolkit.PanelHandle) (*toolkit.UITree, error) {
		return nil, nil
	}, nil)
	tool.Serve()
	same(t, b.lines(t)[1:],
		`{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"no such panel"}}`,
		`{"jsonrpc":"2.0","id":3,"error":{"code":-32602,"message":"the panel is not open"}}`)
}

func TestAnAnswerMayOpenAWindowOrReplyAndTheBadgeIsARequest(t *testing.T) {
	b := (&bench{}).helloOffering(`["1","2"]`).open("deploys", 2).tap("deploys", "log", 3).
		app(`{"jsonrpc":"2.0","id":1,"result":{}}`).goodbye()
	tool := b.tool()
	tool.Panel("deploys",
		func(app *toolkit.App, panel *toolkit.PanelHandle) (*toolkit.UITree, error) {
			return nil, panel.Badge(2, false)
		},
		func(app *toolkit.App, panel *toolkit.PanelHandle, event toolkit.PanelEvent) (toolkit.PanelAnswer, error) {
			return toolkit.OpenWindow("log"), nil
		})
	tool.Serve()
	same(t, b.lines(t)[1:],
		`{"jsonrpc":"2.0","id":1,"method":"ui/badge","params":{"count":2}}`,
		`{"jsonrpc":"2.0","id":2,"result":{}}`,
		`{"jsonrpc":"2.0","id":3,"result":{"open":"log"}}`)
}

func TestAWebPanelsCallsAreTheToolsOwnOrPassedToTheApp(t *testing.T) {
	bridge := func(id int, call string) string {
		return `{"jsonrpc":"2.0","id":` + strconv.Itoa(id) +
			`,"method":"ui/event","params":{"panel":"dashboard","event":"bridge","value":` + call + `}}`
	}
	b := (&bench{}).helloOffering(`["1","2"]`).open("dashboard", 2).
		app(bridge(3, `{"method":"notify/hud","params":{"icon":"checkmark","message":"Saved"}}`)).
		app(`{"jsonrpc":"2.0","id":1,"result":{}}`).
		app(bridge(4, `{"method":"tool/count","params":{"by":2}}`)).
		app(bridge(5, `{"method":"tool/other"}`)).
		app(bridge(6, `{"method":"initialize"}`)).
		goodbye()
	tool := b.tool()
	panel := tool.Panel("dashboard", func(app *toolkit.App, panel *toolkit.PanelHandle) (*toolkit.UITree, error) {
		return nil, nil
	}, nil)
	panel.OnCall = func(app *toolkit.App, method string, params any) (any, error) {
		if method != "tool/count" {
			return nil, &toolkit.Error{Code: -32601, Message: "method not found"}
		}
		return map[string]any{"count": params.(map[string]any)["by"]}, nil
	}
	tool.Serve()
	// A request of the app's is asked of the app as the tool's own; a
	// method of the tool's goes to OnCall.
	same(t, b.lines(t)[2:],
		`{"jsonrpc":"2.0","id":1,"method":"notify/hud","params":{"icon":"checkmark","message":"Saved"}}`,
		`{"jsonrpc":"2.0","id":3,"result":{"reply":{}}}`,
		`{"jsonrpc":"2.0","id":4,"result":{"reply":{"count":2}}}`,
		`{"jsonrpc":"2.0","id":5,"error":{"code":-32601,"message":"method not found"}}`,
		`{"jsonrpc":"2.0","id":6,"error":{"code":-32601,"message":"method not found"}}`)
}

func TestAPageIsWrittenAsTheBlocksItHolds(t *testing.T) {
	count := 12
	rows := []string{"web", "api"}
	blocks := []toolkit.UIBlock{
		ui.Heading("Counter"),
		ui.Text("Pressed "+strconv.Itoa(count)+" times", ui.TextOptions{Style: ui.Secondary}),
		ui.Button("add", "Add one", ui.ButtonOptions{Style: ui.Prominent}),
		ui.If(count > 9, ui.Text("That is a lot", ui.TextOptions{Style: ui.Caption})),
		ui.If(count > 99, ui.Divider()),
		ui.If(count <= 99, ui.Spacer(4)),
	}
	for _, name := range rows {
		blocks = append(blocks, ui.Row(name, ui.RowOptions{ID: name}))
	}
	blocks = append(blocks,
		ui.List("deploys", []toolkit.UIListRow{{ID: "web", Title: "web 1.42.0"}}),
		ui.Toggle("notify", "Tell me", true),
		ui.Field("name", ui.FieldOptions{Title: "Name", Placeholder: "Type and press Return"}),
		ui.Progress(0.5),
		ui.Image("ui/logo.png", ui.ImageOptions{Alt: "Logo"}),
		ui.Link("Dashboard", "https://example.com"))
	page := ui.Tree(blocks...)
	var types, ids []string
	for _, block := range page.Blocks {
		types = append(types, block.Type)
		if block.ID != nil {
			ids = append(ids, *block.ID)
		}
	}
	wantedTypes := []string{
		"heading", "text", "button", "text", "spacer", "row", "row", "list", "toggle", "field",
		"progress", "image", "link",
	}
	if !reflect.DeepEqual(types, wantedTypes) {
		t.Errorf("types %v", types)
	}
	if !reflect.DeepEqual(ids, []string{"add", "web", "api", "deploys", "notify", "name"}) {
		t.Errorf("ids %v", ids)
	}
	if page.Blocks[2].Button == nil || page.Blocks[2].Button.Style == nil || *page.Blocks[2].Button.Style != "prominent" {
		t.Errorf("the button's style: %+v", page.Blocks[2].Button)
	}
	kinds := 0
	for _, field := range reflect.VisibleFields(reflect.TypeOf(toolkit.UIBlock{})) {
		if field.Tag.Get("json") == "-" && field.Name != "Other" {
			kinds++
		}
	}
	if kinds != 13 {
		t.Errorf("%d kinds of block", kinds)
	}
}

func TestAStatusIsSentToAnAppThatHasIt(t *testing.T) {
	b := (&bench{}).helloWith(`["1","2"]`, `["ui.status","ui.later"]`).run("check", 2).
		app(`{"jsonrpc":"2.0","id":1,"result":{}}`).app(`{"jsonrpc":"2.0","id":2,"result":{}}`).goodbye()
	tool := b.tool()
	var shown []bool
	tool.Command("check", func(ctx context.Context, app *toolkit.App) error {
		first, err := app.UI.Status(toolkit.StatusBusy,
			toolkit.StatusOptions{Text: "Checks are running", Icon: "arrow.triangle.branch"})
		if err != nil {
			return err
		}
		second, err := app.UI.Status(toolkit.StatusNone)
		shown = []bool{first, second}
		return err
	})
	tool.Serve()
	if !reflect.DeepEqual(shown, []bool{true, true}) {
		t.Errorf("shown %v", shown)
	}
	same(t, b.lines(t)[1:],
		`{"jsonrpc":"2.0","id":1,"method":"ui/status","params":{"state":"busy","text":"Checks are running","icon":"arrow.triangle.branch"}}`,
		`{"jsonrpc":"2.0","id":2,"method":"ui/status","params":{"state":"none"}}`,
		`{"jsonrpc":"2.0","id":2,"result":{}}`)
}

func TestAStatusSendsItsWordsToAnAppThatDrawsThem(t *testing.T) {
	b := (&bench{}).helloWith(`["2"]`, `["ui.status","ui.status.activity"]`).run("check", 2).
		app(`{"jsonrpc":"2.0","id":1,"result":{}}`).goodbye()
	tool := b.tool()
	shown := false
	tool.Command("check", func(ctx context.Context, app *toolkit.App) error {
		var err error
		shown, err = app.UI.Status(toolkit.StatusBusy, toolkit.StatusOptions{
			Text: "Checks are running", Activity: "3", Since: time.Unix(1760450400, 500_000_000),
		})
		return err
	})
	tool.Serve()
	if !shown {
		t.Errorf("not shown")
	}
	// The words, and the start time in Unix seconds.
	same(t, b.lines(t)[1:],
		`{"jsonrpc":"2.0","id":1,"method":"ui/status","params":{"state":"busy","text":"Checks are running","activity":"3","since":1760450400.5}}`,
		`{"jsonrpc":"2.0","id":2,"result":{}}`)
}

func TestAStatusSendsNoWordsToAnAppFrom348(t *testing.T) {
	// 3.48 and 3.49 name ui.status and not its words: the status goes,
	// without them.
	b := (&bench{}).helloWith(`["2"]`, `["ui.status","ui.choice","preferences.options"]`).run("check", 2).
		app(`{"jsonrpc":"2.0","id":1,"result":{}}`).goodbye()
	tool := b.tool()
	shown := false
	tool.Command("check", func(ctx context.Context, app *toolkit.App) error {
		var err error
		shown, err = app.UI.Status(toolkit.StatusBusy, toolkit.StatusOptions{
			Text: "Checks are running", Activity: "3", Since: time.Now(),
		})
		return err
	})
	tool.Serve()
	if !shown {
		t.Errorf("the mark is shown")
	}
	same(t, b.lines(t)[1:],
		`{"jsonrpc":"2.0","id":1,"method":"ui/status","params":{"state":"busy","text":"Checks are running"}}`,
		`{"jsonrpc":"2.0","id":2,"result":{}}`)
}

func TestAStatusWithWordsWritesNothingForAnAppWithoutAStatus(t *testing.T) {
	b := (&bench{}).helloOffering(`["1","2"]`).run("check", 2).goodbye()
	tool := b.tool()
	shown := true
	tool.Command("check", func(ctx context.Context, app *toolkit.App) error {
		shown, _ = app.UI.Status(toolkit.StatusBusy, toolkit.StatusOptions{Activity: "3", Since: time.Now()})
		return nil
	})
	tool.Serve()
	if shown || len(b.lines(t)) != 2 {
		t.Errorf("shown %v, written %v", shown, b.lines(t))
	}
}

func TestAStatusWritesNothingForAnOlderApp(t *testing.T) {
	// An app before 3.48: its hello has no features. No answer is scripted,
	// so a request sent here would end with the link.
	b := (&bench{}).helloOffering(`["1","2"]`).run("check", 2).goodbye()
	tool := b.tool()
	shown := true
	var failed error
	tool.Command("check", func(ctx context.Context, app *toolkit.App) error {
		shown, failed = app.UI.Status(toolkit.StatusFailure, toolkit.StatusOptions{Text: "main is red"})
		return nil
	})
	tool.Serve()
	if shown || failed != nil {
		t.Errorf("the call says the status is not shown, and that is no error: %v, %v", shown, failed)
	}
	// Nothing was sent for it: only the two answers are on the link.
	same(t, b.lines(t),
		`{"jsonrpc":"2.0","id":"hello","result":{"protocolVersion":"2","toolVersion":"9.9.9"}}`,
		`{"jsonrpc":"2.0","id":2,"result":{}}`)

	// The same for an app that says what it has, and does not have this.
	other := (&bench{}).helloWith(`["2"]`, `["ui.choice"]`).run("check", 2).goodbye()
	second := other.tool()
	again := true
	second.Command("check", func(ctx context.Context, app *toolkit.App) error {
		again, _ = app.UI.Status(toolkit.StatusOK)
		return nil
	})
	second.Serve()
	if again || len(other.lines(t)) != 2 {
		t.Errorf("shown %v, written %v", again, other.lines(t))
	}
}

func TestSupportsIsTrueOnlyForWhatTheHelloListed(t *testing.T) {
	b := (&bench{}).helloWith(`["1"]`, `["ui.choice","preferences.options","ui.later"]`).run("ask", 2).goodbye()
	tool := b.tool()
	var has []bool
	tool.Command("ask", func(ctx context.Context, app *toolkit.App) error {
		for _, name := range []string{
			toolkit.FeatureChoice, toolkit.FeaturePreferenceOptions, toolkit.FeatureStatus,
			"ui.later", "ui.never",
		} {
			has = append(has, app.Supports(name))
		}
		return nil
	})
	tool.Serve()
	if !reflect.DeepEqual(has, []bool{true, true, false, true, false}) {
		t.Errorf("has %v", has)
	}
	names := []string{
		toolkit.FeatureStatus, toolkit.FeatureChoice, toolkit.FeaturePreferenceOptions,
		toolkit.FeatureStatusActivity,
	}
	if !reflect.DeepEqual(names, []string{"ui.status", "ui.choice", "preferences.options", "ui.status.activity"}) {
		t.Errorf("names %v", names)
	}

	// An app that says nothing has none of them.
	old := (&bench{}).hello().run("ask", 2).goodbye()
	before := old.tool()
	var none []bool
	before.Command("ask", func(ctx context.Context, app *toolkit.App) error {
		for _, name := range names {
			none = append(none, app.Supports(name))
		}
		return nil
	})
	before.Serve()
	if !reflect.DeepEqual(none, []bool{false, false, false, false}) {
		t.Errorf("none %v", none)
	}
}

func TestAChoiceIsBuiltAsTheProtocolsExample(t *testing.T) {
	options := []toolkit.UIChoiceOption{
		{Value: "green", Title: "Green"},
		{Value: "breathe green", Title: toolkit.LocalizedText{"en": "Pulsing green", "de": "Pulsierendes Grün"}},
	}
	data, err := os.ReadFile(filepath.Join("..", "..", "protocol", "examples", "messages.json"))
	if err != nil {
		t.Fatal(err)
	}
	var file struct {
		Examples []struct {
			About   string
			Message map[string]any
		}
	}
	if err := json.Unmarshal(data, &file); err != nil {
		t.Fatal(err)
	}
	var example any
	for _, each := range file.Examples {
		if each.About == "a page with a choice among fixed options" {
			tree := each.Message["params"].(map[string]any)["tree"].(map[string]any)
			example = tree["blocks"].([]any)[0]
		}
	}
	plain := func(block toolkit.UIBlock) any {
		written, err := json.Marshal(block)
		if err != nil {
			t.Fatal(err)
		}
		var value any
		if err := json.Unmarshal(written, &value); err != nil {
			t.Fatal(err)
		}
		return value
	}
	enabled := ui.Choice("light", "green", options,
		ui.ChoiceOptions{Title: "Mouse when green", Fallback: "Mouse when green: Green"})
	yes := true
	enabled.Choice.Enabled = &yes
	if built := plain(enabled); example == nil || !reflect.DeepEqual(built, example) {
		t.Errorf("built:\n%v\nthe example:\n%v", built, example)
	}

	// With no fallback given, the builder writes one: an app before 3.48
	// draws it in the menu's place.
	fallback := func(block toolkit.UIBlock) any { return plain(block).(map[string]any)["fallback"] }
	if got := fallback(ui.Choice("light", "green", options, ui.ChoiceOptions{Title: "Mouse when green"})); got != "Mouse when green: Green" {
		t.Errorf("the fallback: %v", got)
	}
	if got := fallback(ui.Choice("light", "green", options)); got != "Green" {
		t.Errorf("with no title, the selected option's title alone: %v", got)
	}
	both := fallback(ui.Choice("light", "breathe green", options, ui.ChoiceOptions{Title: "Mouse when green"}))
	if !reflect.DeepEqual(both, map[string]any{"en": "Mouse when green: Pulsing green", "de": "Mouse when green: Pulsierendes Grün"}) {
		t.Errorf("in every language either text has: %v", both)
	}
	if got := fallback(ui.Choice("light", "typed by hand", options, ui.ChoiceOptions{Title: "Light"})); got != "Light: typed by hand" {
		t.Errorf("a value that is no option's is written as it is: %v", got)
	}
	dimmed := ui.Choice("light", "green", options, ui.ChoiceOptions{Disabled: true})
	if dimmed.Choice.Enabled == nil || *dimmed.Choice.Enabled {
		t.Errorf("a disabled choice says so")
	}
	if dimmed.ID == nil || *dimmed.ID != "light" || dimmed.Type != "choice" {
		t.Errorf("its id and its kind: %+v", dimmed)
	}
	// A pick arrives as the event a field's change is, with the option's value.
	picked, ok := toolkit.PanelEvent{Block: "light", Kind: "change", Value: "breathe green"}.Text()
	if !ok || picked != "breathe green" {
		t.Errorf("picked %q", picked)
	}
}

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
	"reflect"
	"strconv"
	"testing"

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
	if kinds != 12 {
		t.Errorf("%d kinds of block", kinds)
	}
}

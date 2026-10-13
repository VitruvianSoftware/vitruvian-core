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

package toolkit

import (
	"encoding/json"
	"errors"
	"strings"
)

// A tool that draws: its panels, what the person did in one, how a handler
// answers, and the handle that sends a page and sets the badge. The Swift
// kit's Panels.swift, in Go. A page itself is written with package ui.

// PanelEvent is what the person did in one of the tool's panels, as a
// handler sees it.
type PanelEvent struct {
	// Block is the block's id, as the page gave it. Empty for a web page's
	// call.
	Block string
	// Kind is tap, toggle, submit, change or bridge.
	Kind string
	// Value is what the event carries: Row, Text and IsOn read it.
	Value any
}

// Row is, for a tap on a row of a list, the row's id.
func (e PanelEvent) Row() (string, bool) {
	if e.Kind != "tap" {
		return "", false
	}
	row, ok := e.Value.(string)
	return row, ok
}

// Text is, for submit and change, the field's text.
func (e PanelEvent) Text() (string, bool) {
	if e.Kind != "submit" && e.Kind != "change" {
		return "", false
	}
	text, ok := e.Value.(string)
	return text, ok
}

// IsOn is, for toggle, the switch's new state.
func (e PanelEvent) IsOn() (bool, bool) {
	if e.Kind != "toggle" {
		return false, false
	}
	on, ok := e.Value.(bool)
	return on, ok
}

// PanelAnswer is how a handler answers what the person did: one of Page,
// Keep, OpenWindow and Reply.
type PanelAnswer struct {
	result UIEventResult
}

// Page answers with the next page.
func Page(tree UITree) PanelAnswer {
	return PanelAnswer{UIEventResult{Tree: &tree}}
}

// Keep answers that the page stays as it is.
func Keep() PanelAnswer {
	keep := true
	return PanelAnswer{UIEventResult{Keep: &keep}}
}

// OpenWindow answers that one of the tool's window panels opens, by its id.
func OpenWindow(panel string) PanelAnswer {
	return PanelAnswer{UIEventResult{Open: &panel}}
}

// Reply answers a web panel's call: what its window.vitruvian.call gets
// back.
func Reply(value any) PanelAnswer {
	if value == nil {
		value = map[string]any{}
	}
	return PanelAnswer{UIEventResult{Reply: value}}
}

// PanelOpened gives the first page when the person opens the panel; a web
// panel gives nil. Any error refuses the opening: a *Error as it is,
// anything else as an internal error with its words.
type PanelOpened func(app *App, panel *PanelHandle) (*UITree, error)

// PanelActed answers what the person did. Any error refuses the event, as
// for PanelOpened.
type PanelActed func(app *App, panel *PanelHandle, event PanelEvent) (PanelAnswer, error)

// PanelCalled answers a web panel's call of a method of the tool's own,
// one whose name starts with tool/: the method, its params, and the reply.
type PanelCalled func(app *App, method string, params any) (any, error)

// PanelHandle is one of the tool's panels, as the manifest declares it.
// Made by Tool.Panel. Use it from the goroutine that runs the tool, as
// everything of a Tool.
type PanelHandle struct {
	// ID is the id the manifest gives the panel.
	ID string
	// OnCall is, for a web panel, what its page's calls of the tool's own
	// methods answer. With none, such a call is answered as a method not
	// found. A call of a request the app does, such as notify/hud, is
	// passed to the app as the tool's own, with no handler.
	OnCall PanelCalled

	tool    *Tool
	onOpen  PanelOpened
	onEvent PanelActed
	open    bool
}

// IsOpen is true while the app has the panel open: from ui/open to
// ui/close.
func (p *PanelHandle) IsOpen() bool { return p.open }

// Render sends a new page for the panel, unprompted: ui/render. False, and
// nothing is sent, when the panel is not open. The app draws at most four
// pages a second for a panel; send fewer.
func (p *PanelHandle) Render(tree UITree) bool {
	if !p.open {
		return false
	}
	return p.tool.note(MethodUIRender, UIRenderParams{Panel: p.ID, Tree: tree})
}

// Badge puts a count, or a dot, beside the tool in the island's Tools
// area: ui/badge. A count of 0 is none; with neither, the badge goes.
// Needs notify in uses. It returns the app's refusal, if any.
func (p *PanelHandle) Badge(count int, dot bool) error {
	var counted *int
	if count > 0 {
		counted = &count
	}
	return p.tool.app.UI.Badge(counted, dot)
}

// Panel says what a panel does. id is the one the manifest gives it. onOpen
// gives the first page when the person opens it; a web panel gives nil.
// onEvent answers what the person did; nil keeps the page as it is. The
// handle it gives back sends pages unprompted and sets the tool's badge.
func (t *Tool) Panel(id string, onOpen PanelOpened, onEvent PanelActed) *PanelHandle {
	if onEvent == nil {
		onEvent = func(*App, *PanelHandle, PanelEvent) (PanelAnswer, error) { return Keep(), nil }
	}
	panel := &PanelHandle{ID: id, tool: t, onOpen: onOpen, onEvent: onEvent}
	t.panels[id] = panel
	return panel
}

// toolsOwn starts the name of a method of the tool's own, which a web page
// may call.
const toolsOwn = "tool/"

// bridgeCall is a web page's call, as ui/event's value carries it for
// bridge.
type bridgeCall struct {
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
}

func (t *Tool) openPanel(m message) {
	var asked UIOpenParams
	if !decode(m.params, &asked) {
		t.refuse(m.id, CodeInvalidParams, "invalid params", nil)
		return
	}
	panel, ok := t.panels[asked.Panel]
	if !ok {
		t.refuse(m.id, CodeInvalidParams, "no such panel", nil)
		return
	}
	panel.open = true
	tree, err := panel.onOpen(t.app, panel)
	if err != nil {
		t.refusePanel(m.id, err)
		return
	}
	t.answer(m.id, UIOpenResult{Tree: tree})
}

func (t *Tool) panelEvent(m message) {
	var asked UIEventParams
	if !decode(m.params, &asked) {
		t.refuse(m.id, CodeInvalidParams, "invalid params", nil)
		return
	}
	panel, ok := t.panels[asked.Panel]
	if !ok || !panel.open {
		t.refuse(m.id, CodeInvalidParams, "the panel is not open", nil)
		return
	}
	var answer PanelAnswer
	var err error
	if asked.Event == "bridge" {
		var reply any
		reply, err = t.bridge(asked.Value, panel)
		answer = Reply(reply)
	} else {
		event := PanelEvent{Kind: asked.Event, Value: asked.Value}
		if asked.Block != nil {
			event.Block = *asked.Block
		}
		answer, err = panel.onEvent(t.app, panel, event)
	}
	if err != nil {
		t.refusePanel(m.id, err)
		return
	}
	t.answer(m.id, answer.result)
}

// refusePanel answers a request of a panel with a handler's error: a
// *Error as it is, anything else as an internal error with its words.
func (t *Tool) refusePanel(id json.RawMessage, err error) {
	var refusal *Error
	if errors.As(err, &refusal) {
		t.refuse(id, refusal.Code, refusal.Message, refusal.Data)
		return
	}
	t.refuse(id, CodeInternalError, err.Error(), nil)
}

// bridge answers a web panel's call: a request the app does is passed to
// the app as the tool's own, under the tool's uses; a method of the tool's
// own goes to the panel's OnCall.
func (t *Tool) bridge(value any, panel *PanelHandle) (any, error) {
	raw, err := json.Marshal(value)
	var asked bridgeCall
	if err != nil || value == nil || json.Unmarshal(raw, &asked) != nil || asked.Method == "" {
		return nil, &Error{Code: CodeInvalidParams, Message: "invalid params"}
	}
	var params any
	if asked.Params != nil {
		if err := json.Unmarshal(asked.Params, &params); err != nil {
			return nil, &Error{Code: CodeInvalidParams, Message: "invalid params"}
		}
	}
	if strings.HasPrefix(asked.Method, toolsOwn) {
		if panel.OnCall == nil {
			return nil, &Error{Code: CodeMethodNotFound, Message: "method not found"}
		}
		return panel.OnCall(t.app, asked.Method, params)
	}
	for _, method := range Methods {
		if method.Name != asked.Method || method.Sender != "tool" || method.Kind != "request" {
			continue
		}
		if params == nil {
			params = map[string]any{}
		}
		var reply any
		if err := t.call(asked.Method, params, &reply); err != nil {
			return nil, err
		}
		return reply, nil
	}
	return nil, &Error{Code: CodeMethodNotFound, Message: "method not found"}
}

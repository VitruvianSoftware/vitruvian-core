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
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/signal"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// Handler runs one command. It returns nil when the command ran. Any error
// refuses the command: return Refuse("why") to refuse it yourself, or let
// through the error a call to the app returned.
//
// ctx is done once the app has said goodbye or gone away. A handler that
// works for long without calling the app should watch it.
type Handler func(ctx context.Context, app *App) error

// Tool is a tool that runs as its own program: its commands, its panels,
// and the loop that reads what the app sends and answers it. Make one with New, add its
// commands, then call Run. Use a Tool and its App from one goroutine only.
type Tool struct {
	// AnswerTimeout is how long a call to the app waits for its answer.
	AnswerTimeout time.Duration
	// OnStart is called once, after the app has said hello and been
	// answered.
	OnStart func(app *App)
	// OnPreferencesChanged is called when the person changed preferences:
	// each one's id and new value.
	OnPreferencesChanged func(app *App, values map[string]any)
	// OnLanguageChanged is called when the person changed the app's
	// language. App.Language is already the new one.
	OnLanguageChanged func(app *App)
	// OnSlot is called when the tool's slot shows, moves or goes
	// (ui/slot), for a tool whose manifest declares contributes.slot.
	OnSlot func(app *App, slot UISlotParams)

	version    string
	in         io.Reader
	link       link
	app        *App
	handlers   map[string]Handler
	panels     map[string]*PanelHandle
	kept       []message
	lastID     int64
	greeted    bool
	stopping   bool
	language   string
	dataFolder string
	// features is what the app said it has beyond the first release of the
	// protocol version: the hello's features. Empty for an app that said
	// nothing, which is every app before 3.48.
	features map[string]bool
	ctx      context.Context
}

// New makes a tool that talks to the app over standard input and output.
// version is the tool's own, as its manifest gives it.
func New(version string) *Tool {
	return NewLink(version, os.Stdin, os.Stdout)
}

// NewLink makes a tool that talks to the app over in and out. It is for a
// test; a tool uses New.
func NewLink(version string, in io.Reader, out io.Writer) *Tool {
	folder, _ := os.Getwd()
	tool := &Tool{
		AnswerTimeout: 10 * time.Second,
		version:       version,
		in:            in,
		link:          link{out: out},
		handlers:      map[string]Handler{},
		panels:        map[string]*PanelHandle{},
		language:      "en",
		dataFolder:    folder,
		ctx:           context.Background(),
	}
	tool.app = newApp(tool)
	return tool
}

// Command says what a command does. id is the one the manifest gives it.
func (t *Tool) Command(id string, handler Handler) {
	t.handlers[id] = handler
}

// Run reads and answers until the app says goodbye, then exits with 0.
func (t *Tool) Run() {
	os.Exit(t.Serve())
}

// Serve reads and answers until the app says goodbye or the link ends, and
// returns the status to exit with, which is 0: the app going away is not
// the tool's failure. Call it once.
func (t *Tool) Serve() int {
	// A link that has gone is then a failed write, not a signal that ends
	// the program.
	if t.link.out == os.Stdout {
		signal.Ignore(syscall.SIGPIPE)
	}
	ctx, cancel := context.WithCancel(context.Background())
	t.ctx = ctx
	t.link.inbox = make(chan message)
	t.link.done = make(chan struct{})
	go t.link.read(t.in, cancel)
	defer close(t.link.done)
	defer cancel()
	for !t.stopping {
		if len(t.kept) > 0 {
			next := t.kept[0]
			t.kept = t.kept[1:]
			t.handle(next)
			continue
		}
		next, state := t.link.next(nil)
		if state != got {
			t.stopping = true
			continue
		}
		t.handle(next)
	}
	return 0
}

func (t *Tool) handle(m message) {
	switch {
	case m.isRequest():
		switch m.method {
		case MethodInitialize:
			t.greet(m)
		case MethodCommandRun:
			t.runCommand(m)
		case MethodUIOpen:
			t.openPanel(m)
		case MethodUIEvent:
			t.panelEvent(m)
		default:
			t.refuse(m.id, CodeMethodNotFound, "method not found", nil)
		}
	case m.isNotice():
		switch m.method {
		case MethodShutdown:
			t.stopping = true
		case MethodPreferencesChanged:
			var changed PreferencesChangedParams
			if decode(m.params, &changed) && t.OnPreferencesChanged != nil {
				t.OnPreferencesChanged(t.app, changed.Values)
			}
		case MethodLanguageChanged:
			var changed LanguageChangedParams
			if decode(m.params, &changed) {
				t.language = changed.Language
				if t.OnLanguageChanged != nil {
					t.OnLanguageChanged(t.app)
				}
			}
		case MethodUIClose:
			var closed UICloseParams
			if decode(m.params, &closed) {
				if panel, ok := t.panels[closed.Panel]; ok {
					panel.open = false
				}
			}
		case MethodUISlot:
			var slot UISlotParams
			if decode(m.params, &slot) && t.OnSlot != nil {
				t.OnSlot(t.app, slot)
			}
		}
	}
	// An answer here is one nobody waits for: it came after its call gave
	// up.
}

// decode reads params that must be there.
func decode(params json.RawMessage, into any) bool {
	return params != nil && json.Unmarshal(params, into) == nil
}

func (t *Tool) greet(m message) {
	var hello InitializeParams
	if !decode(m.params, &hello) {
		t.refuse(m.id, CodeInvalidParams, "invalid params", nil)
		return
	}
	// The newest version both speak. Version 2 only adds to version 1, so a
	// tool of either is answered by an app of either.
	picked := ""
	for i := len(ProtocolVersions) - 1; i >= 0 && picked == ""; i-- {
		if slices.Contains(hello.ProtocolVersions, ProtocolVersions[i]) {
			picked = ProtocolVersions[i]
		}
	}
	if picked == "" {
		t.refuse(m.id, CodeInvalidParams, "this tool speaks protocols "+strings.Join(ProtocolVersions, " and ")+" only", nil)
		return
	}
	t.language = hello.Language
	t.dataFolder = hello.DataFolder
	t.features = map[string]bool{}
	for _, feature := range hello.Features {
		t.features[feature] = true
	}
	t.greeted = true
	t.answer(m.id, InitializeResult{ProtocolVersion: picked, ToolVersion: t.version})
	if t.OnStart != nil {
		t.OnStart(t.app)
	}
}

func (t *Tool) runCommand(m message) {
	if !t.greeted {
		t.refuse(m.id, CodeInvalidRequest, "initialize comes first", nil)
		return
	}
	var asked CommandRunParams
	if !decode(m.params, &asked) {
		t.refuse(m.id, CodeInvalidParams, "invalid params", nil)
		return
	}
	handler, ok := t.handlers[asked.Command]
	if !ok {
		t.refuse(m.id, CodeInvalidParams, "no such command", nil)
		return
	}
	err := handler(t.ctx, t.app)
	var refused *RefusedError
	var refusal *Error
	switch {
	case err == nil:
		t.answer(m.id, Empty{})
	case errors.As(err, &refused):
		t.refuse(m.id, CodeCommandRefused, refused.Reason, nil)
	case errors.As(err, &refusal):
		// The app refused something the command needed. Its reason goes
		// with ours, for the log.
		t.refuse(m.id, CodeCommandRefused, "command refused", refusal)
	default:
		t.refuse(m.id, CodeCommandRefused, err.Error(), nil)
	}
}

func (t *Tool) answer(id json.RawMessage, result any) {
	written, err := json.Marshal(result)
	if err != nil {
		t.refuse(id, CodeInternalError, "the answer could not be written", nil)
		return
	}
	t.link.send(outgoing{ID: id, Result: json.RawMessage(written)})
}

func (t *Tool) refuse(id json.RawMessage, code int, words string, data any) {
	t.link.send(outgoing{ID: id, Error: &Error{Code: code, Message: words, Data: data}})
}

// call sends a request and reads the link until its answer has come. What
// else comes meanwhile is kept, in order, for after the handler.
func (t *Tool) call(method string, params, result any) error {
	if !t.greeted || t.stopping {
		return ErrLinkClosed
	}
	t.lastID++
	mine := t.lastID
	if !t.link.send(outgoing{ID: json.RawMessage(strconv.FormatInt(mine, 10)), Method: method, Params: params}) {
		t.stopping = true
		return ErrLinkClosed
	}
	deadline := time.NewTimer(t.AnswerTimeout)
	defer deadline.Stop()
	for {
		m, state := t.link.next(deadline.C)
		switch state {
		case ended:
			t.stopping = true
			return ErrLinkClosed
		case late:
			return &NoAnswerError{After: t.AnswerTimeout}
		}
		switch {
		case m.answers(mine) && m.err != nil:
			return m.err
		case m.answers(mine):
			if result == nil {
				return nil
			}
			return json.Unmarshal(m.result, result)
		case m.isNotice() && m.method == MethodShutdown:
			t.stopping = true
			return ErrLinkClosed
		default:
			t.kept = append(t.kept, m)
		}
	}
}

// note sends a notice, and says whether it went. Nothing is sent before
// the greeting or after goodbye.
func (t *Tool) note(method string, params any) bool {
	if !t.greeted || t.stopping {
		return false
	}
	return t.link.send(outgoing{Method: method, Params: params})
}

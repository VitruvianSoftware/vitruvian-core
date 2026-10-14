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
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit"
)

// bench is a tool's link made of two buffers: what the app will have sent,
// written before the tool starts, and what the tool writes. The input's
// end is the end of the link, so no test here can wait for long. These are
// the Swift kit's ToolTests, one for one.
type bench struct {
	sent    strings.Builder
	written bytes.Buffer
}

// app adds one line the app sends.
func (b *bench) app(line string) *bench {
	b.sent.WriteString(line + "\n")
	return b
}

func (b *bench) hello() *bench { return b.helloOffering(`["1"]`) }

func (b *bench) helloOffering(versions string) *bench {
	return b.app(`{"jsonrpc":"2.0","id":"hello","method":"initialize","params":{"protocolVersions":` + versions +
		`,"language":"de-DE","dataFolder":"/tmp/kit-data"}}`)
}

// helloWith is the hello of an app that says what it has: features is the
// list, as JSON. hello and helloOffering are an app from before the field,
// which says nothing.
func (b *bench) helloWith(versions, features string) *bench {
	return b.app(`{"jsonrpc":"2.0","id":"hello","method":"initialize","params":{"protocolVersions":` + versions +
		`,"language":"de-DE","dataFolder":"/tmp/kit-data","features":` + features + `}}`)
}

func (b *bench) run(command string, id int) *bench {
	return b.app(`{"jsonrpc":"2.0","id":` + strconv.Itoa(id) + `,"method":"command/run","params":{"command":"` + command + `"}}`)
}

func (b *bench) goodbye() *bench { return b.app(`{"jsonrpc":"2.0","method":"shutdown"}`) }

// tool makes the tool over the two buffers.
func (b *bench) tool() *toolkit.Tool {
	return toolkit.NewLink("9.9.9", strings.NewReader(b.sent.String()), &b.written)
}

// lines is what the tool wrote, a message a line, each read as JSON.
func (b *bench) lines(t *testing.T) []any {
	t.Helper()
	return decodeAll(t, strings.Split(strings.TrimSuffix(b.written.String(), "\n"), "\n"))
}

func decodeAll(t *testing.T, lines []string) []any {
	t.Helper()
	found := []any{}
	for _, line := range lines {
		if line == "" {
			continue
		}
		var value any
		if err := json.Unmarshal([]byte(line), &value); err != nil {
			t.Fatalf("not JSON: %q", line)
		}
		found = append(found, value)
	}
	return found
}

func same(t *testing.T, got []any, want ...string) {
	t.Helper()
	if expected := decodeAll(t, want); !reflect.DeepEqual(got, expected) {
		t.Errorf("written:\n%v\nwanted:\n%v", got, expected)
	}
}

func TestEveryRequestAToolMaySendHasACall(t *testing.T) {
	calls := map[string]string{
		toolkit.MethodNotifyHUD:               "Notify.HUD",
		toolkit.MethodNotifyBeep:              "Notify.Beep",
		toolkit.MethodOpenURL:                 "Open.URL",
		toolkit.MethodClipboardReadText:       "Clipboard.ReadText",
		toolkit.MethodClipboardWriteText:      "Clipboard.WriteText",
		toolkit.MethodKeystrokesPaste:         "Keystrokes.Paste",
		toolkit.MethodKeystrokesPressMenuItem: "Keystrokes.PressMenuItem",
		toolkit.MethodProcessesTerminate:      "Processes.Terminate",
		toolkit.MethodStorageGet:              "Storage.Get",
		toolkit.MethodStorageSet:              "Storage.Set",
		toolkit.MethodUIBadge:                 "UI.Badge",
		toolkit.MethodUIStatus:                "UI.Status",
	}
	wanted := 0
	for _, method := range toolkit.Methods {
		if method.Sender != "tool" || method.Kind != "request" {
			continue
		}
		wanted++
		call, ok := calls[method.Name]
		if !ok {
			t.Errorf("%s has no call on App", method.Name)
			continue
		}
		group, name, _ := strings.Cut(call, ".")
		field, ok := reflect.TypeOf(toolkit.App{}).FieldByName(group)
		if !ok {
			t.Errorf("App has no %s", group)
			continue
		}
		if _, ok := field.Type.MethodByName(name); !ok {
			t.Errorf("App.%s has no %s, for %s", group, name, method.Name)
		}
	}
	if wanted != len(calls) || wanted != 12 {
		t.Errorf("%d requests a tool may send, %d calls; each request once", wanted, len(calls))
	}
}

func TestHelloACommandAndGoodbye(t *testing.T) {
	b := (&bench{}).hello().run("hello", 2).goodbye()
	tool := b.tool()
	ran := 0
	var seen []string
	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		ran++
		seen = []string{app.Language(), app.DataFolder()}
		return nil
	})
	if status := tool.Serve(); status != 0 {
		t.Fatalf("status %d", status)
	}
	if ran != 1 {
		t.Errorf("ran %d times", ran)
	}
	if !reflect.DeepEqual(seen, []string{"de-DE", "/tmp/kit-data"}) {
		t.Errorf("what the app said at hello is the handler's to read: %v", seen)
	}
	same(t, b.lines(t),
		`{"jsonrpc":"2.0","id":"hello","result":{"protocolVersion":"1","toolVersion":"9.9.9"}}`,
		`{"jsonrpc":"2.0","id":2,"result":{}}`)
}

func TestAHandlerCallsTheAppAndReadsTheAnswer(t *testing.T) {
	b := (&bench{}).hello().run("copy", 2).
		app(`{"jsonrpc":"2.0","id":1,"result":{"text":"from the clipboard"}}`).
		app(`{"jsonrpc":"2.0","id":2,"result":{}}`).
		goodbye()
	tool := b.tool()
	var read string
	tool.Command("copy", func(ctx context.Context, app *toolkit.App) error {
		text, _, err := app.Clipboard.ReadText()
		if err != nil {
			return err
		}
		read = text
		return app.Notify.HUD("Read it", "doc.on.clipboard")
	})
	tool.Serve()
	if read != "from the clipboard" {
		t.Errorf("read %q", read)
	}
	written := b.lines(t)
	if len(written) != 4 {
		t.Fatalf("%d messages written", len(written))
	}
	same(t, written[1:],
		`{"jsonrpc":"2.0","id":1,"method":"clipboard/readText","params":{}}`,
		`{"jsonrpc":"2.0","id":2,"method":"notify/hud","params":{"icon":"doc.on.clipboard","message":"Read it"}}`,
		`{"jsonrpc":"2.0","id":2,"result":{}}`)
}

func TestAnAnswerToAnotherRequestIsNotTakenForThisOne(t *testing.T) {
	// Two answers nobody waits for, as a call that gave up would leave
	// behind, come before the one the handler waits for.
	b := (&bench{}).hello().run("copy", 2).
		app(`{"jsonrpc":"2.0","id":98,"error":{"code":-32004,"message":"not available right now"}}`).
		app(`{"jsonrpc":"2.0","id":99,"result":{"text":"somebody else's"}}`).
		app(`{"jsonrpc":"2.0","id":1,"result":{"text":"mine"}}`).
		goodbye()
	tool := b.tool()
	var read string
	tool.Command("copy", func(ctx context.Context, app *toolkit.App) error {
		text, _, err := app.Clipboard.ReadText()
		read = text
		return err
	})
	tool.Serve()
	if read != "mine" {
		t.Errorf("read %q", read)
	}
	written := b.lines(t)
	same(t, written[len(written)-1:], `{"jsonrpc":"2.0","id":2,"result":{}}`)
}

func TestARefusalTheHandlerLetsThroughRefusesTheCommand(t *testing.T) {
	b := (&bench{}).hello().run("hello", 7).
		app(`{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"not listed in uses","data":{"service":"notify"}}}`).
		goodbye()
	tool := b.tool()
	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		return app.Notify.HUD("Hello", "hand.wave")
	})
	tool.Serve()
	written := b.lines(t)
	// The app's reason goes with it, for the log.
	same(t, written[len(written)-1:],
		`{"jsonrpc":"2.0","id":7,"error":{"code":-32010,"message":"command refused","data":{"code":-32001,"message":"not listed in uses","data":{"service":"notify"}}}}`)
}

func TestAHandlerMayCatchARefusalAndCarryOn(t *testing.T) {
	b := (&bench{}).hello().run("hello", 7).
		app(`{"jsonrpc":"2.0","id":1,"error":{"code":-32004,"message":"not available right now"}}`).
		goodbye()
	tool := b.tool()
	why := 0
	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		var refusal *toolkit.Error
		if err := app.Notify.Beep(); errors.As(err, &refusal) {
			why = refusal.Code
		}
		return nil
	})
	tool.Serve()
	if why != toolkit.CodeUnavailable {
		t.Errorf("why %d", why)
	}
	written := b.lines(t)
	same(t, written[len(written)-1:], `{"jsonrpc":"2.0","id":7,"result":{}}`)
}

func TestACommandThatWillNotRunSaysWhy(t *testing.T) {
	b := (&bench{}).hello().run("hello", 3).run("missing", 4).
		app(`{"jsonrpc":"2.0","id":5,"method":"island/draw"}`).
		goodbye()
	tool := b.tool()
	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		return toolkit.Refuse("nothing is selected")
	})
	tool.Serve()
	same(t, b.lines(t)[1:],
		`{"jsonrpc":"2.0","id":3,"error":{"code":-32010,"message":"nothing is selected"}}`,
		`{"jsonrpc":"2.0","id":4,"error":{"code":-32602,"message":"no such command"}}`,
		`{"jsonrpc":"2.0","id":5,"error":{"code":-32601,"message":"method not found"}}`)
}

func TestWhatComesWhileAHandlerWaitsIsHandledAfterIt(t *testing.T) {
	b := (&bench{}).hello().run("first", 2).
		app(`{"jsonrpc":"2.0","method":"language/changed","params":{"language":"fr"}}`).
		run("second", 3).
		app(`{"jsonrpc":"2.0","id":1,"result":{}}`).
		app(`{"jsonrpc":"2.0","id":2,"result":{}}`).
		goodbye()
	tool := b.tool()
	var order []string
	for _, name := range []string{"first", "second"} {
		tool.Command(name, func(ctx context.Context, app *toolkit.App) error {
			if err := app.Notify.Beep(); err != nil {
				return err
			}
			order = append(order, name+" in "+app.Language())
			return nil
		})
	}
	tool.Serve()
	if !reflect.DeepEqual(order, []string{"first in de-DE", "second in fr"}) {
		t.Errorf("kept in the order it came: %v", order)
	}
	var answered []any
	for _, line := range b.lines(t) {
		if message := line.(map[string]any); message["result"] != nil {
			answered = append(answered, message["id"])
		}
	}
	if !reflect.DeepEqual(answered, []any{"hello", 2.0, 3.0}) {
		t.Errorf("answered %v", answered)
	}
}

func TestGoodbyeWhileAHandlerWaitsEndsTheWait(t *testing.T) {
	b := (&bench{}).hello().run("hello", 2).goodbye()
	tool := b.tool()
	var thrown error
	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		thrown = app.Notify.Beep()
		return thrown
	})
	if status := tool.Serve(); status != 0 {
		t.Fatalf("status %d", status)
	}
	if !errors.Is(thrown, toolkit.ErrLinkClosed) {
		t.Errorf("thrown %v", thrown)
	}
	written := b.lines(t)
	failure, _ := written[len(written)-1].(map[string]any)["error"].(map[string]any)
	if failure == nil || failure["code"] != -32010.0 {
		t.Errorf("not refused: %v", written[len(written)-1])
	}
}

func TestTheLinkEndingEndsTheWaitAndTheLoop(t *testing.T) {
	b := (&bench{}).hello().run("hello", 2)
	tool := b.tool()
	var thrown error
	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		thrown = app.Notify.Beep()
		return nil
	})
	if status := tool.Serve(); status != 0 {
		t.Fatalf("the app going away is not the tool's failure: status %d", status)
	}
	if !errors.Is(thrown, toolkit.ErrLinkClosed) {
		t.Errorf("thrown %v", thrown)
	}
}

func TestACallGivesUpWhenNoAnswerComes(t *testing.T) {
	// A pipe, so that the link stays open with nothing on it.
	reading, writing := io.Pipe()
	go func() {
		_, _ = io.WriteString(writing,
			`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersions":["1"],"language":"en","dataFolder":"/tmp"}}`+"\n"+
				`{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"hello"}}`+"\n")
	}()
	var written bytes.Buffer
	tool := toolkit.NewLink("1", reading, &written)
	tool.AnswerTimeout = 50 * time.Millisecond
	var thrown error
	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		thrown = app.Notify.Beep()
		// The app goes away, which ends the loop.
		writing.Close()
		return nil
	})
	started := time.Now()
	if status := tool.Serve(); status != 0 {
		t.Fatalf("status %d", status)
	}
	var late *toolkit.NoAnswerError
	if !errors.As(thrown, &late) || late.After != 50*time.Millisecond {
		t.Errorf("thrown %v", thrown)
	}
	if time.Since(started) > 5*time.Second {
		t.Errorf("took %v", time.Since(started))
	}
}

func TestTheNewestVersionBothSpeakIsPicked(t *testing.T) {
	for _, pair := range [][2]string{{`["1","2"]`, "2"}, {`["1"]`, "1"}, {`["2","1"]`, "2"}, {`["2","3"]`, "2"}} {
		b := (&bench{}).helloOffering(pair[0]).goodbye()
		b.tool().Serve()
		same(t, b.lines(t), `{"jsonrpc":"2.0","id":"hello","result":{"protocolVersion":"`+pair[1]+`","toolVersion":"9.9.9"}}`)
	}
}

func TestAVersionTheToolDoesNotSpeakIsRefused(t *testing.T) {
	b := (&bench{}).helloOffering(`["3"]`).run("hello", 2).goodbye()
	tool := b.tool()
	ran := false
	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		ran = true
		return nil
	})
	tool.Serve()
	if ran {
		t.Error("ran")
	}
	same(t, b.lines(t),
		`{"jsonrpc":"2.0","id":"hello","error":{"code":-32602,"message":"this tool speaks protocols 1 and 2 only"}}`,
		`{"jsonrpc":"2.0","id":2,"error":{"code":-32600,"message":"initialize comes first"}}`)
}

func TestNoticesReachTheirHandlersAndTheToolsOwnAreWritten(t *testing.T) {
	b := (&bench{}).hello().
		app("this line is not a message").
		app(`{"jsonrpc":"2.0","method":"preferences/changed","params":{"values":{"project":"web"}}}`).
		app(`{"jsonrpc":"2.0","method":"language/changed","params":{"language":"ja"}}`).
		goodbye()
	tool := b.tool()
	var changed map[string]any
	language := ""
	tool.OnStart = func(app *toolkit.App) {
		app.SetRunnable("hello")
		app.Log("started")
	}
	tool.OnPreferencesChanged = func(app *toolkit.App, values map[string]any) { changed = values }
	tool.OnLanguageChanged = func(app *toolkit.App) { language = app.Language() }
	tool.Serve()
	if !reflect.DeepEqual(changed, map[string]any{"project": "web"}) {
		t.Errorf("changed %v", changed)
	}
	if language != "ja" {
		t.Errorf("language %q", language)
	}
	// After the answer to initialize, never before it.
	same(t, b.lines(t)[1:],
		`{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":["hello"]}}`,
		`{"jsonrpc":"2.0","method":"log","params":{"message":"started"}}`)
}

// A tool whose standard output is a pipe nobody reads any more ends with 0
// at its first write, as the Swift kit does: a closed link is the end of
// the conversation, not a crash. The test starts itself again as that tool.
func TestAClosedLinkIsAnEndNotACrash(t *testing.T) {
	if os.Getenv("VITRUVIAN_TOOLKIT_CLOSED_LINK") == "1" {
		tool := toolkit.New("1")
		tool.Command("hello", func(ctx context.Context, app *toolkit.App) error { return nil })
		os.Exit(tool.Serve())
	}
	reading, writing, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	reading.Close()
	run := exec.Command(os.Args[0], "-test.run=^TestAClosedLinkIsAnEndNotACrash$")
	run.Env = append(os.Environ(), "VITRUVIAN_TOOLKIT_CLOSED_LINK=1")
	run.Stdin = strings.NewReader((&bench{}).hello().run("hello", 2).goodbye().sent.String())
	run.Stdout = writing
	done := make(chan error, 1)
	if err := run.Start(); err != nil {
		t.Fatal(err)
	}
	writing.Close()
	go func() { done <- run.Wait() }()
	select {
	case err := <-done:
		if err != nil {
			t.Errorf("the tool did not end with 0: %v", err)
		}
	case <-time.After(20 * time.Second):
		_ = run.Process.Kill()
		t.Fatal("the tool did not end")
	}
}

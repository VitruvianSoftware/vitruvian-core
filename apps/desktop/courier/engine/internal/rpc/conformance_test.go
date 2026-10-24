// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

// The conformance test holds the engine to apps/desktop/courier/protocol: protocol.json is the definition and
// examples/*.json show each method and notification. Every example must fit the definition, and the engine,
// running on the fake network, must answer each example's request with a response of the same shape: the same
// keys and the same JSON types all the way down. Values are not compared (IDs, times and paths differ from run to
// run), except the envelope's id and an error's code and message, which are fixed.

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/login"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/search"
	"github.com/VitruvianSoftware/courier/engine/internal/searchtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// protocolDir finds apps/desktop/courier/protocol: in the test's runfiles under Bazel, and by its place in the
// source tree under plain go test (which runs in this package's directory).
func protocolDir(t *testing.T) string {
	t.Helper()
	const rel = "apps/desktop/courier/protocol"
	var tried []string
	if srcdir := os.Getenv("TEST_SRCDIR"); srcdir != "" {
		ws := os.Getenv("TEST_WORKSPACE")
		if ws == "" {
			ws = "_main"
		}
		tried = append(tried, filepath.Join(srcdir, ws, rel), filepath.Join(srcdir, rel))
	}
	tried = append(tried, filepath.Join("..", "..", "..", "protocol"))
	for _, dir := range tried {
		if _, err := os.Stat(filepath.Join(dir, "protocol.json")); err == nil {
			return dir
		}
	}
	t.Fatalf("protocol.json not found; tried %v", tried)
	return ""
}

type fieldSpec struct {
	Type   string   `json:"type"`
	Values []string `json:"values"`
}

type typeSpec struct {
	Fields map[string]fieldSpec `json:"fields"`
}

type methodSpec struct {
	Params string `json:"params"`
	Result string `json:"result"`
	Errors []int  `json:"errors"`
}

type errorSpec struct {
	Code    int    `json:"code"`
	Name    string `json:"name"`
	Message string `json:"message"`
	Data    string `json:"data"`
}

type protocolSpec struct {
	Protocol  int `json:"protocol"`
	Transport struct {
		MaxFrameBytes int `json:"max_frame_bytes"`
	} `json:"transport"`
	// Conventions are numbers both sides keep to (protocol 5).
	Conventions struct {
		TypingRepeatMS *int64 `json:"typing_repeat_ms"`
	} `json:"conventions"`
	Types         map[string]typeSpec   `json:"types"`
	Methods       map[string]methodSpec `json:"methods"`
	Notifications map[string]struct {
		Params string `json:"params"`
	} `json:"notifications"`
	Errors struct {
		Codes []errorSpec `json:"codes"`
	} `json:"errors"`
}

func (p *protocolSpec) errorByCode(code int) (errorSpec, bool) {
	for _, e := range p.Errors.Codes {
		if e.Code == code {
			return e, true
		}
	}
	return errorSpec{}, false
}

// anyMethodCodes are the codes any request can get, whatever its method lists.
var anyMethodCodes = []int{-32700, -32600, -32601, -32602, -32603, -32002}

type example struct {
	name         string
	Request      map[string]any `json:"request"`
	Response     map[string]any `json:"response"`
	Notification map[string]any `json:"notification"`
}

func loadProtocol(t *testing.T) (*protocolSpec, []example) {
	t.Helper()
	dir := protocolDir(t)
	raw, err := os.ReadFile(filepath.Join(dir, "protocol.json"))
	require.NoError(t, err)
	var p protocolSpec
	require.NoError(t, json.Unmarshal(raw, &p))
	files, err := filepath.Glob(filepath.Join(dir, "examples", "*.json"))
	require.NoError(t, err)
	require.NotEmpty(t, files)
	sort.Strings(files)
	var exs []example
	for _, f := range files {
		b, err := os.ReadFile(f)
		require.NoError(t, err)
		var ex example
		require.NoError(t, json.Unmarshal(b, &ex), f)
		ex.name = strings.TrimSuffix(filepath.Base(f), ".json")
		require.True(t, (ex.Request != nil && ex.Response != nil) != (ex.Notification != nil),
			"%s: an example is a request and its response, or one notification", f)
		exs = append(exs, ex)
	}
	return &p, exs
}

// typeExpr is one parsed type from the protocol's type grammar.
type typeExpr struct {
	optional, nullable bool
	list               bool
	mapOf              bool
	base               string // string, int, bool, object, or a type name
}

func parseType(s string) typeExpr {
	var e typeExpr
	if e.optional = strings.HasSuffix(s, "?"); e.optional {
		s = strings.TrimSuffix(s, "?")
	}
	if e.nullable = strings.HasSuffix(s, "|null"); e.nullable {
		s = strings.TrimSuffix(s, "|null")
	}
	if e.list = strings.HasSuffix(s, "[]"); e.list {
		s = strings.TrimSuffix(s, "[]")
	}
	if inner, ok := strings.CutPrefix(s, "map<"); ok {
		e.mapOf, s = true, strings.TrimSuffix(inner, ">")
	}
	e.base = s
	return e
}

// check says whether v fits the type expression (optional is the caller's business: v is present here).
func (p *protocolSpec) check(v any, typ string, values []string, path string) error {
	e := parseType(typ)
	if v == nil {
		if e.nullable {
			return nil
		}
		return fmt.Errorf("%s: null where %s is wanted", path, typ)
	}
	if e.list {
		arr, ok := v.([]any)
		if !ok {
			return fmt.Errorf("%s: want a list of %s, got %T", path, e.base, v)
		}
		for i, el := range arr {
			if err := p.check(el, e.base, values, fmt.Sprintf("%s[%d]", path, i)); err != nil {
				return err
			}
		}
		return nil
	}
	if e.mapOf {
		obj, ok := v.(map[string]any)
		if !ok {
			return fmt.Errorf("%s: want an object of %s, got %T", path, e.base, v)
		}
		for k, el := range obj {
			if err := p.check(el, e.base, nil, path+"."+k); err != nil {
				return err
			}
		}
		return nil
	}
	switch e.base {
	case "string":
		s, ok := v.(string)
		if !ok {
			return fmt.Errorf("%s: want a string, got %T", path, v)
		}
		if values != nil && !slices.Contains(values, s) {
			return fmt.Errorf("%s: %q is not one of %v", path, s, values)
		}
	case "int":
		n, ok := v.(float64)
		if !ok || n != float64(int64(n)) {
			return fmt.Errorf("%s: want an int, got %v", path, v)
		}
	case "bool":
		if _, ok := v.(bool); !ok {
			return fmt.Errorf("%s: want a bool, got %T", path, v)
		}
	case "object":
		if _, ok := v.(map[string]any); !ok {
			return fmt.Errorf("%s: want an object, got %T", path, v)
		}
	default:
		ts, ok := p.Types[e.base]
		if !ok {
			return fmt.Errorf("%s: unknown type %s", path, e.base)
		}
		obj, ok := v.(map[string]any)
		if !ok {
			return fmt.Errorf("%s: want a %s object, got %T", path, e.base, v)
		}
		for k := range obj {
			if _, ok := ts.Fields[k]; !ok {
				return fmt.Errorf("%s: %s has no field %q", path, e.base, k)
			}
		}
		for name, f := range ts.Fields {
			fv, present := obj[name]
			if !present {
				if parseType(f.Type).optional {
					continue
				}
				return fmt.Errorf("%s: %s needs %q", path, e.base, name)
			}
			if err := p.check(fv, f.Type, f.Values, path+"."+name); err != nil {
				return err
			}
		}
	}
	return nil
}

// checkExample holds one example to the definition.
func (p *protocolSpec) checkExample(ex example) error {
	if ex.Notification != nil {
		n := ex.Notification
		if n["jsonrpc"] != "2.0" {
			return fmt.Errorf("jsonrpc must be 2.0")
		}
		if _, ok := n["id"]; ok {
			return fmt.Errorf("a notification has no id")
		}
		method, _ := n["method"].(string)
		spec, ok := p.Notifications[method]
		if !ok {
			return fmt.Errorf("no notification %q in protocol.json", method)
		}
		return p.check(n["params"], spec.Params, nil, method+".params")
	}
	req, resp := ex.Request, ex.Response
	if req["jsonrpc"] != "2.0" || resp["jsonrpc"] != "2.0" {
		return fmt.Errorf("jsonrpc must be 2.0")
	}
	if req["id"] == nil || req["id"] != resp["id"] {
		return fmt.Errorf("the response must carry the request's id")
	}
	method, _ := req["method"].(string)
	spec, known := p.Methods[method]
	params, hasParams := req["params"]
	if !hasParams {
		params = map[string]any{}
	}
	if known {
		if err := p.check(params, spec.Params, nil, method+".params"); err != nil {
			return err
		}
	}
	_, hasResult := resp["result"]
	rawErr, hasError := resp["error"]
	switch {
	case hasResult == hasError:
		return fmt.Errorf("a response has a result or an error, not both or neither")
	case hasResult:
		if !known {
			return fmt.Errorf("a result for %q, which protocol.json does not define", method)
		}
		return p.check(resp["result"], spec.Result, nil, method+".result")
	}
	e, ok := rawErr.(map[string]any)
	if !ok {
		return fmt.Errorf("error must be an object")
	}
	for k := range e {
		if k != "code" && k != "message" && k != "data" {
			return fmt.Errorf("error has an unknown key %q", k)
		}
	}
	code, _ := e["code"].(float64)
	es, ok := p.errorByCode(int(code))
	if !ok {
		return fmt.Errorf("error code %v is not in protocol.json", e["code"])
	}
	if e["message"] != es.Message {
		return fmt.Errorf("error %d's message is %q, not %q", es.Code, es.Message, e["message"])
	}
	allowed := append(slices.Clone(anyMethodCodes), spec.Errors...)
	if method == "hello" {
		allowed = append(allowed, -32001)
	}
	if !slices.Contains(allowed, es.Code) {
		return fmt.Errorf("%s does not list error %d", method, es.Code)
	}
	data, hasData := e["data"]
	switch {
	case es.Data == "" && hasData:
		return fmt.Errorf("error %d carries no data", es.Code)
	case es.Data != "" && !hasData:
		return fmt.Errorf("error %d needs data", es.Code)
	case hasData:
		return p.check(data, es.Data, nil, "error.data")
	}
	return nil
}

func TestEveryExampleFitsTheProtocol(t *testing.T) {
	p, exs := loadProtocol(t)
	require.Equal(t, Protocol, p.Protocol, "protocol.json and the engine speak the same protocol")
	require.Equal(t, MaxFrameBytes, p.Transport.MaxFrameBytes)
	for _, ex := range exs {
		require.NoError(t, p.checkExample(ex), ex.name)
	}

	// Every method and notification has an example, and so does every kind of change.
	seen := map[string]bool{}
	kinds := map[string]bool{}
	for _, ex := range exs {
		if ex.Notification != nil {
			seen[ex.Notification["method"].(string)] = true
			kinds[ex.Notification["params"].(map[string]any)["kind"].(string)] = true
			continue
		}
		if _, ok := ex.Response["result"]; ok {
			seen[ex.Request["method"].(string)] = true
		}
	}
	for m := range p.Methods {
		require.True(t, seen[m], "method %s has no example of it succeeding", m)
	}
	for n := range p.Notifications {
		require.True(t, seen[n], "notification %s has no example", n)
	}
	for _, k := range p.Types["Changed"].Fields["kind"].Values {
		require.True(t, kinds[k], "changed kind %s has no example", k)
	}
	// Every value of the fields whose values grew in protocol 5 is shown by an example.
	require.NoError(t, p.examplesShowEveryValue(exs, "Event.status", "InboxRow.preview_status"))
	for _, name := range []string{"hello-protocol-mismatch", "message.send-not-linked"} {
		require.True(t, slices.ContainsFunc(exs, func(ex example) bool { return ex.name == name }), "missing example %s", name)
	}
}

// The app pulses room.setTyping every conventions.typing_repeat_ms, and the engine's renewal is set from the same
// number (actions.TypingRepeat): the Swift side reads it from the file too, so the two can't drift.
func TestTypingRepeatMatchesTheProtocol(t *testing.T) {
	p, _ := loadProtocol(t)
	require.NotNil(t, p.Conventions.TypingRepeatMS, "protocol.json has conventions.typing_repeat_ms")
	require.Equal(t, *p.Conventions.TypingRepeatMS, actions.TypingRepeat.Milliseconds())
}

// examplesShowEveryValue says which values of fields ("Type.field") no example's request or result shows.
func (p *protocolSpec) examplesShowEveryValue(exs []example, fields ...string) error {
	seen := map[string]map[string]bool{}
	for _, ex := range exs {
		if ex.Request == nil {
			continue
		}
		spec, ok := p.Methods[fmt.Sprint(ex.Request["method"])]
		if !ok {
			continue
		}
		if params, ok := ex.Request["params"]; ok {
			p.valuesIn(params, spec.Params, seen)
		}
		if result, ok := ex.Response["result"]; ok {
			p.valuesIn(result, spec.Result, seen)
		}
	}
	var missing []string
	for _, f := range fields {
		typ, field, _ := strings.Cut(f, ".")
		for _, v := range p.Types[typ].Fields[field].Values {
			if !seen[f][v] {
				missing = append(missing, fmt.Sprintf("%s %q", f, v))
			}
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("no example shows %s", strings.Join(missing, ", "))
	}
	return nil
}

// valuesIn records, in seen, every value v holds for a field with values, walking it as typ.
func (p *protocolSpec) valuesIn(v any, typ string, seen map[string]map[string]bool) {
	e := parseType(typ)
	switch x := v.(type) {
	case []any:
		for _, el := range x {
			p.valuesIn(el, e.base, seen)
		}
	case map[string]any:
		ts, ok := p.Types[e.base]
		if !ok {
			return
		}
		for name, f := range ts.Fields {
			fv, present := x[name]
			if !present {
				continue
			}
			if s, isString := fv.(string); isString && f.Values != nil {
				key := e.base + "." + name
				if seen[key] == nil {
					seen[key] = map[string]bool{}
				}
				seen[key][s] = true
				continue
			}
			p.valuesIn(fv, f.Type, seen)
		}
	}
}

func TestServerSpeaksExactlyTheProtocolsMethods(t *testing.T) {
	p, _ := loadProtocol(t)
	var defined, served []string
	for m := range p.Methods {
		defined = append(defined, m)
	}
	served = append(served, "hello") // answered by the connection itself
	for m := range methods {
		served = append(served, m)
	}
	require.ElementsMatch(t, defined, served)
}

func TestErrorTableMatchesTheProtocol(t *testing.T) {
	p, _ := loadProtocol(t)
	got := map[int]string{}
	for code, msg := range errorMessages {
		got[code] = msg
	}
	want := map[int]string{}
	for _, e := range p.Errors.Codes {
		want[e.Code] = e.Message
	}
	require.Equal(t, want, got)
}

// sameShape compares a live value to an example's: the same JSON types, the same keys in every object, and
// lists alike element by element (or, when their lengths differ, every live element like the example's first).
// A field whose type is object (an event's content) is only checked to be an object.
func (p *protocolSpec) sameShape(want, got any, typ, path string) error {
	e := parseType(typ)
	if want == nil || got == nil {
		if want == nil && got == nil {
			return nil
		}
		return fmt.Errorf("%s: example has %v, engine sent %v", path, want, got)
	}
	switch w := want.(type) {
	case []any:
		g, ok := got.([]any)
		if !ok {
			return fmt.Errorf("%s: want a list, got %T", path, got)
		}
		if (len(w) == 0) != (len(g) == 0) {
			return fmt.Errorf("%s: example has %d items, engine sent %d", path, len(w), len(g))
		}
		for i := range g {
			wi := w[0]
			if len(w) == len(g) {
				wi = w[i]
			}
			if err := p.sameShape(wi, g[i], e.base, fmt.Sprintf("%s[%d]", path, i)); err != nil {
				return err
			}
		}
		return nil
	case map[string]any:
		g, ok := got.(map[string]any)
		if !ok {
			return fmt.Errorf("%s: want an object, got %T", path, got)
		}
		if e.base == "object" && !e.list {
			return nil
		}
		var wk, gk []string
		for k := range w {
			wk = append(wk, k)
		}
		for k := range g {
			gk = append(gk, k)
		}
		sort.Strings(wk)
		sort.Strings(gk)
		if !slices.Equal(wk, gk) {
			return fmt.Errorf("%s: example has keys %v, engine sent %v", path, wk, gk)
		}
		fields := p.Types[e.base].Fields
		for k := range w {
			ft := ""
			if f, ok := fields[k]; ok {
				ft = f.Type
			} else if e.mapOf {
				ft = e.base
			}
			if err := p.sameShape(w[k], g[k], ft, path+"."+k); err != nil {
				return err
			}
		}
		return nil
	default:
		if fmt.Sprintf("%T", want) != fmt.Sprintf("%T", got) {
			return fmt.Errorf("%s: example has a %T, engine sent a %T (%v)", path, want, got, got)
		}
		return nil
	}
}

// sameResponse compares the engine's response to the example's: the envelope exactly (id, error code and
// message), the rest by shape.
func (p *protocolSpec) sameResponse(method string, want, got map[string]any) error {
	var wk, gk []string
	for k := range want {
		wk = append(wk, k)
	}
	for k := range got {
		gk = append(gk, k)
	}
	sort.Strings(wk)
	sort.Strings(gk)
	if !slices.Equal(wk, gk) {
		return fmt.Errorf("example's response has %v, engine sent %v", wk, gk)
	}
	if fmt.Sprint(want["id"]) != fmt.Sprint(got["id"]) {
		return fmt.Errorf("id: want %v, got %v", want["id"], got["id"])
	}
	if we, ok := want["error"].(map[string]any); ok {
		ge, _ := got["error"].(map[string]any)
		if we["code"] != ge["code"] || we["message"] != ge["message"] {
			return fmt.Errorf("error: want %v %q, got %v %q", we["code"], we["message"], ge["code"], ge["message"])
		}
		es, _ := p.errorByCode(int(we["code"].(float64)))
		if (we["data"] == nil) != (ge["data"] == nil) {
			return fmt.Errorf("error data: want %v, got %v", we["data"], ge["data"])
		}
		if we["data"] != nil {
			return p.sameShape(we["data"], ge["data"], es.Data, "error.data")
		}
		return nil
	}
	return p.sameShape(want["result"], got["result"], p.Methods[method].Result, method+".result")
}

// rawCall sends one request line exactly as given and returns the decoded answer.
func (c *client) rawCall(req map[string]any) map[string]any {
	c.t.Helper()
	b, err := json.Marshal(req)
	require.NoError(c.t, err)
	id, err := json.Marshal(req["id"])
	require.NoError(c.t, err)
	ch := make(chan message, 1)
	c.mu.Lock()
	c.wait[string(id)] = ch
	c.mu.Unlock()
	c.writeLine(b)
	m := c.answer(ch)
	var out map[string]any
	require.NoError(c.t, json.Unmarshal(m.raw, &out))
	return out
}

func TestEveryExampleRoundTrips(t *testing.T) {
	p, exs := loadProtocol(t)
	for _, ex := range exs {
		t.Run(ex.name, func(t *testing.T) {
			t.Parallel()
			w := worldFor(t, ex.name)
			c := dial(t, w.path)
			if ex.Notification != nil {
				c.hello()
				want := ex.Notification["params"].(map[string]any)
				got := triggerNotification(t, w, c, ex.name)
				var gotMap map[string]any
				b, err := json.Marshal(got)
				require.NoError(t, err)
				require.NoError(t, json.Unmarshal(b, &gotMap))
				require.Equal(t, want["kind"], gotMap["kind"])
				require.NoError(t, p.check(gotMap, "Changed", nil, "changed.params"), "the live notification fits protocol.json")
				require.NoError(t, p.sameShape(want, gotMap, "Changed", "changed.params"))
				return
			}
			req := deepCopy(t, ex.Request)
			params, _ := req["params"].(map[string]any)
			prepare(t, w, ex.name, params)
			req = deepCopy(t, req) // as it goes on the wire
			method := req["method"].(string)
			wantErr, _ := ex.Response["error"].(map[string]any)
			code, _ := wantErr["code"].(float64)
			if method != "hello" && code != -32002 {
				c.hello()
			}
			got := c.rawCall(req)
			require.NoError(t, p.checkExample(example{Request: req, Response: got}),
				"the live response fits protocol.json (types, required fields, values): %v", got)
			require.NoError(t, p.sameResponse(method, ex.Response, got), "engine sent %v", got)
		})
	}
}

func deepCopy(t *testing.T, v map[string]any) map[string]any {
	t.Helper()
	b, err := json.Marshal(v)
	require.NoError(t, err)
	var out map[string]any
	require.NoError(t, json.Unmarshal(b, &out))
	return out
}

// worldFor is the world an example runs in: newWorld's, except where the example needs the engine in another state.
func worldFor(t *testing.T, name string) *world {
	t.Helper()
	if name == "accounts.list-starting" {
		return startingWorld(t)
	}
	if name == "room.directChat-not-connected" {
		return newWorldWaiting(t, 0) // the account is down: refused at once rather than after a real-time wait
	}
	return newWorld(t)
}

// startingWorld is an engine that has been told of every test network and started none: each is STARTING, as at
// launch before its bridge is up. whatsapp was linked when the engine last ran (its login's state is stored).
func startingWorld(t *testing.T) *world {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	require.NoError(t, s.SetLoginState(ctx, "whatsapp", "whatsapp-login", json.RawMessage(
		`{"state_event":"CONNECTED","remote_id":"whatsapp-login","remote_name":"Test Account","timestamp":1760600000}`,
	)))
	var specs []engine.Spec
	for _, n := range testNetworks {
		specs = append(specs, engine.Spec{Name: n.Name, Connector: func() (bridgev2.NetworkConnector, error) { return fakenet.New(), nil }})
	}
	eng := engine.New(s)
	t.Cleanup(eng.Stop)
	eng.Expect(specs)
	m := &media.Store{Dir: filepath.Join(dir, "media")}
	w := &world{s: s, m: m, eng: eng}
	w.deps = Deps{Store: s, Engine: eng, Actions: actions.New(eng, s, m), Media: m, Networks: testNetworks, Version: "0.5.0-test"}
	w.path = serve(t, w.deps)
	return w
}

// prepare sets up the world for one example and points its params at the world's own IDs, files and sign-ins
// (the example's are made up). Every example is named here, so a new one has to say what it needs.
func prepare(t *testing.T, w *world, name string, params map[string]any) {
	t.Helper()
	ctx := context.Background()
	failed := func() string {
		id := string(ids.RandomEventID())
		_, err := w.s.InsertEvent(ctx, store.Event{
			RoomID: w.room, EventID: id, Sender: string(ids.Me), Type: "m.room.message",
			Content: json.RawMessage(`{"msgtype":"m.text","body":"did not go"}`), TS: time.Now(),
			Status: "failed", StatusReason: "the network refused it",
		})
		require.NoError(t, err)
		return id
	}
	script := func(steps ...*bridgev2.LoginStep) { w.sig.Script = &fakenet.ScriptedLogin{Steps: steps} }
	waScript := func(steps ...*bridgev2.LoginStep) { w.wa.Script = &fakenet.ScriptedLogin{Steps: steps} }
	// waState stores a state of the whatsapp account accountID, as its bridge sends it.
	waState := func(accountID, event, name, message string) {
		require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", accountID, loginState(event, accountID, name, message)))
	}
	waAccount := func() string { return string(w.waLogin.ID) }
	startSignal := func() string {
		step, err := w.d.Start(ctx, "signal", fakenet.ScriptFlow, login.StartOptions{})
		require.NoError(t, err)
		return step.LoginID
	}
	label := func() int64 {
		l, err := w.s.CreateLabel(ctx, "Work", 3, "briefcase")
		require.NoError(t, err)
		return l.ID
	}
	remind := func() {
		require.NoError(t, w.s.SetReminder(ctx, []string{w.room}, time.Now().Add(time.Hour), "if_no_reply"))
	}
	rule := func() int64 {
		r, err := w.s.SetRule(ctx, store.Rule{Scope: "all", Trigger: "after_read", ChatType: "read", Duration: 10 * time.Minute, Enabled: true})
		require.NoError(t, err)
		return r.ID
	}
	one := []any{w.room}
	// mine is a text message of mine the network has, sent at ts.
	mine := func(ts time.Time) string {
		return w.put(t, string(ids.RandomEventID()), string(ids.Me), "m.room.message", `{"msgtype":"m.text","body":"Lunch at noon"}`, ts)
	}
	lunch := []richtext.Entity{{Kind: richtext.Bold, Offset: 9, Length: 4}, {Kind: richtext.Link, Offset: 0, Length: 5, URL: "https://example.test/lunch"}}
	schedule := func() int64 {
		sc, err := w.deps.Actions.Schedule(ctx, w.room, "Lunch at noon?", actions.SendOptions{Entities: lunch}, time.Now().Add(time.Hour), "if_no_reply")
		require.NoError(t, err)
		return sc.ID
	}
	switch name {
	case "hello", "hello-protocol-mismatch", "hello-required", "login.wait-unknown", "inbox.list-bad-cursor",
		"spaces.setLayout", "spaces.update", "labels.create", "reminder.clearAll", "inbox.markAllRead",
		"accounts.list-starting":
	case "inbox.list":
		// The row shows everything a chat can have at once: a pin, a label, a draft, a reminder, someone typing.
		require.NoError(t, w.s.SetPinned(ctx, w.room, true))
		_, err := w.s.SetLabel(ctx, []string{w.room}, label(), true)
		require.NoError(t, err)
		require.NoError(t, w.s.SetDraft(ctx, w.room, "Half a thought"))
		remind()
		w.s.SetTyping(w.room, "@whatsapp_contact:courier.local", time.Now().Add(time.Minute))
	case "inbox.list-first-page":
		addRooms(t, w.s, "whatsapp", "second", 1)
	case "inbox.list-room-ids", "room.setArchived", "room.setLowPriority", "room.setHidden", "room.setMarkedUnread",
		"inbox.archiveMatching":
		if _, ok := params["room_ids"]; ok {
			params["room_ids"] = one
		}
		if name == "inbox.list-room-ids" {
			mine(time.Now()) // the row's newest message is mine, and has gone
		}
	case "room.setArchived-pinned":
		require.NoError(t, w.s.SetPinned(ctx, w.room, true))
		params["room_ids"] = one
	case "room.setLowPriority-not-entitled":
		w.ent.deny.Store(true)
		params["room_ids"] = one
	case "spaces.list":
		label()
	case "labels.update", "labels.delete":
		params["label_id"] = label()
	case "room.setLabel":
		params["room_ids"], params["label_id"] = one, label()
	case "room.setPinned", "room.setDraft":
		params["room_id"] = w.room
	case "room.acceptRequest":
		require.NoError(t, w.s.SetRequest(ctx, w.room, true))
		params["room_id"] = w.room
	case "room.acceptRequest-not-supported":
		// Signal is running with no account: no one to send the accept.
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!request:courier.local", Network: "signal", Name: "Someone new"}))
		require.NoError(t, w.s.SetRequest(ctx, "!request:courier.local", true))
		params["room_id"] = "!request:courier.local"
	case "reminder.set":
		params["room_ids"], params["due_at"] = one, time.Now().Add(time.Hour).UnixMilli()
	case "reminder.clear":
		remind()
		params["room_ids"] = one
	case "autoArchive.list", "autoArchive.set":
		if name == "autoArchive.list" {
			rule()
		}
	case "autoArchive.delete":
		params["rule_id"] = rule()
	case "accounts.list":
		waState(waAccount(), "CONNECTED", "Test Account", "")
	case "accounts.list-two-accounts":
		h, ok := w.eng.Host("whatsapp")
		require.True(t, ok)
		second, err := w.wa.LoginAs(ctx, h.Bridge, "whatsapp-second", "Second Account")
		require.NoError(t, err)
		waState(waAccount(), "CONNECTED", "Test Account", "")
		waState(string(second.ID), "LOGGED_OUT", "Second Account", "You were signed out on your phone.")
	case "inbox.list-two-accounts":
		// Two accounts, the chat the first's, and my newest message in it read.
		require.NoError(t, w.s.SetRoomLogin(ctx, w.room, waAccount()))
		w.secondAccount(t)
		id := mine(time.Now())
		require.NoError(t, w.s.SetReceipt(ctx, w.room, contact, id, time.Now()))
		params["room_ids"] = one
	case "room.events-receipts":
		// My newest message reached the contact's phone and they read it.
		id := mine(time.Now())
		require.NoError(t, w.s.SetDelivered(ctx, w.room, contact, id, time.Time{}))
		require.NoError(t, w.s.SetReceipt(ctx, w.room, contact, id, time.Now()))
		params["room_id"] = w.room
	case "room.events-waiting":
		// Each state a message of mine can be in before it has gone: failed, pending, held (queued) and waiting.
		failed()
		_, err := w.s.InsertEvent(ctx, store.Event{
			RoomID: w.room, EventID: string(ids.RandomEventID()), Sender: string(ids.Me), Type: "m.room.message",
			Content: json.RawMessage(`{"msgtype":"m.text","body":"See you there"}`), TS: time.Now(), Status: "pending",
		})
		require.NoError(t, err)
		_, err = w.deps.Actions.Send(ctx, w.room, "Lunch at noon?", actions.SendOptions{Hold: 10 * time.Second})
		require.NoError(t, err)
		w.wa.SetLoggedIn(w.waLogin, false)
		_, err = w.deps.Actions.Send(ctx, w.room, "On my way", actions.SendOptions{})
		require.NoError(t, err)
		params["room_id"] = w.room
	case "room.events-waiting-no-account":
		// A chat of an account the bridge no longer has: its message waits with no account to go through.
		const orphan = "!orphan:courier.local"
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: orphan, Network: "whatsapp", Name: "Gone account's chat", LoginID: "gone-login"}))
		_, err := w.deps.Actions.Send(ctx, orphan, "Hello?", actions.SendOptions{})
		require.NoError(t, err)
		params["room_id"] = orphan
	case "inbox.list-delivered":
		id := mine(time.Now())
		require.NoError(t, w.s.SetDelivered(ctx, w.room, contact, id, time.Time{}))
		params["room_ids"] = one
	case "room.setTyping":
		params["room_id"] = w.room
	case "room.setUnreadFrom":
		params["event_id"] = w.events[0]
	case "room.setUnreadFrom-note":
		params["event_id"] = w.put(t, string(ids.RandomEventID()), contact, "m.room.message",
			`{"msgtype":"m.notice","body":"","com.beeper.action_message":{"type":"disappearing_timer","timer":86400000}}`, time.Now())
	case "room.directChat", "room.directChat-not-connected":
		// A group of the account's, with the contact in it; the chat with the contact is the world's own.
		const group = "!lunchgroup:courier.local"
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: group, Network: "whatsapp", Name: "Lunch group", LoginID: waAccount()}))
		require.NoError(t, w.s.SetMember(ctx, group, contact, json.RawMessage(`{"membership":"join"}`)))
		w.direct(t)
		params["room_id"], params["user_id"] = group, contact
		if name == "room.directChat-not-connected" {
			// Someone Courier has no chat with, and the account down: the network can't be asked in time.
			const someone = "@whatsapp_someone:courier.local"
			require.NoError(t, w.s.SetMember(ctx, group, someone, json.RawMessage(`{"membership":"join"}`)))
			w.wa.SetLoggedIn(w.waLogin, false)
			params["user_id"] = someone
		}
	case "message.send-waiting":
		w.wa.SetLoggedIn(w.waLogin, false)
		params["room_id"] = w.room
	case "message.undo-waiting":
		w.wa.SetLoggedIn(w.waLogin, false)
		id, err := w.deps.Actions.Send(ctx, w.room, "On my way", actions.SendOptions{})
		require.NoError(t, err)
		e, _, err := w.s.GetEvent(ctx, id)
		require.NoError(t, err)
		require.Equal(t, store.StatusWaiting, e.Status)
		params["event_id"] = id
	case "login.start-another":
		waState(waAccount(), "CONNECTED", "Test Account", "")
		waScript(qrStep())
		params["flow"] = fakenet.ScriptFlow
	case "login.start-relink":
		waState(waAccount(), "LOGGED_OUT", "Test Account", "You were signed out on your phone.")
		waScript(qrStep())
		params["flow"], params["account_id"] = fakenet.ScriptFlow, waAccount()
	case "login.start-unknown-account":
		params["flow"] = fakenet.ScriptFlow
	case "login.wait-other-account":
		waState(waAccount(), "LOGGED_OUT", "Test Account", "You were signed out on your phone.")
		waScript(qrStep(), waComplete("whatsapp-second", "Second Account"))
		step, err := w.d.Start(ctx, "whatsapp", fakenet.ScriptFlow, login.StartOptions{AccountID: waAccount()})
		require.NoError(t, err)
		params["login_id"] = step.LoginID
	case "method-not-found", "invalid-params", "room.events", "room.markRead", "room.setMuted":
		params["room_id"] = w.room
	case "room.events-older":
		_, before, err := w.s.EventsBefore(ctx, w.room, nil, 2)
		require.NoError(t, err)
		require.NotNil(t, before)
		params["room_id"] = w.room
		params["before"] = map[string]any{"ts": before.TS.UnixMilli(), "seq": before.Seq}
	case "room.events-around":
		// Two newer messages, so the page around the second has the oldest end and a newer page after it.
		for i := range 2 {
			say(t, w.s, w.room, "@whatsapp_contact:courier.local", "later", time.Now().Add(time.Duration(i+1)*time.Minute))
		}
		params["room_id"], params["around"] = w.room, w.events[1]
	case "room.events-newer":
		e, ok, err := w.s.GetEvent(ctx, w.events[0])
		require.NoError(t, err)
		require.True(t, ok)
		params["room_id"], params["after"] = w.room, map[string]any{"ts": e.TS.UnixMilli(), "seq": e.Seq}
	case "room.events-around-not-found":
		params["room_id"] = w.room
	case "search.query-emoji", "search.query-bad-cursor":
	case "search.query-home":
		// The chat open now was archived last: last_archived is the one before it.
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!opened:courier.local", Network: "whatsapp", Name: "Open now"}))
		for _, id := range []string{w.room, "!opened:courier.local"} {
			_, err := w.s.SetArchived(ctx, []string{id}, true)
			require.NoError(t, err)
		}
		params["open_room_id"] = "!opened:courier.local"
	case "search.query", "search.query-next-page":
		picnic(t, w)
		if name == "search.query-next-page" {
			res, err := search.New(w.s).Query(ctx, search.Request{Text: "picnic", Sections: []search.Section{search.Messages}, Limit: 1})
			require.NoError(t, err)
			require.NotEmpty(t, res.Messages.Next)
			params["cursor"] = res.Messages.Next
		}
	case "search.query-in-chat":
		r, ok, err := w.s.GetRoom(ctx, w.room)
		require.NoError(t, err)
		require.True(t, ok)
		r.IsDirect = true
		require.NoError(t, w.s.UpsertRoom(ctx, r))
		say(t, w.s, w.room, "@whatsapp_contact:courier.local", "Are you free later?", time.Now())
		params["filters"].(map[string]any)["room_ids"] = one
	case "message.send":
		params["room_id"], params["reply_to"] = w.room, w.events[2]
	case "message.send-not-linked":
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!unlinked:courier.local", Network: "signal", Name: "Not linked"}))
		params["room_id"] = "!unlinked:courier.local"
	case "message.sendFile":
		path := filepath.Join(t.TempDir(), "example.png")
		require.NoError(t, os.WriteFile(path, []byte("\x89PNG\r\n\x1a\nnot really a picture"), 0o600))
		params["room_id"], params["path"] = w.room, path
	case "message.react":
		params["room_id"], params["event_id"] = w.room, w.events[2]
	case "message.retry", "message.discard":
		params["event_id"] = failed()
	case "message.retry-not-failed":
		params["event_id"] = w.events[0]
	case "room.features":
		w.can(t, everything())
		_, err := w.s.SetState(ctx, w.room, "com.beeper.disappearing_timer", "", json.RawMessage(`{"type":"after_send","timer":604800000}`))
		require.NoError(t, err)
		params["room_id"] = w.room
	case "room.members":
		require.NoError(t, w.s.SetMember(ctx, w.room, "@whatsapp_ana:courier.local", json.RawMessage(`{"membership":"join","displayname":"Ana Example"}`)))
		params["room_id"] = w.room
	case "room.setDisappearing", "poll.create", "message.send-held":
		w.can(t, everything())
		params["room_id"] = w.room
		if name == "room.setDisappearing" {
			params["timer_ms"] = 86400000 // one everything() offers
		}
	case "message.send-thread", "message.sendFile-held":
		w.can(t, everything())
		params["room_id"], params["thread_root"] = w.room, w.events[0]
		if name == "message.sendFile-held" {
			path := filepath.Join(t.TempDir(), "example.png")
			require.NoError(t, os.WriteFile(path, []byte("\x89PNG\r\n\x1a\nnot really a picture"), 0o600))
			params["path"] = path
		}
	case "message.edit", "message.unsend":
		w.can(t, everything())
		params["event_id"] = mine(time.Now())
	case "message.edit-too-old":
		w.can(t, everything()) // edits for 15 minutes
		params["event_id"] = mine(time.Now().Add(-time.Hour))
	case "message.unsend-not-yours", "message.deleteForMe", "message.setBookmarked", "message.history",
		"message.undo-already-sent":
		params["event_id"] = w.events[0]
	case "message.forward":
		params["event_id"], params["room_ids"] = w.events[0], []any{w.room, "!nope:courier.local"}
	case "message.undo":
		w.can(t, everything())
		id, err := w.deps.Actions.Send(ctx, w.room, "Lunch at noon?", actions.SendOptions{Entities: lunch, Hold: 10 * time.Second})
		require.NoError(t, err)
		params["event_id"] = id
	case "message.sendHeld", "message.schedule", "scheduled.list":
		params["room_id"] = w.room
		if name == "message.schedule" {
			params["due_at"] = time.Now().Add(time.Hour).UnixMilli()
		}
		if name == "scheduled.list" {
			schedule()
		}
	case "scheduled.update":
		params["outbox_id"], params["due_at"] = schedule(), time.Now().Add(2*time.Hour).UnixMilli()
	case "scheduled.sendNow", "scheduled.delete":
		params["outbox_id"] = schedule()
	case "poll.vote":
		w.can(t, everything())
		params["event_id"] = w.put(t, string(ids.RandomEventID()), contact, "org.matrix.msc3381.poll.start",
			pollOf("Where for lunch?", 1, "Noodles", "Tacos"), time.Now())
	case "room.events-thread":
		root := w.put(t, "$threadroot", contact, "m.room.message", `{"msgtype":"m.text","body":"Who's in for lunch?"}`, time.Now())
		w.put(t, "$threadreply", "@whatsapp_ana:courier.local", "m.room.message", inThread(root, "Count me in"), time.Now().Add(time.Second))
		params["room_id"], params["thread"] = w.room, root
	case "search.query-bookmarks":
		picnic(t, w)
		hits, _, err := w.s.SearchMessages(ctx, store.MessageQuery{Terms: searchtext.Parse("Saturday"), Limit: 1})
		require.NoError(t, err)
		require.Len(t, hits, 1)
		require.NoError(t, w.s.SetBookmarked(ctx, hits[0].Event.EventID, true))
	case "login.start":
		script(qrStep(), completeStep())
		params["flow"] = fakenet.ScriptFlow
	case "login.start-cookies":
		script(cookiesStep())
		params["network"], params["flow"] = "signal", fakenet.ScriptFlow
	case "login.start-user-input":
		script(threeFieldStep())
		params["network"], params["flow"] = "signal", fakenet.ScriptFlow
	case "login.start-in-progress":
		script(qrStep())
		startSignal()
		params["flow"] = fakenet.ScriptFlow
	case "login.start-already-linked":
		params["flow"] = fakenet.ScriptFlow
	case "login.submit", "login.submit-bad-value":
		script(threeFieldStep(), completeStep())
		params["login_id"] = startSignal()
	case "login.wait":
		script(qrStep(), completeStep())
		params["login_id"] = startSignal()
	case "login.cancel":
		script(qrStep())
		params["login_id"] = startSignal()
	default:
		t.Fatalf("example %s has no setup in prepare: add one", name)
	}
}

// picnic is what the search.query examples find for "picnic": a group named for it, someone in it (with no direct
// chat with me) named for it, two messages and a picture that say it.
func picnic(t *testing.T, w *world) {
	t.Helper()
	ctx := context.Background()
	const group, organiser = "!picnic:courier.local", "@whatsapp_organiser:courier.local"
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: group, Network: "whatsapp", Name: "Picnic planning"}))
	name := "Picnic Organiser"
	require.NoError(t, w.s.SetProfile(ctx, organiser, &name, nil))
	require.NoError(t, w.s.SetMember(ctx, group, organiser, json.RawMessage(`{"membership":"join"}`)))
	now := time.Now()
	say(t, w.s, group, string(ids.Me), "Who is bringing the picnic blanket?", now.Add(-3*time.Minute))
	say(t, w.s, group, organiser, "Picnic on Saturday?", now.Add(-2*time.Minute))
	_, err := w.s.InsertEvent(ctx, store.Event{
		RoomID: group, EventID: "$picnicphoto", Sender: organiser, Type: "m.room.message", TS: now.Add(-time.Minute),
		Content: json.RawMessage(`{"msgtype":"m.image","body":"picnic.jpg","url":"mxc://courier.test/picnic"}`), Status: "sent",
	})
	require.NoError(t, err)
}

// triggerNotification makes the change one notification example shows and returns the engine's notification.
func triggerNotification(t *testing.T, w *world, c *client, name string) changed {
	t.Helper()
	ctx := context.Background()
	switch name {
	case "changed-event":
		id := string(ids.RandomEventID())
		_, err := w.s.InsertEvent(ctx, store.Event{
			RoomID: w.room, EventID: id, Sender: "@whatsapp_contact:courier.local",
			Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.text","body":"new"}`), TS: time.Now(), Status: "sent",
		})
		require.NoError(t, err)
		return c.changed(func(ch changed) bool { return ch.Kind == "event" && ch.EventID == id })
	case "changed-status":
		require.NoError(t, w.s.SetStatus(ctx, w.events[0], "sent", ""))
		return c.changed(func(ch changed) bool { return ch.Kind == "status" && ch.EventID == w.events[0] })
	case "changed-read":
		require.NoError(t, w.s.MarkReadLocal(ctx, w.room, w.events[2], time.Now()))
		return c.changed(func(ch changed) bool { return ch.Kind == "read" && ch.RoomID == w.room })
	case "changed-room":
		require.NoError(t, w.s.SetMuted(ctx, w.room, true))
		return c.changed(func(ch changed) bool { return ch.Kind == "room" && ch.RoomID == w.room })
	case "changed-names":
		n := "Someone"
		require.NoError(t, w.s.SetProfile(ctx, "@whatsapp_someone:courier.local", &n, nil))
		return c.changed(func(ch changed) bool { return ch.Kind == "room" && ch.RoomID == "" })
	case "changed-bridge":
		require.NoError(t, w.s.SetLoginState(ctx, "conformance", "", json.RawMessage(`{"state_event":"CONNECTED"}`)))
		return c.changed(func(ch changed) bool { return ch.Kind == "bridge" && ch.Network == "conformance" })
	case "changed-spaces":
		_, err := w.s.CreateLabel(ctx, "Work", 3, "briefcase")
		require.NoError(t, err)
		return c.changed(func(ch changed) bool { return ch.Kind == "spaces" })
	case "changed-receipt":
		require.NoError(t, w.s.SetReceipt(ctx, w.room, contact, w.events[2], time.Now()))
		return c.changed(func(ch changed) bool { return ch.Kind == "receipt" && ch.RoomID == w.room })
	case "changed-typing":
		w.s.SetTyping(w.room, "@whatsapp_contact:courier.local", time.Now().Add(time.Minute))
		return c.changed(func(ch changed) bool { return ch.Kind == "typing" && ch.RoomID == w.room })
	case "changed-reminder":
		require.NoError(t, w.s.SetReminder(ctx, []string{w.room}, time.Now().Add(time.Minute), "always"))
		w.s.SetClock(func() time.Time { return time.Now().Add(2 * time.Minute) })
		_, err := w.s.FireDueReminders(ctx)
		require.NoError(t, err)
		return c.changed(func(ch changed) bool { return ch.Kind == "reminder" && ch.RoomID == w.room })
	case "changed-scheduled":
		_, err := w.deps.Actions.Schedule(ctx, w.room, "later", actions.SendOptions{}, time.Now().Add(time.Hour), "always")
		require.NoError(t, err)
		return c.changed(func(ch changed) bool { return ch.Kind == "scheduled" && ch.RoomID == w.room })
	case "changed-resync":
		conn, r := rawHello(t, w.path)
		o := overflow(t, w.s, conn, r)
		requireToldToResync(t, o)
		var ch changed
		require.NoError(t, json.Unmarshal(o.resyncs[len(o.resyncs)-1], &ch))
		return ch
	}
	t.Fatalf("notification example %s has no trigger: add one", name)
	return changed{}
}

// waComplete is a WhatsApp sign-in completing as the account accountID.
func waComplete(accountID, name string) *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeComplete, StepID: "fi.mau.whatsapp.complete",
		CompleteParams: &bridgev2.LoginCompleteParams{
			UserLoginID: networkid.UserLoginID(accountID),
			UserLogin:   &bridgev2.UserLogin{UserLogin: &database.UserLogin{ID: networkid.UserLoginID(accountID), RemoteName: name}},
		},
	}
}

func cookiesStep() *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeCookies, StepID: "fi.mau.slack.cookies", Instructions: "Sign in to your workspace.",
		CookiesParams: &bridgev2.LoginCookiesParams{
			URL: "https://example.slack.test/signin", UserAgent: "Example/1.0",
			WaitForURLPattern: `^https://app\.slack\.test/client/`, ExtractJS: "(async () => ({}))()",
			Fields: []bridgev2.LoginCookieField{
				{ID: "d", Required: true, Pattern: "^xoxd-", Sources: []bridgev2.LoginCookieFieldSource{
					{Type: bridgev2.LoginCookieTypeCookie, Name: "d", CookieDomain: ".slack.test"},
				}},
				{ID: "token", Required: true, Sources: []bridgev2.LoginCookieFieldSource{
					{Type: bridgev2.LoginCookieTypeSpecial, Name: "token"},
				}},
			},
		},
	}
}

func threeFieldStep() *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeUserInput, StepID: "fi.mau.telegram.phone", Instructions: "Enter your details.",
		UserInputParams: &bridgev2.LoginUserInputParams{Fields: []bridgev2.LoginInputDataField{
			{Type: bridgev2.LoginInputFieldTypeUsername, ID: "username", Name: "Username", Description: "The name you sign in with"},
			{Type: bridgev2.LoginInputFieldType2FACode, ID: "code", Name: "Code", Description: "The code the app shows", Pattern: "^[0-9]{6}$"},
			{
				Type: bridgev2.LoginInputFieldTypeSelect, ID: "server", Name: "Server", Description: "Which server to use",
				Options: []string{"main", "test"}, DefaultValue: "main",
			},
		}},
	}
}

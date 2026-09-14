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

package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// The phone bridge, pinned end to end without a phone.
//
// The fake phone below is not a mock of the bridge -- it is a real HTTP
// client that opens the real link, reads the real event stream and posts
// real results. What it fakes is Android, which is the only part a Linux CI
// runner genuinely cannot have.

// --- harness ---

// newBridgeAgent is newTestAgent plus the MCP token, which main() creates on
// start and a test server otherwise would not have.
func newBridgeAgent(t *testing.T) (*Store, *httptest.Server) {
	t.Helper()
	s := NewSampler(time.Second, "", "", nil, nil)
	store := NewStore(t.TempDir())
	if _, err := store.EnsureToken(); err != nil {
		t.Fatal(err)
	}
	if _, err := store.EnsureMCPToken(); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(newMux(s, store, "", ""))
	t.Cleanup(srv.Close)
	return store, srv
}

func actToken(t *testing.T, store *Store) string {
	t.Helper()
	tok, err := store.Token()
	if err != nil {
		t.Fatal(err)
	}
	return tok
}

func mcpToken(t *testing.T, store *Store) string {
	t.Helper()
	tok, err := store.EnsureMCPToken()
	if err != nil {
		t.Fatal(err)
	}
	return tok
}

// fakePhone opens a link and answers every call it receives.
type fakePhone struct {
	hello  chan struct{} // closed once `hello` has arrived
	ended  chan struct{} // closed when the stream ends (replaced, or cancelled)
	pings  chan struct{} // one send per ping event, buffered
	cancel context.CancelFunc

	mu    sync.Mutex
	calls []phoneCall
}

// linkPhone starts a fake phone. answer decides what each call returns; a nil
// answer makes every call return its own tool name.
func linkPhone(t *testing.T, srv *httptest.Server, token string, body string, answer func(phoneCall) (content string, isError bool)) *fakePhone {
	t.Helper()
	if answer == nil {
		answer = func(c phoneCall) (string, bool) { return c.Tool, false }
	}
	ctx, cancel := context.WithCancel(context.Background())
	p := &fakePhone{
		hello:  make(chan struct{}),
		ended:  make(chan struct{}),
		pings:  make(chan struct{}, 8),
		cancel: cancel,
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, srv.URL+"/v1/phone/link", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK {
		b, _ := json.Marshal(resp.Status)
		resp.Body.Close()
		cancel()
		t.Fatalf("link: %s", b)
	}
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream" {
		resp.Body.Close()
		cancel()
		t.Fatalf("link Content-Type = %q, want text/event-stream", ct)
	}

	go func() {
		defer close(p.ended)
		defer resp.Body.Close()
		sc := bufio.NewScanner(resp.Body)
		event := ""
		helloSeen := false
		for sc.Scan() {
			line := sc.Text()
			switch {
			case strings.HasPrefix(line, "event: "):
				event = strings.TrimPrefix(line, "event: ")
			case strings.HasPrefix(line, "data: "):
				data := strings.TrimPrefix(line, "data: ")
				switch event {
				case "hello":
					if !helloSeen {
						helloSeen = true
						close(p.hello)
					}
				case "ping":
					select {
					case p.pings <- struct{}{}:
					default:
					}
				case "call":
					var c phoneCall
					if err := json.Unmarshal([]byte(data), &c); err != nil {
						return
					}
					p.mu.Lock()
					p.calls = append(p.calls, c)
					p.mu.Unlock()
					text, isErr := answer(c)
					postResult(srv, token, c.ID, text, isErr)
				}
			case line == "":
				event = ""
			}
		}
	}()

	select {
	case <-p.hello:
	case <-time.After(5 * time.Second):
		cancel()
		t.Fatal("no hello event within 5s")
	}
	t.Cleanup(func() { cancel(); <-p.ended })
	return p
}

// postResult is the phone's half of an answer. Errors are swallowed on
// purpose: a result for a call whose caller has gone is a 404, and the fake
// phone reacting to that would only mask the behaviour under test.
func postResult(srv *httptest.Server, token, id, text string, isErr bool) {
	body, _ := json.Marshal(map[string]any{
		"id":       id,
		"content":  []map[string]string{{"type": "text", "text": text}},
		"is_error": isErr,
	})
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/phone/result", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err == nil {
		resp.Body.Close()
	}
}

// rpc posts one JSON-RPC request to /mcp/phone and returns the decoded body.
func rpc(t *testing.T, srv *httptest.Server, token, body string) (int, map[string]any) {
	t.Helper()
	req, err := http.NewRequest(http.MethodPost, srv.URL+"/mcp/phone", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	if resp.StatusCode == http.StatusAccepted {
		return resp.StatusCode, nil
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatalf("decoding %s: %v", body, err)
	}
	return resp.StatusCode, out
}

const twoTools = `{"device":{"model":"Pixel Fold","android":"16"},"tools":[
  {"name":"sms.list","description":"list texts","inputSchema":{"type":"object"},"tier":"read"},
  {"name":"sms.send","description":"send a text","inputSchema":{"type":"object"},"tier":"outbound"}]}`

// --- the tests ---

// The one that matters: an MCP client asks for a tool, the phone answers,
// and the answer comes back through the JSON-RPC reply. Everything else here
// is a corner of this path.
func TestMCPToolCallRoundTripsThroughThePhone(t *testing.T) {
	store, srv := newBridgeAgent(t)
	tok, mtok := actToken(t, store), mcpToken(t, store)

	p := linkPhone(t, srv, tok, twoTools, func(c phoneCall) (string, bool) {
		if c.Tool != "sms.list" {
			return "unexpected tool " + c.Tool, true
		}
		// Echo the arguments back, which proves they survived the trip.
		return "args=" + string(c.Arguments), false
	})

	// The act log must carry the tool name and NOT the arguments: a phone
	// number in the Mac's log is exactly the leak this endpoint should not
	// have.
	var logbuf bytes.Buffer
	old := log.Writer()
	log.SetOutput(&logbuf)
	t.Cleanup(func() { log.SetOutput(old) })

	status, out := rpc(t, srv, mtok,
		`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"sms.list","arguments":{"n":5}}}`)
	if status != http.StatusOK {
		t.Fatalf("status = %d", status)
	}
	res, ok := out["result"].(map[string]any)
	if !ok {
		t.Fatalf("no result in %v", out)
	}
	if res["isError"] != false {
		t.Errorf("isError = %v, want false", res["isError"])
	}
	content, _ := json.Marshal(res["content"])
	if !strings.Contains(string(content), `args={\"n\":5}`) {
		t.Errorf("the phone did not see the arguments: %s", content)
	}

	if logged := logbuf.String(); !strings.Contains(logged, "act mcp: sms.list") {
		t.Errorf("the call was not logged: %q", logged)
	} else if strings.Contains(logged, `"n":5`) {
		t.Errorf("the arguments were logged: %q", logged)
	}

	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.calls) != 1 {
		t.Fatalf("the phone saw %d calls, want 1", len(p.calls))
	}
	// Ids are the contract's c-<n>, and a client that logs them should see
	// something it can match against the phone's audit list.
	if p.calls[0].ID != "c-1" {
		t.Errorf("call id = %q, want c-1", p.calls[0].ID)
	}
}

// GET /v1/phone is the phone's own view of the link, and it is a read: no
// token, and it names the tools without exposing anything they returned.
func TestPhoneStatusReflectsTheLink(t *testing.T) {
	store, srv := newBridgeAgent(t)
	tok := actToken(t, store)

	get := func() map[string]any {
		resp, err := http.Get(srv.URL + "/v1/phone")
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		var out map[string]any
		if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
			t.Fatal(err)
		}
		return out
	}

	before := get()
	if before["connected"] != false {
		t.Errorf("connected = %v before any link", before["connected"])
	}

	linkPhone(t, srv, tok, twoTools, nil)
	after := get()
	if after["connected"] != true {
		t.Fatalf("connected = %v after linking", after["connected"])
	}
	tools, _ := json.Marshal(after["tools"])
	if string(tools) != `["sms.list","sms.send"]` {
		t.Errorf("tools = %s", tools)
	}
	if after["since"] == nil {
		t.Error("since is null on a live link")
	}
	if after["trust_until"] != nil {
		t.Errorf("trust_until = %v before the phone reported one", after["trust_until"])
	}
}

// trust_until comes from a phone.status result, which is the contract's rule.
// A result body may also carry it directly, for a phone whose trust window
// changed without a status call; both are pinned here.
func TestTrustUntilComesFromThePhone(t *testing.T) {
	store, srv := newBridgeAgent(t)
	tok, mtok := actToken(t, store), mcpToken(t, store)

	const want = "2026-09-08T12:00:00Z"
	linkPhone(t, srv, tok, `{"device":{"model":"Pixel Fold"},"tools":[
	  {"name":"phone.status","description":"status","tier":"read"}]}`,
		func(c phoneCall) (string, bool) {
			return `{"battery":81,"trust_until":"` + want + `"}`, false
		})

	if _, out := rpc(t, srv, mtok,
		`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"phone.status"}}`); out["result"] == nil {
		t.Fatalf("no result: %v", out)
	}

	resp, err := http.Get(srv.URL + "/v1/phone")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var st map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&st); err != nil {
		t.Fatal(err)
	}
	if st["trust_until"] != want {
		t.Errorf("trust_until = %v, want %s", st["trust_until"], want)
	}
}

// One link at a time. The old stream must END, not linger: a phone that
// reconnected after a network change would otherwise leave a handler holding
// a socket and a call queue nobody reads.
func TestASecondLinkReplacesTheFirst(t *testing.T) {
	store, srv := newBridgeAgent(t)
	tok := actToken(t, store)

	first := linkPhone(t, srv, tok, twoTools, nil)
	second := linkPhone(t, srv, tok, `{"device":{"model":"Pixel 9"},"tools":[
	  {"name":"contacts.search","description":"search","tier":"read"}]}`, nil)

	select {
	case <-first.ended:
	case <-time.After(5 * time.Second):
		t.Fatal("the first link was still open after a second one arrived")
	}

	resp, err := http.Get(srv.URL + "/v1/phone")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var st map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&st); err != nil {
		t.Fatal(err)
	}
	// The survivor's state, not a mixture of the two: the replaced handler
	// returning must not clear what its successor just wrote.
	if st["connected"] != true {
		t.Fatalf("connected = %v after the replacement", st["connected"])
	}
	tools, _ := json.Marshal(st["tools"])
	if string(tools) != `["contacts.search"]` {
		t.Errorf("tools = %s, want the second phone's", tools)
	}
	select {
	case <-second.ended:
		t.Error("the second link ended too")
	default:
	}
}

func TestResultForAnUnknownIDIs404(t *testing.T) {
	store, srv := newBridgeAgent(t)
	tok := actToken(t, store)
	linkPhone(t, srv, tok, twoTools, nil)

	body := `{"id":"c-999","content":[{"type":"text","text":"hi"}],"is_error":false}`
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/phone/result", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("unknown id: got %d, want 404", resp.StatusCode)
	}
}

// A second result for the same call is the same 404: the answer is one-shot,
// and a phone that retried after a flaky network must not deliver twice.
func TestASecondResultForTheSameCallIs404(t *testing.T) {
	store, srv := newBridgeAgent(t)
	tok, mtok := actToken(t, store), mcpToken(t, store)

	// The id travels back on a channel rather than a variable: the fake
	// phone answers on its own goroutine.
	ids := make(chan string, 1)
	linkPhone(t, srv, tok, twoTools, func(c phoneCall) (string, bool) {
		select {
		case ids <- c.ID:
		default:
		}
		return "ok", false
	})
	rpc(t, srv, mtok, `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"sms.list"}}`)
	id := <-ids

	body := `{"id":"` + id + `","content":[{"type":"text","text":"again"}],"is_error":false}`
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/phone/result", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("a repeated result: got %d, want 404", resp.StatusCode)
	}
}

func TestLinkRefusesBadToolNamesAndTiers(t *testing.T) {
	store, srv := newBridgeAgent(t)
	tok := actToken(t, store)

	for name, body := range map[string]string{
		"an uppercase name": `{"tools":[{"name":"SMS.list","tier":"read"}]}`,
		"a leading digit":   `{"tools":[{"name":"9lives","tier":"read"}]}`,
		"a space":           `{"tools":[{"name":"sms list","tier":"read"}]}`,
		"a slash":           `{"tools":[{"name":"sms/list","tier":"read"}]}`,
		"an empty name":     `{"tools":[{"name":"","tier":"read"}]}`,
		"a 65-char name":    `{"tools":[{"name":"a` + strings.Repeat("b", 64) + `","tier":"read"}]}`,
		"an unknown tier":   `{"tools":[{"name":"sms.list","tier":"admin"}]}`,
		"a missing tier":    `{"tools":[{"name":"sms.list"}]}`,
	} {
		req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/phone/link", strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tok)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("%s: got %d, want 400", name, resp.StatusCode)
		}
	}
	// And the shape that must still be accepted, so the rule above is not
	// merely "refuse everything".
	linkPhone(t, srv, tok, `{"tools":[{"name":"a","tier":"act"},{"name":"screen.tap","tier":"act"},
	  {"name":"a`+strings.Repeat("b", 63)+`","tier":"outbound"}]}`, nil)
}

func TestMCPToolsListIsEmptyWithoutAPhone(t *testing.T) {
	store, srv := newBridgeAgent(t)
	mtok := mcpToken(t, store)

	_, out := rpc(t, srv, mtok, `{"jsonrpc":"2.0","id":7,"method":"tools/list"}`)
	res, ok := out["result"].(map[string]any)
	if !ok {
		t.Fatalf("no result: %v", out)
	}
	tools, ok := res["tools"].([]any)
	if !ok || len(tools) != 0 {
		t.Errorf("tools = %v, want an empty list", res["tools"])
	}
	// The id is echoed, and echoed as the number it was sent as.
	if out["id"] != float64(7) {
		t.Errorf("id = %v, want 7", out["id"])
	}
}

// No phone is a tool error, not a transport error. The distinction is the
// whole of MCP's error model: a -32603 makes the client give up on the tool,
// isError puts the sentence in front of the model.
func TestMCPToolCallWithoutAPhoneIsAToolError(t *testing.T) {
	store, srv := newBridgeAgent(t)
	mtok := mcpToken(t, store)

	_, out := rpc(t, srv, mtok,
		`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"sms.send","arguments":{}}}`)
	if out["error"] != nil {
		t.Fatalf("a missing phone must not be a JSON-RPC error: %v", out["error"])
	}
	res, ok := out["result"].(map[string]any)
	if !ok {
		t.Fatalf("no result: %v", out)
	}
	if res["isError"] != true {
		t.Errorf("isError = %v, want true", res["isError"])
	}
	content, _ := json.Marshal(res["content"])
	if !strings.Contains(string(content), "phone not connected") {
		t.Errorf("content = %s", content)
	}
}

func TestMCPInitializeAndPing(t *testing.T) {
	store, srv := newBridgeAgent(t)
	mtok := mcpToken(t, store)

	_, out := rpc(t, srv, mtok, `{"jsonrpc":"2.0","id":"a","method":"initialize","params":{}}`)
	res, ok := out["result"].(map[string]any)
	if !ok {
		t.Fatalf("no result: %v", out)
	}
	if res["protocolVersion"] != mcpProtocolVersion {
		t.Errorf("protocolVersion = %v", res["protocolVersion"])
	}
	info, _ := res["serverInfo"].(map[string]any)
	if info["name"] != mcpServerName || info["version"] != version {
		t.Errorf("serverInfo = %v (version should be the agent's, %s)", info, version)
	}
	caps, _ := res["capabilities"].(map[string]any)
	tools, _ := caps["tools"].(map[string]any)
	if tools["listChanged"] != false {
		t.Errorf("capabilities.tools = %v", caps["tools"])
	}
	if out["id"] != "a" {
		t.Errorf("a string id must come back a string: %v", out["id"])
	}

	if _, out := rpc(t, srv, mtok, `{"jsonrpc":"2.0","id":2,"method":"ping"}`); out["result"] == nil {
		t.Errorf("ping: %v", out)
	}

	// A notification has no id and gets no body: 202 and nothing else.
	if status, body := rpc(t, srv, mtok, `{"jsonrpc":"2.0","method":"notifications/initialized"}`); status != http.StatusAccepted || body != nil {
		t.Errorf("notifications/initialized: %d %v, want 202 and an empty body", status, body)
	}
}

func TestMCPUnknownMethodAndBadJSON(t *testing.T) {
	store, srv := newBridgeAgent(t)
	mtok := mcpToken(t, store)

	_, out := rpc(t, srv, mtok, `{"jsonrpc":"2.0","id":1,"method":"resources/list"}`)
	e, ok := out["error"].(map[string]any)
	if !ok || e["code"] != float64(rpcMethodNotFound) {
		t.Errorf("unknown method: %v, want -32601", out)
	}

	_, out = rpc(t, srv, mtok, `{"jsonrpc":"2.0","id":1,`)
	e, ok = out["error"].(map[string]any)
	if !ok || e["code"] != float64(rpcParseError) {
		t.Errorf("bad JSON: %v, want -32700", out)
	}
	// Nothing was parsed, so there is no id to echo and null is the only
	// honest answer.
	if out["id"] != nil {
		t.Errorf("id = %v on a parse error, want null", out["id"])
	}
}

func TestMCPNeedsItsOwnToken(t *testing.T) {
	store, srv := newBridgeAgent(t)
	pairTok := actToken(t, store)

	for name, tok := range map[string]string{
		"no token":          "",
		"a wrong token":     strings.Repeat("a", 64),
		"the PAIRING token": pairTok,
	} {
		req, _ := http.NewRequest(http.MethodPost, srv.URL+"/mcp/phone",
			strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"ping"}`))
		if tok != "" {
			req.Header.Set("Authorization", "Bearer "+tok)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("%s: got %d, want 401", name, resp.StatusCode)
		}
	}
}

// GET is 405: v1.3 has no server-initiated stream, and an empty SSE response
// would leave a client waiting on a channel that never delivers.
func TestMCPGetIs405(t *testing.T) {
	store, srv := newBridgeAgent(t)
	mtok := mcpToken(t, store)
	req, _ := http.NewRequest(http.MethodGet, srv.URL+"/mcp/phone", nil)
	req.Header.Set("Authorization", "Bearer "+mtok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Errorf("GET /mcp/phone: got %d, want 405", resp.StatusCode)
	}
	if resp.Header.Get("Allow") != "POST" {
		t.Errorf("Allow = %q", resp.Header.Get("Allow"))
	}
}

// The loopback rule, driven through the handler with a forged RemoteAddr.
// A tailnet peer reaching the same port must be refused BEFORE the token is
// even considered: the phone's tools can text people, and "somewhere on the
// tailnet" is not the same as "a process on this Mac".
func TestMCPRefusesANonLoopbackCaller(t *testing.T) {
	s := NewSampler(time.Second, "", "", nil, nil)
	store := NewStore(t.TempDir())
	if _, err := store.EnsureToken(); err != nil {
		t.Fatal(err)
	}
	tok, err := store.EnsureMCPToken()
	if err != nil {
		t.Fatal(err)
	}
	mux := newMux(s, store, "", "")

	for _, addr := range []string{"100.101.102.103:51234", "192.168.1.10:9000", "[2606:4700::1]:443"} {
		req := httptest.NewRequest(http.MethodPost, "/mcp/phone",
			strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"ping"}`))
		req.RemoteAddr = addr
		// A CORRECT token, so what this proves is the address check and not
		// an accidental 401.
		req.Header.Set("Authorization", "Bearer "+tok)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("%s: got %d, want 403", addr, rec.Code)
		}
	}
	// And loopback in both families is allowed, so the rule is a check and
	// not a blanket refusal.
	for _, addr := range []string{"127.0.0.1:51234", "[::1]:51234"} {
		req := httptest.NewRequest(http.MethodPost, "/mcp/phone",
			strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"ping"}`))
		req.RemoteAddr = addr
		req.Header.Set("Authorization", "Bearer "+tok)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("%s: got %d, want 200", addr, rec.Code)
		}
	}
}

// The link and the results are act-tier, and an unpaired caller gets the same
// 401 as every other act endpoint. /v1/phone is read-tier and does not.
func TestPhoneEndpointTiers(t *testing.T) {
	_, srv := newBridgeAgent(t)

	for _, path := range []string{"/v1/phone/link", "/v1/phone/result"} {
		req, _ := http.NewRequest(http.MethodPost, srv.URL+path, strings.NewReader(`{}`))
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("%s with no token: got %d, want 401", path, resp.StatusCode)
		}
	}
	resp, err := http.Get(srv.URL + "/v1/phone")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("GET /v1/phone with no token: got %d, want 200", resp.StatusCode)
	}
}

// The timeout is a function of the tier so this can be pinned in a
// microsecond rather than by waiting ninety seconds for the real thing.
func TestPhoneCallTimeoutDependsOnTheTier(t *testing.T) {
	if got := phoneCallTimeout(tierOutbound); got != 90*time.Second {
		t.Errorf("outbound timeout = %s, want 90s (someone has to tap Approve)", got)
	}
	for _, tier := range []string{tierRead, tierAct, "", "nonsense"} {
		if got := phoneCallTimeout(tier); got != 30*time.Second {
			t.Errorf("%q timeout = %s, want 30s", tier, got)
		}
	}
}

// tierOf is the other half of that: the timeout a call actually gets comes
// from the phone's own declaration, so an outbound tool must be recognised as
// one after a link.
func TestTierOfUsesThePhonesDeclaration(t *testing.T) {
	store, srv := newBridgeAgent(t)
	linkPhone(t, srv, actToken(t, store), twoTools, nil)

	// The bridge is inside the mux, so go at it the way a call does: pin the
	// declared tiers through a fresh bridge with the same input.
	b := newPhoneBridge()
	var body struct {
		Tools []phoneTool `json:"tools"`
	}
	if err := json.Unmarshal([]byte(twoTools), &body); err != nil {
		t.Fatal(err)
	}
	b.tools = body.Tools
	if got := b.tierOf("sms.send"); got != tierOutbound {
		t.Errorf("sms.send tier = %q, want outbound", got)
	}
	if got := phoneCallTimeout(b.tierOf("sms.send")); got != phoneOutboundTimeout {
		t.Errorf("sms.send timeout = %s", got)
	}
	if got := phoneCallTimeout(b.tierOf("sms.list")); got != phoneToolTimeout {
		t.Errorf("sms.list timeout = %s", got)
	}
	// An undeclared tool gets the SHORT timeout: the call will fail on the
	// phone anyway and holding the caller for 90 s would be worse.
	if got := phoneCallTimeout(b.tierOf("nothing.here")); got != phoneToolTimeout {
		t.Errorf("an unknown tool got %s", got)
	}
}

// A call in flight when the link drops must not hang until its timeout. The
// caller gets the same "phone not connected" it would get with no link at
// all, immediately.
func TestACallInFlightEndsWhenTheLinkDrops(t *testing.T) {
	store, srv := newBridgeAgent(t)
	tok, mtok := actToken(t, store), mcpToken(t, store)

	reached := make(chan struct{})
	// stop releases the fake phone at the end of the test. Without it the
	// answer function below would block its reader goroutine forever and the
	// harness's own cleanup would deadlock.
	stop := make(chan struct{})
	var once sync.Once
	p := linkPhone(t, srv, tok, twoTools, func(c phoneCall) (string, bool) {
		once.Do(func() { close(reached) })
		// Never answers while the test runs: the phone received the call and
		// then died.
		<-stop
		return "too late", true
	})
	t.Cleanup(func() { close(stop) })

	done := make(chan map[string]any, 1)
	go func() {
		_, out := rpc(t, srv, mtok,
			`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"sms.list"}}`)
		done <- out
	}()
	<-reached
	p.cancel()

	select {
	case out := <-done:
		res, ok := out["result"].(map[string]any)
		if !ok || res["isError"] != true {
			t.Fatalf("want a tool error after the link dropped, got %v", out)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the call did not end when the link dropped")
	}
}

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
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The phone bridge: the phone as an MCP server, relayed by this agent.
//
// The shape is the whole point. The phone never accepts a connection -- it
// is behind cellular NAT and there is nothing to dial. Instead it opens ONE
// outbound link to the Mac it already paired with (POST /v1/phone/link) and
// holds it open as an event stream. Calls travel down that stream as `call`
// events; answers come back as ordinary POSTs to /v1/phone/result. So the
// agent is a relay with a waiting room, and nothing in this file knows what
// `sms.list` means -- the tool list is whatever the phone declared.
//
// Everything here is state, not behaviour: one link at a time, a map of
// calls waiting for an answer, and the rules for matching them up.

const (
	// phonePingInterval is the contract's 20 s. Not decoration: the link
	// crosses a cellular NAT that forgets an idle flow in a couple of
	// minutes, and a phone that is merely idle must not look disconnected.
	phonePingInterval = 20 * time.Second
	// phoneCallQueue bounds how many calls may be in flight to a phone that
	// has stopped reading. Small on purpose -- an agent that has queued
	// sixteen unanswered taps has a broken phone, not a busy one.
	phoneCallQueue = 16
	// maxToolNameLen is the contract's cap on a declared tool name.
	maxToolNameLen = 64
	// phoneToolTimeout is for anything the phone can answer by itself;
	// phoneOutboundTimeout is for the tools where a PERSON has to tap
	// Approve first, which is why it is three times as long.
	phoneToolTimeout     = 30 * time.Second
	phoneOutboundTimeout = 90 * time.Second
)

// The three tiers of the approval rule. The agent does not enforce them --
// the phone does -- but it validates them, and the timeout depends on one.
const (
	tierRead     = "read"
	tierAct      = "act"
	tierOutbound = "outbound"
)

// errNoPhone is the one failure MCP reports as a successful tool error
// rather than a transport error, so it has to be distinguishable here.
var errNoPhone = errors.New("phone not connected")

// phoneTool is one entry of the phone's declared tool list: the MCP tool
// shape plus the tier that decides its timeout (and, on the phone, its
// approval rule).
type phoneTool struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	InputSchema json.RawMessage `json:"inputSchema,omitempty"`
	Tier        string          `json:"tier"`
}

// phoneCall is the `call` event's payload.
type phoneCall struct {
	ID        string          `json:"id"`
	Tool      string          `json:"tool"`
	Arguments json.RawMessage `json:"arguments"`
}

// phoneResult is what POST /v1/phone/result carries back.
type phoneResult struct {
	Content json.RawMessage `json:"content"`
	IsError bool            `json:"is_error"`
}

// waiter is one call parked until the phone answers. The tool name rides
// along because trust_until is read out of `phone.status` results and
// nothing else -- see result() below.
type waiter struct {
	tool string
	ch   chan phoneResult
}

// phoneBridge holds the single link and the calls waiting on it.
//
// gen is what makes "a new link replaces the old" safe. Each link handler
// remembers the generation it created; when it returns it only tears down
// the shared state if that generation is still current. Without it, an old
// handler noticing its replacement would clear the NEW link's fields on its
// way out.
type phoneBridge struct {
	mu      sync.Mutex
	gen     int64
	linked  bool
	since   time.Time
	device  json.RawMessage
	tools   []phoneTool
	trust   string // the phone's last reported trust_until; "" means closed
	calls   chan phoneCall
	closeCh chan struct{}
	pending map[string]*waiter
	nextID  int64
}

func newPhoneBridge() *phoneBridge {
	return &phoneBridge{pending: map[string]*waiter{}}
}

// validTier is the contract's three tiers and nothing else. An unknown tier
// would otherwise silently get the short timeout, which is exactly wrong for
// whatever new outbound thing someone was adding.
func validTier(t string) bool {
	return t == tierRead || t == tierAct || t == tierOutbound
}

// validToolName enforces `[a-z][a-z0-9_.]*`, at most 64 characters, by hand
// rather than by regexp: it is a dozen lines, it allocates nothing, and it
// cannot be read two ways.
func validToolName(n string) bool {
	if n == "" || len(n) > maxToolNameLen {
		return false
	}
	if n[0] < 'a' || n[0] > 'z' {
		return false
	}
	for i := 0; i < len(n); i++ {
		c := n[i]
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9', c == '_', c == '.':
		default:
			return false
		}
	}
	return true
}

// phoneCallTimeout is a function of the tier, and a function on purpose: it
// is the one piece of the timeout rule a test can pin without waiting 90 s.
func phoneCallTimeout(tier string) time.Duration {
	if tier == tierOutbound {
		return phoneOutboundTimeout
	}
	return phoneToolTimeout
}

// tierOf looks up a declared tool's tier. An unknown tool gets the short
// timeout: tools/call will fail on the phone anyway, and the caller should
// not be held for ninety seconds waiting for that.
func (b *phoneBridge) tierOf(tool string) string {
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, t := range b.tools {
		if t.Name == tool {
			return t.Tier
		}
	}
	return tierRead
}

// Tools is the phone's declaration, copied so a caller cannot mutate it.
// Empty when nothing is linked, which is what makes tools/list empty.
func (b *phoneBridge) Tools() []phoneTool {
	b.mu.Lock()
	defer b.mu.Unlock()
	out := make([]phoneTool, len(b.tools))
	copy(out, b.tools)
	return out
}

// status is GET /v1/phone's body.
func (b *phoneBridge) status() map[string]any {
	b.mu.Lock()
	defer b.mu.Unlock()
	names := make([]string, 0, len(b.tools))
	for _, t := range b.tools {
		names = append(names, t.Name)
	}
	out := map[string]any{
		"connected":   b.linked,
		"tools":       names,
		"since":       nil,
		"device":      nil,
		"trust_until": nil,
	}
	if b.linked {
		out["since"] = b.since.UTC().Format(time.RFC3339)
		out["device"] = b.device
		if b.trust != "" {
			out["trust_until"] = b.trust
		}
	}
	return out
}

// dispatch queues one call for the phone and waits for its answer.
//
// The ctx is the MCP request's, so an agent that gives up releases the
// waiter rather than leaking it. The timeout is the tier's.
func (b *phoneBridge) dispatch(ctx context.Context, tool string, args json.RawMessage, timeout time.Duration) (phoneResult, error) {
	b.mu.Lock()
	if !b.linked {
		b.mu.Unlock()
		return phoneResult{}, errNoPhone
	}
	b.nextID++
	id := "c-" + strconv.FormatInt(b.nextID, 10)
	w := &waiter{tool: tool, ch: make(chan phoneResult, 1)}
	b.pending[id] = w
	calls, closeCh := b.calls, b.closeCh
	b.mu.Unlock()

	if len(args) == 0 {
		args = json.RawMessage(`{}`)
	}
	deadline := time.NewTimer(timeout)
	defer deadline.Stop()

	select {
	case calls <- phoneCall{ID: id, Tool: tool, Arguments: args}:
	case <-closeCh:
		b.forget(id)
		return phoneResult{}, errNoPhone
	case <-ctx.Done():
		b.forget(id)
		return phoneResult{}, ctx.Err()
	case <-deadline.C:
		// The queue is full and the phone is not draining it. From the
		// caller's point of view that is the same as having no phone.
		b.forget(id)
		return phoneResult{}, errNoPhone
	}

	select {
	case res := <-w.ch:
		return res, nil
	case <-closeCh:
		b.forget(id)
		return phoneResult{}, errNoPhone
	case <-ctx.Done():
		b.forget(id)
		return phoneResult{}, ctx.Err()
	case <-deadline.C:
		b.forget(id)
		return phoneResult{}, errors.New("the phone did not answer within " + timeout.String())
	}
}

// forget drops a waiter whose caller has gone. A later result for that id is
// then a 404, which is the honest answer: nobody is listening.
func (b *phoneBridge) forget(id string) {
	b.mu.Lock()
	delete(b.pending, id)
	b.mu.Unlock()
}

// result matches an answer to its waiter. false means unknown or already
// answered, which is the 404.
func (b *phoneBridge) result(id string, res phoneResult, trustUntil string) bool {
	b.mu.Lock()
	w, ok := b.pending[id]
	if ok {
		delete(b.pending, id)
	}
	// trust_until, two ways. The contract's own is "whatever the phone last
	// reported in phone.status", so a phone.status result is parsed for it;
	// an explicit field on the result body wins, because a phone that knows
	// the window changed should not have to fake a status call to say so.
	if trustUntil != "" {
		b.trust = trustUntil
	} else if ok && w.tool == "phone.status" && !res.IsError {
		if t := trustFromContent(res.Content); t != "" {
			b.trust = t
		}
	}
	b.mu.Unlock()
	if !ok {
		return false
	}
	// The channel is buffered by one and the waiter is out of the map above,
	// so this never blocks and never delivers twice.
	w.ch <- res
	return true
}

// trustFromContent digs trust_until out of a phone.status result. The MCP
// content shape is a list of parts; the status tool's is a single text part
// holding a JSON object. Anything else -- a plain sentence, an image -- just
// yields "" and leaves the last known value alone.
func trustFromContent(content json.RawMessage) string {
	var parts []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	if err := json.Unmarshal(content, &parts); err != nil {
		return ""
	}
	for _, p := range parts {
		if p.Type != "text" {
			continue
		}
		var obj struct {
			TrustUntil string `json:"trust_until"`
		}
		if err := json.Unmarshal([]byte(p.Text), &obj); err == nil && obj.TrustUntil != "" {
			return obj.TrustUntil
		}
	}
	return ""
}

// --- handlers ---

// phoneLink is POST /v1/phone/link (act tier): the phone's outbound link,
// held open as an event stream for as long as the phone keeps it.
func (srv *server) phoneLink(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Device     json.RawMessage `json:"device"`
		Tools      []phoneTool     `json:"tools"`
		TrustUntil string          `json:"trust_until"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	// Validate BEFORE the first byte. Afterwards the status line is spent,
	// and a rejection could only be expressed inside a stream the phone has
	// already started treating as a live link.
	for _, t := range body.Tools {
		if !validToolName(t.Name) {
			writeError(w, http.StatusBadRequest,
				"tool name "+strconv.Quote(t.Name)+" must match [a-z][a-z0-9_.]* and be at most 64 characters")
			return
		}
		if !validTier(t.Tier) {
			writeError(w, http.StatusBadRequest,
				"tool "+t.Name+" has tier "+strconv.Quote(t.Tier)+"; want read, act or outbound")
			return
		}
	}
	// Flushing is not optional: without it every `call` event would sit in
	// the response buffer, which is the entire link.
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "this server cannot stream")
		return
	}

	b := srv.phone
	b.mu.Lock()
	// A new link replaces the old: closing the old channel is what makes the
	// previous handler return, which is what releases its socket.
	if b.closeCh != nil {
		close(b.closeCh)
	}
	b.gen++
	gen := b.gen
	b.linked = true
	b.since = time.Now()
	b.device = body.Device
	b.tools = body.Tools
	if body.TrustUntil != "" {
		b.trust = body.TrustUntil
	}
	calls := make(chan phoneCall, phoneCallQueue)
	closeCh := make(chan struct{})
	b.calls, b.closeCh = calls, closeCh
	b.mu.Unlock()

	logAct("phone", "link from "+deviceSummary(body.Device)+" with "+strconv.Itoa(len(body.Tools))+" tools")

	defer func() {
		b.mu.Lock()
		// Only tear down if this is still the current link: a handler that
		// was replaced must not clear its successor's state.
		if b.gen == gen {
			b.linked = false
			b.tools = nil
			b.device = nil
			b.trust = ""
			b.calls = nil
			b.closeCh = nil
			close(closeCh)
			// Everyone still waiting is waiting forever now, so tell them.
			for id, wt := range b.pending {
				delete(b.pending, id)
				wt.ch <- phoneResult{IsError: true, Content: textContent(errNoPhone.Error())}
			}
		}
		b.mu.Unlock()
	}()

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-store")
	// nginx and friends buffer a proxied response by default, which would
	// hold every call until the link ended.
	w.Header().Set("X-Accel-Buffering", "no")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	if err := writeEvent(w, "hello", map[string]string{"agent_version": version}); err != nil {
		return
	}
	flusher.Flush()

	ticker := time.NewTicker(phonePingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-closeCh:
			// Replaced by a newer link.
			return
		case c := <-calls:
			if err := writeEvent(w, "call", c); err != nil {
				return
			}
			flusher.Flush()
		case <-ticker.C:
			if err := writeEvent(w, "ping", struct{}{}); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}

// deviceSummary is what the act log records about a linking phone. Model and
// Android version only: the link body is the phone's own description of
// itself, and the log is not the place for all of it.
func deviceSummary(device json.RawMessage) string {
	var d struct {
		Model   string `json:"model"`
		Android string `json:"android"`
	}
	if err := json.Unmarshal(device, &d); err != nil || d.Model == "" {
		return "a phone"
	}
	if d.Android == "" {
		return d.Model
	}
	return d.Model + " (Android " + d.Android + ")"
}

// phoneResultHandler is POST /v1/phone/result (act tier).
func (srv *server) phoneResultHandler(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID         string          `json:"id"`
		Content    json.RawMessage `json:"content"`
		IsError    bool            `json:"is_error"`
		TrustUntil string          `json:"trust_until"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if strings.TrimSpace(body.ID) == "" {
		writeError(w, http.StatusBadRequest, "id is required")
		return
	}
	if len(body.Content) == 0 {
		body.Content = textContent("")
	}
	if !srv.phone.result(body.ID, phoneResult{Content: body.Content, IsError: body.IsError}, body.TrustUntil) {
		// Unknown, expired, or already answered. All three are the same
		// thing to the phone: nobody is waiting for this any more.
		writeError(w, http.StatusNotFound, "no call "+body.ID+" is waiting for a result")
		return
	}
	writeJSON(w, map[string]any{})
}

// phoneStatus is GET /v1/phone (read tier). Read, not act: it says whether a
// link exists and which tools it declared, which is the same class of thing
// as /v1/host -- it exposes no content and performs nothing.
func (srv *server) phoneStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, srv.phone.status())
}

// textContent builds the MCP content list for one piece of text. Used for
// the errors this agent raises itself; everything else comes from the phone
// verbatim.
func textContent(s string) json.RawMessage {
	b, err := json.Marshal([]map[string]string{{"type": "text", "text": s}})
	if err != nil {
		return json.RawMessage(`[{"type":"text","text":""}]`)
	}
	return b
}

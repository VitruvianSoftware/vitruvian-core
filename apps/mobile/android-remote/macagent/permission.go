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
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// v1.6: answer Claude Code permission prompts from the phone.
//
// Claude Code's PermissionRequest hook runs `vitruvian-remote-agent
// permission-hook` (hook.go), which POSTs the hook JSON here on loopback and
// blocks. This file parks that request until the phone decides, the wait
// runs out, or Claude Code gives up -- and in every case but a decision the
// answer is "ask", which means Claude Code shows its own dialog on the Mac.
// The safety property is that asymmetry: the only way to get allow or deny
// out of this file is a person tapping it on a paired phone.
//
// There is no separate on/off switch. The feature is on exactly when our
// PermissionRequest hook is in ~/.claude/settings.json -- the phone's toggle
// installs or removes it (POST /v1/claude/permissions/enabled) -- so that file
// is the single source of truth, and a hook that is running implies the
// feature is on.

const (
	// permissionWaitDefault is the contract's 120 s.
	permissionWaitDefault = 120 * time.Second
	// permissionWaitMin / Max bound --permission-wait. The max is the
	// contract's 140 s: the hook's own timeout in settings.json is 150 s,
	// and if Claude Code kills the hook first the answer is lost.
	permissionWaitMin = 5 * time.Second
	permissionWaitMax = 140 * time.Second
	// maxPendingPermissions bounds the waiting room. Each entry holds an
	// HTTP request open; a runaway loop of prompts past this falls straight
	// through to the Mac dialog instead of growing the map.
	maxPendingPermissions = 64
	// summaryMaxRunes and detailMaxBytes are the contract's 120 chars and
	// 4 KiB.
	summaryMaxRunes = 120
	detailMaxBytes  = 4 << 10
	// denyMessageMaxRunes is the contract's cap on a deny message.
	denyMessageMaxRunes = 300
	// defaultDenyMessage is what Claude Code is told when the phone gave
	// no reason.
	defaultDenyMessage = "Denied from the phone"
)

// The three answers the ask endpoint can give.
const (
	decisionAllow = "allow"
	decisionDeny  = "deny"
	decisionAsk   = "ask"
)

// permissionWait is --permission-wait after clamping. A package variable,
// like execDir, because it is set once in main before anything serves;
// newMux copies it into the server.
var permissionWait = permissionWaitDefault

// clampPermissionWait keeps --permission-wait inside [5 s, 140 s].
func clampPermissionWait(d time.Duration) time.Duration {
	if d < permissionWaitMin {
		return permissionWaitMin
	}
	if d > permissionWaitMax {
		return permissionWaitMax
	}
	return d
}

// logPermissionWait says at start when the flag was clamped.
func logPermissionWait(asked, got time.Duration) {
	if asked != got {
		log.Printf("--permission-wait %s is outside [%s, %s]; using %s", asked, permissionWaitMin, permissionWaitMax, got)
	}
}

// --- the hook token ---

// hookTokenPath is the hook's bearer: a loopback token of its own, created
// the same way as the MCP one (ensureSecret), and separate from it so that a
// leaked MCP client config cannot answer permission prompts and vice versa.
func (s *Store) hookTokenPath() string { return filepath.Join(s.dir, "hook-token") }

// EnsureHookToken returns the hook token, creating it on first start.
func (s *Store) EnsureHookToken() (string, error) { return s.ensureSecret(s.hookTokenPath()) }

// HookAuthorized compares a presented bearer to the hook token.
func (s *Store) HookAuthorized(presented string) bool {
	return secretMatches(s.hookTokenPath(), presented)
}

// --- the waiting room ---

// permissionRequest is one parked prompt, and exactly the shape
// GET /v1/claude/permissions lists.
type permissionRequest struct {
	ID string `json:"id"`
	// Source is which agent asked: "claude" (v1.6, the default) or
	// "antigravity" (v1.7, from agy-permission-hook). One queue for both, so
	// the phone has one list to answer.
	Source    string    `json:"source"`
	SessionID string    `json:"session_id"`
	Project   string    `json:"project"`
	Cwd       string    `json:"cwd"`
	Tool      string    `json:"tool"`
	Summary   string    `json:"summary"`
	Detail    string    `json:"detail"`
	CreatedAt time.Time `json:"created_at"`
	ExpiresAt time.Time `json:"expires_at"`
}

// permissionAnswer is what travels from decide to the parked ask handler.
type permissionAnswer struct {
	Decision string
	Message  string
}

type pendingPermission struct {
	req permissionRequest
	ch  chan permissionAnswer // buffered 1: the sender never blocks
}

// permissionBroker is the map of parked prompts plus their arrival order.
// Every exit path -- decision, timeout, cancellation -- removes the entry
// under the lock, and whoever removes it owns it: that is what makes a decide
// racing a timeout come out as exactly one of the two.
type permissionBroker struct {
	mu      sync.Mutex
	nextID  int64
	order   []string
	pending map[string]*pendingPermission
}

func newPermissionBroker() *permissionBroker {
	return &permissionBroker{pending: map[string]*pendingPermission{}}
}

// add parks a request and returns it with its id and its channel, or false
// when the room is full.
func (b *permissionBroker) add(req permissionRequest) (permissionRequest, chan permissionAnswer, bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if len(b.pending) >= maxPendingPermissions {
		return req, nil, false
	}
	b.nextID++
	req.ID = "p-" + strconv.FormatInt(b.nextID, 10)
	p := &pendingPermission{req: req, ch: make(chan permissionAnswer, 1)}
	b.pending[req.ID] = p
	b.order = append(b.order, req.ID)
	return req, p.ch, true
}

// takeLocked removes an entry; the caller holds mu.
func (b *permissionBroker) takeLocked(id string) (*pendingPermission, bool) {
	p, ok := b.pending[id]
	if !ok {
		return nil, false
	}
	delete(b.pending, id)
	for i, o := range b.order {
		if o == id {
			b.order = append(b.order[:i], b.order[i+1:]...)
			break
		}
	}
	return p, true
}

// drop removes an entry without answering it. It reports whether the entry
// was still there; false means decide already answered it.
func (b *permissionBroker) drop(id string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	_, ok := b.takeLocked(id)
	return ok
}

// answer delivers a decision. False means unknown, already answered, or
// already expired -- the contract's 404.
func (b *permissionBroker) answer(id string, a permissionAnswer, now time.Time) (permissionRequest, bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	p, ok := b.pending[id]
	if !ok || !now.Before(p.req.ExpiresAt) {
		// Past its deadline the handler is about to give up, or has: a 404
		// is honest, a 200 would report an answer nobody will read. The
		// entry is left for the handler, which owns its removal.
		return permissionRequest{}, false
	}
	b.takeLocked(id)
	p.ch <- a
	return p.req, true
}

// list is the parked prompts, oldest first, never nil.
func (b *permissionBroker) list(now time.Time) []permissionRequest {
	b.mu.Lock()
	defer b.mu.Unlock()
	out := make([]permissionRequest, 0, len(b.order))
	for _, id := range b.order {
		if p := b.pending[id]; p != nil && now.Before(p.req.ExpiresAt) {
			out = append(out, p.req)
		}
	}
	return out
}

// len is how many prompts are parked, for tests.
func (b *permissionBroker) len() int {
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.pending)
}

// --- summary and detail ---

// The two sources the queue knows.
const (
	sourceClaude      = "claude"
	sourceAntigravity = "antigravity"
)

// hookInput is the part of Claude Code's hook JSON this agent reads.
// transcript_path is accepted and not used yet. source is absent from Claude
// Code's JSON (it means "claude"); agy-permission-hook sends "antigravity".
type hookInput struct {
	Source         string          `json:"source"`
	SessionID      string          `json:"session_id"`
	Cwd            string          `json:"cwd"`
	ToolName       string          `json:"tool_name"`
	ToolInput      json.RawMessage `json:"tool_input"`
	TranscriptPath string          `json:"transcript_path"`
}

// permissionSummary is the one line a notification shows.
//
//	Bash                                  -> the command
//	Edit, Write, MultiEdit, NotebookEdit  -> "edit <file_path | notebook_path>"
//	WebFetch                              -> the URL
//	anything else                         -> "<tool> <compact JSON of the input>"
//
// Newlines and runs of whitespace collapse to one space, and the result is at
// most 120 characters, the last of them "…" when it was cut. A known tool
// missing its expected field falls back to the generic form.
func permissionSummary(tool string, input json.RawMessage) string {
	var fields map[string]any
	_ = json.Unmarshal(input, &fields)
	str := func(k string) string {
		v, _ := fields[k].(string)
		return strings.TrimSpace(v)
	}
	var s string
	switch tool {
	case "Bash", agyRunCommand:
		s = str("command")
	case "Edit", "Write", "MultiEdit", "NotebookEdit":
		if p := str("file_path"); p != "" {
			s = "edit " + p
		} else if p := str("notebook_path"); p != "" {
			s = "edit " + p
		}
	case "WebFetch":
		s = str("url")
	}
	if s == "" {
		s = strings.TrimSpace(tool + " " + compactJSON(input))
	}
	return truncateRunes(strings.Join(strings.Fields(s), " "), summaryMaxRunes)
}

// permissionDetail is what the phone shows when the prompt is opened: the
// full command for Bash, indented JSON of the input for everything else, at
// most 4 KiB.
func permissionDetail(tool string, input json.RawMessage) string {
	var d string
	if tool == "Bash" || tool == agyRunCommand {
		var in struct {
			Command string `json:"command"`
		}
		if json.Unmarshal(input, &in) == nil && strings.TrimSpace(in.Command) != "" {
			d = in.Command
		}
	}
	if d == "" {
		var buf bytes.Buffer
		if len(bytes.TrimSpace(input)) > 0 && json.Indent(&buf, input, "", "  ") == nil {
			d = buf.String()
		}
	}
	return truncateBytes(d, detailMaxBytes)
}

func compactJSON(raw json.RawMessage) string {
	var buf bytes.Buffer
	if len(bytes.TrimSpace(raw)) == 0 || json.Compact(&buf, raw) != nil {
		return ""
	}
	return buf.String()
}

// truncateRunes cuts s to at most n runes, the last of them "…" when cut.
func truncateRunes(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return string(r[:n-1]) + "…"
}

// truncateBytes cuts s to at most n bytes on a rune boundary, the last three
// of them "…" when cut.
func truncateBytes(s string, n int) string {
	if len(s) <= n {
		return s
	}
	const ell = "…"
	cut := n - len(ell)
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return s[:cut] + ell
}

// --- endpoints ---

func (srv *server) permissionRoutes(mux *http.ServeMux) {
	// Loopback + hook token, checked inside the handler like /mcp/phone.
	// NOT act(): the caller is Claude Code on this Mac, not the phone.
	mux.HandleFunc("/v1/claude/permission/ask", postOnly(srv.permissionAsk))
	// Act tier, all three, wrapped one at a time: the list shows commands
	// and paths, and the other two decide what Claude Code may run.
	mux.HandleFunc("/v1/claude/permissions", getOnly(srv.act(srv.permissionList)))
	mux.HandleFunc("/v1/claude/permissions/enabled", postOnly(srv.act(srv.permissionEnabled)))
	mux.HandleFunc("/v1/claude/permissions/decide", postOnly(srv.act(srv.permissionDecide)))
}

// askReply writes one of the three decisions.
func askReply(w http.ResponseWriter, a permissionAnswer) {
	body := map[string]any{"decision": a.Decision}
	if a.Decision == decisionDeny && a.Message != "" {
		body["message"] = a.Message
	}
	writeJSON(w, body)
}

// permissionAsk is POST /v1/claude/permission/ask: the hook's call. There is
// no on/off check here -- the hook only runs when the phone's toggle put it
// in settings.json.
func (srv *server) permissionAsk(w http.ResponseWriter, r *http.Request) {
	if !loopbackGate(w, r, srv.store.HookAuthorized, "vitruvian-remote-hook",
		"the permission hook endpoint is loopback-only",
		"send the token in ~/.config/vitruvian-remote-agent/hook-token as a bearer") {
		return
	}
	var in hookInput
	if err := decodeJSON(r, &in); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if strings.TrimSpace(in.ToolName) == "" {
		writeError(w, http.StatusBadRequest, "tool_name is required")
		return
	}
	switch in.Source {
	case "":
		in.Source = sourceClaude
	case sourceClaude, sourceAntigravity:
	default:
		// A 400 is "ask" to either hook: an unknown source falls back to the
		// agent's own prompt rather than being filed under the wrong name.
		writeError(w, http.StatusBadRequest, `source must be "claude" or "antigravity"`)
		return
	}

	now := time.Now()
	wait := srv.permissionWait
	project := ""
	if in.Cwd != "" {
		project = filepath.Base(filepath.Clean(in.Cwd))
	}
	req, ch, ok := srv.perms.add(permissionRequest{
		Source:    in.Source,
		SessionID: in.SessionID,
		Project:   project,
		Cwd:       in.Cwd,
		Tool:      in.ToolName,
		Summary:   permissionSummary(in.ToolName, in.ToolInput),
		Detail:    permissionDetail(in.ToolName, in.ToolInput),
		CreatedAt: now.UTC(),
		ExpiresAt: now.Add(wait).UTC(),
	})
	if !ok {
		askReply(w, permissionAnswer{Decision: decisionAsk})
		return
	}

	// Fire and forget, on its own context: the push must neither be
	// cancelled by nor hold up the request it announces. notify logs and
	// drops a failure, and is silent when unconfigured or muted.
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		body := req.Summary
		if req.Project != "" {
			body = req.Project + " · " + req.Summary
		}
		key, title, click := "claude-permission-", "Claude wants to: ", "vitruvian-remote://apps/claude"
		if req.Source == sourceAntigravity {
			key, title, click = "antigravity-permission-", "Antigravity wants to: ", "vitruvian-remote://apps/antigravity"
		}
		srv.sampler.Notifier().notify(ctx, key+req.ID, title+req.Tool, body, "high", "question", click)
	}()

	timer := time.NewTimer(wait)
	defer timer.Stop()
	select {
	case a := <-ch:
		askReply(w, a)
	case <-timer.C:
		if srv.perms.drop(req.ID) {
			askReply(w, permissionAnswer{Decision: decisionAsk})
			return
		}
		// decide won the race and its answer is already buffered: honour
		// it, because the phone was told 200.
		askReply(w, <-ch)
	case <-r.Context().Done():
		// Claude Code gave up, or the person answered on the Mac. Take the
		// prompt off the phone; there is nobody left to write to.
		srv.perms.drop(req.ID)
	}
}

// permissionList is GET /v1/claude/permissions. "enabled" is read from
// settings.json on every call: it is one small file, and a person who edits
// it by hand should see the phone agree on the next refresh. A settings file
// that cannot be read or parsed reads as not enabled.
func (srv *server) permissionList(w http.ResponseWriter, r *http.Request) {
	on, _ := claudeHookInstalled(srv.claudeSettings, srv.hookCommand)
	writeJSON(w, map[string]any{
		"enabled":      on,
		"wait_seconds": int(srv.permissionWait / time.Second),
		"pending":      srv.perms.list(time.Now()),
	})
}

// permissionEnabled is POST /v1/claude/permissions/enabled: the phone's
// toggle. It runs the same install/remove as `install-claude-hook`, so the
// file is identical whichever way the hook went in. Pending prompts are left
// alone either way; decide and the timeout still end them.
func (srv *server) permissionEnabled(w http.ResponseWriter, r *http.Request) {
	var body struct {
		// A pointer so {} is a 400 rather than a silent uninstall.
		Enabled *bool `json:"enabled"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if body.Enabled == nil {
		writeError(w, http.StatusBadRequest, `"enabled" is required (true or false)`)
		return
	}
	if *body.Enabled && srv.hookCommand == "" {
		writeError(w, http.StatusInternalServerError, "cannot find this agent's own path to write into the hook command")
		return
	}
	if _, err := installClaudeHook(srv.claudeSettings, !*body.Enabled, srv.hookCommand); err != nil {
		// An unreadable or unparseable settings.json lands here, and the
		// error says the file was not touched.
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	logAct("claude", "hook enabled "+strconv.FormatBool(*body.Enabled))
	on, err := claudeHookInstalled(srv.claudeSettings, srv.hookCommand)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, map[string]any{"enabled": on, "settings_path": tildePath(srv.claudeSettings)})
}

// errNoSuchPermission is decide's 404.
var errNoSuchPermission = errors.New("no such pending request (unknown, already answered, or expired)")

// permissionDecide is POST /v1/claude/permissions/decide.
func (srv *server) permissionDecide(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID       string `json:"id"`
		Decision string `json:"decision"`
		Message  string `json:"message"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if body.Decision != decisionAllow && body.Decision != decisionDeny {
		writeError(w, http.StatusBadRequest, `decision must be "allow" or "deny"`)
		return
	}
	a := permissionAnswer{Decision: body.Decision}
	if body.Decision == decisionDeny {
		a.Message = truncateRunes(strings.TrimSpace(body.Message), denyMessageMaxRunes)
	}
	req, ok := srv.perms.answer(body.ID, a, time.Now())
	if !ok {
		writeError(w, http.StatusNotFound, errNoSuchPermission.Error())
		return
	}
	// The tool and the project, never the command: the phone's own history
	// has that, and the Mac's log is readable by more things than the phone.
	logAct(req.Source, body.Decision+" "+req.Tool+" in "+req.Project)
	writeJSON(w, map[string]any{})
}

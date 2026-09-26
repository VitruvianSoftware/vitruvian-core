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
	"fmt"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// v1.7: Antigravity (agy) gets a session list and a resume that streams, as
// Claude Code has.
//
// Answering agy's permission prompts from the phone is deliberately NOT
// here. Measured on agy 1.2.11: a PreToolUse hook that answers "allow" does
// not skip agy's own "Run this command?" prompt -- agy reads it as "no
// objection" and still asks at the Mac -- and a headless `agy -p` still
// auto-denies a command that needs permission. Only "deny" is honoured.
// Until agy lets a hook grant permission there is nothing for the phone to
// approve, so a phone-sent prompt works for whatever agy does without asking
// and a command that needs permission is refused, which the reply says.
//
// Everything here reads agy's own files under ~/.gemini/antigravity-cli; the
// path is a server field so a test points it at a temp dir.

const (
	// agyIdleStatus is the conversation status of a conversation at rest.
	agyIdleStatus = "CASCADE_RUN_STATUS_IDLE"
	// agySessionsMax is the contract's 20.
	agySessionsMax = 20
	// agyPromptMaxBytes bounds a resume prompt: it travels as one argv
	// element, and a phone keyboard does not type 8 KiB by accident.
	agyPromptMaxBytes = 8 << 10
	// agyResumeTimeout bounds one `agy -p` run from the phone. An agent run
	// is minutes, not seconds; the phone's Cancel (a hang-up) kills it sooner.
	agyResumeTimeout = 30 * time.Minute
	// agySQLiteTimeout bounds one read of the summaries database.
	agySQLiteTimeout = 5 * time.Second
)

// agyIDPattern is a conversation id: a UUID, lower-case hex and dashes. It is
// checked before the id reaches an argv or an SQL string.
var agyIDPattern = regexp.MustCompile(`^[0-9a-f-]{36}$`)

// agyDir is ~/.gemini/antigravity-cli, absolute.
func agyDir() string { return expandHome("~/.gemini/antigravity-cli") }

func defaultAgySummaries() string { return filepath.Join(agyDir(), "conversation_summaries.db") }

// agyStreamFunc runs one argv in dir and streams its output: runStreamArgv
// in the agent, a fake in tests (launching a real agy from a unit test is
// neither fast nor safe).
type agyStreamFunc func(ctx context.Context, argv []string, dir string, lines chan<- streamLine) (int, time.Duration)

func realAgyStream(ctx context.Context, argv []string, dir string, lines chan<- streamLine) (int, time.Duration) {
	return runStreamArgv(ctx, argv, dir, agyResumeTimeout, lines)
}

func (srv *server) antigravityRoutes(mux *http.ServeMux) {
	// READ, like /v1/claude/sessions: titles and projects anyone at the
	// keyboard sees in agy's own picker.
	mux.HandleFunc("/v1/antigravity/sessions", getOnly(srv.agySessions))
	// ACT: it runs an agent.
	mux.HandleFunc("/v1/antigravity/resume", postOnly(srv.act(srv.agyResume)))
}

// --- sessions ---

// agyRow is one row of conversation_summaries as `sqlite3 -json` prints it.
type agyRow struct {
	ConversationID string          `json:"conversation_id"`
	Title          string          `json:"title"`
	Preview        string          `json:"preview"`
	StepCount      int64           `json:"step_count"`
	LastModified   string          `json:"last_modified_time"`
	WorkspaceURIs  string          `json:"workspace_uris"`
	Status         string          `json:"status"`
	NotFullyIdle   json.RawMessage `json:"not_fully_idle"`
	Killed         json.RawMessage `json:"killed"`
}

// agySession is one entry of GET /v1/antigravity/sessions.
type agySession struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Preview   string `json:"preview"`
	Project   string `json:"project"`
	Steps     int64  `json:"steps"`
	UpdatedAt string `json:"updated_at"`
	State     string `json:"state"`
}

type agySessionsReply struct {
	Available bool         `json:"available"`
	Reason    string       `json:"reason,omitempty"`
	Sessions  []agySession `json:"sessions"`
}

const agyRowColumns = "conversation_id, title, preview, step_count, last_modified_time, workspace_uris, status, not_fully_idle, killed"

// querySummaries runs one SELECT against the summaries database with
// `sqlite3 -readonly -json`. agy holds the file open in WAL mode, which
// -readonly reads safely alongside it. The query is built from constants and
// an id that already matched agyIDPattern, never from free text.
func querySummaries(ctx context.Context, db, query string) ([]agyRow, error) {
	if _, err := os.Stat(db); err != nil {
		return nil, fmt.Errorf("no Antigravity conversations yet (%s not found)", tildePath(db))
	}
	if _, err := exec.LookPath("sqlite3"); err != nil {
		return nil, errors.New("sqlite3 not found on PATH")
	}
	ctx, cancel := context.WithTimeout(ctx, agySQLiteTimeout)
	defer cancel()
	out, err := runSQLite(ctx, "-readonly", db, query)
	if err != nil && strings.Contains(err.Error(), "unable to open database file") {
		// Found on the Mac: when agy is not running, the WAL side files
		// (-wal, -shm) are gone, and a read-only open of a WAL database
		// cannot create the -shm it needs, so -readonly fails outright. A
		// plain open can create it; the statement is still a SELECT built
		// from constants, so nothing is written to agy's data.
		out, err = runSQLite(ctx, "", db, query)
	}
	if err != nil {
		return nil, err
	}
	return parseAgyRows(out)
}

// runSQLite runs one statement with `sqlite3 -json`, plus mode ("-readonly" or
// nothing), and returns stdout or the first line of stderr as the error.
func runSQLite(ctx context.Context, mode, db, query string) ([]byte, error) {
	args := []string{"-json", db, query}
	if mode != "" {
		args = append([]string{mode}, args...)
	}
	cmd := exec.CommandContext(ctx, "sqlite3", args...)
	var so, se bytes.Buffer
	cmd.Stdout, cmd.Stderr = &so, &se
	if err := cmd.Run(); err != nil {
		msg := firstLine(se.String())
		if msg == "" {
			msg = err.Error()
		}
		return nil, fmt.Errorf("sqlite3: %s", msg)
	}
	return so.Bytes(), nil
}

// parseAgyRows reads sqlite3's -json output. No rows prints nothing at all,
// which is an empty list rather than a parse error.
func parseAgyRows(out []byte) ([]agyRow, error) {
	rows := []agyRow{}
	if len(bytes.TrimSpace(out)) == 0 {
		return rows, nil
	}
	if err := json.Unmarshal(out, &rows); err != nil {
		return nil, fmt.Errorf("cannot parse sqlite3 output: %w", err)
	}
	return rows, nil
}

// sqlBool reads a SQLite "numeric" boolean however it was stored: 0/1, a JSON
// true/false, or the text "true"/"false".
func sqlBool(raw json.RawMessage) bool {
	s := strings.Trim(strings.TrimSpace(string(raw)), `"`)
	switch strings.ToLower(s) {
	case "", "0", "false", "null":
		return false
	}
	if f, err := strconv.ParseFloat(s, 64); err == nil {
		return f != 0
	}
	return true
}

// agyWorkspaces decodes workspace_uris, a JSON array of file:// URIs, into
// paths. Anything that is not a file URI is skipped.
func agyWorkspaces(uris string) []string {
	var list []string
	if json.Unmarshal([]byte(uris), &list) != nil {
		return nil
	}
	var out []string
	for _, u := range list {
		pu, err := url.Parse(u)
		if err != nil || pu.Scheme != "file" || pu.Path == "" {
			continue
		}
		out = append(out, pu.Path)
	}
	return out
}

// agyTime turns SQLite's "2026-09-26 02:23:19.452133+00:00" into RFC 3339
// UTC. Anything else passes through as written rather than being dropped.
func agyTime(s string) string {
	for _, layout := range []string{"2006-01-02 15:04:05.999999999-07:00", "2006-01-02 15:04:05.999999999Z07:00", time.RFC3339Nano} {
		if t, err := time.Parse(layout, s); err == nil {
			return t.UTC().Format(time.RFC3339)
		}
	}
	return s
}

// agyState maps a row to the contract's three states. Killed comes first: a
// killed conversation may never have gone back to IDLE. An empty status is
// agy's column default, read as idle rather than as a claim that something
// is running.
func agyState(r agyRow) string {
	switch {
	case sqlBool(r.Killed):
		return "killed"
	case (r.Status != "" && r.Status != agyIdleStatus) || sqlBool(r.NotFullyIdle):
		return "working"
	default:
		return "idle"
	}
}

// agySessionsFrom builds the reply list, newest first, at most 20.
func agySessionsFrom(rows []agyRow) []agySession {
	out := make([]agySession, 0, len(rows))
	for _, r := range rows {
		project := ""
		if ws := agyWorkspaces(r.WorkspaceURIs); len(ws) > 0 {
			project = filepath.Base(filepath.Clean(ws[0]))
		}
		out = append(out, agySession{
			ID:        r.ConversationID,
			Title:     r.Title,
			Preview:   r.Preview,
			Project:   project,
			Steps:     r.StepCount,
			UpdatedAt: agyTime(r.LastModified),
			State:     agyState(r),
		})
	}
	// SQL already ordered them as text; sorting again on the parsed time
	// keeps the contract's "newest first" true whatever the stored format
	// was. A time that does not parse sorts last rather than first.
	key := func(s agySession) time.Time {
		t, _ := time.Parse(time.RFC3339, s.UpdatedAt)
		return t
	}
	sort.SliceStable(out, func(i, j int) bool { return key(out[i]).After(key(out[j])) })
	if len(out) > agySessionsMax {
		out = out[:agySessionsMax]
	}
	return out
}

// agySessions is GET /v1/antigravity/sessions.
func (srv *server) agySessions(w http.ResponseWriter, r *http.Request) {
	rows, err := querySummaries(r.Context(), srv.agySummaries,
		"SELECT "+agyRowColumns+" FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT "+strconv.Itoa(agySessionsMax))
	if err != nil {
		writeJSON(w, agySessionsReply{Reason: err.Error(), Sessions: []agySession{}})
		return
	}
	writeJSON(w, agySessionsReply{Available: true, Sessions: agySessionsFrom(rows)})
}

// --- resume ---

// agyResumeArgv is `agy -p <prompt> --output-format text [--conversation
// <id>]`. The prompt and the id are each one argv element: values, never
// command text.
func agyResumeArgv(conversationID, prompt string) []string {
	argv := []string{"agy", "-p", prompt, "--output-format", "text"}
	if conversationID != "" {
		argv = append(argv, "--conversation", conversationID)
	}
	return argv
}

// validateAgyResume checks the body before anything runs: an id that is
// empty (a new conversation) or a UUID, and a prompt that is there and not
// huge.
func validateAgyResume(conversationID, prompt string) error {
	if conversationID != "" && !agyIDPattern.MatchString(conversationID) {
		return errors.New("conversation_id must be empty or a conversation id (36 characters of 0-9, a-f and -)")
	}
	if strings.TrimSpace(prompt) == "" {
		return errors.New("prompt is required")
	}
	if len(prompt) > agyPromptMaxBytes {
		return fmt.Errorf("prompt is %d bytes; the limit is %d", len(prompt), agyPromptMaxBytes)
	}
	return nil
}

// agyResumeDir is where the run happens: the conversation's first workspace
// when the database knows it and it is still a directory, else --exec-dir.
func (srv *server) agyResumeDir(ctx context.Context, conversationID string) string {
	if conversationID == "" {
		return execDir
	}
	rows, err := querySummaries(ctx, srv.agySummaries,
		"SELECT "+agyRowColumns+" FROM conversation_summaries WHERE conversation_id = '"+conversationID+"' LIMIT 1")
	if err != nil || len(rows) == 0 {
		return execDir
	}
	ws := agyWorkspaces(rows[0].WorkspaceURIs)
	if len(ws) == 0 {
		return execDir
	}
	if st, err := os.Stat(ws[0]); err != nil || !st.IsDir() {
		return execDir
	}
	return ws[0]
}

// agyResume is POST /v1/antigravity/resume: the same SSE stream as
// /v1/exec/stream, running agy.
func (srv *server) agyResume(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ConversationID string `json:"conversation_id"`
		Prompt         string `json:"prompt"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	body.ConversationID = strings.TrimSpace(body.ConversationID)
	if err := validateAgyResume(body.ConversationID, body.Prompt); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "this server cannot stream")
		return
	}
	dir := srv.agyResumeDir(r.Context(), body.ConversationID)
	argv := agyResumeArgv(body.ConversationID, body.Prompt)
	id := execStreamID.Add(1)
	target := body.ConversationID
	if target == "" {
		target = "new conversation"
	}
	logAct("antigravity-resume", fmt.Sprintf("stream #%d start: %s: %s", id, target, body.Prompt))
	code, dur := serveSSE(w, flusher, func(lines chan<- streamLine) (int, time.Duration) {
		return srv.agyStream(r.Context(), argv, dir, lines)
	})
	logAct("antigravity-resume", fmt.Sprintf("stream #%d exit %d after %dms", id, code, dur.Milliseconds()))
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		srv.sampler.Notifier().notify(ctx, "exec:"+strconv.FormatInt(id, 10),
			"Antigravity finished · exit "+strconv.Itoa(code),
			firstNChars(body.Prompt, 80), "default", "checkered_flag", "vitruvian-remote://apps/antigravity")
	}()
}

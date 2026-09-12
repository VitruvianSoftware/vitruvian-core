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

package metrics

import (
	"encoding/json"
	"strings"
	"time"
)

// The v1.2 Claude Code session reader. Pure, like everything else in this
// package: the caller does the file I/O and hands over the tail; this turns
// it into "what is that session doing right now".
//
// The honest framing, which the API document repeats: this is a HEURISTIC.
// Claude Code writes no "I am blocked on a permission prompt" record, so the
// only evidence available is the shape of the last few transcript entries.
// A tool call that has produced no result for twenty seconds is USUALLY a
// permission prompt and OCCASIONALLY a slow grep. Reporting it as "waiting"
// is the useful error to make -- a person who looks and finds it working has
// lost two seconds; a person never told has lost the afternoon.

// The session states. Strings, not an enum, because they cross the wire to
// the phone and a JSON number would have to be kept in step by hand on both
// sides.
const (
	StateWaitingForPermission = "waiting_for_permission"
	StateWorking              = "working"
	StateIdle                 = "idle"
	StateUnknown              = "unknown"
)

// permissionAfter is how long an unanswered tool call has to sit before the
// session is called "waiting" rather than busy.
//
// Twenty seconds was the first guess and it flagged the agent's own author:
// a Bash tool running a Bazel build sits unanswered for minutes and is not
// waiting for anyone. The transcript cannot tell a permission prompt from a
// long command -- both are a tool_use with no result -- so the state is a
// heuristic and its consumers say so. Ninety seconds keeps most builds out
// of it while still catching a prompt before a person gives up on the phone.
const permissionAfter = 90 * time.Second

// lastTextLimit is how much of the final assistant message travels to the
// phone: enough to recognise the turn, short enough for a notification.
const lastTextLimit = 300

// SessionState is what one transcript tail says about its session.
//
// LastActive and Cwd come from the same pass rather than from the file's
// mtime and a separate read of its head: the tail already carries both, and
// a second source would be a second thing that can disagree.
type SessionState struct {
	State      string
	LastRole   string
	LastText   string
	LastTool   string
	LastActive time.Time
	Cwd        string
}

// ClaudeSession is one row of GET /v1/claude/sessions.
type ClaudeSession struct {
	SessionID  string    `json:"session_id"`
	Project    string    `json:"project"`
	Cwd        string    `json:"cwd"`
	Path       string    `json:"path"`
	LastActive time.Time `json:"last_active"`
	State      string    `json:"state"`
	LastRole   string    `json:"last_role"`
	LastText   string    `json:"last_text"`
	LastTool   string    `json:"last_tool"`
}

// ClaudeSessions is the body of GET /v1/claude/sessions.
type ClaudeSessions struct {
	Sessions []ClaudeSession `json:"sessions"`
}

// transcriptRecord is the subset of a transcript line this cares about.
// Everything else in those objects -- and there is a lot of it -- is left
// alone, so a new field upstream cannot break the parse.
type transcriptRecord struct {
	Type      string `json:"type"`
	Timestamp string `json:"timestamp"`
	Cwd       string `json:"cwd"`
	Message   struct {
		Role string `json:"role"`
		// Content is a list of blocks on a normal record and a bare string
		// on a user record typed by a person, so it is decoded late.
		Content json.RawMessage `json:"content"`
	} `json:"message"`
}

// contentBlock is one item of message.content.
type contentBlock struct {
	Type string `json:"type"`
	Text string `json:"text"`
	Name string `json:"name"`
}

// ParseTranscriptTail reads the last records of a Claude Code transcript and
// decides what the session is doing, as of now.
//
// The tail starts mid-record: the caller reads a fixed 64 KiB from the end of
// the file, which lands in the middle of a line far more often than not. The
// first line is therefore dropped whenever it does not parse -- silently,
// because that is the normal case and not a fault. Every other unparseable
// line is skipped too, along with the record types Claude Code interleaves
// with the conversation (attachment, system, atis-latch, pr-link,
// bridge-session, custom-title, ...), which cluster at the end of a file and
// would otherwise be read as "the last thing that happened".
func ParseTranscriptTail(tail string, now time.Time) SessionState {
	st := SessionState{State: StateUnknown}

	var last transcriptRecord
	var lastBlocks []contentBlock
	found := false
	// Cwd is taken from any record that carries one, not only the last: the
	// records that carry it are not always the conversational ones.
	for i, line := range strings.Split(tail, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var rec transcriptRecord
		if err := json.Unmarshal([]byte(line), &rec); err != nil {
			// i == 0 is the expected truncation; the rest is a record shape
			// this does not know, and skipping is the same answer for both.
			_ = i
			continue
		}
		if rec.Cwd != "" {
			st.Cwd = rec.Cwd
		}
		if rec.Type != "user" && rec.Type != "assistant" {
			continue
		}
		blocks, ok := decodeContent(rec.Message.Content)
		if !ok {
			continue
		}
		last, lastBlocks, found = rec, blocks, true
	}
	if !found {
		return st
	}

	st.LastRole = last.Type
	if ts, err := time.Parse(time.RFC3339, last.Timestamp); err == nil {
		st.LastActive = ts
	}

	// The last assistant text in the whole tail, not only in the last
	// record: an assistant turn that ends in a tool call still has text
	// worth showing above it, and a phone with a blank summary is no better
	// than no phone.
	st.LastText = lastAssistantText(tail)

	switch last.Type {
	case "user":
		// A tool result (or a person's prompt) just landed, so the model has
		// something to do. Working, whatever it was before.
		st.State = StateWorking
	case "assistant":
		if tool := lastToolUse(lastBlocks); tool != "" {
			st.LastTool = tool
			// A tool call with no result after it. Age decides which kind of
			// waiting this is; a zero timestamp cannot, so it is treated as
			// fresh rather than promoted to "blocked" on no evidence.
			if !st.LastActive.IsZero() && now.Sub(st.LastActive) >= permissionAfter {
				st.State = StateWaitingForPermission
			} else {
				st.State = StateWorking
			}
		} else if hasText(lastBlocks) {
			// The turn ended with prose: it is the person's move now.
			st.State = StateIdle
		} else {
			// Thinking only, with nothing after it -- a turn caught in
			// flight rather than a finished one.
			st.State = StateWorking
		}
	}
	return st
}

// decodeContent turns message.content into blocks. A user record typed by a
// person carries a bare string there, which is a real record and not a
// broken one, so it becomes a single text block rather than a skip.
func decodeContent(raw json.RawMessage) ([]contentBlock, bool) {
	if len(raw) == 0 {
		return nil, false
	}
	var blocks []contentBlock
	if err := json.Unmarshal(raw, &blocks); err == nil {
		return blocks, true
	}
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		return []contentBlock{{Type: "text", Text: s}}, true
	}
	return nil, false
}

// lastToolUse names the tool if the record's final meaningful block is a
// tool call. Final, not "any": an assistant turn that called a tool and then
// wrote prose has finished with the prose.
func lastToolUse(blocks []contentBlock) string {
	for i := len(blocks) - 1; i >= 0; i-- {
		switch blocks[i].Type {
		case "tool_use":
			return blocks[i].Name
		case "text":
			if strings.TrimSpace(blocks[i].Text) != "" {
				return ""
			}
		case "thinking":
			// Thinking is not an answer to anything; keep looking past it.
			continue
		}
	}
	return ""
}

func hasText(blocks []contentBlock) bool {
	for _, b := range blocks {
		if b.Type == "text" && strings.TrimSpace(b.Text) != "" {
			return true
		}
	}
	return false
}

// lastAssistantText finds the newest assistant prose in the tail and trims
// it to lastTextLimit. Bytes, not runes, would cut a multi-byte character in
// half and produce a notification body a phone renders as a replacement
// glyph, so the trim is on runes.
func lastAssistantText(tail string) string {
	out := ""
	for _, line := range strings.Split(tail, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var rec transcriptRecord
		if err := json.Unmarshal([]byte(line), &rec); err != nil || rec.Type != "assistant" {
			continue
		}
		blocks, ok := decodeContent(rec.Message.Content)
		if !ok {
			continue
		}
		for _, b := range blocks {
			if b.Type == "text" && strings.TrimSpace(b.Text) != "" {
				out = strings.TrimSpace(b.Text)
			}
		}
	}
	return TrimRunes(out, lastTextLimit)
}

// TrimRunes cuts s to at most n runes. Exported because the notifier trims
// the same strings to a shorter length for a notification body, and two
// copies of this would eventually disagree about multi-byte characters.
func TrimRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}

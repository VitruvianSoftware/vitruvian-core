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
	"strings"
	"testing"
	"time"
)

// The records below are the real shapes, copied from a live transcript on
// this machine (~/.claude/projects/.../*.jsonl, 2026-09-07) and shortened:
// same keys, same nesting, same content-block types, less prose. The tail
// of a real file is exactly this -- conversation records interleaved with
// bookkeeping ones (attachment, atis-latch, pr-link, bridge-session) that
// cluster at the very end and would be read as "the last thing that
// happened" by anything that did not skip them.

// now is the fixed clock these tests reason against. A real one would make
// the twenty-second permission rule flaky at exactly the wrong moment.
var sessionNow = time.Date(2026, 9, 7, 20, 30, 0, 0, time.UTC)

func at(offset time.Duration) string {
	return sessionNow.Add(-offset).Format(time.RFC3339)
}

// recAssistantTool is an assistant turn whose last content block is a Bash
// tool call: the shape that means either "running a command" or "sitting on
// a permission prompt", depending only on how old it is.
func recAssistantTool(offset time.Duration, tool string) string {
	return `{"parentUuid":"e1c42cb5-4095-45c5-b767-db9a7e70a1b3","isSidechain":false,` +
		`"message":{"model":"claude-fable-5-1","id":"msg_011Cepgz","type":"message","role":"assistant",` +
		`"content":[{"type":"thinking","thinking":"weighing it up","signature":"CAQS"},` +
		`{"type":"tool_use","id":"toolu_01A","name":"` + tool + `","input":{"command":"pgrep sleep"}}]},` +
		`"type":"assistant","uuid":"3dc60e27-3c23-47f9-9a7d-1876ae7fc2d2","timestamp":"` + at(offset) + `",` +
		`"cwd":"/Users/james/Workspace/gh/application/vitruvian/vitruvian-core","sessionId":"b4d0359c-d7e1-4db0-8960-536873764a56"}`
}

func recUserToolResult(offset time.Duration) string {
	return `{"parentUuid":"3dc60e27-3c23-47f9-9a7d-1876ae7fc2d2","isSidechain":false,` +
		`"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01A","content":"no output"}]},` +
		`"type":"user","uuid":"40497659-2495-43e4-b298-4876b5f5c5d5","timestamp":"` + at(offset) + `",` +
		`"cwd":"/Users/james/Workspace/gh/application/vitruvian/vitruvian-core","sessionId":"b4d0359c-d7e1-4db0-8960-536873764a56"}`
}

func recAssistantText(offset time.Duration, text string) string {
	return `{"parentUuid":"40497659-2495-43e4-b298-4876b5f5c5d5","isSidechain":false,` +
		`"message":{"model":"claude-fable-5-1","id":"msg_011Cepgz","type":"message","role":"assistant",` +
		`"content":[{"type":"text","text":"` + text + `"}]},` +
		`"type":"assistant","uuid":"0fa29aab-2f57-4a76-b158-5db72ef06612","timestamp":"` + at(offset) + `",` +
		`"cwd":"/Users/james/Workspace/gh/application/vitruvian/vitruvian-core","sessionId":"b4d0359c-d7e1-4db0-8960-536873764a56"}`
}

// The bookkeeping records. These are what the end of a real transcript is
// mostly made of, and every one of them must be invisible to the state.
const (
	recAtisLatch     = `{"parentUuid":"0fa29aab-2f57-4a76-b158-5db72ef06612","type":"atis-latch","uuid":"a72db1d5-e7f9-405a-8c31-294f45758799","timestamp":"2026-09-07T20:29:58Z","cwd":"/Users/james/Workspace/gh/application/vitruvian/vitruvian-core","sessionId":"b4d0359c-d7e1-4db0-8960-536873764a56","latched":true}`
	recPRLink        = `{"parentUuid":"a72db1d5-e7f9-405a-8c31-294f45758799","type":"pr-link","uuid":"c1a4b2f0-1111-2222-3333-444455556666","timestamp":"2026-09-07T20:29:59Z","cwd":"/Users/james/Workspace/gh/application/vitruvian/vitruvian-core","sessionId":"b4d0359c-d7e1-4db0-8960-536873764a56","url":"https://github.com/VitruvianSoftware/vitruvian-core/pull/2226"}`
	recBridgeSession = `{"parentUuid":"c1a4b2f0-1111-2222-3333-444455556666","type":"bridge-session","uuid":"d2b5c3e1-7777-8888-9999-aaaabbbbcccc","timestamp":"2026-09-07T20:30:00Z","cwd":"/Users/james/Workspace/gh/application/vitruvian/vitruvian-core","sessionId":"b4d0359c-d7e1-4db0-8960-536873764a56"}`
	recAttachment    = `{"parentUuid":"d2b5c3e1-7777-8888-9999-aaaabbbbcccc","attachment":{"type":"batching_reminder_sent","text":"a reminder"},"type":"attachment","uuid":"e3c6d4f2-dddd-eeee-ffff-000011112222","timestamp":"2026-09-07T20:30:00Z","cwd":"/Users/james/Workspace/gh/application/vitruvian/vitruvian-core","sessionId":"b4d0359c-d7e1-4db0-8960-536873764a56"}`
)

// tailing joins records the way the file does, and prepends the shard of a
// record that a 64 KiB read from the end of the file always lands in.
func tailing(records ...string) string {
	const truncated = `mp":"2026-09-07T20:12:41Z","cwd":"/Users/james/Workspace","sessionId":"b4d0359c"}`
	return truncated + "\n" + strings.Join(records, "\n") + "\n"
}

func TestParseTranscriptTailStates(t *testing.T) {
	for _, tc := range []struct {
		name     string
		tail     string
		want     string
		wantTool string
		wantRole string
	}{
		{
			// A tool call still fresh: the model is running something, not
			// blocked. Calling this "waiting" would push a notification for
			// every grep.
			name:     "fresh tool call is working",
			tail:     tailing(recAssistantText(2*time.Minute, "Let me check."), recAssistantTool(5*time.Second, "Bash")),
			want:     StateWorking,
			wantTool: "Bash",
			wantRole: "assistant",
		},
		{
			// The same call, twenty seconds older and still unanswered. This
			// is the transition the phone exists to catch.
			name:     "stale tool call is waiting for permission",
			tail:     tailing(recAssistantText(2*time.Minute, "Let me check."), recAssistantTool(45*time.Second, "Bash")),
			want:     StateWaitingForPermission,
			wantTool: "Bash",
			wantRole: "assistant",
		},
		{
			// A tool_result landed: whatever it was waiting on is answered.
			name:     "tool result means working again",
			tail:     tailing(recAssistantTool(90*time.Second, "Bash"), recUserToolResult(3*time.Second)),
			want:     StateWorking,
			wantRole: "user",
		},
		{
			// The turn ended in prose. Nothing is running; it is the
			// person's move, however long ago that was.
			name:     "assistant text is idle",
			tail:     tailing(recUserToolResult(3*time.Minute), recAssistantText(90*time.Second, "Done -- all four gates are green.")),
			want:     StateIdle,
			wantRole: "assistant",
		},
		{
			// The bookkeeping records at the end of every real file. The
			// state must come from the last CONVERSATION record underneath
			// them, and this is the case a naive "last line" reader fails.
			name:     "bookkeeping records at the end are skipped",
			tail:     tailing(recAssistantText(90*time.Second, "Done."), recAtisLatch, recPRLink, recBridgeSession, recAttachment),
			want:     StateIdle,
			wantRole: "assistant",
		},
		{
			// Nothing parseable at all: say so rather than guess a state.
			name: "no conversation records is unknown",
			tail: tailing(recAtisLatch, recPRLink),
			want: StateUnknown,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := ParseTranscriptTail(tc.tail, sessionNow)
			if got.State != tc.want {
				t.Errorf("state = %q, want %q (%+v)", got.State, tc.want, got)
			}
			if got.LastTool != tc.wantTool {
				t.Errorf("last_tool = %q, want %q", got.LastTool, tc.wantTool)
			}
			if got.LastRole != tc.wantRole {
				t.Errorf("last_role = %q, want %q", got.LastRole, tc.wantRole)
			}
		})
	}
}

func TestParseTranscriptTailSurvivesATruncatedFirstLine(t *testing.T) {
	// Reading the last 64 KiB of a file lands mid-record almost every time,
	// so the first line is normally a fragment. It must be dropped without
	// taking the rest of the parse with it -- and the fragment's own cwd
	// (which is a DIFFERENT path here) must not become the session's.
	tail := tailing(recAssistantText(30*time.Second, "Fine."))
	got := ParseTranscriptTail(tail, sessionNow)
	if got.State != StateIdle {
		t.Fatalf("a truncated first line broke the parse: %+v", got)
	}
	if got.Cwd != "/Users/james/Workspace/gh/application/vitruvian/vitruvian-core" {
		t.Errorf("cwd came from the truncated fragment: %q", got.Cwd)
	}
	if got.LastText != "Fine." {
		t.Errorf("last_text = %q", got.LastText)
	}
	// A tail with nothing but a fragment is unknown, not a crash.
	if s := ParseTranscriptTail(`{"type":"assis`, sessionNow); s.State != StateUnknown {
		t.Errorf("fragment only: %+v", s)
	}
	if s := ParseTranscriptTail("", sessionNow); s.State != StateUnknown {
		t.Errorf("empty tail: %+v", s)
	}
}

func TestParseTranscriptTailCarriesTextAndTimestamp(t *testing.T) {
	tail := tailing(recAssistantText(90*time.Second, "Both halves are building."), recAssistantTool(45*time.Second, "Read"))
	got := ParseTranscriptTail(tail, sessionNow)
	// The text of the turn survives past the tool call it ended with: a
	// notification saying only "Read" tells nobody anything.
	if got.LastText != "Both halves are building." {
		t.Errorf("last_text = %q", got.LastText)
	}
	if want := sessionNow.Add(-45 * time.Second); !got.LastActive.Equal(want) {
		t.Errorf("last_active = %v, want %v", got.LastActive, want)
	}
	// A person's typed prompt arrives as a bare string in message.content,
	// not a block list. It is a real record and means the model is working.
	typed := `{"type":"user","timestamp":"` + at(time.Second) + `","cwd":"/tmp","sessionId":"x","message":{"role":"user","content":"do the thing"}}`
	if s := ParseTranscriptTail(tailing(typed), sessionNow); s.State != StateWorking {
		t.Errorf("a typed prompt: %+v", s)
	}
}

func TestTrimRunesDoesNotSplitACharacter(t *testing.T) {
	if got := TrimRunes("héllo", 3); got != "hél" {
		t.Errorf("got %q", got)
	}
	if got := TrimRunes("short", 300); got != "short" {
		t.Errorf("got %q", got)
	}
	long := strings.Repeat("é", 400)
	if got := TrimRunes(long, lastTextLimit); len([]rune(got)) != lastTextLimit {
		t.Errorf("trimmed to %d runes", len([]rune(got)))
	}
}

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
	"flag"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// agy-permission-hook: agy's PreToolUse hook, the Antigravity twin of
// permission-hook.
//
// The difference that shapes all of this: agy has no "about to prompt" event.
// PreToolUse fires for EVERY tool call, BEFORE agy's own prompt. So this hook
// first decides whether agy would have asked at all, and stays silent when it
// would not -- otherwise every grep would wait on the phone. And because agy
// shows nothing on the Mac while a hook runs, the hook shows its own Mac
// dialog alongside the phone prompt, so someone at the desk is never stuck
// waiting for a phone they are not holding. First answer wins.
//
// Same rule as permission-hook: it prints a decision or NOTHING and always
// exits 0. Nothing printed means agy carries on as if there were no hook --
// which, for a command that needs permission, means agy shows its own prompt.

// agyHookInput is the part of agy's PreToolUse JSON this hook reads.
type agyHookInput struct {
	ConversationID string   `json:"conversationId"`
	WorkspacePaths []string `json:"workspacePaths"`
	ToolCall       struct {
		Name string         `json:"name"`
		Args map[string]any `json:"args"`
	} `json:"toolCall"`
}

// agyHookReply is what the hook prints. Key order is the contract's.
type agyHookReply struct {
	Decision string `json:"decision"`
	Reason   string `json:"reason,omitempty"`
}

// The two default deny reasons.
const (
	agyDeniedPhone = "Denied from the phone"
	agyDeniedMac   = "Denied on the Mac"
)

// dialogFunc shows the Mac dialog for command and returns "allow", "deny",
// or "" for no answer (it gave up). It must return promptly when ctx is
// cancelled: that is how the losing dialog is taken off the screen.
type dialogFunc func(ctx context.Context, command string, wait time.Duration) (string, error)

// agyHookDeps is everything the hook talks to, so a test can replace each.
type agyHookDeps struct {
	settingsPath string        // agy's settings.json, for permissions.allow
	baseURL      string        // the agent
	token        string        // the hook token; empty skips the phone
	client       *http.Client  // to the agent
	dialog       dialogFunc    // the Mac dialog; nil skips it
	dialogWait   time.Duration // how long the dialog stays up
	total        time.Duration // the whole hook's bound
}

// agyAllowPrefixes reads the `command(<prefix>)` rules from permissions.allow
// in agy's settings.json. An error means the file could not be read or
// parsed; the caller then assumes agy WOULD prompt.
func agyAllowPrefixes(path string) ([]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var s struct {
		Permissions struct {
			Allow []string `json:"allow"`
		} `json:"permissions"`
	}
	if err := json.Unmarshal(b, &s); err != nil {
		return nil, err
	}
	var out []string
	for _, rule := range s.Permissions.Allow {
		rule = strings.TrimSpace(rule)
		inner, ok := strings.CutPrefix(rule, "command(")
		if !ok {
			continue
		}
		inner, ok = strings.CutSuffix(inner, ")")
		if !ok {
			continue
		}
		if inner = strings.TrimSpace(inner); inner != "" {
			out = append(out, inner)
		}
	}
	return out, nil
}

// agyWouldPrompt reports whether agy would ask before this tool call. Only
// run_command is routed, and it is allowed without asking when the trimmed
// command line IS an allowed prefix or starts with one followed by a space
// (so `command(grep)` allows `grep -r x` but not `grepx`). Unreadable
// settings count as "would prompt": asking once too often is safe, staying
// silent when agy is about to wait on a person is the thing to avoid.
func agyWouldPrompt(tool, commandLine, settingsPath string) bool {
	if tool != agyRunCommand {
		return false
	}
	cmd := strings.TrimSpace(commandLine)
	if cmd == "" {
		return false
	}
	prefixes, err := agyAllowPrefixes(settingsPath)
	if err != nil {
		return true
	}
	for _, p := range prefixes {
		if cmd == p || strings.HasPrefix(cmd, p+" ") {
			return false
		}
	}
	return true
}

// agyAnswer is one side's result in the race.
type agyAnswer struct {
	decision string // allow, deny, or "" for no answer
	reason   string
}

// askAgentForAgy is the phone side: the agent's ask endpoint, with the body
// normalised to Claude Code's shape plus source. Any failure is no answer.
func askAgentForAgy(ctx context.Context, d agyHookDeps, in agyHookInput, command, cwd string) agyAnswer {
	if d.token == "" || d.client == nil {
		return agyAnswer{}
	}
	input, _ := json.Marshal(map[string]string{"command": command})
	body, err := json.Marshal(map[string]any{
		"source":     sourceAntigravity,
		"session_id": in.ConversationID,
		"cwd":        cwd,
		"tool_name":  agyRunCommand,
		"tool_input": json.RawMessage(input),
	})
	if err != nil {
		return agyAnswer{}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(d.baseURL, "/")+"/v1/claude/permission/ask", bytes.NewReader(body))
	if err != nil {
		return agyAnswer{}
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+d.token)
	resp, err := d.client.Do(req)
	if err != nil {
		return agyAnswer{}
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return agyAnswer{}
	}
	var reply struct {
		Decision string `json:"decision"`
		Message  string `json:"message"`
	}
	if json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&reply) != nil {
		return agyAnswer{}
	}
	switch reply.Decision {
	case decisionAllow:
		return agyAnswer{decision: decisionAllow}
	case decisionDeny:
		msg := strings.TrimSpace(reply.Message)
		if msg == "" {
			msg = agyDeniedPhone
		}
		return agyAnswer{decision: decisionDeny, reason: msg}
	}
	return agyAnswer{}
}

// agyPermissionHookOutput is the whole hook minus the process: the bytes to
// print, or nil for nothing.
func agyPermissionHookOutput(stdin io.Reader, d agyHookDeps) []byte {
	raw, err := io.ReadAll(io.LimitReader(stdin, maxRequestBody+1))
	if err != nil || len(raw) > maxRequestBody {
		return nil
	}
	var in agyHookInput
	if json.Unmarshal(raw, &in) != nil {
		return nil
	}
	command, _ := in.ToolCall.Args["CommandLine"].(string)
	if !agyWouldPrompt(in.ToolCall.Name, command, d.settingsPath) {
		return nil
	}
	cwd, _ := in.ToolCall.Args["Cwd"].(string)
	if cwd == "" && len(in.WorkspacePaths) > 0 {
		cwd = in.WorkspacePaths[0]
	}

	total := d.total
	if total <= 0 {
		total = hookTotalTimeout
	}
	ctx, cancel := context.WithTimeout(context.Background(), total)
	// Cancelling is how the loser is stopped: the agent request is dropped
	// (the pending item leaves the phone) and the dialog process is killed.
	defer cancel()

	answers := make(chan agyAnswer, 2)
	sides := 0
	if d.token != "" && d.client != nil {
		sides++
		go func() { answers <- askAgentForAgy(ctx, d, in, command, cwd) }()
	}
	if d.dialog != nil {
		sides++
		go func() {
			got, err := d.dialog(ctx, command, d.dialogWait)
			if err != nil || (got != decisionAllow && got != decisionDeny) {
				answers <- agyAnswer{}
				return
			}
			a := agyAnswer{decision: got}
			if got == decisionDeny {
				a.reason = agyDeniedMac
			}
			answers <- a
		}()
	}

	// The first real answer wins. A side with no answer (timed out, agent
	// down, dialog failed) does not end the race; the other side still can.
	var win agyAnswer
	received := 0
race:
	for received < sides {
		select {
		case a := <-answers:
			received++
			if a.decision != "" {
				win = a
				break race
			}
		case <-ctx.Done():
			break race
		}
	}
	cancel()
	// Wait for the loser to wind down before returning. The subcommand exits
	// right after printing, and exiting first would orphan osascript -- the
	// dialog would stay on screen after the phone already answered. Both
	// sides return promptly once ctx is cancelled.
	for ; received < sides; received++ {
		<-answers
	}
	if win.decision == "" {
		return nil
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(agyHookReply{Decision: win.decision, Reason: win.reason}); err != nil {
		return nil
	}
	return buf.Bytes()
}

// agyDialogScript takes the command as an argument (item 1 of argv), never
// spliced into the script text, so no command can break out of the string.
const agyDialogScript = `on run argv
	set r to display dialog ("Antigravity wants to run: " & item 1 of argv) with title "Vitruvian Remote" buttons {"Deny", "Allow"} default button "Allow" giving up after (item 2 of argv as integer)
	if gave up of r then return "gave up"
	return button returned of r
end run`

// macDialog is the real dialogFunc: osascript's display dialog. "gave up"
// is no answer; the process is killed when ctx is cancelled.
func macDialog(ctx context.Context, command string, wait time.Duration) (string, error) {
	secs := int(wait / time.Second)
	if secs < 1 {
		secs = 1
	}
	cmd := exec.CommandContext(ctx, "osascript", "-e", agyDialogScript, truncateRunes(command, 1000), strconv.Itoa(secs))
	cmd.WaitDelay = time.Second
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	switch strings.TrimSpace(string(out)) {
	case "Allow":
		return decisionAllow, nil
	case "Deny":
		return decisionDeny, nil
	}
	return "", nil
}

// runAgyPermissionHook is the subcommand. Like runPermissionHook it swallows
// everything, a panic included: its only permitted failure is printing
// nothing and exiting 0.
func runAgyPermissionHook(args []string, stdin io.Reader, stdout io.Writer) {
	defer func() { _ = recover() }()
	fs := flag.NewFlagSet(agyHookVerb, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	configDir := fs.String("config-dir", "", "")
	settings := fs.String("agy-settings", "", "")
	_ = fs.Parse(args)
	d := agyHookDeps{
		settingsPath: defaultAgySettings(),
		baseURL:      "http://127.0.0.1:" + defaultPort,
		client:       newHookClient(),
		dialog:       macDialog,
		dialogWait:   agyDialogWait,
		total:        hookTotalTimeout,
	}
	if *settings != "" {
		d.settingsPath = expandHome(*settings)
	}
	// No token is not fatal here, unlike permission-hook: the Mac dialog
	// still works with the agent down or never started.
	if b, err := os.ReadFile(NewStore(*configDir).hookTokenPath()); err == nil {
		d.token = strings.TrimSpace(string(b))
	}
	if out := agyPermissionHookOutput(stdin, d); out != nil {
		_, _ = stdout.Write(out)
	}
}

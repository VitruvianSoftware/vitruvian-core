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
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// The two v1.6 subcommands that run on the Claude Code side of the wire:
//
//   permission-hook      Claude Code's PermissionRequest hook. stdin -> agent
//                        -> stdout. Prints a decision or NOTHING, and always
//                        exits 0, because a hook that fails loudly makes
//                        Claude Code worse than no hook at all.
//   install-claude-hook  adds (or with --remove, takes out) exactly one entry
//                        in ~/.claude/settings.json and touches nothing else.

const (
	// hookBinaryName and hookVerb identify OUR entry in settings.json: a
	// command that mentions the binary and ends in the verb. Loose on the
	// directory on purpose, so an entry written by an install elsewhere, or
	// by an older build that wrote "~/.local/bin/...", is still recognised
	// as ours and replaced rather than duplicated.
	hookBinaryName = "vitruvian-remote-agent"
	hookVerb       = "permission-hook"
	// hookTimeoutSeconds is the timeout Claude Code gives the hook. The
	// agent's wait is clamped to 140 s so this is never what ends a wait.
	hookTimeoutSeconds = 150
	// hookConnectTimeout / hookTotalTimeout are the contract's 1 s to reach
	// the agent and 145 s overall (above the agent's 140 s max, below
	// Claude Code's 150 s).
	hookConnectTimeout = time.Second
	hookTotalTimeout   = 145 * time.Second
)

// --- permission-hook ---

// hookOutput is the PermissionRequest hook's stdout shape. Structs rather
// than a map so the key order is the contract's, byte for byte.
type hookOutput struct {
	HookSpecificOutput hookSpecific `json:"hookSpecificOutput"`
}

type hookSpecific struct {
	HookEventName string       `json:"hookEventName"`
	Decision      hookDecision `json:"decision"`
}

type hookDecision struct {
	Behavior string `json:"behavior"`
	Message  string `json:"message,omitempty"`
}

// newHookClient is the hook's HTTP client: 1 s to connect, 145 s in all,
// and no proxy -- an HTTP_PROXY in Claude Code's environment must not route
// a loopback call through somewhere else.
func newHookClient() *http.Client {
	return &http.Client{
		Timeout: hookTotalTimeout,
		Transport: &http.Transport{
			Proxy:       nil,
			DialContext: (&net.Dialer{Timeout: hookConnectTimeout}).DialContext,
		},
	}
}

// permissionHookOutput is the whole hook, minus the process: it reads the
// hook JSON from stdin, asks the agent at baseURL, and returns the bytes to
// print -- or nil, which means print nothing and let Claude Code show its own
// dialog. Every failure is nil. It never returns partial JSON, because the
// caller writes the result in one piece or not at all.
func permissionHookOutput(stdin io.Reader, baseURL, token string, client *http.Client) []byte {
	if token == "" {
		return nil
	}
	in, err := io.ReadAll(io.LimitReader(stdin, maxRequestBody+1))
	if err != nil || len(in) > maxRequestBody || !json.Valid(in) {
		return nil
	}
	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(baseURL, "/")+"/v1/claude/permission/ask", bytes.NewReader(in))
	if err != nil {
		return nil
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := client.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil
	}
	var reply struct {
		Decision string `json:"decision"`
		Message  string `json:"message"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&reply); err != nil {
		return nil
	}
	var d hookDecision
	switch reply.Decision {
	case decisionAllow:
		d = hookDecision{Behavior: decisionAllow}
	case decisionDeny:
		msg := strings.TrimSpace(reply.Message)
		if msg == "" {
			msg = defaultDenyMessage
		}
		d = hookDecision{Behavior: decisionDeny, Message: msg}
	default:
		// "ask", or anything this build does not know: the Mac dialog.
		return nil
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(hookOutput{hookSpecific{HookEventName: "PermissionRequest", Decision: d}}); err != nil {
		return nil
	}
	return buf.Bytes()
}

// runPermissionHook is the subcommand. It swallows everything -- a bad flag,
// a missing token, even a panic -- because its only failure mode allowed is
// "Claude Code shows its normal dialog".
func runPermissionHook(args []string, stdin io.Reader, stdout io.Writer) {
	defer func() { _ = recover() }()
	fs := flag.NewFlagSet("permission-hook", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	configDir := fs.String("config-dir", "", "")
	_ = fs.Parse(args)
	b, err := os.ReadFile(NewStore(*configDir).hookTokenPath())
	if err != nil {
		return
	}
	out := permissionHookOutput(stdin, "http://127.0.0.1:"+defaultPort, strings.TrimSpace(string(b)), newHookClient())
	if out != nil {
		_, _ = stdout.Write(out)
	}
}

// runInstallClaudeHook is the `install-claude-hook [--remove] [--settings
// PATH]` subcommand: the manual path to what the phone's toggle does.
func runInstallClaudeHook(args []string) error {
	fs := flag.NewFlagSet("install-claude-hook", flag.ExitOnError)
	remove := fs.Bool("remove", false, "take the hook out instead of adding it")
	settings := fs.String("settings", "", "Claude Code settings file (default ~/.claude/settings.json)")
	if err := fs.Parse(args); err != nil {
		return err
	}
	path := defaultClaudeSettings()
	if *settings != "" {
		path = expandHome(*settings)
	}
	cmd, err := hookCommandLine()
	if err != nil {
		return err
	}
	msg, err := installClaudeHook(path, *remove, cmd)
	if err != nil {
		return err
	}
	fmt.Println(msg)
	return nil
}

// defaultClaudeSettings is ~/.claude/settings.json, absolute.
func defaultClaudeSettings() string { return expandHome("~/.claude/settings.json") }

// tildePath shows a path under $HOME as ~/..., for replies a phone renders.
func tildePath(p string) string {
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		if rest, ok := strings.CutPrefix(p, home+string(filepath.Separator)); ok {
			return "~/" + rest
		}
	}
	return p
}

// hookCommandLine is the command written into settings.json: the ABSOLUTE
// path of the running binary, symlinks resolved, then the verb. Absolute
// because Claude Code is not promised to run the hook through a shell that
// expands ~, and the running binary because the agent that installs the hook
// is the one that must answer it (under launchd that is
// ~/.local/bin/vitruvian-remote-agent, which install.sh put there).
func hookCommandLine() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("cannot find this binary's path: %w", err)
	}
	if real, err := filepath.EvalSymlinks(exe); err == nil {
		exe = real
	}
	return shellQuote(exe) + " " + hookVerb, nil
}

// shellQuote single-quotes a path only when it needs it, so the common case
// stays readable in settings.json.
func shellQuote(s string) string {
	safe := s != ""
	for _, c := range s {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || strings.ContainsRune("/._-+", c)) {
			safe = false
			break
		}
	}
	if safe {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// isOurHook reports whether a hook command is this agent's: exactly the
// command we would write, or any command naming the binary and ending in the
// verb.
func isOurHook(command, ours string) bool {
	c := strings.TrimSpace(command)
	if c == ours {
		return true
	}
	return strings.Contains(c, hookBinaryName) && strings.HasSuffix(c, hookVerb)
}

// claudeSettingsFile is settings.json read for editing.
type claudeSettingsFile struct {
	path     string // symlinks resolved
	orig     []byte
	existed  bool
	perm     os.FileMode
	settings map[string]any
	hooks    map[string]any
	groups   []any // hooks.PermissionRequest
}

// readClaudeSettings reads and parses settings.json. A missing or empty file
// is {}. Anything that is not a JSON object, or whose "hooks" or
// "hooks.PermissionRequest" has the wrong shape, is an error that says the
// file was left alone -- this code never overwrites what it could not parse.
func readClaudeSettings(path string) (*claudeSettingsFile, error) {
	// Write through a symlink rather than replacing it: dotfile managers
	// keep settings.json as a link into a repo.
	if real, err := filepath.EvalSymlinks(path); err == nil {
		path = real
	}
	f := &claudeSettingsFile{path: path, perm: 0o600, settings: map[string]any{}, hooks: map[string]any{}}
	orig, err := os.ReadFile(path)
	switch {
	case err == nil:
		f.orig, f.existed = orig, true
		if st, err := os.Stat(path); err == nil {
			f.perm = st.Mode().Perm()
		}
	case errors.Is(err, os.ErrNotExist):
	default:
		return nil, fmt.Errorf("cannot read %s; left it untouched: %w", path, err)
	}
	if len(bytes.TrimSpace(orig)) > 0 {
		dec := json.NewDecoder(bytes.NewReader(orig))
		dec.UseNumber()
		if err := dec.Decode(&f.settings); err != nil || f.settings == nil {
			if err == nil {
				err = errors.New("null")
			}
			return nil, fmt.Errorf("%s is not a valid JSON object; left it untouched: %w", path, err)
		}
	}
	if v, ok := f.settings["hooks"]; ok {
		m, ok := v.(map[string]any)
		if !ok {
			return nil, fmt.Errorf(`%s: "hooks" is not an object; left it untouched`, path)
		}
		f.hooks = m
	}
	if v, ok := f.hooks["PermissionRequest"]; ok {
		g, ok := v.([]any)
		if !ok {
			return nil, fmt.Errorf(`%s: "hooks.PermissionRequest" is not an array; left it untouched`, path)
		}
		f.groups = g
	}
	return f, nil
}

// claudeHookInstalled reports whether our PermissionRequest entry is in the
// settings file. This is the feature's on/off state: there is no other.
func claudeHookInstalled(path, ours string) (bool, error) {
	f, err := readClaudeSettings(path)
	if err != nil {
		return false, err
	}
	_, n, _ := withoutOurHook(f.groups, ours)
	return n > 0, nil
}

// installClaudeHook adds our PermissionRequest entry (command ours) to the
// settings file at path, or with remove takes it out, and returns a sentence
// saying what it did. It changes nothing else: the file is decoded into
// map[string]any and re-encoded, so every other key and hook survives --
// though encoding/json sorts object keys, so their ORDER may change. Numbers
// are kept as written (json.Number) and <, >, & are not escaped, so a hook
// command containing `&&` comes back unchanged.
//
// Idempotent both ways: when there is nothing to do, nothing is written. An
// entry of ours with a different command (the binary moved, or an older build
// wrote "~/...") is replaced by the current one. On every write the original
// is copied to <path>.bak first, and the new file replaces it atomically (temp
// file in the same directory, then rename) with the original's permissions,
// 0600 for a new file.
func installClaudeHook(path string, remove bool, ours string) (string, error) {
	f, err := readClaudeSettings(path)
	if err != nil {
		return "", err
	}
	kept, removed, exact := withoutOurHook(f.groups, ours)

	if remove {
		if removed == 0 {
			return "the Vitruvian Remote permission hook is not in " + f.path + "; nothing to remove", nil
		}
		f.setGroups(kept)
		if err := f.write(); err != nil {
			return "", err
		}
		return "removed the Vitruvian Remote permission hook from " + f.path + f.backupNote(), nil
	}

	if removed == 1 && exact {
		return "the Vitruvian Remote permission hook is already in " + f.path + "; nothing to do", nil
	}
	f.setGroups(append(kept, map[string]any{
		"matcher": "",
		"hooks": []any{map[string]any{
			"type":    "command",
			"command": ours,
			"timeout": hookTimeoutSeconds,
		}},
	}))
	if err := f.write(); err != nil {
		return "", err
	}
	verb := "added"
	if removed > 0 {
		verb = "updated"
	}
	return verb + " the Vitruvian Remote permission hook in " + f.path + " (" + ours + ")" + f.backupNote(), nil
}

// setGroups puts PermissionRequest back, dropping it -- and "hooks" -- when
// our entry was all they held, so add-then-remove leaves the file as it was.
func (f *claudeSettingsFile) setGroups(groups []any) {
	if len(groups) == 0 {
		delete(f.hooks, "PermissionRequest")
	} else {
		f.hooks["PermissionRequest"] = groups
	}
	if len(f.hooks) == 0 {
		delete(f.settings, "hooks")
	} else {
		f.settings["hooks"] = f.hooks
	}
}

func (f *claudeSettingsFile) backupNote() string {
	if !f.existed {
		return ""
	}
	return "; the previous file is at " + f.path + ".bak"
}

func (f *claudeSettingsFile) write() error {
	return writeSettings(f.path, f.orig, f.existed, f.perm, f.settings)
}

// withoutOurHook returns the matcher groups with our hook taken out of each,
// dropping a group only if ours was all it held; how many were removed; and
// whether every removed one was exactly the current command. Anything whose
// shape it does not recognise is kept untouched.
func withoutOurHook(groups []any, ours string) ([]any, int, bool) {
	out := make([]any, 0, len(groups))
	removed := 0
	exact := true
	for _, g := range groups {
		gm, ok := g.(map[string]any)
		if !ok {
			out = append(out, g)
			continue
		}
		hs, ok := gm["hooks"].([]any)
		if !ok {
			out = append(out, g)
			continue
		}
		keep := make([]any, 0, len(hs))
		for _, h := range hs {
			if hm, ok := h.(map[string]any); ok {
				if c, _ := hm["command"].(string); isOurHook(c, ours) {
					removed++
					exact = exact && strings.TrimSpace(c) == ours
					continue
				}
			}
			keep = append(keep, h)
		}
		if len(keep) == len(hs) {
			out = append(out, g)
			continue
		}
		if len(keep) == 0 {
			continue
		}
		cp := make(map[string]any, len(gm))
		for k, v := range gm {
			cp[k] = v
		}
		cp["hooks"] = keep
		out = append(out, cp)
	}
	return out, removed, exact
}

// writeSettings backs up the original, then replaces the file atomically.
func writeSettings(path string, orig []byte, existed bool, perm os.FileMode, settings map[string]any) error {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(settings); err != nil {
		return err
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	if existed {
		if err := os.WriteFile(path+".bak", orig, perm); err != nil {
			return fmt.Errorf("backup: %w", err)
		}
	}
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	ok := false
	defer func() {
		if !ok {
			_ = os.Remove(tmpName)
		}
	}()
	if err := tmp.Chmod(perm); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(buf.Bytes()); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		return err
	}
	ok = true
	return nil
}

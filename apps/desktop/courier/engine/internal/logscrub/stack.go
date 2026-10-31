// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package logscrub

import (
	"bufio"
	"bytes"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"sync"
)

const (
	// StderrLogName is the rolling stderr log file inside the engine data directory.
	StderrLogName = "engine-stderr.log"
	// MaxStderrLogBytes is the 256 KB ceiling for the engine's rolling stderr log file.
	MaxStderrLogBytes = 256 * 1024
)

var (
	// macOS or Linux home directory prefix (/Users/<username>/... or /home/<username>/...).
	userHomeRE = regexp.MustCompile(`(?:/Users|/home)/[^/\s:"']+/?`)

	// Go stack trace header: "goroutine 42 [running]:" or "goroutine 1 [chan receive, 2 minutes]:"
	goroutineRE = regexp.MustCompile(`^goroutine \d+ \[[a-zA-Z0-9 ,._-]+\]:$`)

	// Go stack frame call line: "pkg/path.(*Type).Method(0x14000123456, 0x102938475, ...)" or "panic({0x..., 0x...})"
	// Captures the qualified function name before the opening parenthesis of the argument list.
	frameCallRE = regexp.MustCompile(`^((?:created by )?(?:panic|[A-Za-z0-9_./@-]+(?:\.\(\*?[A-Za-z0-9_]+(?:\[[^\]]+\])?\))?(?:\.[A-Za-z0-9_]+(?:\[[^\]]+\])?)+))\([^\n]*\)( in goroutine \d+)?$`)

	// Go stack frame created-by line without parens: "created by pkg/path.Func in goroutine 1"
	createdByRE = regexp.MustCompile(`^created by [A-Za-z0-9_./@-]+(?:\.\(\*?[A-Za-z0-9_]+(?:\[[^\]]+\])?\))?(?:\.[A-Za-z0-9_]+(?:\[[^\]]+\])?)+( in goroutine \d+)?$`)

	// Go stack source location line: "\t/path/to/file.go:123 +0x45" or "\t/path/to/file.go:123"
	frameFileRE = regexp.MustCompile(`^\t(.+\.go:\d+)( \+0x[0-9a-fA-F]+)?$`)
)

func replaceHomePrefix(s, home string) string {
	home = strings.TrimRight(home, "/")
	if home == "" || home == "/" {
		return s
	}
	s = strings.ReplaceAll(s, home+"/", "~/")
	for _, delim := range []string{":", " ", "\"", "'", "\t", "\r", "\n", ")"} {
		s = strings.ReplaceAll(s, home+delim, "~"+delim)
	}
	if strings.HasSuffix(s, home) {
		s = s[:len(s)-len(home)] + "~"
	}
	return s
}

// ScrubPath replaces os.UserHomeDir() (and its resolved realpath) as well as any /Users/<username>
// or /home/<username> prefix with ~, and applies Redact.
func ScrubPath(s string) string {
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		homes := []string{strings.TrimRight(home, "/")}
		if realHome, err := filepath.EvalSymlinks(home); err == nil {
			realHome = strings.TrimRight(realHome, "/")
			if realHome != "" && !slices.Contains(homes, realHome) {
				homes = append(homes, realHome)
			}
		}
		slices.SortFunc(homes, func(a, b string) int { return len(b) - len(a) })
		for _, h := range homes {
			s = replaceHomePrefix(s, h)
		}
	}
	s = userHomeRE.ReplaceAllStringFunc(s, func(m string) string {
		if strings.HasSuffix(m, "/") {
			return "~/"
		}
		return "~"
	})
	return Redact(s)
}

// ScrubStartupError scrubs a startup error message before printing it to stderr,
// ensuring OS usernames, phone numbers, tokens, and IDs never reach stderr or diagnostics.
func ScrubStartupError(prefix string, err error) string {
	if err == nil {
		return ""
	}
	msg := ScrubPath(err.Error())
	if prefix == "" {
		return msg
	}
	return prefix + " " + msg
}

// cleanSourcePath strips local filesystem prefixes from a Go stack frame file:line path,
// keeping module@version/... or repo-relative paths.
func cleanSourcePath(p string) string {
	for _, marker := range []string{"/go/pkg/mod/", "/external/", "github.com/VitruvianSoftware/courier/"} {
		if idx := strings.Index(p, marker); idx >= 0 {
			if marker == "github.com/VitruvianSoftware/courier/" {
				return p[idx:]
			}
			return p[idx+len(marker):]
		}
	}
	if idx := strings.Index(p, "apps/desktop/courier/"); idx >= 0 {
		return "github.com/VitruvianSoftware/courier/" + strings.TrimPrefix(p[idx:], "apps/desktop/courier/")
	}
	return filepath.Base(p)
}

// ScrubExportLine sanitizes a single line from engine stderr for diagnostics export.
// Returns ("", false) if the line is unrecognized or empty and must be dropped.
func ScrubExportLine(raw string) (string, bool) {
	trimmed := strings.TrimRight(raw, "\r\n")
	if strings.TrimSpace(trimmed) == "" {
		return "", false
	}

	// 1. JSON log line -> pass through object() and drop empty "{}" or invalid JSON.
	if strings.HasPrefix(strings.TrimSpace(trimmed), "{") {
		if out, ok := object([]byte(strings.TrimSpace(trimmed))); ok && len(out) > 2 {
			return string(out), true
		}
		return "", false
	}

	// 2. Startup error prefix ("courier-engine: ...") -> scrub paths and IDs.
	if strings.HasPrefix(trimmed, "courier-engine: ") {
		return "courier-engine: " + ScrubPath(strings.TrimPrefix(trimmed, "courier-engine: ")), true
	}

	// 3. Panic / fatal header -> replace payload with [redacted] so panic(userJID) never leaks.
	if strings.HasPrefix(trimmed, "panic: ") {
		return "panic: [redacted]", true
	}
	if strings.HasPrefix(trimmed, "fatal error: ") {
		return "fatal error: [redacted]", true
	}

	// 4. Goroutine header.
	if goroutineRE.MatchString(trimmed) {
		return trimmed, true
	}

	// 5. Stack frame source file line ("\t/path/to/file.go:123 +0x1c4").
	if m := frameFileRE.FindStringSubmatch(trimmed); m != nil {
		return "\t" + cleanSourcePath(m[1]) + m[2], true
	}

	// 6. Stack frame function call line -> strip raw pointer/value arguments to "(...)".
	if m := frameCallRE.FindStringSubmatch(trimmed); m != nil {
		return m[1] + "(...)" + m[2], true
	}
	if createdByRE.MatchString(trimmed) {
		return trimmed, true
	}

	// Everything else (arbitrary third-party stderr text, signal dumps, raw values) is dropped.
	return "", false
}

// ScrubStderrExport reads a raw engine stderr string and returns sanitized lines.
func ScrubStderrExport(dump string) []string {
	var out []string
	sc := bufio.NewScanner(strings.NewReader(dump))
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		if line, ok := ScrubExportLine(sc.Text()); ok {
			out = append(out, line)
		}
	}
	return out
}

// RollingFile is a thread-safe writer that persists the tail of stderr to disk,
// bounding the file size to maxBytes (default 256 KB) and trimming to the last
// maxBytes/2 on a line boundary when rolling over.
type RollingFile struct {
	mu       sync.Mutex
	path     string
	maxBytes int
	buf      []byte
	f        *os.File
}

// OpenRollingFile opens or creates a bounded rolling file at path with mode 0600.
func OpenRollingFile(path string, maxBytes int) (*RollingFile, error) {
	if maxBytes <= 0 {
		maxBytes = MaxStderrLogBytes
	}
	var existing []byte
	rewrote := false
	if b, err := os.ReadFile(path); err == nil {
		if len(b) > maxBytes {
			existing = trimLeadingLine(b, maxBytes/2)
			rewrote = true
		} else {
			existing = b
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR|os.O_APPEND, 0o600)
	if err != nil {
		return nil, err
	}
	_ = f.Chmod(0o600)
	rf := &RollingFile{
		path:     path,
		maxBytes: maxBytes,
		buf:      existing,
		f:        f,
	}
	if rewrote {
		if err := rf.rewriteLocked(); err != nil {
			_ = f.Close()
			return nil, err
		}
	}
	return rf, nil
}

// File returns the underlying open file descriptor so runtime/debug.SetCrashOutput can direct
// unhandled Go runtime panics to the same rolling stderr file (single writer).
func (r *RollingFile) File() *os.File {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.f
}

func trimLeadingLine(b []byte, maxBytes int) []byte {
	if len(b) <= maxBytes {
		return append([]byte(nil), b...)
	}
	b = b[len(b)-maxBytes:]
	if nl := bytes.IndexByte(b, '\n'); nl >= 0 && nl+1 < len(b) {
		b = b[nl+1:]
	}
	return append([]byte(nil), b...)
}

// Write appends p to the open file on ordinary writes, and on rollover above
// maxBytes truncates the file to the last maxBytes/2 on a line boundary.
func (r *RollingFile) Write(p []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if err := r.ensureOpenLocked(); err != nil {
		return 0, err
	}
	r.buf = append(r.buf, p...)
	if len(r.buf) > r.maxBytes {
		target := r.maxBytes / 2
		if len(p) > target && len(p) <= r.maxBytes {
			target = len(p)
		}
		r.buf = trimLeadingLine(r.buf, target)
		if err := r.rewriteLocked(); err != nil {
			return 0, err
		}
		return len(p), nil
	}
	if _, err := r.f.Write(p); err != nil {
		return 0, err
	}
	return len(p), nil
}

func (r *RollingFile) ensureOpenLocked() error {
	if r.f != nil {
		return nil
	}
	f, err := os.OpenFile(r.path, os.O_CREATE|os.O_RDWR|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	_ = f.Chmod(0o600)
	r.f = f
	return nil
}

func (r *RollingFile) rewriteLocked() error {
	if err := r.f.Truncate(0); err != nil {
		return err
	}
	if _, err := r.f.Seek(0, io.SeekStart); err != nil {
		return err
	}
	_, err := r.f.Write(r.buf)
	return err
}

// Close closes the underlying file handle.
func (r *RollingFile) Close() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.f == nil {
		return nil
	}
	err := r.f.Close()
	r.f = nil
	return err
}

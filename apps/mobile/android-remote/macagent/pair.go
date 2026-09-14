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
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Pairing exists to answer one question: does the thing making this request
// have physical access to this Mac?
//
// The phone shows a six-digit code. A person reads it off the screen and
// types it into a terminal on the Mac. That is the whole proof -- it is not
// a secret, it does not need to be strong, and it is deliberately awkward,
// because anything easier would also be easy for something that merely
// reached the port. What it buys is a 64-hex-character token, and THAT is
// the credential every act endpoint checks.
//
// The failure this design takes seriously is a race: something on the
// tailnet that can see the port and is guessing codes. Two things bound it.
// The window is five minutes, and five wrong guesses delete the pair file --
// so an attacker gets five tries in a window a person opened deliberately,
// against a million codes.

const (
	// pairTTL is how long a code stays good. Long enough to walk to the Mac,
	// short enough that a file left behind is not a standing invitation.
	pairTTL = 5 * time.Minute
	// maxPairAttempts is how many wrong codes it takes to burn the pairing.
	maxPairAttempts = 5
	// tokenBytes is 32 -> 64 hex characters.
	tokenBytes = 32
)

// pairing is the on-disk pair.json.
type pairing struct {
	Code     string    `json:"code"`
	Expires  time.Time `json:"expires"`
	Attempts int       `json:"attempts"`
}

// Store owns the agent's config directory: the token, the pending pairing,
// and the marker that says a phone has ever completed one.
//
// Every method re-reads the files rather than caching them. That is what
// lets `vitruvian-remote-agent pair 482917` in a terminal affect a server
// that is already running, with no restart and no signal.
type Store struct{ dir string }

// defaultConfigDir is ~/.config/vitruvian-remote-agent. Not the macOS
// ~/Library/Application Support, because this is a developer tool that a
// person will want to cat, and everything else in this repo that keeps
// per-user state keeps it under ~/.config.
func defaultConfigDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ".vitruvian-remote-agent"
	}
	return filepath.Join(home, ".config", "vitruvian-remote-agent")
}

func NewStore(dir string) *Store {
	if dir == "" {
		dir = defaultConfigDir()
	}
	return &Store{dir: dir}
}

func (s *Store) tokenPath() string  { return filepath.Join(s.dir, "token") }
func (s *Store) pairPath() string   { return filepath.Join(s.dir, "pair.json") }
func (s *Store) pairedPath() string { return filepath.Join(s.dir, "paired") }

// EnsureToken returns the agent's token, creating it on first start.
//
// 0600 on the file and 0700 on the directory: on a shared Mac every other
// user account can read a world-readable file, and this one is the whole
// authorisation to run commands as this user.
func (s *Store) EnsureToken() (string, error) {
	if err := os.MkdirAll(s.dir, 0o700); err != nil {
		return "", err
	}
	b, err := os.ReadFile(s.tokenPath())
	if err == nil {
		if tok := strings.TrimSpace(string(b)); tok != "" {
			return tok, nil
		}
		// An empty or whitespace-only file is a half-finished write from a
		// previous run, not a token. Replace it rather than serving it --
		// an empty token would compare equal to an empty header.
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	return s.RotateToken()
}

// RotateToken writes a new token, which invalidates every phone that holds
// the old one. That is the un-pair: there is no per-device record to revoke.
func (s *Store) RotateToken() (string, error) {
	if err := os.MkdirAll(s.dir, 0o700); err != nil {
		return "", err
	}
	raw := make([]byte, tokenBytes)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	tok := hex.EncodeToString(raw)
	if err := os.WriteFile(s.tokenPath(), []byte(tok+"\n"), 0o600); err != nil {
		return "", err
	}
	// Every previously paired phone is now holding a dead token, so the
	// agent is no longer paired with anything.
	_ = os.Remove(s.pairedPath())
	_ = os.Remove(s.pairPath())
	return tok, nil
}

// Token reads the token without creating one.
func (s *Store) Token() (string, error) {
	b, err := os.ReadFile(s.tokenPath())
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

// Paired reports whether any phone has ever completed a pairing against the
// current token. It is what /healthz shows, so a person looking at the agent
// can tell "nobody has paired yet" from "a phone lost its token".
func (s *Store) Paired() bool {
	_, err := os.Stat(s.pairedPath())
	return err == nil
}

// WritePairing opens the pairing window. Called by the `pair` subcommand,
// never by an HTTP handler: opening it requires a terminal on this Mac.
func (s *Store) WritePairing(code string) error {
	if err := ValidateCode(code); err != nil {
		return err
	}
	if err := os.MkdirAll(s.dir, 0o700); err != nil {
		return err
	}
	p := pairing{Code: code, Expires: time.Now().Add(pairTTL).UTC()}
	b, err := json.MarshalIndent(p, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.pairPath(), append(b, '\n'), 0o600)
}

// ValidateCode rejects anything that is not six digits, so a typo becomes an
// error at the terminal rather than a pairing nobody can complete.
func ValidateCode(code string) error {
	if len(code) != 6 {
		return fmt.Errorf("pairing code must be six digits, got %q", code)
	}
	for _, r := range code {
		if r < '0' || r > '9' {
			return fmt.Errorf("pairing code must be six digits, got %q", code)
		}
	}
	return nil
}

// Errors POST /v1/pair distinguishes. All three are a 403 to the caller --
// telling a guesser which of "wrong", "expired" and "never started" it hit
// is telling it where to spend its next four attempts -- but the agent log
// gets the real reason.
var (
	errNoPairing   = errors.New("no pairing in progress")
	errPairExpired = errors.New("pairing code expired")
	errPairWrong   = errors.New("wrong pairing code")
)

// ClaimPairing is the whole of POST /v1/pair's logic.
//
// One-shot on success: the pair file is deleted, so a second phone that
// learned the code cannot use it after the first. Counting on failure: the
// fifth wrong guess deletes it too.
func (s *Store) ClaimPairing(code string) (string, error) {
	b, err := os.ReadFile(s.pairPath())
	if errors.Is(err, os.ErrNotExist) {
		return "", errNoPairing
	} else if err != nil {
		return "", err
	}
	var p pairing
	if err := json.Unmarshal(b, &p); err != nil {
		// An unreadable pair file is not a pairing. Remove it rather than
		// leaving something that fails forever with no way to notice.
		_ = os.Remove(s.pairPath())
		return "", errNoPairing
	}
	if time.Now().After(p.Expires) {
		_ = os.Remove(s.pairPath())
		return "", errPairExpired
	}
	// Constant-time even here. The code is short-lived and low-entropy, but
	// a length-and-prefix leak on a six-digit secret is worth more to a
	// guesser than it would be on a 64-character one.
	if subtle.ConstantTimeCompare([]byte(p.Code), []byte(code)) != 1 {
		p.Attempts++
		if p.Attempts >= maxPairAttempts {
			_ = os.Remove(s.pairPath())
			return "", fmt.Errorf("%w (%d attempts; pairing cancelled)", errPairWrong, p.Attempts)
		}
		if nb, err := json.MarshalIndent(p, "", "  "); err == nil {
			_ = os.WriteFile(s.pairPath(), append(nb, '\n'), 0o600)
		}
		return "", fmt.Errorf("%w (%d of %d)", errPairWrong, p.Attempts, maxPairAttempts)
	}
	tok, err := s.EnsureToken()
	if err != nil {
		return "", err
	}
	// Success is one-shot: the window closes with the first phone through it.
	_ = os.Remove(s.pairPath())
	if err := os.WriteFile(s.pairedPath(), []byte(time.Now().UTC().Format(time.RFC3339)+"\n"), 0o600); err != nil {
		return "", err
	}
	return tok, nil
}

// Authorized compares a request's bearer token to the agent's, in constant
// time. A byte-by-byte comparison that returns early leaks the token one
// character at a time to anything that can measure the reply.
func (s *Store) Authorized(presented string) bool {
	tok, err := s.Token()
	if err != nil || tok == "" || presented == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(tok), []byte(presented)) == 1
}

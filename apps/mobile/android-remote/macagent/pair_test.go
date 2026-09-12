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
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Pairing is the only thing standing between the tailnet and a shell on this
// Mac, so these pin the bounds rather than the happy path alone: the window
// closes on success, and it closes on the fifth wrong guess.

func TestTokenIsCreatedOnceAt0600(t *testing.T) {
	store := NewStore(t.TempDir())
	tok, err := store.EnsureToken()
	if err != nil {
		t.Fatal(err)
	}
	if len(tok) != 64 {
		t.Errorf("want 64 hex characters, got %d: %q", len(tok), tok)
	}
	// Stable across calls: a token regenerated on every read would un-pair
	// every phone on every restart.
	again, err := store.EnsureToken()
	if err != nil || again != tok {
		t.Errorf("EnsureToken is not idempotent: %q then %q", tok, again)
	}
	fi, err := os.Stat(filepath.Join(store.dir, "token"))
	if err != nil {
		t.Fatal(err)
	}
	// On a shared Mac every other account can read a world-readable file,
	// and this one is the whole authorisation to run commands as this user.
	if perm := fi.Mode().Perm(); perm != 0o600 {
		t.Errorf("token mode is %o, want 600", perm)
	}

	rotated, err := store.RotateToken()
	if err != nil {
		t.Fatal(err)
	}
	if rotated == tok {
		t.Error("rotate produced the same token")
	}
	if store.Authorized(tok) {
		t.Error("the old token still authorises after a rotate")
	}
	if !store.Authorized(rotated) {
		t.Error("the new token does not authorise")
	}
}

func TestPairingIsOneShot(t *testing.T) {
	store := NewStore(t.TempDir())
	if err := store.WritePairing("482917"); err != nil {
		t.Fatal(err)
	}
	if store.Paired() {
		t.Error("an open window is not a completed pairing")
	}
	tok, err := store.ClaimPairing("482917")
	if err != nil {
		t.Fatal(err)
	}
	if len(tok) != 64 {
		t.Errorf("token: %q", tok)
	}
	if !store.Paired() {
		t.Error("a successful claim must be recorded")
	}
	// A second phone that overheard the code gets nothing: success deletes
	// the window.
	if _, err := store.ClaimPairing("482917"); err == nil {
		t.Error("the same code paired twice")
	}
}

func TestFiveWrongCodesBurnThePairing(t *testing.T) {
	store := NewStore(t.TempDir())
	if err := store.WritePairing("482917"); err != nil {
		t.Fatal(err)
	}
	for i := 1; i <= maxPairAttempts; i++ {
		if _, err := store.ClaimPairing("000000"); err == nil {
			t.Fatalf("attempt %d: a wrong code succeeded", i)
		}
	}
	if _, err := os.Stat(store.pairPath()); !os.IsNotExist(err) {
		t.Error("pair.json survived five wrong codes")
	}
	// And the right code no longer works either -- the window is gone, not
	// merely locked.
	if _, err := store.ClaimPairing("482917"); err == nil {
		t.Error("the correct code worked after the pairing was burnt")
	}
}

func TestExpiredPairingIsRefusedAndCleanedUp(t *testing.T) {
	store := NewStore(t.TempDir())
	if err := os.MkdirAll(store.dir, 0o700); err != nil {
		t.Fatal(err)
	}
	stale := `{"code":"482917","expires":"` + time.Now().Add(-time.Minute).UTC().Format(time.RFC3339) + `","attempts":0}`
	if err := os.WriteFile(store.pairPath(), []byte(stale), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := store.ClaimPairing("482917"); err == nil {
		t.Fatal("an expired code was accepted")
	}
	if _, err := os.Stat(store.pairPath()); !os.IsNotExist(err) {
		t.Error("an expired pair.json was left behind as a standing invitation")
	}
}

func TestValidateCodeRejectsAnythingButSixDigits(t *testing.T) {
	for _, bad := range []string{"", "12345", "1234567", "48291a", "48-917", " 82917"} {
		if err := ValidateCode(bad); err == nil {
			t.Errorf("%q was accepted as a pairing code", bad)
		}
	}
	if err := ValidateCode("482917"); err != nil {
		t.Errorf("482917: %v", err)
	}
}

// TestPairOverHTTP walks the sequence the phone actually performs, including
// the part that matters most: every refusal looks the same from outside.
func TestPairOverHTTP(t *testing.T) {
	_, store, srv := newTestAgent(t)

	post := func(body string) (int, map[string]string) {
		resp, err := http.Post(srv.URL+"/v1/pair", "application/json", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		var out map[string]string
		_ = json.NewDecoder(resp.Body).Decode(&out)
		return resp.StatusCode, out
	}

	// Polling before anyone has run `pair` on the Mac.
	code, body := post(`{"code":"482917"}`)
	if code != http.StatusForbidden {
		t.Errorf("no pairing in progress: got %d, want 403", code)
	}
	// The reply must not say WHICH of "wrong", "expired" and "never started"
	// it was: that tells a guesser where to spend its four remaining tries.
	if strings.Contains(strings.ToLower(body["error"]), "expired") ||
		strings.Contains(strings.ToLower(body["error"]), "wrong") {
		t.Errorf("the refusal leaks the reason: %q", body["error"])
	}

	if err := store.WritePairing("482917"); err != nil {
		t.Fatal(err)
	}
	if code, body := post(`{"code":"482917"}`); code != http.StatusOK || len(body["token"]) != 64 {
		t.Fatalf("pairing: got %d %v", code, body)
	}

	// The token that came back is the one the act endpoints accept.
	tok, err := store.Token()
	if err != nil {
		t.Fatal(err)
	}
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/power", strings.NewReader(`{"action":"launch-missiles"}`))
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	// Authorised, and still refused: the token buys the two documented
	// actions, not an arbitrary one. 400, not 403 -- the caller is paired.
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("unknown power action: got %d, want 400", resp.StatusCode)
	}
}

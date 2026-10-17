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
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPlanDigestIgnoresOrderButNotContent(t *testing.T) {
	a := []invocation{
		{Lane: "build-test", Targets: []string{"//a:t", "//b:t"}},
		{Lane: "unit:x", Targets: []string{"//x:t"}},
	}
	b := []invocation{
		{Lane: "unit:x", Targets: []string{"//x:t"}},
		{Lane: "build-test", Targets: []string{"//b:t", "//a:t"}},
		{Lane: "build-test", Targets: []string{"//a:t"}}, // a re-run of the same target
	}
	if planDigest(a) != planDigest(b) {
		t.Fatal("the same work in another order must give the same digest")
	}
	c := []invocation{{Lane: "build-test", Targets: []string{"//a:t"}}, {Lane: "unit:x", Targets: []string{"//x:t"}}}
	if planDigest(a) == planDigest(c) {
		t.Fatal("dropping a target must change the digest")
	}
	d := []invocation{{Lane: "unit:y", Targets: []string{"//a:t", "//b:t"}}, {Lane: "unit:x", Targets: []string{"//x:t"}}}
	if planDigest(a) == planDigest(d) {
		t.Fatal("the same target in another lane must change the digest")
	}
}

func TestRecordDescriptionFitsGitHubLimit(t *testing.T) {
	r := newRecord(strings.Repeat("a", 40), strings.Repeat("b", 40), strings.Repeat("c", 40),
		[]invocation{{Lane: "build-test", URL: "u1"}, {Lane: "unit:x", URL: "u2"}})
	d := r.description()
	if len(d) > 140 {
		t.Fatalf("description is %d chars: %s", len(d), d)
	}
	if !strings.Contains(d, "tree="+strings.Repeat("b", 40)) {
		t.Fatalf("the full tree hash must be in the record: %s", d)
	}
	if r.TargetURL != "https://app.buildbuddy.io/history/commit/"+strings.Repeat("a", 40) {
		t.Fatalf("two runs should link the commit's page, got %s", r.TargetURL)
	}
	one := newRecord("h", "t", "b", []invocation{{URL: "u1"}, {URL: "u1"}})
	if one.TargetURL != "u1" {
		t.Fatalf("one run should link that run, got %s", one.TargetURL)
	}
}

// The committed recorder is scout. (Against the real registry it is checked
// on every run; here against a copy of scout's row.)
func TestCommittedRecorderIsScout(t *testing.T) {
	_, ap, _ := writeFiles(t, "")
	cfg, err := loadRecorder("recorder.tsv", ap)
	if err != nil {
		t.Fatal(err)
	}
	want := recorderConfig{Agent: "scout", AppID: "4521103", InstallationID: "152054588", BotUserID: "314429511"}
	if cfg != want {
		t.Fatalf("got %+v want %+v", cfg, want)
	}
}

const testAgents = "# agent\tapp\tinst\tbot\nscout\t4521103\t152054588\t314429511\nwren\t4521094\t152054411\t314429222\n"

func writeFiles(t *testing.T, recorder string) (recorderPath, agentsPath, keyDir string) {
	t.Helper()
	dir := t.TempDir()
	recorderPath, agentsPath, keyDir = filepath.Join(dir, "recorder.tsv"), filepath.Join(dir, "agents.tsv"), filepath.Join(dir, "keys")
	for p, c := range map[string]string{recorderPath: recorder, agentsPath: testAgents} {
		if err := os.WriteFile(p, []byte(c), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Mkdir(keyDir, 0o700); err != nil {
		t.Fatal(err)
	}
	return recorderPath, agentsPath, keyDir
}

func TestLoadRecorderRefusals(t *testing.T) {
	for name, c := range map[string]struct{ content, want string }{
		"names nobody":           {"# only comments\n", "names no recorder"},
		"two recorders":          {"scout\t314429511\nwren\t314429222\n", "exactly one"},
		"missing bot id":         {"scout\n", "one line"},
		"bot id not a number":    {"scout\tabc\n", "one line"},
		"bot id disagrees":       {"scout\t1\n", "agents.tsv says 314429511"},
		"not a registered agent": {"ghost\t314429511\n", "not in tools/agent-app/agents.tsv"},
	} {
		t.Run(name, func(t *testing.T) {
			rp, ap, _ := writeFiles(t, c.content)
			_, err := loadRecorder(rp, ap)
			if err == nil || !strings.Contains(err.Error(), c.want) {
				t.Fatalf("want refusal containing %q, got %v", c.want, err)
			}
		})
	}
}

func TestRecordRefusesWithoutTheKey(t *testing.T) {
	rp, ap, keyDir := writeFiles(t, "scout\t314429511\n")
	minted := false
	s := statusRecorder{configPath: rp, agentsPath: ap, keyDir: keyDir, mint: func(context.Context, recorderConfig, string) (string, error) {
		minted = true
		return "tok", nil
	}}
	err := s.record(context.Background(), record{Head: "h"})
	if err == nil || !strings.Contains(err.Error(), "private key is not at "+filepath.Join(keyDir, "scout.pem")) {
		t.Fatalf("got %v", err)
	}
	if minted {
		t.Fatal("must not try for a token without the key")
	}
}

func recorderAgainst(t *testing.T, h http.HandlerFunc) (statusRecorder, *recorderConfig) {
	t.Helper()
	rp, ap, keyDir := writeFiles(t, "scout\t314429511\n")
	if err := os.WriteFile(filepath.Join(keyDir, "scout.pem"), []byte("fake"), 0o600); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	var mintedWith recorderConfig
	return statusRecorder{
		configPath: rp, agentsPath: ap, keyDir: keyDir, apiBase: srv.URL,
		mint: func(_ context.Context, cfg recorderConfig, key string) (string, error) {
			mintedWith = cfg
			if key != filepath.Join(keyDir, "scout.pem") {
				t.Errorf("minted with key %s", key)
			}
			return "recorder-token", nil
		},
	}, &mintedWith
}

func TestRecordPostsTheStatusWithTheRecorderTokenOnly(t *testing.T) {
	t.Setenv("GH_TOKEN", "someone-elses-token")
	t.Setenv("GITHUB_TOKEN", "someone-elses-token")
	var gotPath, gotAuth string
	var gotBody map[string]string
	s, minted := recorderAgainst(t, func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotAuth = r.URL.Path, r.Header.Get("Authorization")
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"state":"success","creator":{"login":"vitruvian-scout-agent[bot]","id":314429511}}`))
	})
	r := record{Head: strings.Repeat("a", 40), Tree: strings.Repeat("b", 40), Base: strings.Repeat("c", 40), Plan: strings.Repeat("d", 64), TargetURL: "https://app.buildbuddy.io/invocation/x"}
	if err := s.record(context.Background(), r); err != nil {
		t.Fatal(err)
	}
	if minted.AppID != "4521103" || minted.InstallationID != "152054588" {
		t.Fatalf("minted with %+v", *minted)
	}
	if gotPath != "/repos/VitruvianSoftware/vitruvian-core/statuses/"+r.Head {
		t.Fatalf("path %s", gotPath)
	}
	if gotAuth != "Bearer recorder-token" {
		t.Fatalf("authorization %q: only the recorder's token may be used", gotAuth)
	}
	want := map[string]string{"state": "success", "context": "verified-run", "description": r.description(), "target_url": r.TargetURL}
	for k, v := range want {
		if gotBody[k] != v {
			t.Errorf("%s = %q, want %q", k, gotBody[k], v)
		}
	}
}

func TestRecordDistrustsAStatusSetBySomeoneElse(t *testing.T) {
	s, _ := recorderAgainst(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"creator":{"login":"ipv1337","id":42}}`))
	})
	err := s.record(context.Background(), record{Head: "h"})
	if err == nil || !strings.Contains(err.Error(), "Do not trust it") {
		t.Fatalf("got %v", err)
	}
}

func TestRecordReportsGitHubRefusal(t *testing.T) {
	s, _ := recorderAgainst(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_, _ = w.Write([]byte(`{"message":"No commit found for SHA"}`))
	})
	err := s.record(context.Background(), record{Head: "h"})
	if err == nil || !strings.Contains(err.Error(), "422") || !strings.Contains(err.Error(), "pushed") {
		t.Fatalf("got %v", err)
	}
}

func TestWithoutGitHubTokens(t *testing.T) {
	got := withoutGitHubTokens([]string{"GH_TOKEN=a", "GITHUB_TOKEN=b", "PATH=/bin", "GH_TOKENISH=c"})
	if strings.Join(got, " ") != "PATH=/bin GH_TOKENISH=c" {
		t.Fatalf("got %q", got)
	}
}

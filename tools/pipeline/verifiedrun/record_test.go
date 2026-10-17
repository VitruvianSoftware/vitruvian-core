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

// The committed recorder.tsv has no App in it today; recording must refuse,
// and say what is missing, rather than reach for any other credential.
func TestCommittedRecorderFileRefusesUntilAnAppExists(t *testing.T) {
	_, err := loadRecorder("recorder.tsv")
	if err != errNoRecorder {
		t.Fatalf("want errNoRecorder, got %v", err)
	}
	for _, want := range []string{"no recorder identity", "Commit statuses: write", "no agent app", recorderFile, recorderKey} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal should mention %q:\n%s", want, err)
		}
	}
}

func TestLoadRecorderRejectsMalformedRows(t *testing.T) {
	dir := t.TempDir()
	for name, content := range map[string]string{
		"two apps":   "1\t2\t3\n4\t5\t6\n",
		"two fields": "1\t2\n",
		"not ids":    "app\tinst\tbot\n",
	} {
		p := filepath.Join(dir, strings.ReplaceAll(name, " ", "_"))
		if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := loadRecorder(p); err == nil || err == errNoRecorder {
			t.Errorf("%s: want a refusal, got %v", name, err)
		}
	}
	p := filepath.Join(dir, "good")
	if err := os.WriteFile(p, []byte("# comment\n123\t456\t789\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := loadRecorder(p)
	if err != nil || cfg != (recorderConfig{"123", "456", "789"}) {
		t.Fatalf("got %+v %v", cfg, err)
	}
}

func writeRecorder(t *testing.T) (cfgPath, keyDir string) {
	t.Helper()
	dir := t.TempDir()
	cfgPath = filepath.Join(dir, "recorder.tsv")
	if err := os.WriteFile(cfgPath, []byte("123\t456\t789\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	keyDir = filepath.Join(dir, "keys")
	if err := os.Mkdir(keyDir, 0o700); err != nil {
		t.Fatal(err)
	}
	return cfgPath, keyDir
}

func TestRecordRefusesWithoutTheKey(t *testing.T) {
	cfgPath, keyDir := writeRecorder(t)
	minted := false
	s := statusRecorder{configPath: cfgPath, keyDir: keyDir, mint: func(context.Context, recorderConfig, string) (string, error) {
		minted = true
		return "tok", nil
	}}
	err := s.record(context.Background(), record{Head: "h"})
	if err == nil || !strings.Contains(err.Error(), "private key is not at "+filepath.Join(keyDir, recorderKey)) {
		t.Fatalf("got %v", err)
	}
	if minted {
		t.Fatal("must not try for a token without the key")
	}
}

func TestRecordPostsTheStatusWithTheRecorderTokenOnly(t *testing.T) {
	t.Setenv("GH_TOKEN", "the-pr-authors-token")
	t.Setenv("GITHUB_TOKEN", "the-pr-authors-token")
	cfgPath, keyDir := writeRecorder(t)
	if err := os.WriteFile(filepath.Join(keyDir, recorderKey), []byte("fake"), 0o600); err != nil {
		t.Fatal(err)
	}
	var gotPath, gotAuth string
	var gotBody map[string]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotAuth = r.URL.Path, r.Header.Get("Authorization")
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		w.WriteHeader(http.StatusCreated)
	}))
	defer srv.Close()

	var mintedWith recorderConfig
	s := statusRecorder{
		configPath: cfgPath, keyDir: keyDir, apiBase: srv.URL,
		mint: func(_ context.Context, cfg recorderConfig, key string) (string, error) {
			mintedWith = cfg
			return "recorder-token", nil
		},
	}
	r := record{Head: strings.Repeat("a", 40), Tree: strings.Repeat("b", 40), Base: strings.Repeat("c", 40), Plan: strings.Repeat("d", 64), TargetURL: "https://app.buildbuddy.io/invocation/x"}
	if err := s.record(context.Background(), r); err != nil {
		t.Fatal(err)
	}
	if mintedWith.AppID != "123" || mintedWith.InstallationID != "456" {
		t.Fatalf("minted with %+v", mintedWith)
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

func TestRecordReportsGitHubRefusal(t *testing.T) {
	cfgPath, keyDir := writeRecorder(t)
	_ = os.WriteFile(filepath.Join(keyDir, recorderKey), []byte("fake"), 0o600)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_, _ = w.Write([]byte(`{"message":"No commit found for SHA"}`))
	}))
	defer srv.Close()
	s := statusRecorder{
		configPath: cfgPath, keyDir: keyDir, apiBase: srv.URL,
		mint: func(context.Context, recorderConfig, string) (string, error) { return "t", nil },
	}
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

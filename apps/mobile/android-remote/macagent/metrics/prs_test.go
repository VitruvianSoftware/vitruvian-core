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
	"os"
	"testing"
)

// testdata/gh-pr-view.json and testdata/gh-search-prs.json were captured from
// the public repo on 2026-09-07:
//
//	gh pr view 2226 --repo VitruvianSoftware/vitruvian-core --json isDraft,\
//	  headRefName,baseRefName,mergeStateStatus,reviewDecision,\
//	  statusCheckRollup,autoMergeRequest,author
//	gh search prs --author @me --state open \
//	  --json number,repository,title,url,updatedAt --limit 20
//
// Nothing is scrubbed: both are public data, and a fixture that had been
// edited would stop pinning the real shape, which is the only reason to keep
// one.

func TestParseGhPrViewOnARealPR(t *testing.T) {
	b, err := os.ReadFile("testdata/gh-pr-view.json")
	if err != nil {
		t.Fatal(err)
	}
	pr, err := ParseGhPrView(string(b))
	if err != nil {
		t.Fatal(err)
	}
	if pr.HeadRef != "claude/remote-polish" || pr.BaseRef != "main" {
		t.Errorf("refs: %+v", pr)
	}
	if pr.Author != "ipv1337" {
		t.Errorf("author = %q", pr.Author)
	}
	if pr.MergeState != "CLEAN" || pr.IsDraft {
		t.Errorf("merge state / draft: %+v", pr)
	}
	// autoMergeRequest is JSON null on this PR. Decoded into a value type it
	// would be indistinguishable from an empty object and auto_merge would
	// read true for every PR in the list.
	if pr.AutoMerge {
		t.Error("auto_merge must be false when autoMergeRequest is null")
	}
	// The real rollup: 45 checks, 26 green and 19 skipped, none failed and
	// none pending. Skipped is its own bucket because a phone that folded it
	// into "failure" would call a clean PR red on every run.
	want := Checks{Success: 26, Skipped: 19}
	if pr.Checks != want {
		t.Errorf("checks = %+v, want %+v", pr.Checks, want)
	}
}

func TestParseGhPrViewBucketsEveryConclusion(t *testing.T) {
	// A synthetic rollup with one of each shape gh can emit: a CheckRun with
	// a conclusion, a CheckRun still running (no conclusion, a status), and a
	// StatusContext, which is the older commit-status API and carries only
	// `state`. Several bots still post those.
	const raw = `{"isDraft":true,"headRefName":"wip","baseRefName":"main","mergeStateStatus":"BLOCKED",
	  "reviewDecision":"CHANGES_REQUESTED","author":{"login":"someone"},"autoMergeRequest":{"enabledAt":"x"},
	  "statusCheckRollup":[
	    {"__typename":"CheckRun","conclusion":"SUCCESS","status":"COMPLETED"},
	    {"__typename":"CheckRun","conclusion":"FAILURE","status":"COMPLETED"},
	    {"__typename":"CheckRun","conclusion":"TIMED_OUT","status":"COMPLETED"},
	    {"__typename":"CheckRun","conclusion":"","status":"IN_PROGRESS"},
	    {"__typename":"CheckRun","conclusion":"","status":"QUEUED"},
	    {"__typename":"CheckRun","conclusion":"SKIPPED","status":"COMPLETED"},
	    {"__typename":"StatusContext","state":"PENDING"},
	    {"__typename":"StatusContext","state":"SUCCESS"},
	    {"__typename":"CheckRun","conclusion":"WHAT_IS_THIS","status":"COMPLETED"}
	  ]}`
	pr, err := ParseGhPrView(raw)
	if err != nil {
		t.Fatal(err)
	}
	// TIMED_OUT and the unknown conclusion both count as failure: a check
	// nobody can classify is not one to paint green.
	want := Checks{Success: 2, Failure: 3, Pending: 3, Skipped: 1}
	if pr.Checks != want {
		t.Errorf("checks = %+v, want %+v", pr.Checks, want)
	}
	if !pr.AutoMerge || !pr.IsDraft || pr.ReviewDecision != "CHANGES_REQUESTED" {
		t.Errorf("flags: %+v", pr)
	}
}

func TestParseGhSearchPrs(t *testing.T) {
	b, err := os.ReadFile("testdata/gh-search-prs.json")
	if err != nil {
		t.Fatal(err)
	}
	refs, err := ParseGhSearchPrs(string(b))
	if err != nil {
		t.Fatal(err)
	}
	if len(refs) == 0 {
		t.Fatal("no PRs parsed from the fixture")
	}
	if refs[0].Repo != "VitruvianSoftware/vitruvian-core" || refs[0].Number != 2226 {
		t.Errorf("first row: %+v", refs[0])
	}
	// nameWithOwner, not name: `gh pr view --repo vitruvian-core` cannot
	// find a repo without its owner, so the wrong field here is a 404 later.
	if refs[0].UpdatedAt.IsZero() {
		t.Error("updatedAt did not parse")
	}
	// An empty search is zero PRs, not an error: nothing open is a normal
	// morning.
	if r, err := ParseGhSearchPrs("[]"); err != nil || len(r) != 0 {
		t.Errorf("empty search: %v %v", r, err)
	}
	// gh not logged in prints a message on stderr and nothing on stdout;
	// an empty stdout must be an error rather than "you have no PRs".
	if _, err := ParseGhSearchPrs(""); err == nil {
		t.Error("empty stdout must be an error, not zero PRs")
	}
}

func TestPRChecksVerdictWaitsForPending(t *testing.T) {
	// A run still going is not a result: notifying "green" before the last
	// check reports is the notification that teaches someone to ignore them.
	if v := PRChecksVerdict(Checks{Success: 20, Pending: 1}); v != "" {
		t.Errorf("pending: %q", v)
	}
	if v := PRChecksVerdict(Checks{Success: 20, Failure: 1}); v != "red" {
		t.Errorf("failure: %q", v)
	}
	if v := PRChecksVerdict(Checks{Success: 20, Skipped: 4}); v != "green" {
		t.Errorf("green: %q", v)
	}
	// No checks at all is neither: a PR whose workflows have not started is
	// not green.
	if v := PRChecksVerdict(Checks{}); v != "" {
		t.Errorf("no checks: %q", v)
	}
}

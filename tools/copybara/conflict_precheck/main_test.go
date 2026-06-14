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
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// ---------------------------------------------------------------------------
// helpers: spin up a real git repo in a temp dir
// ---------------------------------------------------------------------------

func gitCmd(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v in %s: %v\n%s", args, dir, err, out)
	}
	return strings.TrimSpace(string(out))
}

// initRepo initialises a bare-minimum git repo with an initial commit.
func initRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	gitCmd(t, dir, "init")
	gitCmd(t, dir, "config", "user.email", "test@example.com")
	gitCmd(t, dir, "config", "user.name", "Test")
	// Write an initial file and commit so HEAD exists.
	if err := os.WriteFile(filepath.Join(dir, "README.md"), []byte("init\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitCmd(t, dir, "add", ".")
	gitCmd(t, dir, "commit", "-m", "init")
	return dir
}

// addCommit writes a file with given content and commits with the message.
func addCommit(t *testing.T, dir, filename, content, msg string) string {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(filepath.Join(dir, filename)), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, filename), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	gitCmd(t, dir, "add", filename)
	gitCmd(t, dir, "commit", "-m", msg)
	return gitCmd(t, dir, "rev-parse", "HEAD")
}

// ---------------------------------------------------------------------------
// unit tests for importLabel
// ---------------------------------------------------------------------------

func TestImportLabel(t *testing.T) {
	tests := []struct {
		component string
		want      string
	}{
		{"mcp-slack", "MCP_SLACK_REV_ID"},
		{"devx", "DEVX_REV_ID"},
		{"nexus-agent", "NEXUS_AGENT_REV_ID"},
		{"homelab", "HOMELAB_REV_ID"},
	}
	for _, tc := range tests {
		got := importLabel(tc.component)
		if got != tc.want {
			t.Errorf("importLabel(%q) = %q, want %q", tc.component, got, tc.want)
		}
	}
}

// ---------------------------------------------------------------------------
// unit tests for latestRev
// ---------------------------------------------------------------------------

func TestLatestRev_ExtractsSha(t *testing.T) {
	dir := initRepo(t)
	sha := addCommit(t, dir, "a.txt", "hello", "feat: something\n\nMONOREPO_REV_ID: abc1234\n")
	// latestRev should find the 7-char sha.
	got := latestRev(dir, "MONOREPO_REV_ID")
	if got != "abc1234" {
		t.Errorf("latestRev = %q, want abc1234 (commit sha was %s)", got, sha)
	}
}

func TestLatestRev_NoLabel_ReturnsEmpty(t *testing.T) {
	dir := initRepo(t)
	addCommit(t, dir, "b.txt", "world", "plain commit no label")
	got := latestRev(dir, "MONOREPO_REV_ID")
	if got != "" {
		t.Errorf("latestRev = %q, want empty", got)
	}
}

func TestLatestRev_LongerSha(t *testing.T) {
	dir := initRepo(t)
	addCommit(t, dir, "c.txt", "v", "sync\n\nDEVX_REV_ID: deadbeefdeadbeefdeadbeef12345678abcdef01\n")
	got := latestRev(dir, "DEVX_REV_ID")
	if got != "deadbeefdeadbeefdeadbeef12345678abcdef01" {
		t.Errorf("latestRev = %q", got)
	}
}

// ---------------------------------------------------------------------------
// integration tests via run()
// ---------------------------------------------------------------------------

// TestExport_NoBaseline: no IMPORT_LABEL commit in mono → exit 0 (skip).
func TestExport_NoBaseline(t *testing.T) {
	mono := initRepo(t)
	std := initRepo(t)
	// No commits with IMPORT_LABEL in mono.
	code := run([]string{"export", "devx", mono, std})
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (no baseline)", code)
	}
}

// TestImport_NoBaseline: no EXPORT_LABEL commit in standalone → exit 0.
func TestImport_NoBaseline(t *testing.T) {
	mono := initRepo(t)
	std := initRepo(t)
	code := run([]string{"import", "devx", mono, std})
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (no baseline)", code)
	}
}

// TestExport_BaselineNotReachable: baseline sha not in standalone → exit 0 (skip).
func TestExport_BaselineNotReachable(t *testing.T) {
	mono := initRepo(t)
	std := initRepo(t)
	// Stamp an import label in mono pointing to a sha that doesn't exist in std.
	addCommit(t, mono, "x.txt", "v", "import sync\n\nDEVX_REV_ID: deadbeef123\n")
	code := run([]string{"export", "devx", mono, std})
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (baseline not reachable)", code)
	}
}

// TestImport_BaselineNotReachable: export baseline sha not in mono → exit 0.
func TestImport_BaselineNotReachable(t *testing.T) {
	mono := initRepo(t)
	std := initRepo(t)
	addCommit(t, std, "x.txt", "v", "export sync\n\nMONOREPO_REV_ID: deadbeef456\n")
	code := run([]string{"import", "devx", mono, std})
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (baseline not reachable)", code)
	}
}

// TestExport_GenuineStandaloneCommit: standalone has a genuine commit since baseline → exit 1.
func TestExport_GenuineStandaloneCommit(t *testing.T) {
	mono := initRepo(t)
	std := initRepo(t)

	// Seed baseline: commit in std, then stamp its sha in mono as DEVX_REV_ID.
	baseSha := addCommit(t, std, "src.go", "v1", "feat: initial import\n\nMONOREPO_REV_ID: abc0001\n")
	addCommit(t, mono, "z.txt", "v", "import sync\n\nDEVX_REV_ID: "+baseSha+"\n")

	// Now add a genuine commit in std (no EXPORT_LABEL, will be detected).
	addCommit(t, std, "standalone.go", "new feature", "feat: standalone genuine change")

	code := run([]string{"export", "devx", mono, std})
	if code != 1 {
		t.Errorf("exit code = %d, want 1 (genuine standalone pending)", code)
	}
}

// TestExport_OnlySyncedCommits: standalone commit carries EXPORT_LABEL → exit 0.
func TestExport_OnlySyncedCommits(t *testing.T) {
	mono := initRepo(t)
	std := initRepo(t)

	baseSha := addCommit(t, std, "src.go", "v1", "feat: init\n\nMONOREPO_REV_ID: abc0002\n")
	addCommit(t, mono, "z.txt", "v", "import sync\n\nDEVX_REV_ID: "+baseSha+"\n")

	// Commit with EXPORT_LABEL in msg: this is a synced-in commit, not genuine.
	addCommit(t, std, "synced.go", "synced", "sync: from monorepo\n\nMONOREPO_REV_ID: feedbeef\n")

	code := run([]string{"export", "devx", mono, std})
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (only synced commits)", code)
	}
}

// TestImport_GenuineMonorepoCommit: monorepo has genuine change since baseline → exit 1.
func TestImport_GenuineMonorepoCommit(t *testing.T) {
	mono := initRepo(t)
	std := initRepo(t)

	// Seed: create devx/ and export stamp in standalone pointing to a real mono sha.
	addCommit(t, mono, "devx/src.go", "v1", "feat: init")
	baseSha := gitCmd(t, mono, "rev-parse", "HEAD")
	addCommit(t, std, "z.txt", "v", "export sync\n\nMONOREPO_REV_ID: "+baseSha+"\n")

	// Genuine commit in monorepo's devx/ subtree (no IMPORT_LABEL).
	addCommit(t, mono, "devx/new.go", "new feature", "feat: genuine monorepo change")

	code := run([]string{"import", "devx", mono, std})
	if code != 1 {
		t.Errorf("exit code = %d, want 1 (genuine monorepo pending)", code)
	}
}

// TestImport_Clean: monorepo devx/ has no new genuine commits → exit 0.
func TestImport_Clean(t *testing.T) {
	mono := initRepo(t)
	std := initRepo(t)

	addCommit(t, mono, "devx/src.go", "v1", "feat: init\n\nDEVX_REV_ID: 0000001\n")
	baseSha := gitCmd(t, mono, "rev-parse", "HEAD")
	addCommit(t, std, "z.txt", "v", "export sync\n\nMONOREPO_REV_ID: "+baseSha+"\n")

	// No new commits in devx/ after baseline.
	code := run([]string{"import", "devx", mono, std})
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (clean)", code)
	}
}

// TestUnknownDirection → exit 2.
func TestUnknownDirection(t *testing.T) {
	code := run([]string{"sideways", "devx", "/tmp", "/tmp"})
	if code != 2 {
		t.Errorf("exit code = %d, want 2 (unknown direction)", code)
	}
}

// TestExport_StandaloneOnly_Excluded: change is in a standalone-only path → exit 0.
func TestExport_StandaloneOnly_Excluded(t *testing.T) {
	mono := initRepo(t)
	std := initRepo(t)

	baseSha := addCommit(t, std, "src.go", "v1", "feat: init\n\nMONOREPO_REV_ID: abc0003\n")
	addCommit(t, mono, "z.txt", "v", "import sync\n\nDEVX_REV_ID: "+baseSha+"\n")

	// Change is in a standalone-only path — should be excluded.
	addCommit(t, std, ".github/workflows/sync.yaml", "wf: v1", "ci: update dispatch workflow")

	// Pass standalone_only so the workflow file is excluded from scan.
	code := run([]string{"export", "devx", mono, std, ".github/workflows/sync.yaml"})
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (change is standalone-only)", code)
	}
}

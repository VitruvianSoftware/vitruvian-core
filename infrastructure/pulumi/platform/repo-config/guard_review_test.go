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
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// gitignoreMatch is the subset of .gitignore matching the guard patterns use:
// anchored at the repository root (every pattern has a slash), "**" crosses
// directories, "*" and "?" stay inside one path segment.
func gitignoreMatch(pattern, path string) bool {
	var b strings.Builder
	b.WriteString("^")
	for i := 0; i < len(pattern); i++ {
		switch {
		case strings.HasPrefix(pattern[i:], "**"):
			b.WriteString(".*")
			i++
		case pattern[i] == '*':
			b.WriteString("[^/]*")
		case pattern[i] == '?':
			b.WriteString("[^/]")
		default:
			b.WriteString(regexp.QuoteMeta(string(pattern[i])))
		}
	}
	b.WriteString("$")
	return regexp.MustCompile(b.String()).MatchString(path)
}

func guardCovers(path string) bool {
	for _, p := range guardReviewPaths {
		if gitignoreMatch(p, path) {
			return true
		}
	}
	return false
}

// Every file James named, and the files that enforce the requirement, need
// his approval; nothing else does.
func TestGuardReviewPathsCoverage(t *testing.T) {
	protected := []string{
		"tools/agent-guard/policy.json",
		"tools/agent-guard/agent_guard.py",
		"tools/agent-guard/hook.sh",
		"tools/agent-guard/install.py",
		"tools/agent-guard/BUILD",
		"tools/agent-guard/README.md",
		".claude/settings.json",
		".claude/settings.local.json",
		".claude/block-queue-bypass.sh",
		".claude/session-start.sh",
		".agents/hooks.json",
		"tools/cloud-bootstrap/cloud-bootstrap.sh",
		// What that launcher builds and runs at session start.
		"tools/cloud-bootstrap/src/cloud_bootstrap/main.rs",
		"tools/cloud-bootstrap/src/cloud_bootstrap/creds.rs",
		"tools/cloud-bootstrap/profiles.tsv",
		"tools/remote/setup.sh",
		"infrastructure/pulumi/platform/repo-config/guard_review.go",
		"infrastructure/pulumi/platform/repo-config/main.go",
		"infrastructure/pulumi/platform/repo-config/Pulumi.dev.yaml",
	}
	for _, p := range protected {
		if !guardCovers(p) {
			t.Errorf("%s is not covered by guardReviewPaths; changing it must need James's approval", p)
		}
	}

	// Ordinary work stays autonomous.
	free := []string{
		"README.md",
		"tools/agent-app/main.go",
		"tools/agent-guard-other/x.py",
		"tools/cloud-bootstrap/README.md",
		"tools/cloud-bootstrap/BUILD",
		"tools/cloud-bootstrap/cloud-bootstrap_test.sh",
		// The tests beside the launcher's sources, and the other tool there.
		"tools/cloud-bootstrap/src/launcher_test.rs",
		"tools/cloud-bootstrap/src/configure_tailscale/lib.rs",
		"tools/remote/setup_test.sh",
		"apps/cli/devx/main.go",
		".claude/agents/wren.md",
		".agents/agents/wren.md",
		".github/workflows/ci.yaml",
		"infrastructure/pulumi/platform/repo-config/internal/secrets/secrets.go",
		"infrastructure/pulumi/platform/repo-config/guard_review_test.go",
		"infrastructure/pulumi/platform/dev-local/main.go",
	}
	for _, p := range free {
		if guardCovers(p) {
			t.Errorf("%s is covered by guardReviewPaths; only agent-guard's rules and their enforcement should need James", p)
		}
	}
}

// A pattern with no slash (or only a trailing one) matches at ANY depth in
// .gitignore syntax, so "main.go" would protect every main.go in the repo.
func TestGuardReviewPathsAreAnchored(t *testing.T) {
	seen := map[string]bool{}
	for _, p := range guardReviewPaths {
		if !strings.Contains(strings.TrimSuffix(p, "/"), "/") {
			t.Errorf("pattern %q has no slash, so it would match at any depth", p)
		}
		if strings.HasPrefix(p, "/") || strings.HasPrefix(p, "!") {
			t.Errorf("pattern %q: write paths from the repository root, without a leading / or a negation", p)
		}
		if seen[p] {
			t.Errorf("pattern %q is listed twice", p)
		}
		seen[p] = true
	}
}

// The rule needs ONE approval from the team, a new push makes it stale, and it
// asks nothing of pull requests outside the paths (no count, no code owners).
func TestGuardReviewRuleShape(t *testing.T) {
	r := guardReviewPullRequestRule(pulumi.Int(42))

	if got := r.RequiredApprovingReviewCount; got != pulumi.Int(0) {
		t.Errorf("RequiredApprovingReviewCount = %v, want 0: other pull requests must not need an approval", got)
	}
	if got := r.RequireCodeOwnerReview; got != pulumi.Bool(false) {
		t.Errorf("RequireCodeOwnerReview = %v, want false: CODEOWNERS covers most paths", got)
	}
	if got := r.DismissStaleReviewsOnPush; got != pulumi.Bool(true) {
		t.Errorf("DismissStaleReviewsOnPush = %v, want true: an approval must not survive a later push", got)
	}
	if got := r.RequireLastPushApproval; got != pulumi.Bool(false) {
		t.Errorf("RequireLastPushApproval = %v, want false", got)
	}
	methods, ok := r.AllowedMergeMethods.(pulumi.StringArray)
	if !ok || len(methods) != 1 || methods[0] != pulumi.String("squash") {
		t.Errorf("AllowedMergeMethods = %v, want [squash] (main is squash-only)", r.AllowedMergeMethods)
	}

	reviewers, ok := r.RequiredReviewers.(github.RepositoryRulesetRulesPullRequestRequiredReviewerArray)
	if !ok || len(reviewers) != 1 {
		t.Fatalf("RequiredReviewers = %#v, want exactly one entry", r.RequiredReviewers)
	}
	rv, ok := reviewers[0].(*github.RepositoryRulesetRulesPullRequestRequiredReviewerArgs)
	if !ok {
		t.Fatalf("reviewer entry is %T", reviewers[0])
	}
	if rv.MinimumApprovals != pulumi.Int(1) {
		t.Errorf("MinimumApprovals = %v, want 1 (0 would only add the team for visibility)", rv.MinimumApprovals)
	}
	who, ok := rv.Reviewer.(*github.RepositoryRulesetRulesPullRequestRequiredReviewerReviewerArgs)
	if !ok {
		t.Fatalf("reviewer is %T", rv.Reviewer)
	}
	if who.Type != pulumi.String("Team") || who.Id != pulumi.Int(42) {
		t.Errorf("reviewer = {%v %v}, want {Team 42}", who.Type, who.Id)
	}
	patterns, ok := rv.FilePatterns.(pulumi.StringArray)
	if !ok || len(patterns) != len(guardReviewPaths) {
		t.Fatalf("FilePatterns = %v, want guardReviewPaths", rv.FilePatterns)
	}
	for i, p := range guardReviewPaths {
		if patterns[i] != pulumi.String(p) {
			t.Errorf("FilePatterns[%d] = %v, want %q", i, patterns[i], p)
		}
	}
}

// The review's bypass list must equal the merge-queue ruleset's: a narrower
// one would block direct pushes the queue's ruleset allows (this ruleset's
// pull_request rule applies to every change to main), a wider one would let
// someone skip James's approval who cannot skip the queue.
func TestGuardReviewBypassMatchesMergeQueue(t *testing.T) {
	type actor struct {
		id        int
		typ, mode string
	}
	flatten := func(name string, arr github.RepositoryRulesetBypassActorArray) []actor {
		var out []actor
		for _, a := range arr {
			args, ok := a.(*github.RepositoryRulesetBypassActorArgs)
			if !ok {
				t.Fatalf("%s: bypass actor is %T", name, a)
			}
			id, ok1 := args.ActorId.(pulumi.Int)
			typ, ok2 := args.ActorType.(pulumi.String)
			mode, ok3 := args.BypassMode.(pulumi.String)
			if !ok1 || !ok2 || !ok3 {
				t.Fatalf("%s: bypass actor fields are not literals: %#v", name, args)
			}
			out = append(out, actor{int(id), string(typ), string(mode)})
		}
		return out
	}

	got := flatten("agent-guard-review", guardReviewBypassActors())
	want := flatten("merge-queue", mergeQueueBypassActors())
	if len(got) != len(want) {
		t.Fatalf("agent-guard-review bypass = %v, merge-queue bypass = %v; they must be equal", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("agent-guard-review bypass = %v, merge-queue bypass = %v; they must be equal", got, want)
		}
	}
	// And what that list is today: admins and copybara-sync, both "always".
	pinned := []actor{{5, "RepositoryRole", "always"}, {copybaraSyncAppID, "Integration", "always"}}
	for i := range pinned {
		if i >= len(got) || got[i] != pinned[i] {
			t.Fatalf("bypass actors = %v, want %v", got, pinned)
		}
	}
}

type guardMocks struct {
	mu        sync.Mutex
	resources map[string]resource.PropertyMap // by type token
}

func (m *guardMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.resources[args.TypeToken] = args.Inputs
	id := args.Name + "-id"
	if args.TypeToken == "github:index/team:Team" {
		id = "4242" // GitHub team ids are numeric
	}
	return id, args.Inputs, nil
}

func (m *guardMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// The whole program fragment, under Pulumi's mock engine: the team, James's
// membership, write access, and a ruleset whose reviewer is the team's
// NUMERIC id (the provider takes an int; a team id that fails to parse must
// fail the run, not produce a rule nobody can satisfy).
func TestAgentGuardReviewResources(t *testing.T) {
	mocks := &guardMocks{resources: map[string]resource.PropertyMap{}}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		repo, err := github.NewRepository(ctx, "vitruvian-core", &github.RepositoryArgs{
			Name: pulumi.String("vitruvian-core"),
		})
		if err != nil {
			return err
		}
		return agentGuardReview(ctx, repo)
	}, pulumi.WithMocks("repo-config", "dev", mocks))
	if err != nil {
		t.Fatalf("agentGuardReview: %v", err)
	}

	team := mocks.resources["github:index/team:Team"]
	if team == nil || team["name"].StringValue() != guardReviewTeamSlug {
		t.Fatalf("team = %v, want one named %q", team, guardReviewTeamSlug)
	}
	member := mocks.resources["github:index/teamMembership:TeamMembership"]
	if member == nil || member["username"].StringValue() != "ipv1337" || member["teamId"].StringValue() != "4242" {
		t.Errorf("membership = %v, want ipv1337 in team 4242", member)
	}
	access := mocks.resources["github:index/teamRepository:TeamRepository"]
	if access == nil || access["permission"].StringValue() != "push" {
		t.Errorf("team repository access = %v, want push (the rule counts only teams that can write)", access)
	}

	rs := mocks.resources["github:index/repositoryRuleset:RepositoryRuleset"]
	if rs == nil {
		t.Fatal("no ruleset declared")
	}
	if rs["name"].StringValue() != "agent-guard-review" || rs["enforcement"].StringValue() != "active" {
		t.Errorf("ruleset = %v, want an active agent-guard-review", rs)
	}
	inc := rs["conditions"].ObjectValue()["refName"].ObjectValue()["includes"].ArrayValue()
	if len(inc) != 1 || inc[0].StringValue() != "~DEFAULT_BRANCH" {
		t.Errorf("ruleset targets %v, want ~DEFAULT_BRANCH", inc)
	}
	pr := rs["rules"].ObjectValue()["pullRequest"].ObjectValue()
	rr := pr["requiredReviewers"].ArrayValue()
	if len(rr) != 1 {
		t.Fatalf("requiredReviewers = %v, want one", rr)
	}
	reviewer := rr[0].ObjectValue()["reviewer"].ObjectValue()
	if reviewer["id"].NumberValue() != 4242 || reviewer["type"].StringValue() != "Team" {
		t.Errorf("reviewer = %v, want team 4242", reviewer)
	}
	if got := len(rr[0].ObjectValue()["filePatterns"].ArrayValue()); got != len(guardReviewPaths) {
		t.Errorf("filePatterns has %d entries, want %d", got, len(guardReviewPaths))
	}
}

// Every file the session-start launcher compiles must need James's approval:
// cloud-bootstrap.sh builds src/cloud_bootstrap/main.rs with rustc, and rustc
// reads main.rs plus every `mod x;` it declares. Enumerated from the real
// crate, so narrowing the pattern, or adding a module it misses, fails here.
func TestGuardReviewCoversEverySessionStartSource(t *testing.T) {
	const crate = "tools/cloud-bootstrap/src/cloud_bootstrap"
	root, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	for {
		if _, err := os.Stat(filepath.Join(root, crate, "main.rs")); err == nil {
			break
		}
		parent := filepath.Dir(root)
		if parent == root {
			t.Fatalf("could not find %s/main.rs above the working directory; this test must see the crate to check it", crate)
		}
		root = parent
	}
	main, err := os.ReadFile(filepath.Join(root, crate, "main.rs"))
	if err != nil {
		t.Fatal(err)
	}
	files := []string{"tools/cloud-bootstrap/cloud-bootstrap.sh", crate + "/main.rs"}
	for _, line := range strings.Split(string(main), "\n") {
		l := strings.TrimSpace(line)
		l = strings.TrimPrefix(l, "pub ")
		if strings.HasPrefix(l, "mod ") && strings.HasSuffix(l, ";") {
			name := strings.TrimSuffix(strings.TrimPrefix(l, "mod "), ";")
			files = append(files, crate+"/"+strings.TrimSpace(name)+".rs")
		}
	}
	if len(files) < 4 {
		t.Fatalf("found only %v; the module scan is broken", files)
	}
	for _, f := range files {
		if _, err := os.Stat(filepath.Join(root, f)); err != nil {
			t.Errorf("%s is compiled by the launcher but missing: %v", f, err)
		}
		if !guardCovers(f) {
			t.Errorf("%s is compiled and run at session start but is not covered by guardReviewPaths", f)
		}
	}
	// Any .rs a later change adds beside them is covered too.
	entries, err := os.ReadDir(filepath.Join(root, crate))
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".rs") && !guardCovers(crate+"/"+e.Name()) {
			t.Errorf("%s/%s is not covered by guardReviewPaths", crate, e.Name())
		}
	}
}

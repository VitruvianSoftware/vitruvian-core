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
	"path"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// githubActionsAppID is the GitHub Actions App (github-actions[bot]), the
// identity behind every workflow's GITHUB_TOKEN.
const githubActionsAppID = 15368

func literalStrings(t *testing.T, name string, arr pulumi.StringArrayInput) []string {
	t.Helper()
	a, ok := arr.(pulumi.StringArray)
	if !ok {
		t.Fatalf("%s is %T, want a literal pulumi.StringArray", name, arr)
	}
	out := make([]string, len(a))
	for i, s := range a {
		v, ok := s.(pulumi.String)
		if !ok {
			t.Fatalf("%s[%d] is %T, want a literal", name, i, s)
		}
		out[i] = string(v)
	}
	return out
}

// tagProtected reports whether the ruleset's conditions select refs/tags/<tag>,
// read from the declared conditions (not from rollingTags) so it tests what is
// applied.
func tagProtected(t *testing.T, tag string) bool {
	t.Helper()
	c := releaseTagConditions().RefName.(*github.RepositoryRulesetConditionsRefNameArgs)
	ref := "refs/tags/" + tag
	included := false
	for _, inc := range literalStrings(t, "includes", c.Includes) {
		if inc == "~ALL" {
			included = true
		} else if ok, _ := path.Match(inc, ref); ok {
			included = true
		}
	}
	for _, exc := range literalStrings(t, "excludes", c.Excludes) {
		if ok, _ := path.Match(exc, ref); ok {
			return false
		}
	}
	return included
}

// Every tag, minus the exact rolling names; and nobody without bypass may
// create, move or delete one.
func TestReleaseTagRulesetShape(t *testing.T) {
	c := releaseTagConditions().RefName.(*github.RepositoryRulesetConditionsRefNameArgs)
	if inc := literalStrings(t, "includes", c.Includes); len(inc) != 1 || inc[0] != "~ALL" {
		t.Errorf("includes = %v, want [~ALL]: a list of release prefixes drifts, and a missing one fails open", inc)
	}
	exc := literalStrings(t, "excludes", c.Excludes)
	if len(exc) != len(rollingTags) {
		t.Fatalf("excludes = %v, want exactly the rolling tags %v", exc, rollingTags)
	}
	for i, tag := range rollingTags {
		if exc[i] != "refs/tags/"+tag {
			t.Errorf("excludes[%d] = %q, want %q", i, exc[i], "refs/tags/"+tag)
		}
	}

	r := releaseTagRules()
	for name, got := range map[string]pulumi.BoolPtrInput{"Creation": r.Creation, "Update": r.Update, "Deletion": r.Deletion} {
		if got != pulumi.Bool(true) {
			t.Errorf("%s = %v, want true: only bypass actors may do it", name, got)
		}
	}
}

// Exempting a tag that an Environment accepts would reopen the deploy path,
// and a wildcard exemption could do it for names nobody has thought of yet.
func TestRollingTagsAreExactAndUndeployable(t *testing.T) {
	seen := map[string]bool{}
	for _, tag := range rollingTags {
		if strings.ContainsAny(tag, "*?[]\\") {
			t.Errorf("rolling tag %q has a wildcard; list exact names only", tag)
		}
		if !strings.HasSuffix(tag, "-latest") {
			t.Errorf("rolling tag %q does not end in -latest; only the rolling pre-release tags are exempt", tag)
		}
		if seen[tag] {
			t.Errorf("rolling tag %q is listed twice", tag)
		}
		seen[tag] = true
		for _, p := range environmentTagPatterns {
			if ok, _ := path.Match(p, tag); ok {
				t.Errorf("rolling tag %q matches Environment tag pattern %q; it must stay protected", tag, p)
			}
		}
	}
}

// Every release tag format in use stays protected, including names built to
// look like a rolling tag, and every tag an Environment accepts.
func TestReleaseTagsProtected(t *testing.T) {
	protected := []string{
		// release-please's <component>-v<version>, one per family on origin.
		"tabula-api-v0.30.0",
		"tabula-web-v0.29.0",
		"courier-v0.1.0",
		"oauth-user-inspector-v1.4.0",
		"oauth-user-inspector-infra-v0.9.0",
		"vitruvian-v4.12.0",
		"vitruvian-sdk-v0.14.0",
		"home-speaker-v2.3.0",
		"esp32-s3-v0.1.12",
		"gravastar-mouse-v0.2.0",
		"foundation-gcp-projects-v0.30.0",
		"go-network-v2.0.0",
		// pulumi-library's plain v<version>, and the older calendar tags.
		"v1.0.1",
		"2026.26",
		// Look-alikes of the rolling names.
		"tabula-api-v9.9.9-beta-latest",
		"vitruvian-beta-latest-2",
		"beta-latest",
	}
	for _, p := range environmentTagPatterns {
		protected = append(protected, strings.ReplaceAll(p, "*", "1.0.0"))
	}
	for _, tag := range protected {
		if !tagProtected(t, tag) {
			t.Errorf("tag %q is not protected by the release-tags ruleset", tag)
		}
	}
	for _, tag := range rollingTags {
		if tagProtected(t, tag) {
			t.Errorf("rolling tag %q is protected; its publisher (GITHUB_TOKEN) could no longer move it", tag)
		}
	}
}

// release-please (copybara-sync) and admins, the same list as main's; never
// the GitHub Actions token, which any branch's workflow can hold, and never
// Renovate.
func TestReleaseTagBypassActors(t *testing.T) {
	type actor struct {
		id        int
		typ, mode string
	}
	flatten := func(arr github.RepositoryRulesetBypassActorArray) []actor {
		var out []actor
		for _, a := range arr {
			args := a.(*github.RepositoryRulesetBypassActorArgs)
			out = append(out, actor{int(args.ActorId.(pulumi.Int)), string(args.ActorType.(pulumi.String)), string(args.BypassMode.(pulumi.String))})
		}
		return out
	}
	got := flatten(releaseTagBypassActors())
	want := []actor{{5, "RepositoryRole", "always"}, {copybaraSyncAppID, "Integration", "always"}}
	if len(got) != len(want) {
		t.Fatalf("bypass actors = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("bypass actors = %v, want %v", got, want)
		}
	}
	for _, a := range got {
		if a.typ == "Integration" && (a.id == githubActionsAppID || a.id == renovateAppID) {
			t.Errorf("bypass actor %v must not bypass the release-tag ruleset", a)
		}
	}
}

// The Environment deployment policies use the constants in release_tags.go,
// so environmentTagPatterns is the whole set the tests above check against.
// An inline tag glob anywhere else in the program would escape them.
func TestEnvironmentTagPatternsAreDeclaredHere(t *testing.T) {
	files, err := filepath.Glob("*.go")
	if err != nil || len(files) < 3 {
		t.Fatalf("listing the program's .go files (the test runs in the package directory): %v %v", files, err)
	}
	// A string literal with a wildcard and no slash: a tag glob. (File paths,
	// like guardReviewPaths, carry a slash.)
	glob := regexp.MustCompile(`"[^"/\n]*\*[^"/\n]*"`)
	var mainSrc string
	for _, f := range files {
		if strings.HasSuffix(f, "_test.go") || f == "release_tags.go" {
			continue
		}
		src, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		if f == "main.go" {
			mainSrc = string(src)
		}
		for i, line := range strings.Split(string(src), "\n") {
			if strings.HasPrefix(strings.TrimSpace(line), "//") {
				continue
			}
			if m := glob.FindString(line); m != "" {
				t.Errorf("%s:%d has the pattern %s inline; declare tag patterns in environmentTagPatterns (release_tags.go)", f, i+1, m)
			}
		}
	}
	if !strings.Contains(mainSrc, "releaseTagProtection(ctx, repo)") {
		t.Error("main.go does not call releaseTagProtection; the ruleset would never be declared")
	}
}

// Under Pulumi's mock engine: one active tag ruleset with the rules above.
func TestReleaseTagResources(t *testing.T) {
	mocks := &guardMocks{resources: map[string]resource.PropertyMap{}}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		repo, err := github.NewRepository(ctx, "vitruvian-core", &github.RepositoryArgs{
			Name: pulumi.String("vitruvian-core"),
		})
		if err != nil {
			return err
		}
		return releaseTagProtection(ctx, repo)
	}, pulumi.WithMocks("repo-config", "dev", mocks))
	if err != nil {
		t.Fatalf("releaseTagProtection: %v", err)
	}
	rs := mocks.resources["github:index/repositoryRuleset:RepositoryRuleset"]
	if rs == nil {
		t.Fatal("no ruleset declared")
	}
	if rs["name"].StringValue() != "release-tags" || rs["target"].StringValue() != "tag" || rs["enforcement"].StringValue() != "active" {
		t.Errorf("ruleset = %v, want an active tag ruleset named release-tags", rs)
	}
	rules := rs["rules"].ObjectValue()
	for _, k := range []resource.PropertyKey{"creation", "update", "deletion"} {
		if !rules[k].IsBool() || !rules[k].BoolValue() {
			t.Errorf("rules.%s = %v, want true", k, rules[k])
		}
	}
	if got := len(rs["bypassActors"].ArrayValue()); got != 2 {
		t.Errorf("bypassActors has %d entries, want 2 (admins, copybara-sync)", got)
	}
}

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
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path"
	"regexp"
	"sort"
	"strconv"
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
// Renovate. The App id is pinned as a literal, so a changed constant cannot
// carry the test along with it.
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
	want := []actor{{5, "RepositoryRole", "always"}, {3863936, "Integration", "always"}}
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

// programMocks is envMocks plus numeric team ids (GitHub's are numbers, and
// the guard review ruleset parses one).
type programMocks struct{ envMocks }

func (m *programMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	id, props, err := m.envMocks.NewResource(args)
	if args.TypeToken == "github:index/team:Team" {
		id = "4242"
	}
	return id, props, err
}

// runProgram runs the WHOLE stack (program, as main runs it) under Pulumi's
// mock engine with the committed stack config, and returns every registered
// resource's inputs by type token.
func runProgram(t *testing.T) map[string][]resource.PropertyMap {
	t.Helper()
	t.Setenv("PULUMI_CONFIG", stackConfigEnv(t))
	// Stand-ins for the secrets CI injects (copybara-sync App, CI telemetry
	// webhook), and the
	// site-domain switch left off, so the run needs no real secret.
	t.Setenv("SYNC_APP_ID", "1")
	t.Setenv("SYNC_APP_PRIVATE_KEY", "test-only-not-a-key")
	t.Setenv("OTEL_GITHUB_WEBHOOK_SECRET", "test-only")
	t.Setenv("SITE_DOMAIN_MANAGED", "")
	mocks := &programMocks{envMocks{resources: map[string][]resource.PropertyMap{}}}
	if err := pulumi.RunErr(program, pulumi.WithMocks("vitruvian-core-repo-config", "dev", mocks)); err != nil {
		t.Fatalf("program: %v", err)
	}
	return mocks.resources
}

func propStrings(v resource.PropertyValue) []string {
	if !v.IsArray() {
		return nil
	}
	var out []string
	for _, e := range v.ArrayValue() {
		out = append(out, e.StringValue())
	}
	return out
}

// The program as applied registers exactly one tag ruleset, release-tags,
// with the shape the unit tests above check piecewise: wiring it out of
// main.go, or changing it on the way, fails here.
func TestProgramRegistersReleaseTagRuleset(t *testing.T) {
	res := runProgram(t)

	var tagRulesets []resource.PropertyMap
	for _, rs := range res["github:index/repositoryRuleset:RepositoryRuleset"] {
		if rs["target"].StringValue() == "tag" || rs["name"].StringValue() == "release-tags" {
			tagRulesets = append(tagRulesets, rs)
		}
	}
	if len(tagRulesets) != 1 {
		t.Fatalf("program registers %d tag rulesets, want exactly one (release-tags)", len(tagRulesets))
	}
	rs := tagRulesets[0]
	if rs["name"].StringValue() != "release-tags" || rs["target"].StringValue() != "tag" || rs["enforcement"].StringValue() != "active" {
		t.Errorf("ruleset = %v/%v/%v, want release-tags/tag/active", rs["name"], rs["target"], rs["enforcement"])
	}

	ref := rs["conditions"].ObjectValue()["refName"].ObjectValue()
	if inc := propStrings(ref["includes"]); len(inc) != 1 || inc[0] != "~ALL" {
		t.Errorf("includes = %v, want [~ALL]", inc)
	}
	exc := propStrings(ref["excludes"])
	var wantExc []string
	for _, tag := range []string{"vitruvian-beta-latest", "esp32-s3-beta-latest", "gravastar-mouse-beta-latest", "tabula-extension-dev-latest"} {
		wantExc = append(wantExc, "refs/tags/"+tag)
	}
	if strings.Join(exc, " ") != strings.Join(wantExc, " ") {
		t.Errorf("excludes = %v, want %v", exc, wantExc)
	}

	rules := rs["rules"].ObjectValue()
	if len(rules) != 3 {
		t.Errorf("rules = %v, want exactly creation, update and deletion", rules)
	}
	for _, k := range []resource.PropertyKey{"creation", "update", "deletion"} {
		if !rules[k].IsBool() || !rules[k].BoolValue() {
			t.Errorf("rules.%s = %v, want true", k, rules[k])
		}
	}

	var actors []string
	for _, a := range rs["bypassActors"].ArrayValue() {
		o := a.ObjectValue()
		actors = append(actors, fmt.Sprintf("%d/%s/%s", int64(o["actorId"].NumberValue()), o["actorType"].StringValue(), o["bypassMode"].StringValue()))
	}
	if got, want := strings.Join(actors, " "), "5/RepositoryRole/always 3863936/Integration/always"; got != want {
		t.Errorf("bypassActors = %s, want %s", got, want)
	}
}

// Every tag pattern an Environment really accepts deploys from (read from
// the deployment policies the program registers, however the pattern was
// built) must leave the exempt rolling tags out: an exempt tag that an
// Environment accepts reopens the deploy path. The registered set must also
// equal environmentTagPatterns, so the constants stay the truth.
func TestDeployTagPatternsNeverMatchExemptTags(t *testing.T) {
	res := runProgram(t)

	var rulesetRepo string
	var exempt []string
	for _, rs := range res["github:index/repositoryRuleset:RepositoryRuleset"] {
		if rs["name"].StringValue() != "release-tags" {
			continue
		}
		rulesetRepo = rs["repository"].StringValue()
		for _, e := range propStrings(rs["conditions"].ObjectValue()["refName"].ObjectValue()["excludes"]) {
			exempt = append(exempt, strings.TrimPrefix(e, "refs/tags/"))
		}
	}
	if len(exempt) == 0 {
		t.Fatal("found no exempt tags on a registered release-tags ruleset; the check would be blind")
	}

	// Inspect EVERY tag deployment policy the program registers across every
	// repository (never silently skipping non-monorepo policies): vitruvian-core
	// policies must equal environmentTagPatterns and reject every exempt rolling
	// tag, while standalone mirror tag policies must belong only to declared
	// mirrors (vitruvian-code's v*).
	registeredByRepo := map[string]map[string]bool{}
	for _, p := range res["github:index/repositoryEnvironmentDeploymentPolicy:RepositoryEnvironmentDeploymentPolicy"] {
		v, ok := p["tagPattern"]
		if !ok || !v.IsString() || v.StringValue() == "" {
			continue
		}
		repo := p["repository"].StringValue()
		if repo == "" {
			t.Fatalf("deployment policy %v has tagPattern %q with empty repository", p, v.StringValue())
		}
		if registeredByRepo[repo] == nil {
			registeredByRepo[repo] = map[string]bool{}
		}
		registeredByRepo[repo][v.StringValue()] = true
	}

	for repo, patterns := range registeredByRepo {
		if repo != rulesetRepo && repo != "vitruvian-code" {
			t.Errorf("unexpected repository %q registers tag deployment policies %v", repo, patterns)
		}
	}

	registered := registeredByRepo[rulesetRepo]
	if len(registered) == 0 {
		t.Fatal("the program registers no tag deployment policy on the monorepo; the check would be blind")
	}
	for pattern := range registered {
		for _, tag := range exempt {
			if ok, err := path.Match(pattern, tag); err != nil || ok {
				t.Errorf("Environment tag pattern %q accepts the exempt tag %q (err %v); exempt tags must never be deployable", pattern, tag, err)
			}
		}
	}

	declared := map[string]bool{}
	for _, p := range environmentTagPatterns {
		declared[p] = true
	}
	for p := range registered {
		if !declared[p] {
			t.Errorf("the program registers tag pattern %q on %s, which is not in environmentTagPatterns", p, rulesetRepo)
		}
	}
	for p := range declared {
		if !registered[p] {
			t.Errorf("environmentTagPatterns lists %q, which no Environment on %s uses", p, rulesetRepo)
		}
	}

	mirrorRegistered := registeredByRepo["vitruvian-code"]
	if len(mirrorRegistered) != 1 || !mirrorRegistered["v*"] {
		t.Errorf("vitruvian-code tag deployment policies = %v, want exactly map[v*:true]", mirrorRegistered)
	}
}

// Vitruvian Code's mirror cuts plain `v<version>` tags on `vitruvian-code` and
// deploys to `vitruvian-code-release` there. On `vitruvian-core`, `v*` would
// match the exempt rolling tag `vitruvian-beta-latest`, so `vitruvian-code`'s
// `v*` policy and `vitruvian-code-release` environment must stay strictly
// isolated from the monorepo's environments and release tags.
func TestVitruvianCodeReleaseTagsStaySeparateFromMonorepoReleaseTags(t *testing.T) {
	if ok, err := path.Match("v*", "vitruvian-beta-latest"); err != nil || !ok {
		t.Fatalf("expected v* to match vitruvian-beta-latest (got ok=%v, err=%v); this invariant explains why v* must never sit on vitruvian-core", ok, err)
	}
	for _, p := range environmentTagPatterns {
		if p == "v*" {
			t.Fatal("environmentTagPatterns must never include bare v* on vitruvian-core")
		}
		for _, vcTag := range []string{"v1.33.0", "vitruvian-code-v1.33.0"} {
			if ok, _ := path.Match(p, vcTag); ok {
				t.Errorf("monorepo Environment tag pattern %q unexpectedly matches vitruvian-code tag %q", p, vcTag)
			}
		}
	}
	for _, vcTag := range []string{"v1.33.0", "vitruvian-code-v1.33.0"} {
		if !tagProtected(t, vcTag) {
			t.Errorf("tag %q must remain protected by release-tags on vitruvian-core", vcTag)
		}
	}

	res := runProgram(t)

	var vcEnvs int
	for _, env := range res["github:index/repositoryEnvironment:RepositoryEnvironment"] {
		repo := env["repository"].StringValue()
		name := env["environment"].StringValue()
		if name == "vitruvian-code-release" {
			vcEnvs++
			if repo != "vitruvian-code" {
				t.Errorf("vitruvian-code-release registered on repository %q, want vitruvian-code", repo)
			}
		} else if repo == "vitruvian-code" {
			t.Errorf("unexpected environment %q registered on vitruvian-code", name)
		}
	}
	if vcEnvs != 1 {
		t.Fatalf("program registered %d vitruvian-code-release environments, want 1", vcEnvs)
	}

	var vcPolicies []string
	for _, p := range res["github:index/repositoryEnvironmentDeploymentPolicy:RepositoryEnvironmentDeploymentPolicy"] {
		repo := p["repository"].StringValue()
		env := p["environment"].StringValue()
		branch := ""
		if v, ok := p["branchPattern"]; ok && v.IsString() {
			branch = v.StringValue()
		}
		tag := ""
		if v, ok := p["tagPattern"]; ok && v.IsString() {
			tag = v.StringValue()
		}
		if repo == "vitruvian-core" {
			if env == "vitruvian-code-release" || tag == "v*" {
				t.Errorf("vitruvian-core must never carry vitruvian-code-release or v* policy (got env=%q tag=%q)", env, tag)
			}
		}
		if env == "vitruvian-code-release" || repo == "vitruvian-code" {
			if repo != "vitruvian-code" || env != "vitruvian-code-release" {
				t.Errorf("mismatched mirror policy repo=%q env=%q", repo, env)
			}
			vcPolicies = append(vcPolicies, fmt.Sprintf("branch=%s,tag=%s", branch, tag))
		}
	}
	sort.Strings(vcPolicies)
	if got, want := strings.Join(vcPolicies, " "), "branch=,tag=v* branch=main,tag="; got != want {
		t.Errorf("vitruvian-code-release policies = %q, want %q", got, want)
	}
}

// //tools/conformance:check reads the rolling tags between the rolling-tags
// markers in release_tags.go (it cannot import Go). Those markers must wrap
// exactly the rollingTags literal: every element inside them, and no other
// string, in either quote style. Otherwise a tag placed outside the markers
// would escape that check.
func TestRollingTagMarkersMatchRollingTags(t *testing.T) {
	src, err := os.ReadFile("release_tags.go")
	if err != nil {
		t.Fatalf("reading release_tags.go (the test runs in the package directory): %v", err)
	}
	// The conformance reader takes the first textual occurrence of each
	// marker, so any other mention (an earlier comment, say) would point it
	// at a different block from the one checked here.
	for _, marker := range []string{"rolling-tags:begin", "rolling-tags:end"} {
		if n := strings.Count(string(src), marker); n != 1 {
			t.Errorf("%q appears %d times in release_tags.go, want exactly once", marker, n)
		}
	}
	// The same line-shape rule the conformance reader applies
	// (rolling_tag_line in tools/conformance/src/checks/security.rs): the
	// markers stand alone on their lines, and every line between them is
	// blank, a whole-line // comment, or exactly one plain "[a-z0-9.-]+",
	// literal. Nothing else (escapes, raw strings, block comments, two
	// literals on a line), so the two readers agree by construction.
	lines := strings.Split(string(src), "\n")
	bl, el := -1, -1
	for i, l := range lines {
		if strings.Contains(l, "rolling-tags:begin") {
			bl = i
		}
		if strings.Contains(l, "rolling-tags:end") {
			el = i
		}
	}
	if bl < 0 || el <= bl {
		t.Fatalf("rolling-tags markers missing or out of order (begin line %d, end line %d)", bl+1, el+1)
	}
	for i, want := range map[int]string{bl: "// rolling-tags:begin", el: "// rolling-tags:end"} {
		if strings.TrimSpace(lines[i]) != want {
			t.Errorf("release_tags.go:%d = %q, want exactly %q", i+1, lines[i], want)
		}
	}
	shape := regexp.MustCompile(`^[ \t]*(//.*|"[a-z0-9.-]+",[ \t]*)?$`)
	for i := bl + 1; i < el; i++ {
		if !shape.MatchString(lines[i]) {
			t.Errorf("release_tags.go:%d %q is not blank, a // comment, or one plain \"[a-z0-9.-]+\", literal", i+1, lines[i])
		}
	}

	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "release_tags.go", src, parser.ParseComments)
	if err != nil {
		t.Fatalf("parsing release_tags.go: %v", err)
	}
	begin, end := token.NoPos, token.NoPos
	for _, cg := range f.Comments {
		for _, c := range cg.List {
			switch strings.TrimSpace(strings.TrimPrefix(c.Text, "//")) {
			case "rolling-tags:begin":
				if begin != token.NoPos {
					t.Fatal("rolling-tags:begin appears twice")
				}
				begin = c.Pos()
			case "rolling-tags:end":
				if end != token.NoPos {
					t.Fatal("rolling-tags:end appears twice")
				}
				end = c.Pos()
			}
		}
	}
	if begin == token.NoPos || end == token.NoPos || end < begin {
		t.Fatalf("rolling-tags markers missing or out of order (begin %v, end %v)", begin, end)
	}

	// Every string literal between the markers, in source order.
	var marked []string
	ast.Inspect(f, func(n ast.Node) bool {
		if lit, ok := n.(*ast.BasicLit); ok && lit.Kind == token.STRING && lit.Pos() > begin && lit.End() < end {
			v, err := strconv.Unquote(lit.Value)
			if err != nil {
				t.Fatalf("unquoting %s: %v", lit.Value, err)
			}
			marked = append(marked, v)
		}
		return true
	})
	if strings.Join(marked, " ") != strings.Join(rollingTags, " ") {
		t.Errorf("strings between the rolling-tags markers = %v, want exactly rollingTags = %v", marked, rollingTags)
	}

	// And every element of the rollingTags literal sits between them.
	found := false
	ast.Inspect(f, func(n ast.Node) bool {
		vs, ok := n.(*ast.ValueSpec)
		if !ok || len(vs.Names) != 1 || vs.Names[0].Name != "rollingTags" {
			return true
		}
		found = true
		cl, ok := vs.Values[0].(*ast.CompositeLit)
		if !ok {
			t.Fatalf("rollingTags is %T, want a literal []string{...}", vs.Values[0])
		}
		for _, e := range cl.Elts {
			if e.Pos() < begin || e.End() > end {
				t.Errorf("rollingTags element at %v is outside the rolling-tags markers", fset.Position(e.Pos()))
			}
		}
		return false
	})
	if !found {
		t.Fatal("no rollingTags declaration in release_tags.go")
	}
}

// The whole program also registers main's two branch rulesets: the merge
// queue and the guard review.
func TestProgramRegistersMainRulesets(t *testing.T) {
	res := runProgram(t)
	byName := map[string]resource.PropertyMap{}
	for _, rs := range res["github:index/repositoryRuleset:RepositoryRuleset"] {
		byName[rs["name"].StringValue()] = rs
	}
	for _, name := range []string{"merge-queue", "agent-guard-review"} {
		rs, ok := byName[name]
		if !ok {
			t.Errorf("program does not register the %s ruleset", name)
			continue
		}
		if rs["target"].StringValue() != "branch" || rs["enforcement"].StringValue() != "active" {
			t.Errorf("%s = %v/%v, want branch/active", name, rs["target"], rs["enforcement"])
		}
		inc := propStrings(rs["conditions"].ObjectValue()["refName"].ObjectValue()["includes"])
		if len(inc) != 1 || inc[0] != "~DEFAULT_BRANCH" {
			t.Errorf("%s targets %v, want ~DEFAULT_BRANCH", name, inc)
		}
	}
	if rs, ok := byName["agent-guard-review"]; ok {
		pr := rs["rules"].ObjectValue()["pullRequest"].ObjectValue()
		rr := pr["requiredReviewers"].ArrayValue()
		if len(rr) != 1 || len(propStrings(rr[0].ObjectValue()["filePatterns"])) != len(guardReviewPaths) {
			t.Errorf("agent-guard-review requiredReviewers = %v, want one reviewer over guardReviewPaths", rr)
		}
	}
}

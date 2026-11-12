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
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Release tags are made by release-please and nobody else.
//
// A release tag starts deploys: the release event runs the delivery
// workflows, and some GitHub Environments accept a deploy from a tag that
// matches environmentTagPatterns. So creating, moving or deleting one is a
// release decision, and only the automation that cuts releases (and the
// admin break-glass) may do it.
//
// The ruleset covers EVERY tag (~ALL), not a list of release prefixes: a
// list drifts as components are added, and a missing prefix would fail open.
// What it leaves out is a short list of exact names, the rolling pre-release
// tags the beta/dev publishers move on every push to main (rollingTags).
//
// Who still may (the bypass list is main's, see releaseTagBypassActors):
//   - release-please runs as the vitruvian-copybara-sync App
//     (mint-sync-app-token) in every *-release.yaml workflow, and creates the
//     tag when it creates the GitHub release.
//   - repository admins, James's break-glass (a hand-cut release).
//
// Who may not, on purpose: the GitHub Actions token (github-actions[bot]).
// Any workflow on any branch can hold it with contents: write, so it is not a
// bypass actor. The rolling publishers that use it are why rollingTags exist.
//
// This ruleset is only as strong as its bypass actors' credentials: the
// bypass App's key must stay limited to main. That is tracked separately;
// this file does not establish it.

// environmentTagPatterns are the tag patterns GitHub Environments accept
// deploys from (the deployment policies in main.go and courier_release.go
// use these constants). TestDeployTagPatternsNeverMatchExemptTags runs the
// whole program and fails if the patterns it registers differ from this list
// or accept an exempt tag.
const (
	vitruvianTabsAPIReleaseTagPattern   = "vitruvian-tabs-api-v*"
	vitruvianTabsWebReleaseTagPattern   = "vitruvian-tabs-web-v*"
	oauthUserInspectorReleaseTagPattern = "oauth-user-inspector-v*"
	courierReleaseTagPattern            = "courier-v*"
)

var environmentTagPatterns = []string{
	vitruvianTabsAPIReleaseTagPattern,
	vitruvianTabsWebReleaseTagPattern,
	oauthUserInspectorReleaseTagPattern,
	courierReleaseTagPattern,
}

// rollingTags are moved to main's HEAD by the beta/dev publishers, with the
// GitHub Actions token, on every push to main. Exact names only: a wildcard
// here (say "*-latest") would also exempt "vitruvian-tabs-api-v9-latest", which an
// Environment accepts. TestRollingTagsAreExactAndUndeployable holds that,
// and //tools/conformance:check (check_release_tag_exemptions) fails if one
// starts with a release tag prefix derived from any release-please-config.json,
// the prefixes the release-event delivery jobs act on. It reads the names
// between the markers below.
//
// Where each is set:
//   - vitruvian-beta-latest: apps/desktop/vitruvian/bazel/src/publish/lib.rs
//   - esp32-s3-beta-latest: apps/embedded/esp32-s3/host_companion/src/publish/lib.rs
//   - gravastar-mouse-beta-latest: packages/peripherals/scripts/src/lib.rs
//   - vitruvian-tabs-extension-dev-latest: apps/suites/vitruvian-tabs/extension/scripts/src/publish_dev_latest.rs
//
// A new rolling tag that is not listed fails its publish job on the first
// push (the ruleset refuses the move), which is the safe way round.
var rollingTags = []string{
	// rolling-tags:begin
	"vitruvian-beta-latest",
	"esp32-s3-beta-latest",
	"gravastar-mouse-beta-latest",
	"vitruvian-tabs-extension-dev-latest",
	// rolling-tags:end
}

// releaseTagBypassActors is main's merge-queue bypass list: repository admins
// and the vitruvian-copybara-sync App (release-please's identity), both
// "always". Shared with guardReviewBypassActors so the three rulesets name
// the same actors.
func releaseTagBypassActors() github.RepositoryRulesetBypassActorArray {
	return mergeQueueBypassActors()
}

// releaseTagConditions targets every tag except the rolling ones.
func releaseTagConditions() *github.RepositoryRulesetConditionsArgs {
	excludes := pulumi.StringArray{}
	for _, t := range rollingTags {
		excludes = append(excludes, pulumi.String("refs/tags/"+t))
	}
	return &github.RepositoryRulesetConditionsArgs{
		RefName: &github.RepositoryRulesetConditionsRefNameArgs{
			Includes: pulumi.StringArray{pulumi.String("~ALL")},
			Excludes: excludes,
		},
	}
}

// releaseTagRules: only bypass actors may create, move or delete a tag.
func releaseTagRules() *github.RepositoryRulesetRulesArgs {
	return &github.RepositoryRulesetRulesArgs{
		Creation: pulumi.Bool(true),
		Update:   pulumi.Bool(true),
		Deletion: pulumi.Bool(true),
	}
}

// releaseTagProtection declares the tag ruleset.
func releaseTagProtection(ctx *pulumi.Context, repo *github.Repository) error {
	_, err := github.NewRepositoryRuleset(ctx, "release-tags", &github.RepositoryRulesetArgs{
		Name:         pulumi.String("release-tags"),
		Repository:   repo.Name,
		Target:       pulumi.String("tag"),
		Enforcement:  pulumi.String("active"),
		BypassActors: releaseTagBypassActors(),
		Conditions:   releaseTagConditions(),
		Rules:        releaseTagRules(),
	})
	return err
}

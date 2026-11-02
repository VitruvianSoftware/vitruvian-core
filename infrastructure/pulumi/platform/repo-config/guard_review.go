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
	"strconv"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Changes to agent-guard's rules need James's approval (approved by James on
// 2026-10-17).
//
// main's merge-queue ruleset requires no approving review, and agents arm
// auto-merge on their own pull requests, so without this an agent could merge
// a change that weakens agent-guard without James ever seeing it.
//
// The mechanism is GitHub's own "required reviewers" rule: a pull_request rule
// parameter that requires approval from a TEAM for pull requests that change
// files matching given patterns. Pull requests that change none of them are
// untouched. It is a second ruleset rather than a field on the merge-queue one
// so the whole requirement lives in this one file. Its bypass list IS the
// merge-queue ruleset's (see guardReviewBypassActors).
//
// Why not a required status check (a workflow that looks for James's
// approval): a pull_request, pull_request_review or merge_group run uses the
// pull request's OWN copy of the workflow, so a pull request could edit the
// check to pass itself; and a status can be posted by any App with
// statuses:write (vitruvian-scout-agent has it). A ruleset lives in GitHub and
// changes only when this program is applied, after merge.
//
// Limits, stated honestly:
//   - The approval proves the "ipv1337" account approved, not that James did.
//     Agents sometimes run gh as ipv1337; one doing so could approve.
//   - James cannot approve his own pull request. A protected-path pull request
//     opened as ipv1337 needs his admin bypass (a direct merge, his
//     break-glass), not an approval.
//   - The rest of this Pulumi program (internal/*, go.mod) runs with the same
//     org-admin App token and could in principle undo the ruleset; only the
//     files that declare and wire it are protected, to keep everyday
//     repo-config work autonomous.

// guardApproverLogin is the only member of the reviewer team.
const guardApproverLogin = "ipv1337"

// guardReviewTeamSlug is the team the rule requires an approval from. The rule
// accepts teams only, not users, and counts an approval only from a team with
// write access to the repository.
const guardReviewTeamSlug = "agent-guard-approvers"

// guardReviewPaths are the files whose changes need the team's approval. The
// format is GitHub's: .gitignore style, matched from the repository root.
//
// tools/conformance/check.sh (check_guard_review_paths) reads this list
// between the markers, fails if a pattern stops matching any file (a rename
// would otherwise drop the protection silently), and checks that
// tools/agent-guard/README.md lists each one.
var guardReviewPaths = []string{
	// guard-review-paths:begin
	// agent-guard itself: policy.json decides what is blocked; hook.sh and
	// agent_guard.py are what every checkout runs (from origin/main).
	"tools/agent-guard/**",
	// The hook wiring and the hook scripts the project settings run.
	".claude/settings.json",
	".claude/settings.local.json",
	".claude/*.sh",
	".agents/hooks.json",
	// What .claude/session-start.sh runs from the working copy, with the
	// session's credentials: cloud-bootstrap.sh (a launcher that builds and
	// runs the Rust sources beside it, so those are covered too), the profiles
	// it reads (which secrets each session fetches), and the build-cache
	// configurator it runs.
	"tools/cloud-bootstrap/cloud-bootstrap.sh",
	"tools/cloud-bootstrap/src/cloud_bootstrap/**",
	"tools/cloud-bootstrap/profiles.tsv",
	"tools/remote/setup.sh",
	// This requirement itself: the ruleset and team (this file), where it is
	// wired in and the other ruleset's bypass list (main.go), and the stack
	// it is applied to.
	"infrastructure/pulumi/platform/repo-config/guard_review.go",
	"infrastructure/pulumi/platform/repo-config/main.go",
	"infrastructure/pulumi/platform/repo-config/Pulumi.yaml",
	"infrastructure/pulumi/platform/repo-config/Pulumi.dev.yaml",
	// guard-review-paths:end
}

// guardReviewBypassActors is exactly the merge-queue ruleset's bypass list,
// read from the same function so the two cannot drift apart: repository
// admins and the copybara-sync App, both "always".
//
// It has to match. This ruleset carries a pull_request rule, which makes
// every change to main go through a pull request; a narrower list here would
// newly block the direct pushes the merge-queue ruleset allows them, a change
// for work that has nothing to do with agent-guard. The cost: an admin
// (James's break-glass) or the copybara-sync App merging directly also skips
// James's approval, the same as it skips the queue. A bypass never applies to
// auto-merge into the merge queue, so agents' own Apps get no path through it.
func guardReviewBypassActors() github.RepositoryRulesetBypassActorArray {
	return mergeQueueBypassActors()
}

// guardReviewPullRequestRule is the rule: one approval from the team on any
// pull request touching guardReviewPaths, and a new push dismisses it.
//
// DismissStaleReviewsOnPush applies to every pull request into main (GitHub
// has no per-path version). Other pull requests need no approval, so for them
// it changes only what the review list shows, never whether they can merge.
// RequireLastPushApproval is left off: it does not dismiss an earlier
// approval (the docs say dismissing is the safer setting), and it would stop
// James's own pushes from ever being approvable.
func guardReviewPullRequestRule(teamID pulumi.IntInput) *github.RepositoryRulesetRulesPullRequestArgs {
	return &github.RepositoryRulesetRulesPullRequestArgs{
		RequiredApprovingReviewCount: pulumi.Int(0),
		RequireCodeOwnerReview:       pulumi.Bool(false),
		DismissStaleReviewsOnPush:    pulumi.Bool(true),
		RequireLastPushApproval:      pulumi.Bool(false),
		AllowedMergeMethods:          pulumi.StringArray{pulumi.String("squash")},
		RequiredReviewers: github.RepositoryRulesetRulesPullRequestRequiredReviewerArray{
			&github.RepositoryRulesetRulesPullRequestRequiredReviewerArgs{
				FilePatterns:     pulumi.ToStringArray(guardReviewPaths),
				MinimumApprovals: pulumi.Int(1),
				Reviewer: &github.RepositoryRulesetRulesPullRequestRequiredReviewerReviewerArgs{
					Id:   teamID,
					Type: pulumi.String("Team"),
				},
			},
		},
	}
}

// agentGuardReview declares the reviewer team, its membership and repository
// access, and the ruleset.
func agentGuardReview(ctx *pulumi.Context, repo *github.Repository) error {
	team, err := github.NewTeam(ctx, guardReviewTeamSlug, &github.TeamArgs{
		Name:        pulumi.String(guardReviewTeamSlug),
		Description: pulumi.String("Approves changes to agent-guard's rules (tools/agent-guard and the hook wiring)"),
		Privacy:     pulumi.String("closed"),
	})
	if err != nil {
		return fmt.Errorf("team %q: %w", guardReviewTeamSlug, err)
	}

	membership, err := github.NewTeamMembership(ctx, guardReviewTeamSlug+"-"+guardApproverLogin, &github.TeamMembershipArgs{
		TeamId:   team.ID(),
		Username: pulumi.String(guardApproverLogin),
		Role:     pulumi.String("maintainer"),
	})
	if err != nil {
		return fmt.Errorf("team %q membership: %w", guardReviewTeamSlug, err)
	}

	// The rule counts an approval only from a team with write access.
	access, err := github.NewTeamRepository(ctx, guardReviewTeamSlug+"-repo", &github.TeamRepositoryArgs{
		TeamId:     team.ID(),
		Repository: repo.Name,
		Permission: pulumi.String("push"),
	})
	if err != nil {
		return fmt.Errorf("team %q repo access: %w", guardReviewTeamSlug, err)
	}

	teamID := team.ID().ToStringOutput().ApplyT(func(id string) (int, error) {
		n, err := strconv.Atoi(id)
		if err != nil {
			return 0, fmt.Errorf("team %q has a non-numeric id %q: %w", guardReviewTeamSlug, id, err)
		}
		return n, nil
	}).(pulumi.IntOutput)

	// DependsOn: create the rule only once James is in the team and the team
	// can write, so it is never live with no one able to satisfy it.
	_, err = github.NewRepositoryRuleset(ctx, "agent-guard-review", &github.RepositoryRulesetArgs{
		Name:         pulumi.String("agent-guard-review"),
		Repository:   repo.Name,
		Target:       pulumi.String("branch"),
		Enforcement:  pulumi.String("active"),
		BypassActors: guardReviewBypassActors(),
		Conditions: &github.RepositoryRulesetConditionsArgs{
			RefName: &github.RepositoryRulesetConditionsRefNameArgs{
				Includes: pulumi.StringArray{pulumi.String("~DEFAULT_BRANCH")},
				Excludes: pulumi.StringArray{},
			},
		},
		Rules: &github.RepositoryRulesetRulesArgs{
			PullRequest: guardReviewPullRequestRule(teamID),
		},
	}, pulumi.DependsOn([]pulumi.Resource{membership, access}))
	return err
}

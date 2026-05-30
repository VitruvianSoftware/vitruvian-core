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
// Command repo_config is a standalone Pulumi program that manages THIS generated
// repository's own GitHub settings: auto-deletion of head branches on merge and
// parameterized branch protection on the default branch.
//
// The repository already exists (the developer created it), so this program
// ADOPTS it via pulumi.Import rather than creating it, and uses
// pulumi.IgnoreChanges so Pulumi only manages the handful of attributes it owns
// (DeleteBranchOnMerge) and never clobbers description/visibility/feature flags.
//
// All behaviour is driven by Pulumi config (see README.md). The GitHub provider
// authenticates via the GITHUB_TOKEN environment variable.
//
// Usage:
//
//	cd infrastructure/pulumi/repo_config
//	export GITHUB_TOKEN=<token with repo + admin scope>
//	pulumi config set repoOwner <your-org-or-user>
//	pulumi up --stack dev
package main

import (
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "")

		// repoOwner is the GitHub org or user that owns this repository
		// (required). repoName defaults to this project's kebab-case name but
		// can be overridden if the repository was renamed.
		repoOwner := cfg.Require("repoOwner")
		repoName := repoName(cfg)
		defaultBranch := defaultBranch(cfg)

		// Branch-protection knobs, all config-driven with sane defaults.
		requirePullRequest := requirePullRequest(cfg)
		requiredApprovals := cfg.GetInt("requiredApprovals") // default 0
		requireStatusChecks := requireStatusChecks(cfg)
		// statusCheckContexts is an optional JSON string list. GetObject returns
		// an error when the key is unset; we treat that as "no named contexts".
		var statusCheckContexts []string
		_ = cfg.GetObject("statusCheckContexts", &statusCheckContexts)
		enforceAdmins := cfg.GetBool("enforceAdmins") // default false

		// Adopt the EXISTING repository rather than create it. The import ID is
		// the bare repo name (the GitHub provider derives the owner from the
		// token / provider config). IgnoreChanges keeps Pulumi from touching the
		// attributes the developer owns; we only manage DeleteBranchOnMerge.
		repo, err := github.NewRepository(ctx, repoName, &github.RepositoryArgs{
			Name:                pulumi.String(repoName),
			DeleteBranchOnMerge: pulumi.Bool(true),
		},
			pulumi.Import(pulumi.ID(repoName)),
			pulumi.IgnoreChanges([]string{
				// We manage ONLY DeleteBranchOnMerge; ignore drift on every other
				// attribute so adopting a brownfield repo never clobbers settings
				// the developer owns (homepage, merge buttons, feature flags, the
				// generated-from-template marker, topics, etc.).
				"description",
				"homepageUrl",
				"visibility",
				"hasIssues",
				"hasProjects",
				"hasWiki",
				"hasDownloads",
				"hasDiscussions",
				"isTemplate",
				"template",
				"topics",
				"allowForking",
				"allowMergeCommit",
				"allowSquashMerge",
				"allowRebaseMerge",
				"allowAutoMerge",
				"mergeCommitTitle",
				"mergeCommitMessage",
				"squashMergeCommitTitle",
				"squashMergeCommitMessage",
				"vulnerabilityAlerts",
				"securityAndAnalysis",
				"pages",
				"name",
			}),
		)
		if err != nil {
			return err
		}

		// Assemble the branch-protection args from config. Only attach the PR
		// review / status check blocks when their respective toggles are on.
		protectionArgs := &github.BranchProtectionArgs{
			RepositoryId:      repo.NodeId,
			Pattern:           pulumi.String(defaultBranch),
			EnforceAdmins:     pulumi.Bool(enforceAdmins),
			AllowsForcePushes: pulumi.Bool(false),
			AllowsDeletions:   pulumi.Bool(false),
		}

		if requirePullRequest {
			protectionArgs.RequiredPullRequestReviews = github.BranchProtectionRequiredPullRequestReviewArray{
				&github.BranchProtectionRequiredPullRequestReviewArgs{
					RequiredApprovingReviewCount: pulumi.Int(requiredApprovals),
				},
			}
		}

		if requireStatusChecks {
			statusCheck := &github.BranchProtectionRequiredStatusCheckArgs{
				Strict: pulumi.Bool(true),
			}
			if len(statusCheckContexts) > 0 {
				statusCheck.Contexts = pulumi.ToStringArray(statusCheckContexts)
			}
			protectionArgs.RequiredStatusChecks = github.BranchProtectionRequiredStatusCheckArray{
				statusCheck,
			}
		}

		_, err = github.NewBranchProtection(ctx, repoName+"-default-protection", protectionArgs)
		if err != nil {
			return err
		}

		// Surface the resolved owner so `pulumi stack output` records which
		// account these settings were applied to.
		ctx.Export("repoOwner", pulumi.String(repoOwner))
		ctx.Export("repoName", repo.Name)
		ctx.Export("defaultBranch", pulumi.String(defaultBranch))

		return nil
	})
}

// repoName returns the configured repo name, defaulting to this project's
// kebab-case name.
func repoName(cfg *config.Config) string {
	if v := cfg.Get("repoName"); v != "" {
		return v
	}
	return "vitruvian-core"
}

// defaultBranch returns the configured default branch, defaulting to "main".
func defaultBranch(cfg *config.Config) string {
	if v := cfg.Get("defaultBranch"); v != "" {
		return v
	}
	return "main"
}

// requirePullRequest defaults to true when unset.
func requirePullRequest(cfg *config.Config) bool {
	if v, err := cfg.TryBool("requirePullRequest"); err == nil {
		return v
	}
	return true
}

// requireStatusChecks defaults to true when unset.
func requireStatusChecks(cfg *config.Config) bool {
	if v, err := cfg.TryBool("requireStatusChecks"); err == nil {
		return v
	}
	return true
}

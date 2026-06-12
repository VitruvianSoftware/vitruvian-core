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
	"fmt"
	"sort"
	"strconv"

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

		if err := tabulaEnvironments(ctx, cfg, repo); err != nil {
			return err
		}

		if err := dependabotSecrets(ctx, cfg, repo); err != nil {
			return err
		}

		if err := dependabotLabels(ctx, repo); err != nil {
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

// tabulaEnvironments manages the per-component GitHub Environments for the
// tabula deploy pipeline (.github/workflows/tabula-deploy.yaml). The
// environment name carries the component namespace (tabula-<env>), so the
// variables inside use bare names (GCP_PROJECT_ID, ...) and protection rules
// are scoped to tabula alone — a future component's production gate never
// shares reviewers with this one.
//
// Only non-credential identifiers live here as Actions VARIABLES (project id,
// service-account email, workload-identity provider path — keyless WIF needs
// no key material). Runtime secrets such as DATABASE_URL stay in GCP Secret
// Manager, managed by //infrastructure/pulumi/tabula; the only GitHub-side
// secret the deploy needs is the repo-level PULUMI_ACCESS_TOKEN.
//
// Per-environment variable values come from Pulumi config as JSON objects
// (committed in Pulumi.<stack>.yaml — they are identifiers, not secrets):
//
//	pulumi config set --path 'tabulaVars["development"]' \
//	  '{"GCP_PROJECT_ID":"...","GCP_SERVICE_ACCOUNT":"...","GCP_WORKLOAD_IDENTITY_PROVIDER":"..."}'
//
// Environments with no config entry are still created (empty), so protection
// rules exist before the first deploy is wired up.
func tabulaEnvironments(ctx *pulumi.Context, cfg *config.Config, repo *github.Repository) error {
	var tabulaVars map[string]map[string]string
	_ = cfg.GetObject("tabulaVars", &tabulaVars)

	for _, env := range []string{"development", "nonproduction", "production"} {
		name := "tabula-" + env

		args := &github.RepositoryEnvironmentArgs{
			Repository:  repo.Name,
			Environment: pulumi.String(name),
		}

		if env == "production" {
			// Production deploys only from protected branches (main) and
			// require an approval from the repo owner (or the configured
			// reviewer ids). GitHub allows self-approval of deployments, so
			// this works for a single-maintainer repo as a deliberate
			// "break glass" pause rather than a four-eyes gate.
			args.DeploymentBranchPolicy = &github.RepositoryEnvironmentDeploymentBranchPolicyArgs{
				ProtectedBranches:    pulumi.Bool(true),
				CustomBranchPolicies: pulumi.Bool(false),
			}
			reviewerIds, err := productionReviewerIds(ctx, cfg)
			if err != nil {
				return err
			}
			args.Reviewers = github.RepositoryEnvironmentReviewerArray{
				&github.RepositoryEnvironmentReviewerArgs{
					Users: pulumi.ToIntArray(reviewerIds),
				},
			}
		}

		envRes, err := github.NewRepositoryEnvironment(ctx, name, args)
		if err != nil {
			return err
		}

		// Deterministic resource names: iterate variables in sorted order.
		vars := tabulaVars[env]
		keys := make([]string, 0, len(vars))
		for k := range vars {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			_, err := github.NewActionsEnvironmentVariable(ctx, fmt.Sprintf("%s-%s", name, k), &github.ActionsEnvironmentVariableArgs{
				Repository:   repo.Name,
				Environment:  envRes.Environment,
				VariableName: pulumi.String(k),
				Value:        pulumi.String(vars[k]),
			})
			if err != nil {
				return err
			}
		}
	}
	return nil
}

// dependabotSecrets mirrors the Actions secrets that Dependabot-triggered CI
// runs need into the repository's *Dependabot* secret store.
//
// GitHub deliberately does NOT expose regular Actions secrets to workflows
// triggered by Dependabot PRs (they run with a restricted token and a separate
// secrets scope). The build-test job authenticates to BuildBuddy RBE with
// `--remote_header=x-buildbuddy-api-key=$BUILDBUDDY_API_KEY`; on a Dependabot PR
// that secret is empty, so every remote action fails with UNAUTHENTICATED and
// build-test goes red even though the dependency bump is fine. Declaring the
// key as a Dependabot secret lets those runs use RBE like any other PR.
//
// The value is a Pulumi config SECRET, never committed in plaintext:
//
//	pulumi config set --secret buildbuddyApiKey <key> --stack dev
//
// It is intentionally optional: when unset the secret is simply not managed, so
// the program (and its auto-apply on merge) stays green until the key is wired
// up — the same defensive pattern as tabulaVars.
func dependabotSecrets(ctx *pulumi.Context, cfg *config.Config, repo *github.Repository) error {
	if cfg.Get("buildbuddyApiKey") == "" {
		return nil
	}
	_, err := github.NewDependabotSecret(ctx, "buildbuddy-api-key-dependabot", &github.DependabotSecretArgs{
		Repository:     repo.Name,
		SecretName:     pulumi.String("BUILDBUDDY_API_KEY"),
		PlaintextValue: cfg.RequireSecret("buildbuddyApiKey"),
	})
	return err
}

// dependabotLabels creates the issue labels that .github/dependabot.yml applies
// to dependency PRs (gomod -> "dependencies","go"; github-actions ->
// "dependencies","ci"). Dependabot does not create missing labels itself — it
// posts a "The following labels could not be found" warning and skips them — so
// they must already exist in the repo. Managed here as code alongside the rest
// of the repository configuration.
func dependabotLabels(ctx *pulumi.Context, repo *github.Repository) error {
	labels := []struct{ name, color, description string }{
		{"dependencies", "0366d6", "Dependency updates (Dependabot)"},
		{"go", "00add8", "Go (gomod) ecosystem"},
		{"ci", "fbca04", "CI / GitHub Actions"},
	}
	for _, l := range labels {
		if _, err := github.NewIssueLabel(ctx, "label-"+l.name, &github.IssueLabelArgs{
			Repository:  repo.Name,
			Name:        pulumi.String(l.name),
			Color:       pulumi.String(l.color),
			Description: pulumi.String(l.description),
		}); err != nil {
			return err
		}
	}
	return nil
}

// productionReviewerIds returns the numeric GitHub user ids that must approve
// tabula-production deployments. Resolution order:
//
//  1. `tabulaProductionReviewerIds` (numeric ids, used verbatim);
//  2. `tabulaProductionReviewers` (usernames, resolved via GET /users/{login}
//     — this also works for the Actions GITHUB_TOKEN, which is an integration
//     token; this is the form committed in Pulumi.<stack>.yaml);
//  3. the authenticated user — convenient for ad-hoc human runs, but GET
//     /user returns 403 for integration tokens, hence the config options.
func productionReviewerIds(ctx *pulumi.Context, cfg *config.Config) ([]int, error) {
	var ids []int
	_ = cfg.GetObject("tabulaProductionReviewerIds", &ids)
	if len(ids) > 0 {
		return ids, nil
	}

	var usernames []string
	_ = cfg.GetObject("tabulaProductionReviewers", &usernames)
	for _, username := range usernames {
		user, err := github.GetUser(ctx, &github.GetUserArgs{Username: username})
		if err != nil {
			return nil, fmt.Errorf("resolving production reviewer %q: %w", username, err)
		}
		id, err := strconv.Atoi(user.Id)
		if err != nil {
			return nil, fmt.Errorf("unexpected non-numeric user id %q for %q: %w", user.Id, username, err)
		}
		ids = append(ids, id)
	}
	if len(ids) > 0 {
		return ids, nil
	}

	me, err := github.GetUser(ctx, &github.GetUserArgs{Username: ""})
	if err != nil {
		return nil, fmt.Errorf(
			"resolving authenticated user for production reviewers (integration tokens cannot call GET /user; set tabulaProductionReviewers in the stack config): %w", err)
	}
	id, err := strconv.Atoi(me.Id)
	if err != nil {
		return nil, fmt.Errorf("unexpected non-numeric user id %q: %w", me.Id, err)
	}
	return []int{id}, nil
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

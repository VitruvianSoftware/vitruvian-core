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
//	cd infrastructure/pulumi/platform/repo_config
//	export GITHUB_TOKEN=<token with repo + admin scope>
//	pulumi config set repoOwner <your-org-or-user>
//	pulumi up --stack dev
package main

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/pkg/secrets"
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
		repo, err := github.NewRepository(
			ctx, repoName, &github.RepositoryArgs{
				Name:                pulumi.String(repoName),
				DeleteBranchOnMerge: pulumi.Bool(true),
				// Required by the merge-queue ruleset (#83): GitHub adds PRs to the
				// merge queue via the auto-merge mechanism, so "Allow auto-merge"
				// must be enabled for the queue to function.
				AllowAutoMerge: pulumi.Bool(true),
			},
			pulumi.Import(pulumi.ID(repoName)),
			pulumi.IgnoreChanges([]string{
				// We manage DeleteBranchOnMerge + AllowAutoMerge; ignore drift on every other
				// attribute so adopting a brownfield repo never clobbers settings
				// the developer owns (homepage, merge buttons, feature flags, the
				// generated-from-template marker, topics, etc.).
				"description",
				"homepageUrl",
				"visibility",
				"hasIssues",
				"hasProjects",
				"hasWiki",
				// hasDownloads stays ignored: the GitHub provider deprecated it, but
				// dropping it from this list makes Pulumi want to TOGGLE the repo's
				// (defunct) hasDownloads setting (preview: `- hasDownloads: true`),
				// which is exactly the brownfield clobber this list prevents. The
				// cosmetic deprecation warning on preview is the lesser evil.
				"hasDownloads",
				"hasDiscussions",
				"isTemplate",
				"template",
				"topics",
				"allowForking",
				"allowMergeCommit",
				"allowSquashMerge",
				"allowRebaseMerge",
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

		// Merge queue (#83): serialize merges into the default branch through a
		// GitHub merge queue, configured as a repository RULESET (the modern,
		// API-managed mechanism; classic branch protection cannot express a
		// merge queue). For each group GitHub builds the would-be-merged commit,
		// runs the required CI checks on it, and only fast-forwards the branch
		// when they pass -- the trunk-based postsubmit gate from the scaling
		// roadmap. The jobs in .github/workflows/ci.yaml now also run on the
		// `merge_group` event so the queue has checks to wait on.
		if mergeQueueEnabled(cfg) {
			// Required checks default to the merge-queue gate set — the job names
			// across ci.yaml (build-test, build-macos, license-check, go-lint,
			// go-test, validate-butane), tidy-check.yaml and conformance-check.yaml.
			// Each of those workflows triggers on the `merge_group` event so the
			// queue has a result to wait on. The go-lint/go-test jobs are matrix'd
			// over the standalone-mirror modules, so their check contexts are the
			// per-matrix names ("go-lint (devx)", …), not the bare job name —
			// listing the bare name would never report and wedge the queue pending.
			// go-lint/go-test/validate-butane were added when the monorepo became
			// the single CI authority and the per-app mirror CI was retired; they
			// ran on every PR but were never in the gate set, so a lint/race/Butane
			// regression could still merge. Override via the
			// `mergeQueueRequiredChecks` JSON-list config.
			//
			// GUARDED: `bazel run //tools/conformance:check` (#458) asserts every
			// name here is produced by a job that runs on the `merge_group` event —
			// so a rename on either side can't silently wedge the queue "pending".
			var checks []string
			_ = cfg.GetObject("mergeQueueRequiredChecks", &checks)
			if len(checks) == 0 {
				checks = []string{
					"build-test", "build-macos", "license-check", "tidy-check", "conformance-check",
					"go-lint (devx)", "go-lint (homelab)", "go-test (devx)", "go-test (homelab)", "validate-butane",
					// gitops-validate (kubeconform over gitops/**, which reconciles to
					// the LIVE cluster) and actionlint (workflow lint) now also trigger
					// on merge_group, so they gate the queue instead of only advising on
					// PRs. Both validate their whole dir on every queued commit, so they
					// always report — safe to require.
					"gitops-validate", "actionlint",
				}
			}
			requiredChecks := github.RepositoryRulesetRulesRequiredStatusChecksRequiredCheckArray{}
			for _, c := range checks {
				requiredChecks = append(requiredChecks, &github.RepositoryRulesetRulesRequiredStatusChecksRequiredCheckArgs{
					Context: pulumi.String(c),
				})
			}

			if _, err := github.NewRepositoryRuleset(ctx, repoName+"-merge-queue", &github.RepositoryRulesetArgs{
				Name:        pulumi.String("merge-queue"),
				Repository:  repo.Name,
				Target:      pulumi.String("branch"),
				Enforcement: pulumi.String("active"),
				// Let repository admins bypass the queue as a break-glass valve,
				// so a single maintainer can never be fully locked out of main.
				// RepositoryRole actor id 5 == "admin".
				BypassActors: github.RepositoryRulesetBypassActorArray{
					&github.RepositoryRulesetBypassActorArgs{
						ActorId:    pulumi.Int(5),
						ActorType:  pulumi.String("RepositoryRole"),
						BypassMode: pulumi.String("always"),
					},
				},
				Conditions: &github.RepositoryRulesetConditionsArgs{
					RefName: &github.RepositoryRulesetConditionsRefNameArgs{
						// ~DEFAULT_BRANCH tracks the default branch even if it is
						// renamed later.
						Includes: pulumi.StringArray{pulumi.String("~DEFAULT_BRANCH")},
						Excludes: pulumi.StringArray{},
					},
				},
				Rules: &github.RepositoryRulesetRulesArgs{
					MergeQueue: &github.RepositoryRulesetRulesMergeQueueArgs{
						MergeMethod:                  pulumi.String("SQUASH"),
						GroupingStrategy:             pulumi.String("ALLGREEN"),
						CheckResponseTimeoutMinutes:  pulumi.Int(60),
						MinEntriesToMerge:            pulumi.Int(1),
						MinEntriesToMergeWaitMinutes: pulumi.Int(5),
						MaxEntriesToBuild:            pulumi.Int(5),
						MaxEntriesToMerge:            pulumi.Int(5),
					},
					// Checks the queue must see green before merging a group.
					// strict_policy=false: the queue rebases each entry onto the
					// latest base itself, so "require branches up to date" is
					// both redundant and incompatible with a merge queue.
					RequiredStatusChecks: &github.RepositoryRulesetRulesRequiredStatusChecksArgs{
						RequiredChecks:                   requiredChecks,
						StrictRequiredStatusChecksPolicy: pulumi.Bool(false),
					},
				},
			}); err != nil {
				return err
			}
		}

		if err := tabulaEnvironments(ctx, cfg, repo); err != nil {
			return err
		}

		if err := oauthEnvironment(ctx, cfg, repo); err != nil {
			return err
		}

		if err := foundationEnvironments(ctx, cfg, repo); err != nil {
			return err
		}

		if err := pipelineGates(ctx, cfg, repo); err != nil {
			return err
		}

		if err := dependabotSecrets(ctx, cfg, repo); err != nil {
			return err
		}

		if err := dependabotLabels(ctx, repo); err != nil {
			return err
		}

		if err := manageTeams(ctx, repo, repoName); err != nil {
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
// Manager, managed by //infrastructure/pulumi/apps/tabula; the only GitHub-side
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

// oauthEnvironment manages the GitHub Environment + repo-level gate for the
// oauth-user-inspector deploy pipeline (.github/workflows/oauth-user-inspector-
// deploy.yaml).
//
// As in tabulaEnvironments, only NON-credential identifiers live here as Actions
// VARIABLES — the deploy authenticates to GCP with keyless WIF, so project id,
// region, deploy SA, and the WIF provider path are config-as-code, not secrets.
//
// The deploy's GitHub-side SECRETS (ZITADEL_MACHINE_KEY_JSON and the Tailscale
// on-ramp TS_OAUTH_CLIENT_ID/TS_OAUTH_SECRET) are deliberately NOT managed here.
// repo_config is applied by BOTH a maintainer locally and CI (_repo-config-
// apply.yaml) against one shared Pulumi state; a secret whose value lived only in
// a gitignored local file would be set by the local apply but, absent in CI,
// DELETED by the next CI apply. Those secrets are synced from a gitignored,
// Bitwarden-backed store by //tools/sync-env-secrets instead (§2.4, §2.18).
//
// These resources were created out-of-band during bring-up, so each is ADOPTED
// via pulumi.Import. The provider's variable Create is a create-only POST that
// 409s when the name already exists, so declare-and-overwrite is unsafe — import
// is mandatory for the variables (and clean for the environment).
//
// Variable values are committed config (identifiers, not secrets):
//
//	pulumi config set --path 'oauthVars["GCP_PROJECT_ID"]' '<value>' --stack dev
func oauthEnvironment(ctx *pulumi.Context, cfg *config.Config, repo *github.Repository) error {
	nm := repoName(cfg)

	// Repo-level gate the zitadel-infra job reads to decide whether to apply the
	// Zitadel application stack. It must be repo-scoped: a job-level `if:` cannot
	// see an environment-scoped variable.
	if _, err := github.NewActionsVariable(ctx, "zitadel-apps-auto-apply", &github.ActionsVariableArgs{
		Repository:   repo.Name,
		VariableName: pulumi.String("ZITADEL_APPS_AUTO_APPLY"),
		Value:        pulumi.String("true"),
	}, pulumi.Import(pulumi.ID(nm+":ZITADEL_APPS_AUTO_APPLY"))); err != nil {
		return err
	}

	const envName = "oauth-user-inspector-development"
	envRes, err := github.NewRepositoryEnvironment(ctx, envName, &github.RepositoryEnvironmentArgs{
		Repository:  repo.Name,
		Environment: pulumi.String(envName),
	}, pulumi.Import(pulumi.ID(nm+":"+envName)))
	if err != nil {
		return err
	}

	var oauthVars map[string]string
	_ = cfg.GetObject("oauthVars", &oauthVars)

	// Deterministic resource names: iterate variables in sorted order.
	keys := make([]string, 0, len(oauthVars))
	for k := range oauthVars {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if _, err := github.NewActionsEnvironmentVariable(ctx, fmt.Sprintf("%s-%s", envName, k), &github.ActionsEnvironmentVariableArgs{
			Repository:   repo.Name,
			Environment:  envRes.Environment,
			VariableName: pulumi.String(k),
			Value:        pulumi.String(oauthVars[k]),
		}, pulumi.Import(pulumi.ID(fmt.Sprintf("%s:%s:%s", nm, envName, k)))); err != nil {
			return err
		}
	}
	return nil
}

// foundationEnvironments manages the highly privileged GitHub Environments
// used by the foundation IaC pipelines. These map to the per-stage Workload
// Identity Federation (WIF) service accounts provisioned by gcp-bootstrap.
//
// Like tabulaEnvironments, only non-credential identifiers live here as
// Actions VARIABLES (GCP_PROJECT_ID, GCP_SERVICE_ACCOUNT, GCP_WORKLOAD_IDENTITY_PROVIDER).
//
//	pulumi config set --path 'foundationVars["foundation-bootstrap"]' \
//	  '{"GCP_SERVICE_ACCOUNT":"...","GCP_WORKLOAD_IDENTITY_PROVIDER":"..."}'
func foundationEnvironments(ctx *pulumi.Context, cfg *config.Config, repo *github.Repository) error {
	var foundationVars map[string]map[string]string
	_ = cfg.GetObject("foundationVars", &foundationVars)

	for _, env := range []string{"foundation-bootstrap", "foundation-org", "foundation-org-folders"} {
		args := &github.RepositoryEnvironmentArgs{
			Repository:  repo.Name,
			Environment: pulumi.String(env),
		}

		// Foundation deploys only from protected branches (main) and require
		// an approval from the repo owner (or the configured reviewer ids),
		// similar to tabula-production.
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

		envRes, err := github.NewRepositoryEnvironment(ctx, env, args)
		if err != nil {
			return err
		}

		// Preview environment for PRs (no branch policy or reviewers required)
		previewEnv := env + "-preview"
		previewEnvRes, err := github.NewRepositoryEnvironment(ctx, previewEnv, &github.RepositoryEnvironmentArgs{
			Repository:  repo.Name,
			Environment: pulumi.String(previewEnv),
		})
		if err != nil {
			return err
		}

		// Deterministic resource names: iterate variables in sorted order.
		vars := foundationVars[env]
		keys := make([]string, 0, len(vars))
		for k := range vars {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			_, err := github.NewActionsEnvironmentVariable(ctx, fmt.Sprintf("%s-%s", env, k), &github.ActionsEnvironmentVariableArgs{
				Repository:   repo.Name,
				Environment:  envRes.Environment,
				VariableName: pulumi.String(k),
				Value:        pulumi.String(vars[k]),
			})
			if err != nil {
				return err
			}

			_, err = github.NewActionsEnvironmentVariable(ctx, fmt.Sprintf("%s-%s", previewEnv, k), &github.ActionsEnvironmentVariableArgs{
				Repository:   repo.Name,
				Environment:  previewEnvRes.Environment,
				VariableName: pulumi.String(k),
				Value:        pulumi.String(vars[k]),
			})
			if err != nil {
				return err
			}
		}
	}

	// ── Phase 2: Environments promotion environments ──────────────────────
	// The environments stage uses a chained promotion workflow where each
	// environment is a separate Pulumi stack deployed via the reusable
	// foundation-env-deploy.yaml workflow:
	//
	//   foundation-env-development  → auto-deploy (no reviewers)
	//   foundation-env-nonproduction → manual approval (requires reviewers)
	//   foundation-env-production    → manual approval (requires reviewers)
	//
	// All three share the same WIF credentials as the foundation-org stage
	// (the environments SA has equivalent org-level permissions).
	envPhaseEnvironments := []struct {
		name            string
		requireReviewer bool
	}{
		{"foundation-env-development", false},
		{"foundation-env-nonproduction", true},
		{"foundation-env-production", true},
	}

	for _, envDef := range envPhaseEnvironments {
		args := &github.RepositoryEnvironmentArgs{
			Repository:  repo.Name,
			Environment: pulumi.String(envDef.name),
		}

		args.DeploymentBranchPolicy = &github.RepositoryEnvironmentDeploymentBranchPolicyArgs{
			ProtectedBranches:    pulumi.Bool(true),
			CustomBranchPolicies: pulumi.Bool(false),
		}

		if envDef.requireReviewer {
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

		envRes, err := github.NewRepositoryEnvironment(ctx, envDef.name, args)
		if err != nil {
			return err
		}

		// Propagate foundation WIF variables to the environment so the
		// reusable deploy workflow resolves ${{ vars.GCP_* }} correctly.
		// Uses the env SA (sa-terraform-env), not the org SA.
		envVars := foundationVars["foundation-env"]
		varKeys := make([]string, 0, len(envVars))
		for k := range envVars {
			varKeys = append(varKeys, k)
		}
		sort.Strings(varKeys)
		for _, k := range varKeys {
			_, err := github.NewActionsEnvironmentVariable(ctx, fmt.Sprintf("%s-%s", envDef.name, k), &github.ActionsEnvironmentVariableArgs{
				Repository:   repo.Name,
				Environment:  envRes.Environment,
				VariableName: pulumi.String(k),
				Value:        pulumi.String(envVars[k]),
			})
			if err != nil {
				return err
			}
		}
	}

	// ── Phase 3: Networks promotion environments ──────────────────────────
	// The networks stage uses a chained promotion workflow where each
	// environment is a separate Pulumi stack deployed via the reusable
	// foundation-net-deploy.yaml workflow:
	//
	//   foundation-net-development  → auto-deploy (no reviewers)
	//   foundation-net-nonproduction → manual approval (requires reviewers)
	//   foundation-net-production    → manual approval (requires reviewers)
	//
	// All three share the same WIF credentials as the foundation-net stage
	// (the networks SA has equivalent org-level permissions).
	netPhaseEnvironments := []struct {
		name            string
		requireReviewer bool
	}{
		{"foundation-net-development", false},
		{"foundation-net-nonproduction", true},
		{"foundation-net-production", true},
	}

	for _, envDef := range netPhaseEnvironments {
		args := &github.RepositoryEnvironmentArgs{
			Repository:  repo.Name,
			Environment: pulumi.String(envDef.name),
		}

		args.DeploymentBranchPolicy = &github.RepositoryEnvironmentDeploymentBranchPolicyArgs{
			ProtectedBranches:    pulumi.Bool(true),
			CustomBranchPolicies: pulumi.Bool(false),
		}

		if envDef.requireReviewer {
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

		envRes, err := github.NewRepositoryEnvironment(ctx, envDef.name, args)
		if err != nil {
			return err
		}

		// Propagate foundation WIF variables to the environment so the
		// reusable deploy workflow resolves ${{ vars.GCP_* }} correctly.
		// Uses the net SA (sa-terraform-net), not the org SA.
		envVars := foundationVars["foundation-net"]
		varKeys := make([]string, 0, len(envVars))
		for k := range envVars {
			varKeys = append(varKeys, k)
		}
		sort.Strings(varKeys)
		for _, k := range varKeys {
			_, err := github.NewActionsEnvironmentVariable(ctx, fmt.Sprintf("%s-%s", envDef.name, k), &github.ActionsEnvironmentVariableArgs{
				Repository:   repo.Name,
				Environment:  envRes.Environment,
				VariableName: pulumi.String(k),
				Value:        pulumi.String(envVars[k]),
			})
			if err != nil {
				return err
			}
		}
	}

	// ── Preview environments for the env & net promotion stages ───────────
	// The environments and networks stages are previewed on PRs by
	// .github/workflows/foundation-preview.yaml (the `development` stack of
	// each). Their DEPLOY environments (foundation-{env,net}-<stage>) are gated
	// to protected branches, so — like the Phase-1 stages above — the PR preview
	// needs a dedicated, UNGATED environment (no branch policy, no reviewers).
	//
	// Each preview env reuses its stage's WIF variables/SA (foundation-env uses
	// sa-terraform-env, foundation-net uses sa-terraform-net). The matching WIF
	// principalSet already exists: gcp-bootstrap's generic per-stage binding
	// grants attribute.environment/foundation-<stage>-preview for every stage SA,
	// so no gcp-bootstrap change is needed. PULUMI_ACCESS_TOKEN is repo-level
	// (see tabulaEnvironments), so only the GCP_* variables are set here.
	for _, stage := range []string{"foundation-env", "foundation-net"} {
		previewEnv := stage + "-preview"
		previewEnvRes, err := github.NewRepositoryEnvironment(ctx, previewEnv, &github.RepositoryEnvironmentArgs{
			Repository:  repo.Name,
			Environment: pulumi.String(previewEnv),
		})
		if err != nil {
			return err
		}

		// Deterministic resource names: iterate variables in sorted order.
		vars := foundationVars[stage]
		keys := make([]string, 0, len(vars))
		for k := range vars {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			_, err := github.NewActionsEnvironmentVariable(ctx, fmt.Sprintf("%s-%s", previewEnv, k), &github.ActionsEnvironmentVariableArgs{
				Repository:   repo.Name,
				Environment:  previewEnvRes.Environment,
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

// pipelineGates codifies the repo-level Actions variables that gate the IaC
// pipeline workflows (#499). These were previously hand-set (or absent), which
// violated the everything-as-code rule for governance state: a variable that
// exists only in the GitHub UI can drift, and a local hand-apply of the very
// stacks these gates control is exactly the out-of-band mutation #499 exists
// to eliminate.
//
//	REPO_CONFIG_AUTO_APPLY      _repo-config-apply.yaml applies repo_config on
//	                            merge (CI is the sole steady-state writer).
//	REPO_CONFIG_PREVIEW_ENABLED _repo-config-preview.yaml posts the diff on PRs.
//	SYNC_AUTH_AUTO_APPLY        copybara-sync-auth-apply.yaml applies on merge
//	                            (was OFF: sync-auth previously required a local
//	                            hand-apply after every change).
//	PULUMI_PREVIEW_ENABLED      pulumi-preview.yaml posts advisory app-stack
//	                            previews (tabula / oauth-user-inspector) on PRs.
//
// The first two variables already exist (hand-set) and use the mandatory
// import-then-manage pattern (the provider's variable Create is a create-only
// POST that 409s on an existing name); the last two are created fresh.
//
// Values default to "true" (the #499 steady state: CI is the sole writer) but
// each can be overridden AS CODE via the optional `pipelineGates` config map,
// so a deliberate opt-out survives every future apply instead of being
// silently clobbered back to "true":
//
//	pulumi config set --path 'pipelineGates["REPO_CONFIG_AUTO_APPLY"]' false --stack dev
func pipelineGates(ctx *pulumi.Context, cfg *config.Config, repo *github.Repository) error {
	nm := repoName(cfg)

	imported := map[string]bool{
		"REPO_CONFIG_AUTO_APPLY":      true,
		"REPO_CONFIG_PREVIEW_ENABLED": true,
		"SYNC_AUTH_AUTO_APPLY":        false,
		"PULUMI_PREVIEW_ENABLED":      false,
	}
	var overrides map[string]string
	_ = cfg.GetObject("pipelineGates", &overrides)

	// Deterministic resource names: iterate in sorted order.
	names := make([]string, 0, len(imported))
	for k := range imported {
		names = append(names, k)
	}
	sort.Strings(names)
	for _, name := range names {
		value := "true"
		if v, ok := overrides[name]; ok && v != "" {
			value = v
		}
		opts := []pulumi.ResourceOption{}
		if imported[name] {
			opts = append(opts, pulumi.Import(pulumi.ID(nm+":"+name)))
		}
		resName := "pipeline-gate-" + strings.ToLower(strings.ReplaceAll(name, "_", "-"))
		if _, err := github.NewActionsVariable(ctx, resName, &github.ActionsVariableArgs{
			Repository:   repo.Name,
			VariableName: pulumi.String(name),
			Value:        pulumi.String(value),
		}, opts...); err != nil {
			return err
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
	// Resolve the BuildBuddy API key WITHOUT committing it to git (issue #456 /
	// secrets-model §2.4): CI injects it as the BUILDBUDDY_API_KEY env var (the
	// same value CI already uses for RBE); a local run falls back to a gitignored
	// `pulumi config set --secret buildbuddyApiKey`. The optional variant returns
	// nil when neither is set, so the Dependabot secret is simply not managed and
	// the auto-apply stays green until the key is wired — the prior behavior.
	// NB: rotating the actual key is a separate BuildBuddy-console action
	// (bazel run //tools/rotate-buildbuddy-key); this only routes WHERE the value
	// comes from through the shared pkg/secrets helper (never git).
	key := secrets.EnvOrConfigOptional(cfg, "BUILDBUDDY_API_KEY", "buildbuddyApiKey")
	if key == nil {
		return nil
	}
	_, err := github.NewDependabotSecret(ctx, "buildbuddy-api-key-dependabot", &github.DependabotSecretArgs{
		Repository:     repo.Name,
		SecretName:     pulumi.String("BUILDBUDDY_API_KEY"),
		PlaintextValue: key,
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

// manageTeams codifies the per-app + platform GitHub teams that CODEOWNERS
// routes review to (issue #460). The teams were created in the org and granted
// repo push access out-of-band, so they are ADOPTED here via pulumi.Import
// (import id = the numeric team id) rather than created — a re-create would 409.
// Each team seeds @ipv1337 as its sole maintainer today; ".github/CODEOWNERS"
// routes review to these teams but does NOT require code-owner review (a solo
// owner cannot approve their own PR), so this changes routing, not the gate.
func manageTeams(ctx *pulumi.Context, repo *github.Repository, repoName string) error {
	type teamDef struct {
		slug string
		id   string
		desc string
	}
	// slug + numeric team id (from the org) + description (matches what was set
	// at creation, so the import shows no drift).
	teams := []teamDef{
		{"platform-team", "18289391", "Platform, build, and infrastructure team"},
		{"devx-team", "18289393", "devx CLI team"},
		{"homelab-team", "18289394", "homelab CLI + k8s apps team"},
		{"mcp-slack-team", "18289395", "mcp-slack MCP server team"},
		{"nexus-agent-team", "18289397", "nexus-agent bot + macOS app team"},
		{"tabula-team", "18289399", "tabula SaaS team"},
		{"oauth-user-inspector-team", "18289401", "oauth-user-inspector SaaS team"},
	}
	for _, t := range teams {
		team, err := github.NewTeam(ctx, t.slug, &github.TeamArgs{
			Name:        pulumi.String(t.slug),
			Description: pulumi.String(t.desc),
			Privacy:     pulumi.String("closed"),
		}, pulumi.Import(pulumi.ID(t.id)))
		if err != nil {
			return fmt.Errorf("team %q: %w", t.slug, err)
		}

		// @ipv1337 is the single member today (maintainer).
		if _, err := github.NewTeamMembership(ctx, t.slug+"-ipv1337", &github.TeamMembershipArgs{
			TeamId:   team.ID(),
			Username: pulumi.String("ipv1337"),
			Role:     pulumi.String("maintainer"),
		}, pulumi.Import(pulumi.ID(t.id+":ipv1337"))); err != nil {
			return fmt.Errorf("team %q membership: %w", t.slug, err)
		}

		// Push access — CODEOWNERS only accepts a team that can write the repo.
		if _, err := github.NewTeamRepository(ctx, t.slug+"-repo", &github.TeamRepositoryArgs{
			TeamId:     team.ID(),
			Repository: repo.Name,
			Permission: pulumi.String("push"),
		}, pulumi.Import(pulumi.ID(t.id+":"+repoName))); err != nil {
			return fmt.Errorf("team %q repo access: %w", t.slug, err)
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
			"resolving authenticated user for production reviewers (integration tokens cannot call GET /user; set tabulaProductionReviewers in the stack config): %w", err,
		)
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

// mergeQueueEnabled defaults to true: the merge queue is the trunk-based
// postsubmit gate (#83). Set `mergeQueue: "false"` in the stack config to
// disable it (e.g. to fall back to direct pushes during a migration).
func mergeQueueEnabled(cfg *config.Config) bool {
	if v, err := cfg.TryBool("mergeQueue"); err == nil {
		return v
	}
	return true
}

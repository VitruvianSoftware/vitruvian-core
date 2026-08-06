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
		requirePullRequest, err := requirePullRequest(cfg)
		if err != nil {
			return err
		}
		requiredApprovals := cfg.GetInt("requiredApprovals") // default 0
		requireStatusChecks, err := requireStatusChecks(cfg)
		if err != nil {
			return err
		}
		// statusCheckContexts is an optional JSON string list. GetObject returns
		// an error when the key is unset; we treat that as "no named contexts".
		var statusCheckContexts []string
		_ = cfg.GetObject("statusCheckContexts", &statusCheckContexts)
		enforceAdmins, err := boolConfig(cfg, "enforceAdmins", false) // default false
		if err != nil {
			return err
		}

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
				// Governance (#803): enable secret scanning + push protection as code
				// (both free on public repos). advanced_security is intentionally
				// omitted -- GitHub Advanced Security is not applicable to public
				// repos. Removed from IgnoreChanges below so Pulumi manages exactly
				// these two settings and nothing else the developer owns.
				SecurityAndAnalysis: &github.RepositorySecurityAndAnalysisArgs{
					SecretScanning: &github.RepositorySecurityAndAnalysisSecretScanningArgs{
						Status: pulumi.String("enabled"),
					},
					SecretScanningPushProtection: &github.RepositorySecurityAndAnalysisSecretScanningPushProtectionArgs{
						Status: pulumi.String("enabled"),
					},
					// NOT DECLARED: SecretScanningNonProviderPatterns.
					//
					// It was declared "enabled" here and NEVER took effect. Pulumi
					// reported `~ Repository updated [diff: ~securityAndAnalysis]`
					// on every apply while the live API kept returning
					// "disabled" -- verified 2026-07-25 after the #1200 apply
					// (run 30169006463, success). A silent no-op, and a perpetual
					// spurious diff on an otherwise clean stack.
					//
					// The cause is not this program. Non-provider patterns is a
					// GitHub Secret Protection (Advanced Security) feature, and
					// the org's code security configuration "dependency-graph-only"
					// (id 262482) pins it `disabled` with enforcement `enforced`.
					// An enforced org configuration overrides the repo-level
					// setting, so this write could never win. That configuration's
					// own description says every setting other than the dependency
					// graph is `not_set` "so repo_config/Pulumi stays the
					// authority" -- this one is the exception to that intent.
					//
					// That is deliberate, not an oversight to fix: Advanced
					// Security is billed per active committer, and this repo
					// intentionally runs free alternatives instead -- gitleaks
					// (the required `secret-scan` gate) for this exact class of
					// generic token / bare private key, and osv-scanner in place
					// of dependency-review. Re-adding the field would restore the
					// phantom diff without turning anything on; the way to
					// actually enable it is to change the org configuration and
					// accept the GHAS bill.
				},
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
				"pages",
				"name",
			}),
		)
		if err != nil {
			return err
		}

		// Dependabot automated security fixes (#815): open PRs to fix dependencies
		// with a known vulnerability. Free on every repo; on a public repo the
		// dependency graph + Dependabot alerts it needs are on by default. Managed
		// as code here alongside the other repo governance settings. These security
		// PRs are authored by Dependabot and auto-merged via the sync App, which
		// bypasses the required-review rule (#804), so they are never blocked.
		if _, err := github.NewRepositoryDependabotSecurityUpdates(
			ctx, repoName+"-dependabot-security-updates",
			&github.RepositoryDependabotSecurityUpdatesArgs{
				Repository: repo.Name,
				Enabled:    pulumi.Bool(true),
			},
		); err != nil {
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
		mergeQueueOn, err := mergeQueueEnabled(cfg)
		if err != nil {
			return err
		}
		if mergeQueueOn {
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
					"go-lint (devx)", "go-lint (homelab)", "validate-butane",
					// gitops-validate (kubeconform over gitops/**, which reconciles to
					// the LIVE cluster) and actionlint (workflow lint) now also trigger
					// on merge_group, so they gate the queue instead of only advising on
					// PRs. Both validate their whole dir on every queued commit, so they
					// always report — safe to require.
					"gitops-validate", "actionlint",
					// migration-safety (#819) Squawk-lints Tabula's Prisma migrations so a
					// backward-incompatible change can't reach main and break the OLD Cloud
					// Run revision during the blue-green traffic shift. Its job runs a
					// self-test on every event (and carries no pull_request paths filter),
					// so it always reports — safe to require.
					"migration-safety",
					// go-test-infra (#1015) runs the Go tests for the IaC programs
					// (infrastructure/pulumi/** and <app>/infra/**), which are outside
					// go.work and emit no go_test target -- so before that job existed
					// they never executed in CI at all. It landed advisory and, like
					// go-lint/go-test/validate-butane before it, ran on every PR without
					// gating: an IaC test regression could still merge. Its job is
					// unconditional (only the STEPS are gated, on a dorny/paths-filter
					// that returns 'false' for non-IaC diffs), so it always reports --
					// safe to require, and a no-op in seconds for the PRs that don't
					// touch IaC.
					"go-test-infra",
					// Supply-chain gates (supply-chain.yaml) -- the class of
					// check this repo had NONE of. Dependabot only alerts AFTER
					// a vulnerable dependency is already on main, and GitHub
					// secret scanning covers known PROVIDER patterns only;
					// neither BLOCKS a merge.
					//
					// Both are diff/lockfile-scoped but use the
					// run-then-noop-green shape: the job always runs and
					// reports on every event including merge_group, which is
					// what makes them safe to require. Neither carries a
					// pull_request paths filter, so they cannot leave a PR stuck
					// unmergeable (asserted by the conformance check).
					//
					// osv-scan (google/osv-scanner) replaced GitHub's
					// dependency-review gate. dependency-review reads GitHub's
					// dependency graph, which is an Advanced Security feature:
					// free on public repos but BILLED PER ACTIVE COMMITTER on
					// private ones, and (verified against the API) the
					// configuration enabling it cannot omit advanced_security --
					// the only accepted values are
					// enabled|disabled|code_security|secret_protection. So the
					// gate could not survive this repo going private without
					// either an invoice or a wedged merge queue. osv-scanner
					// reads the LOCKFILES directly instead, so it costs nothing
					// at any visibility, runs locally as well as in CI, and also
					// covers Cargo and PyPI, which GitHub's graph handled poorly
					// here.
					// go-race (#1039-adjacent) runs the race detector over EVERY Bazel
					// go_test target. Before it, race coverage was the standalone
					// `go test -race` matrix over devx+homelab only -- so every other Go
					// target, tabula's included, was never race-tested anywhere. Its job
					// is unconditional (only the STEPS are path-gated), so it always
					// reports and is safe to require.
					"go-race",
					"osv-scan",
					"secret-scan",
				}
			}
			requiredChecks := github.RepositoryRulesetRulesRequiredStatusChecksRequiredCheckArray{}
			for _, c := range checks {
				requiredChecks = append(requiredChecks, &github.RepositoryRulesetRulesRequiredStatusChecksRequiredCheckArgs{
					Context: pulumi.String(c),
				})
			}

			// #804 code-owner review is gated behind requireCodeOwnerReview
			// (default false). A single maintainer has no second reviewer, so the
			// rule produces zero real reviews; and a ruleset bypass actor's bypass
			// applies only to a DIRECT merge -- NEVER to auto-merge INTO the merge
			// queue -- so bot automation (release-please / Dependabot) cannot
			// satisfy it either and sits REVIEW_REQUIRED forever (verified on a
			// canary). While solo it therefore only blocks auto-merge and forces
			// manual admin merges. Flip requireCodeOwnerReview=true once a second
			// reviewer exists; the merge queue + required status checks below stay
			// enforced either way.
			codeOwnerReview, err := boolConfig(cfg, "requireCodeOwnerReview", false)
			if err != nil {
				return err
			}
			approvals := 0
			if codeOwnerReview {
				approvals = 1
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
					// The vitruvian-copybara-sync App (id 3863936) drives the merge
					// automation -- Dependabot auto-merge, release-please PRs, and PR
					// imports -- so it must bypass the required-review rule below, or
					// that automation would wedge waiting on a human approval that a
					// bot cannot give. Human contributor PRs still require review.
					&github.RepositoryRulesetBypassActorArgs{
						ActorId:    pulumi.Int(3863936),
						ActorType:  pulumi.String("Integration"),
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
					// Require a PR before merging + squash-only, ALWAYS. The
					// code-owner REVIEW requirement (#804) is gated by
					// requireCodeOwnerReview (computed above the ruleset; default
					// OFF for the solo team). When on, the CODEOWNERS catch-all owns
					// every path so a PR needs a code-owner approval, with
					// dismiss-stale + require-last-push-approval so it can't be gamed
					// by a later push. When off, RequiredApprovingReviewCount is 0
					// and no review blocks the merge queue.
					PullRequest: &github.RepositoryRulesetRulesPullRequestArgs{
						RequireCodeOwnerReview:       pulumi.Bool(codeOwnerReview),
						RequiredApprovingReviewCount: pulumi.Int(approvals),
						DismissStaleReviewsOnPush:    pulumi.Bool(codeOwnerReview),
						RequireLastPushApproval:      pulumi.Bool(codeOwnerReview),
						AllowedMergeMethods:          pulumi.StringArray{pulumi.String("squash")},
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
//	  '{"GCP_PROJECT_ID":"...","GCP_DEPLOY_SERVICE_ACCOUNT":"...","GCP_WORKLOAD_IDENTITY_PROVIDER":"..."}'
//
// Environments with no config entry are still created (empty), so protection
// rules exist before the first deploy is wired up.
func tabulaEnvironments(ctx *pulumi.Context, cfg *config.Config, repo *github.Repository) error {
	var tabulaVars map[string]map[string]string
	_ = cfg.GetObject("tabulaVars", &tabulaVars)

	// build pushes the shared Artifact Registry once; preview backs the advisory
	// token-less PR pulumi-preview leg. Both are ungated — they never touch a
	// live service — mirroring the oauth-user-inspector environment set.
	for _, env := range []string{"build", "preview", "development", "nonproduction", "production"} {
		name := "tabula-" + env

		args := &github.RepositoryEnvironmentArgs{
			Repository:  repo.Name,
			Environment: pulumi.String(name),
		}

		// Deployment strategy (docs/engineering/deployment-strategy.md): both
		// nonproduction and production deploy only from protected branches (main),
		// but promotion is release-gated in tabula-deploy.yaml (a tabula-api
		// release merge), so nonproduction carries NO reviewer — the release merge
		// is the human gate. production keeps a required reviewer as the final
		// checkpoint. GitHub allows self-approval, so on a single-maintainer repo
		// that reviewer is a deliberate "break glass" pause, not a four-eyes gate.
		if env == "nonproduction" || env == "production" {
			args.DeploymentBranchPolicy = &github.RepositoryEnvironmentDeploymentBranchPolicyArgs{
				ProtectedBranches:    pulumi.Bool(true),
				CustomBranchPolicies: pulumi.Bool(false),
			}
		}
		if env == "production" {
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
// The `development` environment + its variables were created out-of-band during
// single-env bring-up, so they are ADOPTED via pulumi.Import. The provider's
// variable Create is a create-only POST that 409s when the name already exists,
// so declare-and-overwrite is unsafe — import is mandatory for the pre-existing
// development resources (and clean for its environment). The nonproduction /
// production / build / preview environments are NEW (created here as the OSS
// application stage graduates oauth-user-inspector to multi-env), so they must
// NOT carry an Import option.
//
// Variable values are committed per-env config (identifiers, not secrets):
//
//	pulumi config set --path 'oauthVars["development"]["GCP_PROJECT_ID"]' '<value>' --stack dev
//
// nonproduction / production / build carry no vars yet: their deploy service
// accounts + WIF provider are minted by the Phase-3 per-env identity stacks
// (which land in the prj-{env}-bu1-oss-floating projects). The environments are
// created now — empty but with protection rules — so the gate exists before the
// first deploy, mirroring tabulaEnvironments. Their vars are set in Phase 3.
func oauthEnvironment(ctx *pulumi.Context, cfg *config.Config, repo *github.Repository) error {
	nm := repoName(cfg)

	// Repo-level gate the zitadel-infra job reads to decide whether to apply the
	// Zitadel application stack. It must be repo-scoped: a job-level `if:` cannot
	// see an environment-scoped variable.
	//
	// ENABLED 2026-07-20: the two prerequisites the cutover was waiting on are now
	// met — nonproduction and production have ZITADEL_MACHINE_KEY_JSON +
	// TS_OAUTH_CLIENT_ID/SECRET seeded (via tools/sync-env-secrets), and the
	// multi-env zitadel-apps stack (#926) has landed. With "true", the
	// zitadel-{dev,nonprod,prod} jobs register each env's OIDC client and sync its
	// id/secret into that env's oss-floating Secret Manager before the app deploy.
	if _, err := github.NewActionsVariable(ctx, "zitadel-apps-auto-apply", &github.ActionsVariableArgs{
		Repository:   repo.Name,
		VariableName: pulumi.String("ZITADEL_APPS_AUTO_APPLY"),
		Value:        pulumi.String("true"),
	}, pulumi.Import(pulumi.ID(nm+":ZITADEL_APPS_AUTO_APPLY"))); err != nil {
		return err
	}

	var oauthVars map[string]map[string]string
	_ = cfg.GetObject("oauthVars", &oauthVars)

	// Environment set + gating, per the repo-wide deployment strategy
	// (docs/engineering/deployment-strategy.md):
	//   - development: auto on push, ungated.
	//   - nonproduction: promoted only when the app's release-please PR merges
	//     (release-gated in the deploy workflow). The release merge IS the human
	//     gate, so this env keeps the protected-branch policy but carries NO
	//     reviewer — that removes the every-run approval without weakening the
	//     "deploy only from main" guarantee.
	//   - production: release-gated AND a required reviewer — the one deliberate
	//     human checkpoint before prod.
	//   - build / preview: ungated.
	envs := []struct {
		env          string
		branchPolicy bool // restrict deploys to protected branches (main)
		reviewer     bool // require a human approval
		imported     bool
	}{
		{"development", false, false, true},
		{"nonproduction", true, false, false},
		{"production", true, true, false},
		{"build", false, false, false},
		{"preview", false, false, false},
	}

	for _, e := range envs {
		name := "oauth-user-inspector-" + e.env

		args := &github.RepositoryEnvironmentArgs{
			Repository:  repo.Name,
			Environment: pulumi.String(name),
		}
		if e.branchPolicy {
			// Deploy only from protected branches (main).
			args.DeploymentBranchPolicy = &github.RepositoryEnvironmentDeploymentBranchPolicyArgs{
				ProtectedBranches:    pulumi.Bool(true),
				CustomBranchPolicies: pulumi.Bool(false),
			}
		}
		if e.reviewer {
			// Require an approval from the configured reviewer(s). GitHub permits
			// self-approval, so on a single-maintainer repo this is a deliberate
			// "break glass" pause.
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

		var envOpts []pulumi.ResourceOption
		if e.imported {
			envOpts = append(envOpts, pulumi.Import(pulumi.ID(nm+":"+name)))
		}
		envRes, err := github.NewRepositoryEnvironment(ctx, name, args, envOpts...)
		if err != nil {
			return err
		}

		// Deterministic resource names: iterate variables in sorted order.
		vars := oauthVars[e.env]
		keys := make([]string, 0, len(vars))
		for k := range vars {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			var varOpts []pulumi.ResourceOption
			if e.imported {
				varOpts = append(varOpts, pulumi.Import(pulumi.ID(fmt.Sprintf("%s:%s:%s", nm, name, k))))
			}
			if _, err := github.NewActionsEnvironmentVariable(ctx, fmt.Sprintf("%s-%s", name, k), &github.ActionsEnvironmentVariableArgs{
				Repository:   repo.Name,
				Environment:  envRes.Environment,
				VariableName: pulumi.String(k),
				Value:        pulumi.String(vars[k]),
			}, varOpts...); err != nil {
				return err
			}
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
	// environment is its own leaf Pulumi project (single production stack)
	// deployed via the reusable
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
	// environment is its own leaf Pulumi project (single production stack)
	// deployed via the reusable
	// foundation-net-deploy.yaml workflow:
	//
	//   foundation-net-development  → auto-deploy (no reviewers)
	//   foundation-net-nonproduction → manual approval (requires reviewers)
	//   foundation-net-shared        → manual approval (requires reviewers)
	//   foundation-net-production    → manual approval (requires reviewers)
	//
	// The upstream-leaf layout added the envs/shared leaf (hub VPC / DNS hub /
	// hierarchical firewall). It is production-tier — upstream applies
	// envs/shared from the production branch — so it gets the same reviewer
	// gate as production. All four share the same WIF credentials as the
	// foundation-net stage (the networks SA has equivalent org-level
	// permissions).
	netPhaseEnvironments := []struct {
		name            string
		requireReviewer bool
	}{
		{"foundation-net-development", false},
		{"foundation-net-nonproduction", true},
		{"foundation-net-shared", true},
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

	// ── Phase 4: Projects promotion environments ──────────────────────────
	// The projects stage (gcp-projects, stage 4) uses a chained promotion
	// workflow where each leaf is its own leaf Pulumi project (single
	// production stack) deployed via
	// the reusable foundation-proj-deploy.yaml workflow:
	//
	//   foundation-proj-development  → auto-deploy (no reviewers)
	//   foundation-proj-nonproduction → release-gated, NO reviewer
	//   foundation-proj-shared        → manual approval (requires reviewers)
	//   foundation-proj-production    → manual approval (requires reviewers)
	//
	// The upstream-leaf layout added the business_unit_1/shared leaf (the BU
	// infra-pipeline, modules/infra_pipelines). It is production-tier —
	// upstream applies business_unit_1/shared from the production branch — so
	// it gets the same reviewer gate as production.
	//
	// nonproduction carries NO reviewer, matching the repo-wide deployment
	// strategy already applied to oauthEnvironment above: this stage only
	// promotes when a component's release-please PR merges, so the release
	// merge IS the human gate. Keeping a second per-run approval here meant a
	// single promotion needed ~6 manual clicks (bu1 + bu2 x shared/nonprod/prod)
	// for changes the preview job had already proven non-destructive. The
	// protected-branch policy below is unchanged, so "deploy only from main"
	// still holds.
	//
	// shared and production KEEP the reviewer, for different reasons:
	//   - production is the deliberate last-look before prod.
	//   - shared is the BU infra-pipeline every other leaf consumes, so a bad
	//     apply there has a blast radius across development, nonproduction AND
	//     production at once. The per-leaf "0 deleted / 0 replaced" preview gate
	//     is scoped to one stack and cannot see that cross-env fallout, so the
	//     human check stays.
	//
	// Uses the projects SA (sa-terraform-proj), whose per-leaf WIF principalSet
	// bindings (foundation-proj-<leaf>, incl. shared) are provisioned by
	// gcp-bootstrap — the shared binding must be applied there before the
	// first foundation-proj-shared deploy can authenticate.
	projPhaseEnvironments := []struct {
		name            string
		requireReviewer bool
	}{
		{"foundation-proj-development", false},
		{"foundation-proj-nonproduction", false},
		{"foundation-proj-shared", true},
		{"foundation-proj-production", true},
	}

	for _, envDef := range projPhaseEnvironments {
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

		// Propagate foundation WIF variables to the environment so the reusable
		// deploy workflow resolves ${{ vars.GCP_* }} correctly. Uses the proj SA
		// (sa-terraform-proj), not the org SA.
		envVars := foundationVars["foundation-proj"]
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

	// ── Phase 5: App-infra promotion environments ─────────────────────────
	// The app-infra stage (gcp-app-infra, stage 5) uses a chained promotion
	// workflow where each leaf is its own leaf Pulumi project (single production
	// stack) deployed via the reusable foundation-app-deploy.yaml workflow:
	//
	//   foundation-app-development  → auto-deploy
	//   foundation-app-nonproduction → auto-deploy
	//   foundation-app-production    → auto-deploy
	//
	// UNGATED ON PURPOSE — and this is only safe because of where the identity
	// lives. Stage 5 holds application WORKLOADS; a routine app deploy runs it
	// (twice, for the blue-green publish/promote phases). Gating it would put a
	// human approval in front of every code change. What makes ungating safe is
	// that the SA applying it — the BU app-infra pipeline SA — has ALL of its
	// grants authored in stage 4, which it does not apply. It cannot widen its
	// own permissions, so the reviewer gate has nothing left to protect here.
	// Privileged IAM changes still land in gcp-projects, which IS gated.
	// See docs/engineering/core-vs-application-infrastructure.md §4.1.
	//
	// Unlike stage 4 there is NO `shared` leaf — upstream 5-app-infra has none.
	//
	// Stage 5 consumes the stage-4 BU leaf (the env's app-hosting project) and
	// gcp-bootstrap (the shared WIF pool), so its promotion runs AFTER the
	// corresponding stage-4 leaf.
	//
	// Reuses the projects SA (sa-terraform-proj): stage 5 writes IAM on the same
	// per-env app-hosting projects stage 4 creates, so the proj SA already holds
	// exactly the scope this stage needs and no new org-level identity is
	// introduced. If stage 5 ever grows resources outside those projects, give it
	// its own SA rather than widening this one.
	// One entry per business-unit per env. bu1 keeps the legacy unsuffixed name
	// (foundation-app-<env>) that the live workflow + WIF bindings already use —
	// renaming it would break the completed oauth cutover. bu2 (tabula) is
	// BU-suffixed (foundation-app-bu2-<env>) and reads sa-app-infra-bu2 from the
	// bu2 projects leaf. projBU selects which gcp-projects leaf mints the SA.
	appPhaseEnvironments := []struct {
		name            string
		env             string
		projBU          string
		requireReviewer bool
	}{
		{"foundation-app-development", "development", "bu1", false},
		{"foundation-app-nonproduction", "nonproduction", "bu1", false},
		{"foundation-app-production", "production", "bu1", false},
		{"foundation-app-bu2-development", "development", "bu2", false},
		{"foundation-app-bu2-nonproduction", "nonproduction", "bu2", false},
		{"foundation-app-bu2-production", "production", "bu2", false},
	}

	for _, envDef := range appPhaseEnvironments {
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

		// Propagate foundation WIF variables so the reusable deploy workflow
		// resolves ${{ vars.GCP_* }}. The pool/provider and project are shared
		// with the proj stage, but GCP_SERVICE_ACCOUNT MUST be the BU app-infra
		// pipeline SA: stage 5 is UNGATED, and sa-terraform-proj can author its
		// own grants, so an ungated environment must never reach it.
		//
		// The value is read from the gcp-projects leaf that MINTS the SA rather
		// than from stack config. An earlier revision used
		// cfg.Get("appInfraPipelineServiceAccount") with a fall-through to the
		// proj SA when unset — and because that config lives in the gitignored
		// Pulumi.dev.yaml it was never set, so the ungated stage-5 environments
		// silently pointed at the PRIVILEGED SA. A silent fall-back to a
		// more-privileged identity is the wrong default; sourcing it from the
		// stack output makes the value self-maintaining and removes the
		// fall-back entirely. If the projects leaf has not applied yet the
		// output is empty, the variable is empty, and the deploy fails loudly
		// at google-github-actions/auth — fail-closed, which is the point.
		envVars := map[string]string{}
		for k, v := range foundationVars["foundation-proj"] {
			envVars[k] = v
		}
		delete(envVars, "GCP_SERVICE_ACCOUNT") // set from the stack output below

		projLeaf, err := pulumi.NewStackReference(ctx,
			fmt.Sprintf("projects-%s-%s", envDef.projBU, envDef.env), &pulumi.StackReferenceArgs{
				Name: pulumi.String(fmt.Sprintf("ipv1337/foundation-projects-%s-%s/production", envDef.projBU, envDef.env)),
			})
		if err != nil {
			return err
		}
		// GetStringOutput would ERROR the whole apply when the output is not
		// there yet ("stack reference output ... does not exist"), which took
		// repo_config down with it — and repo_config owns the merge-queue
		// ruleset and repo security settings, so an unrelated foundation
		// rollout must never be able to block it. GetOutputDetails returns nil
		// fields instead, so we can skip the variable and keep applying.
		//
		// Skipping is the SAFE outcome, not a degraded one: with no
		// GCP_SERVICE_ACCOUNT the stage-5 deploy fails loudly at
		// google-github-actions/auth. What must never happen is the variable
		// carrying a MORE-privileged identity (see the git history of this
		// block) — absent beats wrong.
		saDetails, err := projLeaf.GetOutputDetails("app_infra_pipeline_service_account")
		if err != nil {
			return err
		}
		if sa, ok := saDetails.Value.(string); ok && sa != "" {
			if _, err := github.NewActionsEnvironmentVariable(ctx,
				fmt.Sprintf("%s-GCP_SERVICE_ACCOUNT", envDef.name), &github.ActionsEnvironmentVariableArgs{
					Repository:   repo.Name,
					Environment:  envRes.Environment,
					VariableName: pulumi.String("GCP_SERVICE_ACCOUNT"),
					Value:        pulumi.String(sa),
				}); err != nil {
				return err
			}
		} else {
			ctx.Log.Warn(fmt.Sprintf(
				"%s: gcp-projects %s-%s has not exported app_infra_pipeline_service_account yet; "+
					"leaving GCP_SERVICE_ACCOUNT UNSET so stage-5 deploys fail closed rather than "+
					"authenticating as a privileged SA. Re-run after that leaf applies.",
				envDef.name, envDef.projBU, envDef.env,
			), nil)
		}

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

	// ── Preview environments for the env, net & proj promotion stages ─────
	// The environments, networks, and projects stages are previewed on PRs by
	// .github/workflows/foundation-preview.yaml (the `development` stack of
	// each). Their DEPLOY environments (foundation-{env,net,proj}-<stage>) are
	// gated to protected branches, so — like the Phase-1 stages above — the PR
	// preview needs a dedicated, UNGATED environment (no branch policy, no
	// reviewers).
	//
	// Each preview env reuses its stage's WIF variables/SA (foundation-env uses
	// sa-terraform-env, foundation-net uses sa-terraform-net, foundation-proj
	// uses sa-terraform-proj). The matching WIF principalSet already exists:
	// gcp-bootstrap's generic per-stage binding grants
	// attribute.environment/foundation-<stage>-preview for every stage SA, so no
	// gcp-bootstrap change is needed for the preview leg. PULUMI_ACCESS_TOKEN is
	// repo-level (see tabulaEnvironments), so only the GCP_* variables are set here.
	// foundation-app previews with the PROJ stage's vars/SA (stage 5 reuses the
	// proj SA — see Phase 5), so the preview env name and the vars key differ.
	for _, previewDef := range []struct{ envPrefix, varsKey string }{
		{"foundation-env", "foundation-env"},
		{"foundation-net", "foundation-net"},
		{"foundation-proj", "foundation-proj"},
		{"foundation-app", "foundation-proj"},
	} {
		stage := previewDef.varsKey
		previewEnv := previewDef.envPrefix + "-preview"
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
	//
	// PULUMI_ACCESS_TOKEN is here for the same reason, learned the hard way.
	// Dependabot PRs read the SEPARATE Dependabot store, so a repo secret of
	// the same name is simply not visible to them: `secrets.PULUMI_ACCESS_TOKEN`
	// resolves to the empty string with no warning, and pulumi-preview.yaml died
	// with "PULUMI_ACCESS_TOKEN must be set for login during non-interactive CLI
	// sessions" (exit 3) on #1164 -- a PR whose entire diff was a go.mod bump.
	// That leg now degrades to noop-green when the credential is absent, so this
	// is what actually RESTORES the preview coverage on dependency PRs rather
	// than merely silencing the failure.
	//
	// The value is never in git: the repo-config apply workflow already exports
	// PULUMI_ACCESS_TOKEN (it is how pulumi itself authenticates), so the env
	// branch of EnvOrConfigOptional picks it up and mirrors it into the
	// Dependabot store. A local run falls back to the gitignored
	// `pulumi config set --secret pulumiAccessToken`, and when neither is set the
	// secret is simply not managed -- the same optional shape as BuildBuddy, so
	// auto-apply stays green either way.
	//
	// APP_PRIVATE_KEY is the same story one layer earlier. _repo-config-preview
	// mints a GitHub App token for the Pulumi GitHub provider from it, so on a
	// Dependabot PR create-github-app-token failed with "The 'private-key' input
	// must be set to a non-empty string" before pulumi ran at all (#1210). That
	// leg now degrades to noop-green when the key is absent, and -- as with
	// PULUMI_ACCESS_TOKEN above -- mirroring it here is what RESTORES the preview
	// rather than merely silencing it.
	//
	// This one is a deliberate trust decision, not a mechanical fix: it puts a
	// GitHub App private key where Dependabot-triggered runs can read it. Taken
	// knowingly, on two grounds. The App is the narrowly-scoped Pulumi provider
	// App (PULUMI_APP_ID), not a broadly-privileged one; and a sibling App key,
	// SYNC_APP_PRIVATE_KEY, is already in this store (pkg/copybara_sync) for the
	// reconcile automation, so the boundary this crosses was crossed already.
	// Revoking it means rotating the App key, not deleting this line -- if that
	// tradeoff is ever re-litigated, the preview degrade still stands on its own
	// and dropping this entry is safe.
	//
	// `bazel run //tools/ci-preflight` reports exactly this class of gap: any
	// secret a pull_request-triggered workflow reads that the Dependabot store
	// does not carry. It queries the live API, so it turns clean only after this
	// program applies -- not merely because the entry exists here.
	for _, s := range []struct {
		resource string // pulumi resource name (stable; renaming forces replace)
		env      string // CI env var / GitHub secret name
		cfgKey   string // local `pulumi config set --secret <key>` fallback
	}{
		{"buildbuddy-api-key-dependabot", "BUILDBUDDY_API_KEY", "buildbuddyApiKey"},
		{"pulumi-access-token-dependabot", "PULUMI_ACCESS_TOKEN", "pulumiAccessToken"},
		{"app-private-key-dependabot", "APP_PRIVATE_KEY", "appPrivateKey"},
	} {
		// Optional by design: a value that is not available in this context is
		// skipped, never defaulted to empty. Writing an empty Dependabot secret
		// would be worse than having none -- it looks configured and still fails.
		key := secrets.EnvOrConfigOptional(cfg, s.env, s.cfgKey)
		if key == nil {
			continue
		}
		if _, err := github.NewDependabotSecret(ctx, s.resource, &github.DependabotSecretArgs{
			Repository:     repo.Name,
			SecretName:     pulumi.String(s.env),
			PlaintextValue: key,
		}); err != nil {
			return err
		}
	}
	return nil
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

// boolConfig parses a Pulumi config boolean strictly. An unset key resolves
// to def; an unparseable one is a fatal config error rather than silently
// resolving to a value the caller never chose. cfg.GetBool (cast.ToBool) and
// cfg.TryBool's own callers both swallow the parse error and fall back to
// their default -- fine when the default is the safe direction, wrong for
// the branch-protection flags routed through here, where the default is the
// PERMISSIVE setting (see requireCodeOwnerReview/enforceAdmins below): a
// typo like "yes" or "on" would silently mean "off".
func boolConfig(cfg *config.Config, key string, def bool) (bool, error) {
	return parseBoolConfig(key, cfg.Get(key), def)
}

// parseBoolConfig holds boolConfig's actual parsing logic, split out so it's
// testable without standing up a *config.Config (which needs a live
// pulumi.Context).
func parseBoolConfig(key, raw string, def bool) (bool, error) {
	if raw == "" {
		return def, nil
	}
	v, err := strconv.ParseBool(raw)
	if err != nil {
		return false, fmt.Errorf("config %q = %q is not a boolean (use true/false)", key, raw)
	}
	return v, nil
}

// requirePullRequest defaults to true when unset.
func requirePullRequest(cfg *config.Config) (bool, error) {
	return boolConfig(cfg, "requirePullRequest", true)
}

// requireStatusChecks defaults to true when unset.
func requireStatusChecks(cfg *config.Config) (bool, error) {
	return boolConfig(cfg, "requireStatusChecks", true)
}

// mergeQueueEnabled defaults to true: the merge queue is the trunk-based
// postsubmit gate (#83). Set `mergeQueue: "false"` in the stack config to
// disable it (e.g. to fall back to direct pushes during a migration).
func mergeQueueEnabled(cfg *config.Config) (bool, error) {
	return boolConfig(cfg, "mergeQueue", true)
}

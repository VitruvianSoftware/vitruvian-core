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

// Package copybara_sync manages the GitHub auth resources that back the
// Copybara bidirectional sync between the vitruvian-core monorepo and each of
// its standalone component repositories.
//
// For every synced component this creates:
//
//  1. A fresh ED25519 SSH key pair (tls.PrivateKey).
//  2. A WRITE deploy key on the STANDALONE repo, so vitruvian-core's export
//     workflow can push the component out to its standalone repo.
//  3. An Actions secret in vitruvian-core holding that key's PRIVATE half
//     (<PROJECT>_SYNC_SSH_KEY), consumed by the export workflow.
//  4. Two Actions secrets in the STANDALONE repo holding GitHub App dispatch
//     credentials (<PROJECT>_DISPATCH_APP_ID / <PROJECT>_DISPATCH_APP_PRIVATE_KEY),
//     consumed by the standalone repo's dispatch workflow to fire a
//     repository_dispatch back into vitruvian-core (the import trigger).
//     TWO-WAY components only — a one-way mirror has no import-back workflow.
//
// For a ONE-WAY mirror (OneWay:true) it additionally creates read-only branch
// protection on the standalone repo's main (require-a-PR, EnforceAdmins=false so
// the export deploy key keeps its admin-context push bypass), codifying the
// read-only-mirror lockdown as code instead of click-ops.
//
// The GitHub App itself is created MANUALLY by the operator; Pulumi only places
// its credentials, which are supplied as Pulumi config secrets (see below).
package copybara_sync

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi-tls/sdk/v5/go/tls"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/pkg/secrets"
)

// monorepoRepoName is the GitHub repository name of the monorepo. The export
// workflow lives here and consumes the <PROJECT>_SYNC_SSH_KEY secret.
const monorepoRepoName = "vitruvian-core"

// syncedProject describes one component that is bidirectionally synced between
// the monorepo and a standalone repository.
//
// To onboard another component (devx, homelab, nexus-agent, ...) append an
// entry to syncedProjects below — no other code changes are required.
type syncedProject struct {
	// Name is the component / monorepo subfolder name (e.g. "mcp-slack"). It is
	// uppercase-snaked to form the secret-name prefix (mcp-slack -> MCP_SLACK)
	// and is also used as the config-key prefix for the App credentials.
	Name string

	// StandaloneRepo is the name of the EXISTING standalone GitHub repository
	// this component is synced with (e.g. "mcp-slack"). It is referenced by
	// name only — this package never creates repositories.
	StandaloneRepo string

	// OneWay marks a component exported monorepo -> standalone only
	// (copy.bara.sky is_one_way): it has no import-back dispatch workflow,
	// so it needs no GitHub App dispatch credentials — only the export SSH
	// key provisioned in steps 1-3 below.
	OneWay bool
}

// syncedProjects is the source of truth for which components have sync auth
// managed by Pulumi. All components reuse a single GitHub App for the import
// dispatch (its id/private-key are supplied per-component as config secrets,
// pointing at the same App), so onboarding a component is just an entry here.
var syncedProjects = []syncedProject{
	{
		Name:           "mcp-slack",
		StandaloneRepo: "mcp-slack",
	},
	{
		Name:           "devx",
		StandaloneRepo: "devx",
	},
	{
		Name:           "homelab",
		StandaloneRepo: "homelab",
	},
	{
		Name:           "nexus-agent",
		StandaloneRepo: "nexus-agent",
	},
	{
		Name:           "oauth-user-inspector",
		StandaloneRepo: "oauth-user-inspector",
		OneWay:         true,
	},
	{
		// pulumi-library is EXPORT-ONLY (copy.bara.sky export_only): developed and
		// published from the monorepo, its public repo a read-only mirror. OneWay
		// skips the import-back dispatch credentials — it needs only the export
		// SSH deploy key (PULUMI_LIBRARY_SYNC_SSH_KEY), consumed by
		// copybara-export-pulumi-library.yaml.
		Name:           "pulumi-library",
		StandaloneRepo: "pulumi-library",
		OneWay:         true,
	},
	{
		// Export-only reference mirror. Name uppercase-snakes to
		// PULUMI_GO_EXAMPLE_FOUNDATION -> PULUMI_GO_EXAMPLE_FOUNDATION_SYNC_SSH_KEY,
		// consumed by copybara-export-pulumi-go-example-foundation.yaml.
		Name:           "pulumi_go-example-foundation",
		StandaloneRepo: "pulumi_go-example-foundation",
		OneWay:         true,
	},
	{
		Name:           "pulumi_ts-example-foundation",
		StandaloneRepo: "pulumi_ts-example-foundation",
		OneWay:         true,
	},
}

// secretPrefix converts a project name into the UPPER_SNAKE prefix used for its
// Actions secret names, mirroring starter_repos.go (ReplaceAll "-" -> "_",
// then ToUpper). e.g. "mcp-slack" -> "MCP_SLACK".
func secretPrefix(projectName string) string {
	return strings.ToUpper(strings.ReplaceAll(projectName, "-", "_"))
}

// syncAppCreds returns the shared GitHub App id + private key. A single App backs
// the import-back dispatch for every component plus the monorepo-side automation.
// In CI the values are injected from the SYNC_APP_ID / SYNC_APP_PRIVATE_KEY
// pipeline secrets (env); locally they fall back to the gitignored Pulumi stack
// config (syncAppId / syncAppPrivateKey). The secret never lives in git.
func syncAppCreds(cfg *config.Config) (pulumi.StringInput, pulumi.StringInput) {
	return secrets.EnvOrConfig(cfg, "SYNC_APP_ID", "syncAppId"),
		secrets.EnvOrConfig(cfg, "SYNC_APP_PRIVATE_KEY", "syncAppPrivateKey")
}

// ManageSyncAuth provisions the sync-auth resources for every synced project.
func ManageSyncAuth(ctx *pulumi.Context) error {
	cfg := config.New(ctx, "")
	// Shared GitHub App backing every component's import dispatch and the
	// monorepo-side automation (one App; see syncAppCreds).
	appID, appKey := syncAppCreds(cfg)

	for _, project := range syncedProjects {
		prefix := secretPrefix(project.Name)

		// 1. Create a fresh ED25519 key pair for the export push.
		privateKey, err := tls.NewPrivateKey(ctx, fmt.Sprintf("%s-sync-key", project.Name), &tls.PrivateKeyArgs{
			Algorithm: pulumi.String("ED25519"),
		})
		if err != nil {
			return err
		}

		// 2. Install the PUBLIC half as a WRITE deploy key on the STANDALONE repo
		//    so the monorepo's export workflow can push to it.
		_, err = github.NewRepositoryDeployKey(ctx, fmt.Sprintf("%s-standalone-deploy-key", project.Name), &github.RepositoryDeployKeyArgs{
			Title:      pulumi.String("copybara-sync (write)"),
			Repository: pulumi.String(project.StandaloneRepo),
			Key:        privateKey.PublicKeyOpenssh,
			ReadOnly:   pulumi.Bool(false),
		})
		if err != nil {
			return err
		}

		// 3. Store the PRIVATE half as an Actions secret in the MONOREPO, where
		//    the export workflow reads it (<PROJECT>_SYNC_SSH_KEY).
		_, err = github.NewActionsSecret(ctx, fmt.Sprintf("%s-sync-ssh-key-secret", project.Name), &github.ActionsSecretArgs{
			Repository:     pulumi.String(monorepoRepoName),
			SecretName:     pulumi.String(fmt.Sprintf("%s_SYNC_SSH_KEY", prefix)),
			PlaintextValue: privateKey.PrivateKeyOpenssh,
		})
		if err != nil {
			return err
		}

		if project.OneWay {
			// A one-way mirror is READ-ONLY: development happens in the monorepo
			// and Copybara mirrors the subtree out, so the standalone repo must
			// reject direct human pushes to its default branch. Codify that here
			// (previously click-ops) with classic branch protection requiring a
			// pull request — drift-corrected on every apply.
			//
			// CRITICAL: EnforceAdmins=false. The export + go.sum-tidy jobs push
			// over the WRITE deploy key provisioned above, and a deploy key
			// bypasses branch protection ONLY while "Include administrators" is
			// off (deploy keys carry admin context; GITHUB_TOKEN and App tokens do
			// NOT get this bypass — that asymmetry is exactly why the mirror-side
			// tidy push hit GH006). Flip this to true and the mirror sync AND
			// publishing break. Humans pushing over HTTPS/PAT are non-admin for
			// this rule and stay blocked — the one-way-mirror invariant we want.
			//
			// Pattern is "main": every synced standalone repo uses main as its
			// default branch. The provider upserts branch protection (PUT), so
			// this adopts and overwrites any pre-existing manual rule.
			_, err = github.NewBranchProtection(ctx, fmt.Sprintf("%s-mirror-readonly", project.Name), &github.BranchProtectionArgs{
				RepositoryId:      pulumi.String(project.StandaloneRepo),
				Pattern:           pulumi.String("main"),
				EnforceAdmins:     pulumi.Bool(false),
				AllowsForcePushes: pulumi.Bool(false),
				AllowsDeletions:   pulumi.Bool(false),
				RequiredPullRequestReviews: github.BranchProtectionRequiredPullRequestReviewArray{
					&github.BranchProtectionRequiredPullRequestReviewArgs{
						RequiredApprovingReviewCount: pulumi.Int(0),
					},
				},
			})
			if err != nil {
				return err
			}
		}

		if !project.OneWay { // one-way export has no import-back dispatch workflow
			// 4. Place the GitHub App dispatch credentials as Actions secrets in the
			//    STANDALONE repo, where its dispatch workflow reads them to fire a
			//    repository_dispatch back into the monorepo (the import trigger).
			//    Uses the shared sync App creds (syncAppCreds); the App is created manually.
			_, err = github.NewActionsSecret(ctx, fmt.Sprintf("%s-dispatch-app-id-secret", project.Name), &github.ActionsSecretArgs{
				Repository:     pulumi.String(project.StandaloneRepo),
				SecretName:     pulumi.String(fmt.Sprintf("%s_DISPATCH_APP_ID", prefix)),
				PlaintextValue: appID,
			})
			if err != nil {
				return err
			}

			_, err = github.NewActionsSecret(ctx, fmt.Sprintf("%s-dispatch-app-private-key-secret", project.Name), &github.ActionsSecretArgs{
				Repository:     pulumi.String(project.StandaloneRepo),
				SecretName:     pulumi.String(fmt.Sprintf("%s_DISPATCH_APP_PRIVATE_KEY", prefix)),
				PlaintextValue: appKey,
			})
			if err != nil {
				return err
			}
		}
	}

	// Monorepo-side App credentials for the Dependabot reconcile + auto-merge
	// automation (docs/planning/2026-05-26-centralized-dependabot-design.md).
	// Dependabot-triggered workflow runs cannot read normal Actions secrets, so
	// the App id/key are placed as a Dependabot secret; the Actions-secret twins
	// cover any non-Dependabot-context step. Both reuse the single sync App.
	_, err := github.NewDependabotSecret(ctx, "monorepo-sync-app-id-dependabot", &github.DependabotSecretArgs{
		Repository:     pulumi.String(monorepoRepoName),
		SecretName:     pulumi.String("SYNC_APP_ID"),
		PlaintextValue: appID,
	})
	if err != nil {
		return err
	}
	_, err = github.NewDependabotSecret(ctx, "monorepo-sync-app-key-dependabot", &github.DependabotSecretArgs{
		Repository:     pulumi.String(monorepoRepoName),
		SecretName:     pulumi.String("SYNC_APP_PRIVATE_KEY"),
		PlaintextValue: appKey,
	})
	if err != nil {
		return err
	}
	_, err = github.NewActionsSecret(ctx, "monorepo-sync-app-id-actions", &github.ActionsSecretArgs{
		Repository:     pulumi.String(monorepoRepoName),
		SecretName:     pulumi.String("SYNC_APP_ID"),
		PlaintextValue: appID,
	})
	if err != nil {
		return err
	}
	_, err = github.NewActionsSecret(ctx, "monorepo-sync-app-key-actions", &github.ActionsSecretArgs{
		Repository:     pulumi.String(monorepoRepoName),
		SecretName:     pulumi.String("SYNC_APP_PRIVATE_KEY"),
		PlaintextValue: appKey,
	})
	if err != nil {
		return err
	}

	return nil
}

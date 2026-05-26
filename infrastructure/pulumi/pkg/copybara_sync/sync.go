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
}

// secretPrefix converts a project name into the UPPER_SNAKE prefix used for its
// Actions secret names, mirroring starter_repos.go (ReplaceAll "-" -> "_",
// then ToUpper). e.g. "mcp-slack" -> "MCP_SLACK".
func secretPrefix(projectName string) string {
	return strings.ToUpper(strings.ReplaceAll(projectName, "-", "_"))
}

// configKeyPrefix converts a project name into a safe Pulumi config-key prefix
// for the GitHub App credentials. Config keys cannot contain '-' segments that
// would be read as namespaces, so we drop the hyphens and lower-camel the name.
// e.g. "mcp-slack" -> "mcpSlack", yielding config keys "mcpSlackDispatchAppId"
// and "mcpSlackDispatchAppPrivateKey".
func configKeyPrefix(projectName string) string {
	parts := strings.Split(projectName, "-")
	var b strings.Builder
	for i, p := range parts {
		if p == "" {
			continue
		}
		if i == 0 {
			b.WriteString(p)
			continue
		}
		b.WriteString(strings.ToUpper(p[:1]))
		b.WriteString(p[1:])
	}
	return b.String()
}

// ManageSyncAuth provisions the sync-auth resources for every synced project.
func ManageSyncAuth(ctx *pulumi.Context) error {
	cfg := config.New(ctx, "")

	for _, project := range syncedProjects {
		prefix := secretPrefix(project.Name)
		cfgPrefix := configKeyPrefix(project.Name)

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

		// 4. Place the GitHub App dispatch credentials as Actions secrets in the
		//    STANDALONE repo, where its dispatch workflow reads them to fire a
		//    repository_dispatch back into the monorepo (the import trigger).
		//    Values come from Pulumi config secrets; the App is created manually.
		dispatchAppID := cfg.RequireSecret(fmt.Sprintf("%sDispatchAppId", cfgPrefix))
		dispatchAppPrivateKey := cfg.RequireSecret(fmt.Sprintf("%sDispatchAppPrivateKey", cfgPrefix))

		_, err = github.NewActionsSecret(ctx, fmt.Sprintf("%s-dispatch-app-id-secret", project.Name), &github.ActionsSecretArgs{
			Repository:     pulumi.String(project.StandaloneRepo),
			SecretName:     pulumi.String(fmt.Sprintf("%s_DISPATCH_APP_ID", prefix)),
			PlaintextValue: dispatchAppID,
		})
		if err != nil {
			return err
		}

		_, err = github.NewActionsSecret(ctx, fmt.Sprintf("%s-dispatch-app-private-key-secret", project.Name), &github.ActionsSecretArgs{
			Repository:     pulumi.String(project.StandaloneRepo),
			SecretName:     pulumi.String(fmt.Sprintf("%s_DISPATCH_APP_PRIVATE_KEY", prefix)),
			PlaintextValue: dispatchAppPrivateKey,
		})
		if err != nil {
			return err
		}
	}

	return nil
}

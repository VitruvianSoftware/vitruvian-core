/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Package cicd provides reusable Workload Identity Federation (WIF) components
// for external CI/CD integrations. These mirror the functionality of the
// official Google Cloud Foundation Toolkit submodules:
//
//   - GitHubOIDC: terraform-google-modules/github-actions-runners/google//modules/gh-oidc
//   - GitLabOIDC: 0-bootstrap/modules/gitlab-oidc (local CFT module)
//
// Each component bundles a Workload Identity Pool, an OIDC Provider with
// platform-specific attribute mappings, and per-SA IAM bindings into a
// single reusable Pulumi ComponentResource.
package cicd

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/iam"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// SAMappingEntry maps a service account to its WIF attribute binding.
// This mirrors the TF module's sa_mapping object type:
//
//	variable "sa_mapping" {
//	  type = map(object({
//	    sa_name   = string
//	    attribute = string
//	  }))
//	}
type SAMappingEntry struct {
	// SAName is the service account's fully-qualified resource name
	// (e.g., "projects/my-project/serviceAccounts/sa@my-project.iam.gserviceaccount.com").
	SAName pulumi.StringInput
	// Attribute is the WIF attribute binding string
	// (e.g., "attribute.repository/owner/repo" for GitHub,
	// or "attribute.project_path/namespace/project" for GitLab).
	Attribute pulumi.StringInput
}

// GitHubOIDCArgs configures a GitHub Actions OIDC provider, matching
// terraform-google-modules/github-actions-runners/google//modules/gh-oidc.
type GitHubOIDCArgs struct {
	// ProjectID is the GCP project in which to create the WIF resources.
	ProjectID pulumi.StringInput
	// PoolID is the Workload Identity Pool ID (e.g., "foundation-pool").
	PoolID pulumi.StringInput
	// ProviderID is the WIF Provider ID (e.g., "foundation-gh-provider").
	ProviderID pulumi.StringInput
	// AttributeCondition is the CEL expression restricting which tokens are accepted.
	// Example: "assertion.repository_owner=='my-org'"
	AttributeCondition pulumi.StringInput
	// SAMapping maps logical keys to service account + attribute binding pairs.
	SAMapping map[string]SAMappingEntry
}

// GitHubOIDC represents a GitHub Actions Workload Identity Federation configuration.
type GitHubOIDC struct {
	pulumi.ResourceState
	Pool     *iam.WorkloadIdentityPool
	Provider *iam.WorkloadIdentityPoolProvider
	Bindings []*serviceaccount.IAMMember
}

// NewGitHubOIDC creates a new GitHubOIDC component resource.
func NewGitHubOIDC(ctx *pulumi.Context, name string, args *GitHubOIDCArgs, opts ...pulumi.ResourceOption) (*GitHubOIDC, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &GitHubOIDC{}
	err := ctx.RegisterComponentResource("pkg:cicd:GitHubOIDC", name, component, opts...)
	if err != nil {
		return nil, err
	}

	pool, err := iam.NewWorkloadIdentityPool(ctx, name+"-pool", &iam.WorkloadIdentityPoolArgs{
		Project:                args.ProjectID,
		WorkloadIdentityPoolId: args.PoolID,
		Disabled:               pulumi.Bool(false),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Pool = pool

	provider, err := iam.NewWorkloadIdentityPoolProvider(ctx, name+"-provider", &iam.WorkloadIdentityPoolProviderArgs{
		Project:                        args.ProjectID,
		WorkloadIdentityPoolId:         pool.WorkloadIdentityPoolId,
		WorkloadIdentityPoolProviderId: args.ProviderID,
		AttributeCondition:             args.AttributeCondition,
		AttributeMapping: pulumi.StringMap{
			"google.subject":       pulumi.String("assertion.sub"),
			"attribute.actor":      pulumi.String("assertion.actor"),
			"attribute.aud":        pulumi.String("assertion.aud"),
			"attribute.repository": pulumi.String("assertion.repository"),
		},
		Oidc: &iam.WorkloadIdentityPoolProviderOidcArgs{
			IssuerUri: pulumi.String("https://token.actions.githubusercontent.com"),
		},
	}, pulumi.Parent(pool))
	if err != nil {
		return nil, err
	}
	component.Provider = provider

	for key, entry := range args.SAMapping {
		member := pulumi.Sprintf("principalSet://iam.googleapis.com/%s/%s", pool.Name, entry.Attribute)
		binding, err := serviceaccount.NewIAMMember(ctx, fmt.Sprintf("%s-binding-%s", name, key), &serviceaccount.IAMMemberArgs{
			ServiceAccountId: entry.SAName,
			Role:             pulumi.String("roles/iam.workloadIdentityUser"),
			Member:           member,
		}, pulumi.Parent(provider))
		if err != nil {
			return nil, err
		}
		component.Bindings = append(component.Bindings, binding)
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"poolName":     pool.Name,
		"providerName": provider.Name,
	})

	return component, nil
}

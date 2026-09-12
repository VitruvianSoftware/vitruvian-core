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

package cicd

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/iam"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// GitLabOIDCArgs configures a GitLab OIDC provider, matching the
// 0-bootstrap/modules/gitlab-oidc local module in the Terraform foundation.
type GitLabOIDCArgs struct {
	// ProjectID is the GCP project in which to create the WIF resources.
	ProjectID pulumi.StringInput
	// PoolID is the Workload Identity Pool ID (e.g., "foundation-pool").
	PoolID pulumi.StringInput
	// ProviderID is the WIF Provider ID (e.g., "foundation-gl-provider").
	ProviderID pulumi.StringInput
	// AttributeCondition is the CEL expression restricting which tokens are accepted.
	// Example: "assertion.project_path.startsWith('my-group/')"
	AttributeCondition pulumi.StringInput
	// SAMapping maps logical keys to service account + attribute binding pairs.
	SAMapping map[string]SAMappingEntry
	// IssuerUri is the GitLab OIDC issuer URL. Defaults to "https://gitlab.com".
	IssuerUri pulumi.StringInput
}

// GitLabOIDC represents a GitLab Workload Identity Federation configuration.
type GitLabOIDC struct {
	pulumi.ResourceState
	Pool     *iam.WorkloadIdentityPool
	Provider *iam.WorkloadIdentityPoolProvider
	Bindings []*serviceaccount.IAMMember
}

// NewGitLabOIDC creates a new GitLabOIDC component resource.
func NewGitLabOIDC(ctx *pulumi.Context, name string, args *GitLabOIDCArgs, opts ...pulumi.ResourceOption) (*GitLabOIDC, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &GitLabOIDC{}
	err := ctx.RegisterComponentResource("pkg:cicd:GitLabOIDC", name, component, opts...)
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

	issuerUri := args.IssuerUri
	if issuerUri == nil {
		issuerUri = pulumi.String("https://gitlab.com")
	}

	// Attribute mapping matches the full default set from the TF gitlab-oidc
	// module variables.tf (13 attributes), ensuring parity with the upstream.
	provider, err := iam.NewWorkloadIdentityPoolProvider(ctx, name+"-provider", &iam.WorkloadIdentityPoolProviderArgs{
		Project:                        args.ProjectID,
		WorkloadIdentityPoolId:         pool.WorkloadIdentityPoolId,
		WorkloadIdentityPoolProviderId: args.ProviderID,
		AttributeCondition:             args.AttributeCondition,
		AttributeMapping: pulumi.StringMap{
			// Principal IAM
			"google.subject": pulumi.String("assertion.sub"),
			// Standard OIDC claims
			"attribute.sub": pulumi.String("assertion.sub"),
			"attribute.iss": pulumi.String("assertion.iss"),
			"attribute.aud": pulumi.String("assertion.aud"),
			"attribute.exp": pulumi.String("assertion.exp"),
			"attribute.nbf": pulumi.String("assertion.nbf"),
			"attribute.iat": pulumi.String("assertion.iat"),
			"attribute.jti": pulumi.String("assertion.jti"),
			// GitLab custom claims
			"attribute.namespace_id":   pulumi.String("assertion.namespace_id"),
			"attribute.namespace_path": pulumi.String("assertion.namespace_path"),
			"attribute.project_id":     pulumi.String("assertion.project_id"),
			"attribute.project_path":   pulumi.String("assertion.project_path"),
			"attribute.user_id":        pulumi.String("assertion.user_id"),
			"attribute.user_login":     pulumi.String("assertion.user_login"),
			"attribute.user_email":     pulumi.String("assertion.user_email"),
		},
		Oidc: &iam.WorkloadIdentityPoolProviderOidcArgs{
			IssuerUri: issuerUri,
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

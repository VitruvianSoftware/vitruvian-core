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

// Package gitlaboidc mirrors the upstream terraform-example-foundation
// 0-bootstrap/modules/gitlab-oidc module: a Workload Identity Federation
// pool + OIDC provider for GitLab CI/CD, plus per-service-account
// workloadIdentityUser bindings so GitLab pipelines can impersonate the
// foundation stage service accounts.
package gitlaboidc

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/iam"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// NewGitlabOidc provisions the WIF pool, OIDC provider and SA bindings.
func NewGitlabOidc(ctx *pulumi.Context, name string, args *GitlabOidcArgs, opts ...pulumi.ResourceOption) (*GitlabOidc, error) {
	var resource GitlabOidc
	err := ctx.RegisterComponentResource("modules:gitlab-oidc:GitlabOidc", name, &resource, opts...)
	if err != nil {
		return nil, err
	}

	serviceList := args.ServiceList
	if serviceList == nil {
		serviceList = defaultServiceList
	}
	poolDescription := args.PoolDescription
	if poolDescription == "" {
		poolDescription = "Workload Identity Pool managed by Pulumi"
	}
	providerDescription := args.ProviderDescription
	if providerDescription == "" {
		providerDescription = "Workload Identity Pool Provider managed by Pulumi"
	}
	issuerURI := args.IssuerURI
	if issuerURI == "" {
		issuerURI = "https://gitlab.com"
	}
	attributeMapping := args.AttributeMapping
	if attributeMapping == nil {
		attributeMapping = defaultAttributeMapping
	}

	// Mirrors: google_project_service.services (disable_on_destroy = false).
	services := make([]pulumi.Resource, 0, len(serviceList))
	for _, svc := range serviceList {
		service, err := projects.NewService(ctx, fmt.Sprintf("%s-%s", name, svc), &projects.ServiceArgs{
			Project:          args.ProjectID,
			Service:          pulumi.String(svc),
			DisableOnDestroy: pulumi.Bool(false),
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}
		services = append(services, service)
	}

	// Mirrors: google_iam_workload_identity_pool.main.
	// dependsOn the API enablement so a cold first apply is race-free
	// (upstream relies on eventual convergence; we order deterministically).
	poolArgs := &iam.WorkloadIdentityPoolArgs{
		Project:                args.ProjectID,
		WorkloadIdentityPoolId: pulumi.String(args.PoolID),
		Description:            pulumi.String(poolDescription),
		Disabled:               pulumi.Bool(false),
	}
	if args.PoolDisplayName != "" {
		poolArgs.DisplayName = pulumi.String(args.PoolDisplayName)
	}
	pool, err := iam.NewWorkloadIdentityPool(ctx, fmt.Sprintf("%s-pool", name), poolArgs,
		pulumi.Parent(&resource), pulumi.DependsOn(services))
	if err != nil {
		return nil, err
	}

	// Mirrors: google_iam_workload_identity_pool_provider.main.
	mapping := pulumi.StringMap{}
	for k, v := range attributeMapping {
		mapping[k] = pulumi.String(v)
	}
	audiences := pulumi.StringArray{}
	for _, aud := range args.AllowedAudiences {
		audiences = append(audiences, pulumi.String(aud))
	}
	providerArgs := &iam.WorkloadIdentityPoolProviderArgs{
		Project:                        args.ProjectID,
		WorkloadIdentityPoolId:         pool.WorkloadIdentityPoolId,
		WorkloadIdentityPoolProviderId: pulumi.String(args.ProviderID),
		Description:                    pulumi.String(providerDescription),
		AttributeCondition:             args.AttributeCondition,
		AttributeMapping:               mapping,
		Oidc: &iam.WorkloadIdentityPoolProviderOidcArgs{
			AllowedAudiences: audiences,
			IssuerUri:        pulumi.String(issuerURI),
		},
	}
	if args.ProviderDisplayName != "" {
		providerArgs.DisplayName = pulumi.String(args.ProviderDisplayName)
	}
	provider, err := iam.NewWorkloadIdentityPoolProvider(ctx, fmt.Sprintf("%s-provider", name), providerArgs,
		pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	// Mirrors: google_service_account_iam_member.wif-sa.
	for key, entry := range args.SAMapping {
		_, err := serviceaccount.NewIAMMember(ctx, fmt.Sprintf("%s-wif-sa-%s", name, key), &serviceaccount.IAMMemberArgs{
			ServiceAccountId: entry.SAName,
			Role:             pulumi.String("roles/iam.workloadIdentityUser"),
			Member:           pulumi.Sprintf("principalSet://iam.googleapis.com/%s/%s", pool.Name, entry.Attribute),
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}
	}

	resource.PoolName = pool.Name
	resource.ProviderName = provider.Name

	return &resource, nil
}

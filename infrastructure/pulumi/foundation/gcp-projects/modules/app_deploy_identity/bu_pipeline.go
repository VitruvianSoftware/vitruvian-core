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

// bu_pipeline.go issues the BUSINESS-UNIT app-infra pipeline identity: the
// service account that applies the stage-5 (gcp-app-infra) leaf for one BU in
// one environment.
//
// This is the direct analogue of upstream's app-infra pipeline service
// accounts, which 4-projects seeds via modules/single_project's sa_roles. It is
// deliberately SEPARATE from the per-app deploy identity in main.go:
//
//   - per-app SA  → deploys ONE application's own resources
//   - BU pipeline SA → applies the stage-5 LEAF, which may host several apps
//
// A stage-5 leaf is one Pulumi stack per BU per env, so it cannot be applied by
// "the app's" SA once a second app lands there — hence a BU-scoped identity.
//
// WHY THIS MAKES UNGATING STAGE 5 SAFE. This SA applies the workload stage, but
// every grant it holds — including its own — is authored HERE, in stage 4,
// which it does not apply. It therefore cannot widen its own permissions, which
// is what a reviewer gate on stage 5 would otherwise have to enforce by hand on
// every routine deploy (docs/engineering/core-vs-application-infrastructure.md
// §4.1).
package app_deploy_identity

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// PipelineArgs configures one BU's app-infra pipeline identity for one env.
type PipelineArgs struct {
	// BusinessCode is the BU this pipeline serves, e.g. "bu1".
	BusinessCode string
	// Env is the environment (development/nonproduction/production).
	Env string
	// ProjectID is the env's app-hosting project the stage-5 leaf deploys into.
	ProjectID pulumi.StringInput
	// Roles are the project-level roles needed to apply stage-5 workloads.
	Roles []string
	// WorkloadIdentityPool is the shared pool from gcp-bootstrap.
	WorkloadIdentityPool pulumi.StringInput
	// GitHubEnvironment is the stage-5 deploy environment permitted to
	// impersonate it, e.g. "foundation-app-development".
	GitHubEnvironment string
}

// PipelineResult is what the leaf exports for the stage-5 workflow to consume.
type PipelineResult struct {
	ServiceAccountEmail pulumi.StringOutput
}

// DeployBUPipeline issues one BU's app-infra pipeline identity.
func DeployBUPipeline(ctx *pulumi.Context, name string, args *PipelineArgs) (*PipelineResult, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}
	if args.BusinessCode == "" {
		return nil, fmt.Errorf("BusinessCode is required")
	}
	if args.GitHubEnvironment == "" {
		return nil, fmt.Errorf("GitHubEnvironment is required")
	}

	// Account ids are capped at 30 chars; "sa-app-infra-<bu>" stays well under.
	sa, err := serviceaccount.NewAccount(ctx, name+"-app-infra-pipeline-sa", &serviceaccount.AccountArgs{
		AccountId:                 pulumi.String(fmt.Sprintf("sa-app-infra-%s", args.BusinessCode)),
		DisplayName:               pulumi.Sprintf("%s app-infra pipeline (%s)", args.BusinessCode, args.Env),
		Description:               pulumi.String("Applies the gcp-app-infra (stage 5) leaf. Grants authored in foundation/gcp-projects, which it does not apply."),
		Project:                   args.ProjectID,
		CreateIgnoreAlreadyExists: pulumi.Bool(true),
	})
	if err != nil {
		return nil, err
	}

	member := sa.Email.ApplyT(func(e string) string { return "serviceAccount:" + e }).(pulumi.StringOutput)
	for _, role := range args.Roles {
		if _, err := projects.NewIAMMember(ctx, fmt.Sprintf("%s-app-infra-%s", name, sanitize(role)), &projects.IAMMemberArgs{
			Project: args.ProjectID,
			Role:    pulumi.String(role),
			Member:  member,
		}); err != nil {
			return nil, err
		}
	}

	if _, err := serviceaccount.NewIAMMember(ctx, name+"-app-infra-wif", &serviceaccount.IAMMemberArgs{
		ServiceAccountId: sa.Name,
		Role:             pulumi.String("roles/iam.workloadIdentityUser"),
		Member: pulumi.Sprintf("principalSet://iam.googleapis.com/%s/attribute.environment/%s",
			args.WorkloadIdentityPool, args.GitHubEnvironment),
	}); err != nil {
		return nil, err
	}

	return &PipelineResult{ServiceAccountEmail: sa.Email}, nil
}

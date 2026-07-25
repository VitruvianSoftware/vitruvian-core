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

// Package serverless_space is an app-infra module that deploys a serverless
// (Cloud Run) workload into an environment project. It is the serverless peer
// to env_base (Compute Instance) and confidential_space (Confidential VM),
// composing the pkg/cloud_run primitive with a runtime service account, a
// per-app SECRET_PREFIX partition, secret-backed env vars, and an optional
// public (allUsers) invoker binding.
//
// The public invoker binding depends on the environment project carrying a
// Domain Restricted Sharing override (constraints/iam.allowedPolicyMemberDomains
// AllowAll) so that allUsers may be granted run.invoker — see the gcp-org stage.
//
// serverless_space has no upstream terraform-example-foundation counterpart;
// its file layout (main.go/variables.go/outputs.go) follows the same
// per-concern convention as env_base and confidential_space for consistency.
package serverless_space

import (
	"fmt"

	"github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_run"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudrunv2"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// DeployServerlessSpace deploys a Cloud Run workload (runtime SA + service +
// optional public invoker) into the target project.
func DeployServerlessSpace(ctx *pulumi.Context, name string, args *ServerlessSpaceArgs) (*ServerlessSpaceResult, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}
	// The DEPLOYED service name is per-environment: <app>-<env>. ServiceName is
	// the app's base name, so the env suffix is appended here rather than being
	// baked into config — a per-env config value would make the revision naming
	// below double up the environment (<app>-<env>-<env>-<digest>).
	//
	// This must match what oauth-user-inspector/infra/app already runs
	// (fmt.Sprintf("oauth-user-inspector-%s", env)). It previously did NOT: the
	// module used ServiceName verbatim, so the archetype would have declared
	// "oauth-user-inspector" against a live "oauth-user-inspector-development".
	// Importing and applying that renames the service, and a Cloud Run rename is
	// a delete + create — an outage on the production leg of the cutover.
	// TestServiceNameMatchesTheLiveService pins it.
	baseName := args.ServiceName
	if baseName == "" {
		baseName = "serverless-space"
	}
	serviceName := baseName
	if args.Env != "" {
		serviceName = fmt.Sprintf("%s-%s", baseName, args.Env)
	}

	// 1. Runtime service account — created unless the caller supplies one.
	var runtimeSAEmail pulumi.StringOutput
	if args.RuntimeServiceAccountEmail != nil {
		runtimeSAEmail = args.RuntimeServiceAccountEmail.ToStringOutput()
	} else {
		sa, err := serviceaccount.NewAccount(ctx, name+"-sa", &serviceaccount.AccountArgs{
			AccountId:                 pulumi.String("sa-" + baseName),
			DisplayName:               pulumi.Sprintf("%s serverless runtime SA", baseName),
			Project:                   args.ProjectID,
			CreateIgnoreAlreadyExists: pulumi.Bool(true),
		})
		if err != nil {
			return nil, err
		}
		runtimeSAEmail = sa.Email
	}

	// 2. Merge the per-app SECRET_PREFIX into the plain env map.
	envVars := map[string]string{}
	for k, v := range args.EnvVars {
		envVars[k] = v
	}
	if args.SecretPrefix != "" {
		envVars["SECRET_PREFIX"] = args.SecretPrefix
	}

	// 3. Blue-green revision naming + traffic split.
	var revisionName string
	var traffics []cloud_run.TrafficTarget
	if args.RevisionSuffix != "" {
		revisionName = fmt.Sprintf("%s-%s", serviceName, args.RevisionSuffix)
		if args.Promote || args.StableRevision == "" {
			traffics = []cloud_run.TrafficTarget{{Revision: revisionName, Percent: 100}}
		} else {
			traffics = []cloud_run.TrafficTarget{
				{Revision: args.StableRevision, Percent: 100},
				{Revision: revisionName, Percent: 0, Tag: "candidate"},
			}
		}
	}

	// 4. Cloud Run service (promoted digest image).
	cr, err := cloud_run.NewCloudRun(ctx, name, &cloud_run.CloudRunArgs{
		ProjectID:           args.ProjectID,
		Region:              args.Region,
		Name:                serviceName,
		Image:               args.ImageDigest,
		ServiceAccountEmail: runtimeSAEmail,
		Env:                 envVars,
		SecretEnv:           args.SecretEnv,
		RevisionName:        revisionName,
		Traffics:            traffics,
		MinInstances:        args.MinInstances,
		MaxInstances:        args.MaxInstances,
		Labels: map[string]string{
			"env":           args.Env,
			"business-unit": args.BusinessUnit,
		},
	})
	if err != nil {
		return nil, err
	}

	// 4. Optional public invoker (allUsers). Requires the project-scoped DRS
	//    override applied in the gcp-org stage.
	if args.PublicInvoker {
		if _, err := cloudrunv2.NewServiceIamMember(ctx, name+"-public-invoker", &cloudrunv2.ServiceIamMemberArgs{
			Project:  args.ProjectID,
			Location: args.Region,
			Name:     cr.Service.Name,
			Role:     pulumi.String("roles/run.invoker"),
			Member:   pulumi.String("allUsers"),
		}); err != nil {
			return nil, err
		}
	}

	return &ServerlessSpaceResult{
		ServiceName:    cr.Service.Name,
		ServiceUri:     cr.Service.Uri,
		RuntimeSAEmail: runtimeSAEmail,
	}, nil
}

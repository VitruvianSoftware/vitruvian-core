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
	serviceName := args.ServiceName
	if serviceName == "" {
		serviceName = "serverless-space"
	}

	// 1. Runtime service account — created unless the caller supplies one.
	var runtimeSAEmail pulumi.StringOutput
	if args.RuntimeServiceAccountEmail != nil {
		runtimeSAEmail = args.RuntimeServiceAccountEmail.ToStringOutput()
	} else {
		sa, err := serviceaccount.NewAccount(ctx, name+"-sa", &serviceaccount.AccountArgs{
			AccountId:                 pulumi.String("sa-" + serviceName),
			DisplayName:               pulumi.Sprintf("%s serverless runtime SA", serviceName),
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
		revisionName = fmt.Sprintf("%s-%s-%s", serviceName, args.Env, args.RevisionSuffix)
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

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

// remote.go mirrors upstream
// 5-app-infra/business_unit_1/development/remote.tf — the cross-stage reads
// from the 4-projects leaves of this business unit (engine adaptation: Pulumi
// Stack References instead of terraform_remote_state).

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// projectsRemoteState carries the 4-projects outputs this leaf consumes,
// resolved from the business unit's env and shared leaf stacks.
type projectsRemoteState struct {
	// AppProjectID / AppProjectNumber identify the SVPC-attached application
	// project (upstream's shared_vpc_project).
	AppProjectID     pulumi.StringOutput
	AppProjectNumber pulumi.StringOutput
	// SubnetSelfLink is the first shared-VPC subnet self link.
	SubnetSelfLink pulumi.StringOutput
	// WorkloadSAEmail is the Confidential Space workload service account.
	WorkloadSAEmail pulumi.StringOutput
	// ImageProjectID is the project whose Artifact Registry hosts the
	// Confidential Space workload image (see resolveProjectsRemoteState).
	ImageProjectID pulumi.StringOutput
	// Region is the deployment region: the leaf's region config when set,
	// otherwise the 4-projects default_region.
	Region pulumi.StringOutput
}

// resolveProjectsRemoteState opens the 4-projects Stack References and
// resolves the outputs this leaf consumes.
func resolveProjectsRemoteState(ctx *pulumi.Context, cfg *AppInfraConfig) (*projectsRemoteState, error) {
	// 1. Stack Reference: this environment's 4-projects leaf
	// (business_unit_1/<env> — upstream's projects_env remote state).
	projStack, err := pulumi.NewStackReference(ctx, "projects", &pulumi.StackReferenceArgs{
		Name: pulumi.String(cfg.ProjectsStackName),
	})
	if err != nil {
		return nil, err
	}

	// 2. Stack Reference: the BU's 4-projects shared leaf
	// (business_unit_1/shared — upstream's business_unit_shared remote
	// state, which supplies the project that hosts the Confidential Space
	// workload image registry).
	projSharedStack, err := pulumi.NewStackReference(ctx, "projects_shared", &pulumi.StackReferenceArgs{
		Name: pulumi.String(cfg.ProjectsSharedStackName),
	})
	if err != nil {
		return nil, err
	}

	// --- Resolve outputs from the 4-projects env leaf ---
	appProjectID := projStack.GetStringOutput(pulumi.String("shared_vpc_project"))
	appProjectNumber := projStack.GetStringOutput(pulumi.String("shared_vpc_project_number"))
	subnetsSelfLinks := projStack.GetOutput(pulumi.String("subnets_self_links")).ApplyT(func(v interface{}) string {
		if links, ok := v.([]interface{}); ok && len(links) > 0 {
			return links[0].(string)
		}
		return ""
	}).(pulumi.StringOutput)
	workloadSAEmail := projStack.GetStringOutput(pulumi.String("confidential_space_workload_sa"))

	// Upstream's confidential_space module reads
	// bootstrap_cloudbuild_project_id from the 4-projects shared workspace
	// (the project whose Artifact Registry hosts the workload image). Our
	// WIF port has no Cloud Build project chain: the BU's shared
	// build/artifact home is the app-infra pipeline project owned by the
	// 4-projects business_unit_1/shared leaf, exported as
	// infra_pipeline_project_id (documented engine-difference workaround).
	imageProjectID := projSharedStack.GetStringOutput(pulumi.String("infra_pipeline_project_id"))

	appRegion := pulumi.String(cfg.Region).ToStringOutput()
	if cfg.Region == "" {
		appRegion = projStack.GetStringOutput(pulumi.String("default_region"))
	}

	return &projectsRemoteState{
		AppProjectID:     appProjectID,
		AppProjectNumber: appProjectNumber,
		SubnetSelfLink:   subnetsSelfLinks,
		WorkloadSAEmail:  workloadSAEmail,
		ImageProjectID:   imageProjectID,
		Region:           appRegion,
	}, nil
}

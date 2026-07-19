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

// Cross-stage StackReferences for this leaf — the Pulumi analogue of upstream
// 4-projects/business_unit_1/production/remote.tf (its terraform_remote_state
// reads of the earlier stages' states).

package main

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// stackRefs carries the cross-stage outputs this leaf consumes, resolved from
// the earlier stages' stacks by loadStackReferences.
type stackRefs struct {
	// From the 2-environments leaf stack (always required).
	FolderID     pulumi.StringOutput
	KMSProjectID pulumi.StringOutput
	// From the 1-org stack (only when a consuming project type is enabled;
	// empty-string outputs otherwise).
	NetworkProjectID pulumi.StringOutput
	ACMPolicyID      pulumi.StringOutput
	// From the 3-networks leaf stack (only when a perimeter-attaching project
	// type is enabled; an empty-string output otherwise).
	PerimeterName pulumi.StringOutput
}

// loadStackReferences resolves the cross-stage StackReferences. Only the
// environment reference is unconditional; the org and network references are
// created only when an enabled project type consumes their outputs.
func loadStackReferences(ctx *pulumi.Context, cfg *ProjectsConfig) (*stackRefs, error) {
	emptyStr := pulumi.String("").ToStringOutput()
	refs := &stackRefs{
		NetworkProjectID: emptyStr,
		ACMPolicyID:      emptyStr,
		PerimeterName:    emptyStr,
	}

	// 1. Environment StackReference (Stage 2) — always required: it provides
	// the environment folder (BU-folder parent) and the per-env KMS project.
	envStack, err := pulumi.NewStackReference(ctx, "environment", &pulumi.StackReferenceArgs{
		Name: pulumi.String(cfg.EnvStackName),
	})
	if err != nil {
		return nil, err
	}
	// The 2-environments leaf stack for this environment exports bare
	// "env_folder" / "env_kms_project_id" keys (upstream reads
	// env_folder_name from the single 2-environments remote state; our
	// per-env leaf stacks scope the state per environment instead).
	refs.FolderID = envStack.GetStringOutput(pulumi.String("env_folder"))
	refs.KMSProjectID = envStack.GetStringOutput(pulumi.String("env_kms_project_id"))

	// 1b. Organization StackReference (Stage 1) — only when a project type
	// that consumes its outputs is enabled (SVPC host, peering-to-host, or
	// confidential space). The common-folder infra pipeline moved to the
	// business_unit_1/shared leaf, which keeps its own org reference.
	if cfg.SVPCProjectEnabled || cfg.PeeringProjectEnabled || cfg.ConfidentialSpaceEnabled {
		orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.OrgStackName),
		})
		if err != nil {
			return nil, err
		}
		refs.NetworkProjectID = orgStack.GetStringOutput(pulumi.String(fmt.Sprintf("%s_network_project_id", cfg.Env)))
		refs.ACMPolicyID = orgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id"))
	}

	// 1c. Network StackReference (Stage 3) — only when a project attaches to
	// the VPC-SC perimeter (SVPC-attached or confidential-space projects).
	if cfg.SVPCProjectEnabled || cfg.ConfidentialSpaceEnabled {
		netStack, err := pulumi.NewStackReference(ctx, "network", &pulumi.StackReferenceArgs{
			Name: pulumi.String(cfg.NetworkStackName),
		})
		if err != nil {
			return nil, err
		}
		refs.PerimeterName = netStack.GetStringOutput(pulumi.String("service_perimeter_name"))
	}

	return refs, nil
}

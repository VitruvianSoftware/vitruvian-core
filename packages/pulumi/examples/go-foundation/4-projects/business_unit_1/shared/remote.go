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

// Cross-stage StackReferences for the shared leaf — the Pulumi analogue of
// upstream 4-projects/business_unit_1/shared/remote.tf (its
// terraform_remote_state reads of the earlier stages' states).

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// stackRefs carries the cross-stage outputs this leaf consumes, resolved from
// the earlier stages' stacks by loadStackReferences.
type stackRefs struct {
	// CommonFolderID is the 1-org COMMON folder the infra-pipeline project is
	// parented under.
	CommonFolderID pulumi.StringOutput
}

// loadStackReferences resolves the cross-stage StackReferences.
func loadStackReferences(ctx *pulumi.Context, cfg *SharedConfig) (*stackRefs, error) {
	// Organization StackReference (Stage 1) — provides the COMMON folder the
	// infra-pipeline project is parented under.
	orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
		Name: pulumi.String(cfg.OrgStackName),
	})
	if err != nil {
		return nil, err
	}
	return &stackRefs{
		CommonFolderID: orgStack.GetStringOutput(pulumi.String("common_folder_id")),
	}, nil
}

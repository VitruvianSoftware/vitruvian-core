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

// Package single_project wraps the project-factory library for single project
// creation. Mirrors terraform-example-foundation/4-projects/modules/single_project:
// the leaf building block that every BU project type (SVPC-attached, floating,
// peering, confidential-space) is created from.
//
// File layout mirrors the upstream module: main.go (main.tf), variables.go
// (variables.tf), outputs.go (outputs.tf); versions.tf maps to the shared
// modules/go.mod (engine adaptation).
//
// It is a PLAIN factory function (not a ComponentResource): New calls
// project.NewProject with the caller-supplied logical name UNCHANGED, so the
// resulting resource URN is byte-identical to the pre-refactor inline call and
// `pulumi preview` stays a no-op. Type-specific inputs (project id, activated
// APIs, labels, default-SA posture) come in via Args; the common project-factory
// wiring (billing account, folder, random suffix, budget) lives here.
package single_project

import (
	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// New creates a single project via the project-factory library. The logical
// name is passed straight through to project.NewProject to preserve the resource
// URN.
func New(ctx *pulumi.Context, name string, args *Args) (*Result, error) {
	proj, err := project.NewProject(ctx, name, &project.ProjectArgs{
		DefaultServiceAccount: args.DefaultServiceAccount,
		ProjectID:             pulumi.String(args.ProjectID),
		Name:                  pulumi.String(args.ProjectID),
		FolderID:              args.FolderID,
		BillingAccount:        pulumi.String(args.BillingAccount),
		RandomProjectID:       args.RandomProjectID,
		Labels:                args.Labels,
		Budget:                args.Budget,
		ActivateApis:          args.ActivateApis,
		ApiPropagationSeconds: args.ApiPropagationSeconds,
	})
	if err != nil {
		return nil, err
	}

	// Gate the project id on the API-propagation wait when one exists. The
	// factory's ApisReady is a *local.Command only when ApiPropagationSeconds > 0;
	// combining the id with the command's Stdout makes any resource that consumes
	// ApisReadyProjectID wait for the sleep to complete (data dependency), even
	// inside library components we cannot DependsOn into.
	gatedID := proj.Project.ProjectId
	if cmd, ok := proj.ApisReady.(*local.Command); ok {
		gatedID = pulumi.All(proj.Project.ProjectId, cmd.Stdout).ApplyT(func(v []interface{}) string {
			return v[0].(string)
		}).(pulumi.StringOutput)
	}

	return &Result{
		Project:            proj,
		ProjectID:          proj.Project.ProjectId,
		ProjectNumber:      proj.Project.Number,
		ApisReadyProjectID: gatedID,
	}, nil
}

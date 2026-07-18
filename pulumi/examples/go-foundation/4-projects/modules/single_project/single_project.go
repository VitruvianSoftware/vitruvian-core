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

// Args are the inputs to a single project creation. ProjectID doubles as the
// display Name in every upstream call site, so New sets both from this one field
// (matching the pre-refactor inline `ProjectID`/`Name` pair, which were always
// the same fmt.Sprintf string).
type Args struct {
	ProjectID             string
	FolderID              pulumi.StringOutput
	BillingAccount        string
	RandomProjectID       bool
	Labels                pulumi.StringMapInput
	Budget                *project.BudgetConfig
	ActivateApis          []string
	DefaultServiceAccount string
	// ApiPropagationSeconds is forwarded to the project factory: >0 makes the
	// factory's ApisReady handle a `sleep N` gated on all enabled Services (see
	// project_factory.ProjectArgs), 0 leaves ApisReady = the project itself.
	ApiPropagationSeconds int
}

// Result holds the created project. Project is the raw project-factory handle,
// surfaced so callers can attach it to a Shared VPC / VPC-SC perimeter, hang CMEK
// storage off it, or build peering infrastructure on it — exactly as the inline
// code did with the `*project.Project` return value.
type Result struct {
	Project       *project.Project
	ProjectID     pulumi.StringOutput
	ProjectNumber pulumi.StringOutput
	// ApisReadyProjectID is the project id as a DATA dependency on the API
	// propagation gate: it resolves only after the factory's ApisReady wait has
	// run. Thread it (instead of ProjectID) into library components whose inner
	// resources must not race freshly-enabled APIs — a component-level DependsOn
	// does NOT propagate to a component's children in the Pulumi Go SDK, so a
	// data dependency is the only way to gate them from outside the library.
	ApisReadyProjectID pulumi.StringOutput
}

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

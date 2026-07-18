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
}

// Result holds the created project. Project is the raw project-factory handle,
// surfaced so callers can attach it to a Shared VPC / VPC-SC perimeter, hang CMEK
// storage off it, or build peering infrastructure on it — exactly as the inline
// code did with the `*project.Project` return value.
type Result struct {
	Project       *project.Project
	ProjectID     pulumi.StringOutput
	ProjectNumber pulumi.StringOutput
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
	})
	if err != nil {
		return nil, err
	}

	return &Result{
		Project:       proj,
		ProjectID:     proj.Project.ProjectId,
		ProjectNumber: proj.Project.Number,
	}, nil
}

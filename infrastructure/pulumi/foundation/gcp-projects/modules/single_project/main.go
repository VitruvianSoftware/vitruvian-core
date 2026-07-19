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

// Package single_project wraps the project-factory library for single project
// creation. Mirrors terraform-example-foundation/4-projects/modules/single_project:
// the leaf building block that every BU project type (SVPC-attached, floating,
// oss-floating, peering, confidential-space) is created from.
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

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

// Package network creates a single per-environment Shared-VPC host project
// (prj-{env_code}-svpc) under the Network folder via the published
// project_factory library. It mirrors upstream terraform-example-foundation
// 1-org/modules/network (invoked per env as module "environment_network" in
// 1-org projects.tf). The thin stage root (projects.go) resolves scalars from
// stack config and calls New once per environment.
package network

import (
	"fmt"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Args are the inputs to the network module for one environment's Shared-VPC
// host project. It carries resolved scalars (never *OrgConfig — the module
// cannot import the root package) plus the network folder ID and the
// pre-resolved budget config.
type Args struct {
	Env                   string // e.g. "development"
	EnvCode               string // e.g. "d"
	ProjectPrefix         string
	FolderID              pulumi.StringOutput
	BillingAccount        string
	RandomSuffix          bool
	ProjectDeletionPolicy string
	DefaultServiceAccount string
	Budget                *project.BudgetConfig
}

// Result holds the outputs of a single Shared-VPC host project.
type Result struct {
	ProjectID     pulumi.StringOutput
	ProjectNumber pulumi.StringOutput
}

// New creates one per-environment Shared-VPC host project under the Network
// folder. Mirrors module "environment_network" in upstream 1-org projects.tf.
// The project ID follows the upstream convention prj-{env_code}-svpc, and the
// labels/APIs match the upstream shared-vpc-host network module.
func New(ctx *pulumi.Context, name string, args *Args) (*Result, error) {
	projectID := fmt.Sprintf("%s-%s-svpc", args.ProjectPrefix, args.EnvCode)

	p, err := project.NewProject(ctx, name, &project.ProjectArgs{
		ProjectID:       pulumi.String(projectID),
		Name:            pulumi.String(projectID),
		FolderID:        args.FolderID,
		BillingAccount:  pulumi.String(args.BillingAccount),
		RandomProjectID: args.RandomSuffix,
		ActivateApis: []string{
			"compute.googleapis.com",
			"dns.googleapis.com",
			"servicenetworking.googleapis.com",
			"container.googleapis.com",
			"logging.googleapis.com",
			"cloudresourcemanager.googleapis.com", // Gap 2: matches upstream network module
			"accesscontextmanager.googleapis.com", // Gap 2: needed for VPC Service Controls
			"billingbudgets.googleapis.com",
		},
		Labels: pulumi.StringMap{
			"environment":       pulumi.String(args.Env),
			"application_name":  pulumi.String("shared-vpc-host"), // upstream label value
			"billing_code":      pulumi.String("1234"),
			"primary_contact":   pulumi.String("james_nguyen"),
			"secondary_contact": pulumi.String("christine_kim"),
			"business_code":     pulumi.String("shared"),
			"env_code":          pulumi.String(args.EnvCode),
		},
		DeletionPolicy:        pulumi.String(args.ProjectDeletionPolicy),
		Budget:                args.Budget,
		DefaultServiceAccount: args.DefaultServiceAccount,
	})
	if err != nil {
		return nil, err
	}

	return &Result{
		ProjectID:     p.Project.ProjectId,
		ProjectNumber: p.Project.Number,
	}, nil
}

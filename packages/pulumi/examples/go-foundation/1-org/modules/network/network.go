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
			"primary_contact":   pulumi.String("example1"),
			"secondary_contact": pulumi.String("example2"),
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

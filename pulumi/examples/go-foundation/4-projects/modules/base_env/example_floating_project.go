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

package base_env

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-4-projects/modules/single_project"
)

// deployFloatingProject creates the floating project (not attached to any
// VPC), matching upstream's example_floating_project.tf (toggle-gated).
func deployFloatingProject(ctx *pulumi.Context, args *Args, result *BUProjects) error {
	if !args.FloatingProjectEnabled {
		return nil
	}

	floatingProject, err := single_project.New(ctx, "bu-floating-project", &single_project.Args{
		DefaultServiceAccount: "disable", // upstream default; see the svpc project
		ProjectID:             fmt.Sprintf("%s-%s-%s-sample-floating", args.ProjectPrefix, args.EnvCode, args.BusinessCode),
		FolderID:              args.FolderID,
		BillingAccount:        args.BillingAccount,
		RandomProjectID:       args.RandomSuffix,
		Labels:                args.Labels("sample-application", "none"),
		Budget:                args.Budget,
		ActivateApis: []string{
			"compute.googleapis.com",
			"container.googleapis.com",
			"run.googleapis.com",
			"artifactregistry.googleapis.com",
			"billingbudgets.googleapis.com",
			"logging.googleapis.com",
		},
		ApiPropagationSeconds: args.ApiPropagationSeconds,
	})
	if err != nil {
		return err
	}
	result.FloatingProjectID = floatingProject.ProjectID

	return nil
}

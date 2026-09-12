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

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-4-projects/modules/single_project"
)

// deploySharedVPCProject creates the SVPC-attached project, matching upstream's
// example_shared_vpc_project.tf (toggle-gated). This project is attached as a
// service project to the environment's Shared VPC host, enabling shared network
// resource access. CMEK storage (example_storage_cmek.go), the Shared-VPC
// attachment, and the VPC-SC perimeter attach all hang off this project, so
// they live inside the same gate.
func deploySharedVPCProject(ctx *pulumi.Context, args *Args, result *BUProjects) error {
	if !args.SVPCProjectEnabled {
		return nil
	}

	// NOTE: this API set is intentionally BROADER than upstream 4-projects
	// (which enables only accesscontextmanager on the svpc project, dns on
	// peering, and nothing on floating). We pre-enable the common workload APIs
	// (compute/container/run/artifactregistry/logging) so applications deployed
	// into these projects don't each have to turn them on; this also widens the
	// `restricted_enabled_apis` export. The floating/peering projects share
	// this posture.
	svpcApis := []string{
		"compute.googleapis.com",
		"container.googleapis.com",
		"run.googleapis.com",
		"artifactregistry.googleapis.com",
		"billingbudgets.googleapis.com",
		"logging.googleapis.com",
		"accesscontextmanager.googleapis.com",
		// storage: the CMEK bucket (deployCMEKStorage) lands on this project and
		// its GCS service agent is looked up via the API — enable it explicitly
		// so the cold-deploy path doesn't depend on implicit activation.
		"storage.googleapis.com",
	}

	svpcProject, err := single_project.New(ctx, "bu-svpc-project", &single_project.Args{
		// "disable" turns the project's default compute SA OFF, matching upstream
		// 4-projects (which relies on project-factory's default
		// default_service_account = "disable"). "deprivilege" — the softer posture
		// we shipped first — would leave the SA active, only de-editored.
		DefaultServiceAccount: "disable",
		ProjectID:             fmt.Sprintf("%s-%s-%s-sample-svpc", args.ProjectPrefix, args.EnvCode, args.BusinessCode),
		FolderID:              args.FolderID,
		BillingAccount:        args.BillingAccount,
		RandomProjectID:       args.RandomSuffix,
		Labels:                args.Labels("sample-application", "svpc"),
		Budget:                args.Budget,
		ActivateApis:          svpcApis,
		ApiPropagationSeconds: args.ApiPropagationSeconds,
	})
	if err != nil {
		return err
	}

	result.RestrictedEnabledApis = svpcApis

	// TODO(vpc-sc enablement): upstream project-factory serializes the perimeter
	// attach BEFORE the shared-VPC attach and waits vpc_service_control_sleep_
	// duration = "60s" between them, so the project is inside the perimeter
	// before it joins the shared VPC. Here the shared-VPC attach (below) and the
	// VPC-SC attach (further down) both hang only off the project and race. When
	// SVPC/VPC-SC are enabled for real, order them: DependsOn(perimeter-attach)
	// + a 60s propagation gate on this attach (the dependsOn+propagation-wait
	// pattern used elsewhere in the foundation).

	// Attach as a Shared VPC service project. DependsOn(ApisReady): the attach
	// requires compute.googleapis.com to be usable on the service project — on
	// a cold deploy it must wait out the API propagation gate.
	if _, err := compute.NewSharedVPCServiceProject(ctx, "svpc-attachment", &compute.SharedVPCServiceProjectArgs{
		HostProject:    args.NetworkProjectID,
		ServiceProject: svpcProject.Project.Project.ProjectId,
	}, pulumi.DependsOn([]pulumi.Resource{svpcProject.Project.ApisReady})); err != nil {
		return err
	}

	// VPC-SC Perimeter attachment — attach the SVPC project to the perimeter
	// matching upstream's vpc_service_control_attach_enabled behavior.
	if args.EnforceVpcSc {
		_, err := accesscontextmanager.NewServicePerimeterResource(ctx, "svpc-vpcsc-attach", &accesscontextmanager.ServicePerimeterResourceArgs{
			PerimeterName: args.PerimeterName,
			Resource: svpcProject.Project.Project.Number.ApplyT(func(n string) string {
				return fmt.Sprintf("projects/%s", n)
			}).(pulumi.StringOutput),
		})
		if err != nil {
			return err
		}
	} else {
		_, err := accesscontextmanager.NewServicePerimeterDryRunResource(ctx, "svpc-vpcsc-attach-dry-run", &accesscontextmanager.ServicePerimeterDryRunResourceArgs{
			PerimeterName: args.PerimeterName,
			Resource: svpcProject.Project.Project.Number.ApplyT(func(n string) string {
				return fmt.Sprintf("projects/%s", n)
			}).(pulumi.StringOutput),
		})
		if err != nil {
			return err
		}
	}

	result.SVPCProjectID = svpcProject.ProjectID
	result.SVPCProjectNumber = svpcProject.ProjectNumber

	// CMEK Storage — KMS keyring + crypto key in the env KMS project, encrypted
	// GCS bucket on the SVPC project (example_storage_cmek.go).
	if args.CMEKEnabled {
		cmekResult, err := deployCMEKStorage(ctx, args, svpcProject.Project, args.KMSProjectID)
		if err != nil {
			return err
		}
		result.CMEKBucket = &cmekResult.BucketName
		result.CMEKKeyring = &cmekResult.KeyringName
		// Populate CMEKKeys so the leaf's `keys` export is the crypto-key list
		// (upstream `keys(module.kms.keys)`), not the empty stub it was before.
		result.CMEKKeys = &cmekResult.Keys
	}

	return nil
}

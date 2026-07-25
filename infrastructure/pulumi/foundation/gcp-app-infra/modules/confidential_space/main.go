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

// Example: Confidential Space VM deployment with WIF attestation.
// To enable, remove this build constraint or build with: go build -tags=example
//
// Package confidential_space is an app-infra module that deploys a Confidential
// Space (Confidential VM) workload into an environment project: a Workload
// Identity Pool + OIDC attestation provider, the workloadIdentityUser IAM
// binding, and a Confidential VM built from a TEE image. It is the
// Confidential-VM archetype in the stage-5 catalog — peer to env_base (Compute
// Instance) and serverless_space (Cloud Run).
//
// It mirrors upstream terraform-example-foundation
// 5-app-infra/modules/confidential_space (main.go↔main.tf, variables.go↔
// variables.tf, outputs.go↔outputs.tf). Engine adaptation: upstream's
// remote_state reads have no equivalent — the calling env leaf resolves the
// 4-projects StackReferences itself and passes resolved values in (ProjectID,
// ProjectNumber, SubnetworkSelfLink, ...).
//
// Currently DORMANT in the live foundation: no leaf calls
// DeployConfidentialSpace yet (like env_base and serverless_space, it is part
// of the catalog awaiting a consumer). It is kept compiling and unit-tested so
// the archetype is ready to instantiate the moment an environment needs a
// Confidential Space workload.
package confidential_space

import (
	"fmt"

	computeinstance "github.com/VitruvianSoftware/pulumi-library/go/pkg/compute_instance"
	instancetemplate "github.com/VitruvianSoftware/pulumi-library/go/pkg/instance_template"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/iam"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumiverse/pulumi-time/sdk/go/time"
)

// deployConfidentialSpace creates a Workload Identity Pool, OIDC attestation
// provider, IAM bindings, and a Confidential VM, matching the upstream
// Terraform foundation's confidential_space module.
func DeployConfidentialSpace(ctx *pulumi.Context, name string, args *ConfidentialSpaceArgs) (*ConfidentialSpaceResult, error) {
	// 1. Workload Identity Pool
	pool, err := iam.NewWorkloadIdentityPool(ctx, name+"-pool", &iam.WorkloadIdentityPoolArgs{
		WorkloadIdentityPoolId: pulumi.String("confidential-space-pool"),
		Disabled:               pulumi.Bool(false),
		Project:                args.ProjectID,
	})
	if err != nil {
		return nil, err
	}

	// 2. Workload Identity Pool Provider — OIDC attestation verifier
	// Attribute condition matches upstream's attribute_condition heredoc exactly.
	attributeCondition := args.WorkloadSAEmail.ToStringOutput().ApplyT(func(saEmail string) string {
		return fmt.Sprintf(
			`assertion.submods.container.image_digest == "%s" && "%s" in assertion.google_service_accounts && assertion.swname == "CONFIDENTIAL_SPACE" && "STABLE" in assertion.submods.confidential_space.support_attributes`,
			args.ConfidentialImageDigest, saEmail,
		)
	}).(pulumi.StringOutput)

	provider, err := iam.NewWorkloadIdentityPoolProvider(ctx, name+"-provider", &iam.WorkloadIdentityPoolProviderArgs{
		WorkloadIdentityPoolId:         pool.WorkloadIdentityPoolId,
		WorkloadIdentityPoolProviderId: pulumi.String("attestation-verifier"),
		DisplayName:                    pulumi.String("attestation-verifier"),
		Description:                    pulumi.String("OIDC provider for confidential computing attestation"),
		Project:                        args.ProjectID,
		Oidc: &iam.WorkloadIdentityPoolProviderOidcArgs{
			IssuerUri:        pulumi.String("https://confidentialcomputing.googleapis.com/"),
			AllowedAudiences: pulumi.StringArray{pulumi.String("https://sts.googleapis.com")},
		},
		AttributeMapping: pulumi.StringMap{
			"google.subject":         pulumi.String(`"gcpcs::" + assertion.submods.container.image_digest + "::" + assertion.submods.gce.project_number + "::" + assertion.submods.gce.instance_id`),
			"attribute.image_digest": pulumi.String(`assertion.submods.container.image_digest`),
		},
		AttributeCondition: attributeCondition,
	})
	if err != nil {
		return nil, err
	}

	// 2.5. Wait for Workload Identity Pool propagation
	// Matches upstream's time_sleep.wait_workload_pool_propagation
	// GCP IAM can take up to 60s to recognize the new pool's principal identifiers.
	wait, err := time.NewSleep(ctx, name+"-wait-wip", &time.SleepArgs{
		CreateDuration: pulumi.String("60s"),
	}, pulumi.DependsOn([]pulumi.Resource{provider}))
	if err != nil {
		return nil, err
	}

	// 3. IAM Binding for the Workload SA
	// Uses the project number from the 4-projects stack export — NOT a
	// runtime LookupProject call (which would be a Pulumi anti-pattern
	// breaking previews).
	member := args.ProjectNumber.ToStringOutput().ApplyT(func(num string) string {
		return fmt.Sprintf(
			"principalSet://iam.googleapis.com/projects/%s/locations/global/workloadIdentityPools/confidential-space-pool/*",
			num,
		)
	}).(pulumi.StringOutput)

	serviceAccountID := pulumi.All(args.ProjectID, args.WorkloadSAEmail).ApplyT(func(a []interface{}) string {
		return fmt.Sprintf("projects/%s/serviceAccounts/%s", a[0].(string), a[1].(string))
	}).(pulumi.StringOutput)

	_, err = serviceaccount.NewIAMMember(ctx, name+"-iam", &serviceaccount.IAMMemberArgs{
		ServiceAccountId: serviceAccountID,
		Role:             pulumi.String("roles/iam.workloadIdentityUser"),
		Member:           member,
	}, pulumi.DependsOn([]pulumi.Resource{wait}))
	if err != nil {
		return nil, err
	}

	// 4. Confidential VM Template — TEE image reference from CI/CD project's Artifact Registry
	defaultTeeImageRef := pulumi.All(args.Region, args.CloudBuildProjectID).ApplyT(func(a []interface{}) string {
		region := a[0].(string)
		cbID := a[1].(string)
		return fmt.Sprintf("%s-docker.pkg.dev/%s/tf-runners/confidential_space_image:latest", region, cbID)
	}).(pulumi.StringOutput)

	tmpl, err := instancetemplate.NewInstanceTemplate(ctx, name+"-tmpl", &instancetemplate.InstanceTemplateArgs{
		Project:                  args.ProjectID,
		NamePrefix:               "confidential-template-",
		MachineType:              args.ConfidentialMachineType,
		Region:                   args.Region,
		MinCpuPlatform:           args.CpuPlatform,
		Network:                  pulumi.String(""),
		Subnetwork:               args.SubnetworkSelfLink,
		EnableConfidentialVm:     true,
		ConfidentialInstanceType: args.ConfidentialInstanceType,
		EnableShieldedVm:         true,
		SourceImageFamily:        "confidential-space",
		SourceImageProject:       "confidential-space-images",
		DiskSizeGb:               20,
		DiskType:                 "pd-ssd",
		ServiceAccountEmail:      args.WorkloadSAEmail,
		ServiceAccountScopes:     []string{"https://www.googleapis.com/auth/cloud-platform"},
		Metadata: pulumi.StringMap{
			"tee-image-reference": defaultTeeImageRef,
		},
	}, pulumi.DependsOn([]pulumi.Resource{wait}))
	if err != nil {
		return nil, err
	}

	// 5. Compute Instance from Template
	inst, err := computeinstance.NewComputeInstance(ctx, name+"-vm", &computeinstance.ComputeInstanceArgs{
		Project: args.ProjectID,
		Zone: pulumi.All(args.ProjectID, args.Region).ApplyT(func(args []interface{}) (string, error) {
			project := args[0].(string)
			region := args[1].(string)
			zones, err := compute.GetZones(ctx, &compute.GetZonesArgs{
				Project: &project,
				Region:  &region,
			})
			if err != nil {
				return "", err
			}
			if len(zones.Names) == 0 {
				return "", fmt.Errorf("no zones found in region %s", region)
			}
			return zones.Names[0], nil
		}).(pulumi.StringOutput),
		Hostname:         "confidential-instance",
		InstanceTemplate: tmpl.Template.SelfLink,
		NumInstances:     1,
	})
	if err != nil {
		return nil, err
	}

	return &ConfidentialSpaceResult{
		InstanceSelfLink:       inst.Instances[0].SelfLink,
		InstanceName:           inst.Instances[0].Name,
		InstanceZone:           inst.Instances[0].Zone,
		WorkloadPoolID:         pool.WorkloadIdentityPoolId,
		WorkloadPoolProviderID: provider.WorkloadIdentityPoolProviderId,
	}, nil
}

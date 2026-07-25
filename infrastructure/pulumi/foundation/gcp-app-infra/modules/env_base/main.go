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

// Package env_base is an app-infra module that deploys the standard Compute
// Engine workload for an environment project: a dedicated service account, an
// instance template, and a Compute Instance on the shared-VPC subnet. It is the
// Compute-Instance archetype in the stage-5 catalog — peer to serverless_space
// (Cloud Run) and confidential_space (Confidential VM).
//
// It mirrors upstream terraform-example-foundation 5-app-infra/modules/env_base
// (main.go↔main.tf, variables.go↔variables.tf, outputs.go↔outputs.tf). Engine
// adaptation: upstream's remote_state_bucket read has no equivalent — the
// calling env leaf resolves the 4-projects StackReferences itself (see the
// leaf's remote.go) and passes resolved values in.
//
// Currently DORMANT in the live foundation: no leaf calls DeployEnvBase yet
// (like serverless_space, it is part of the catalog awaiting a consumer). It is
// kept compiling so the archetype is ready to instantiate the moment an
// environment needs a Compute Engine base workload.
package env_base

import (
	"fmt"

	"github.com/VitruvianSoftware/pulumi-library/go/pkg/compute_instance"
	"github.com/VitruvianSoftware/pulumi-library/go/pkg/instance_template"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployEnvBase creates a service account and Compute Instance in the target
// project, matching the upstream Terraform foundation's env_base module.
//
// Upstream uses terraform-google-modules/vm which creates an instance template
// then a compute instance from that template. Here we create the instance
// directly since we're not using the TF module wrapper.
func DeployEnvBase(ctx *pulumi.Context, name string, args *EnvBaseArgs) (*EnvBaseResult, error) {
	hostname := args.Hostname
	if hostname == "" {
		hostname = "example-app"
	}
	if args.MachineType == "" {
		args.MachineType = "f1-micro"
	}
	if args.NumInstances == 0 {
		args.NumInstances = 1
	}
	if args.SourceImageFamily == "" {
		args.SourceImageFamily = "debian-12"
	}
	if args.SourceImageProject == "" {
		args.SourceImageProject = "debian-cloud"
	}

	// 1. Service Account — matching upstream's google_service_account.compute_engine_service_account
	sa, err := serviceaccount.NewAccount(ctx, name+"-sa", &serviceaccount.AccountArgs{
		AccountId:                 pulumi.String("sa-example-app"),
		DisplayName:               pulumi.String("Example app service Account"),
		Project:                   args.ProjectID,
		CreateIgnoreAlreadyExists: pulumi.Bool(true),
	})
	if err != nil {
		return nil, err
	}

	// 2. Instance Template
	tmpl, err := instance_template.NewInstanceTemplate(ctx, name+"-tmpl", &instance_template.InstanceTemplateArgs{
		Project:              args.ProjectID,
		Region:               args.Region,
		MachineType:          args.MachineType,
		SourceImageFamily:    args.SourceImageFamily,
		SourceImageProject:   args.SourceImageProject,
		SourceImage:          "",
		Network:              pulumi.String(""),
		Subnetwork:           args.SubnetworkSelfLink,
		ServiceAccountEmail:  sa.Email,
		ServiceAccountScopes: []string{"https://www.googleapis.com/auth/compute"},
		Metadata: pulumi.StringMap{
			"block-project-ssh-keys": pulumi.String("true"),
		},
	})
	if err != nil {
		return nil, err
	}

	// 3. Compute Instance
	inst, err := compute_instance.NewComputeInstance(ctx, name+"-inst", &compute_instance.ComputeInstanceArgs{
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
		Hostname:            fmt.Sprintf("%s-%s", hostname, args.ProjectSuffix),
		InstanceTemplate:    tmpl.Template.SelfLink,
		NumInstances:        args.NumInstances,
		ResourceManagerTags: args.IAPFirewallTags,
	})
	if err != nil {
		return nil, err
	}

	// Extract the single instance for outputs
	instance := inst.Instances[0]

	return &EnvBaseResult{
		InstanceSelfLink: instance.SelfLink,
		InstanceName:     instance.Name,
		InstanceZone:     instance.Zone,
		InstanceDetails: pulumi.All(instance.Name, instance.Zone, instance.SelfLink).ApplyT(func(args []interface{}) map[string]interface{} {
			return map[string]interface{}{
				"name":     args[0],
				"zone":     args[1],
				"selfLink": args[2],
			}
		}).(pulumi.MapOutput),
	}, nil
}

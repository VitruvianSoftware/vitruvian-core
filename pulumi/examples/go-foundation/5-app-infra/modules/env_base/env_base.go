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

// Example: env_base compute instance deployment.
// To enable, remove this build constraint or build with: go build -tags=example
//


package env_base

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/VitruvianSoftware/pulumi-library/go/pkg/compute_instance"
	"github.com/VitruvianSoftware/pulumi-library/go/pkg/instance_template"
)

// EnvBaseArgs configures a standard Compute Instance deployment,
// matching the upstream Terraform env_base module.
type EnvBaseArgs struct {
	Env                string
	BusinessUnit       string
	ProjectSuffix      string
	Hostname           string
	MachineType        string
	NumInstances       int
	SourceImageFamily  string
	SourceImageProject string
	ProjectID          pulumi.StringInput
	Region             pulumi.StringInput
	SubnetworkSelfLink pulumi.StringInput
	IAPFirewallTags    pulumi.StringMapInput // nil for non-peering projects
}

// EnvBaseResult holds outputs from the env_base deployment.
type EnvBaseResult struct {
	InstanceSelfLink pulumi.StringOutput
	InstanceName     pulumi.StringOutput
	InstanceZone     pulumi.StringOutput
	InstanceDetails  pulumi.MapOutput
}

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
		Project:          args.ProjectID,
		Zone:             pulumi.All(args.ProjectID, args.Region).ApplyT(func(args []interface{}) (string, error) {
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
		Hostname:         fmt.Sprintf("%s-%s", hostname, args.ProjectSuffix),
		InstanceTemplate: tmpl.Template.SelfLink,
		NumInstances:     args.NumInstances,
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

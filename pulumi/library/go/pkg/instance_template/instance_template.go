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

// Package instance_template provides a compute instance template component.
// Mirrors: terraform-google-modules/vm/google//modules/instance_template
package instance_template

import (
	"fmt"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type InstanceTemplateArgs struct {
	Project            pulumi.StringInput
	Region             string
	MachineType        string
	SourceImage        string
	SourceImageFamily  string
	SourceImageProject string
	DiskSizeGb         int
	DiskType           string
	Network            pulumi.StringInput
	Subnetwork         pulumi.StringInput
	ServiceAccountEmail pulumi.StringInput
	ServiceAccountScopes []string
	Tags               []string
	Labels             map[string]string
	Metadata           map[string]string
	EnableShieldedVm   bool
	EnableConfidentialVm bool
	NamePrefix         string
	MinCpuPlatform     string
	ConfidentialInstanceType string
}

type InstanceTemplate struct {
	pulumi.ResourceState
	Template *compute.InstanceTemplate
}

func NewInstanceTemplate(ctx *pulumi.Context, name string, args *InstanceTemplateArgs, opts ...pulumi.ResourceOption) (*InstanceTemplate, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}
	component := &InstanceTemplate{}
	err := ctx.RegisterComponentResource("pkg:index:InstanceTemplate", name, component, opts...)
	if err != nil {
		return nil, err
	}

	diskType := args.DiskType
	if diskType == "" {
		diskType = "pd-standard"
	}
	diskSize := args.DiskSizeGb
	if diskSize == 0 {
		diskSize = 100
	}
	machineType := args.MachineType
	if machineType == "" {
		machineType = "n1-standard-1"
	}

	tmplArgs := &compute.InstanceTemplateArgs{
		Project:     args.Project,
		Region:      pulumi.String(args.Region),
		MachineType: pulumi.String(machineType),
		Disks: compute.InstanceTemplateDiskArray{
			&compute.InstanceTemplateDiskArgs{
				SourceImage: pulumi.String(args.SourceImage),
				DiskSizeGb:  pulumi.Int(diskSize),
				DiskType:    pulumi.String(diskType),
				Boot:        pulumi.Bool(true),
				AutoDelete:  pulumi.Bool(true),
			},
		},
		NetworkInterfaces: compute.InstanceTemplateNetworkInterfaceArray{
			&compute.InstanceTemplateNetworkInterfaceArgs{
				Network:    args.Network,
				Subnetwork: args.Subnetwork,
			},
		},
	}

	if args.NamePrefix != "" {
		tmplArgs.NamePrefix = pulumi.String(args.NamePrefix)
	}
	if args.MinCpuPlatform != "" {
		tmplArgs.MinCpuPlatform = pulumi.String(args.MinCpuPlatform)
	}

	if args.ServiceAccountEmail != nil {
		var scopes pulumi.StringArray
		for _, s := range args.ServiceAccountScopes {
			scopes = append(scopes, pulumi.String(s))
		}
		if len(scopes) == 0 {
			scopes = pulumi.StringArray{pulumi.String("https://www.googleapis.com/auth/cloud-platform")}
		}
		tmplArgs.ServiceAccount = &compute.InstanceTemplateServiceAccountArgs{
			Email:  args.ServiceAccountEmail,
			Scopes: scopes,
		}
	}

	if len(args.Tags) > 0 {
		var tags pulumi.StringArray
		for _, t := range args.Tags {
			tags = append(tags, pulumi.String(t))
		}
		tmplArgs.Tags = tags
	}

	if len(args.Labels) > 0 {
		labels := pulumi.StringMap{}
		for k, v := range args.Labels {
			labels[k] = pulumi.String(v)
		}
		tmplArgs.Labels = labels
	}

	if len(args.Metadata) > 0 {
		metadata := pulumi.StringMap{}
		for k, v := range args.Metadata {
			metadata[k] = pulumi.String(v)
		}
		tmplArgs.Metadata = metadata
	}

	if args.EnableShieldedVm {
		tmplArgs.ShieldedInstanceConfig = &compute.InstanceTemplateShieldedInstanceConfigArgs{
			EnableSecureBoot:          pulumi.Bool(true),
			EnableVtpm:                pulumi.Bool(true),
			EnableIntegrityMonitoring: pulumi.Bool(true),
		}
	}

	if args.EnableConfidentialVm {
		confArgs := &compute.InstanceTemplateConfidentialInstanceConfigArgs{
			EnableConfidentialCompute: pulumi.Bool(true),
		}
		if args.ConfidentialInstanceType != "" {
			confArgs.ConfidentialInstanceType = pulumi.String(args.ConfidentialInstanceType)
		}
		tmplArgs.ConfidentialInstanceConfig = confArgs
	}

	tmpl, err := compute.NewInstanceTemplate(ctx, name, tmplArgs, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Template = tmpl

	ctx.RegisterResourceOutputs(component, pulumi.Map{"selfLink": tmpl.SelfLink})
	return component, nil
}

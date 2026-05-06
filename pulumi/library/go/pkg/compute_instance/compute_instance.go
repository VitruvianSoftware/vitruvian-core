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

// Package compute_instance provides a compute instance from template component.
// Mirrors: terraform-google-modules/vm/google//modules/compute_instance
package compute_instance

import (
	"fmt"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type ComputeInstanceArgs struct {
	Project            pulumi.StringInput
	Zone               string
	Hostname           string
	InstanceTemplate   pulumi.StringInput
	NumInstances       int
	DeletionProtection bool
}

type ComputeInstance struct {
	pulumi.ResourceState
	Instances []*compute.InstanceFromTemplate
}

func NewComputeInstance(ctx *pulumi.Context, name string, args *ComputeInstanceArgs, opts ...pulumi.ResourceOption) (*ComputeInstance, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}
	component := &ComputeInstance{}
	err := ctx.RegisterComponentResource("pkg:index:ComputeInstance", name, component, opts...)
	if err != nil {
		return nil, err
	}

	count := args.NumInstances
	if count == 0 {
		count = 1
	}

	for i := 0; i < count; i++ {
		hostname := args.Hostname
		if count > 1 {
			hostname = fmt.Sprintf("%s-%d", args.Hostname, i)
		}

		inst, err := compute.NewInstanceFromTemplate(ctx, fmt.Sprintf("%s-%d", name, i), &compute.InstanceFromTemplateArgs{
			Project:                 args.Project,
			Zone:                    pulumi.String(args.Zone),
			Name:                    pulumi.String(hostname),
			SourceInstanceTemplate:  args.InstanceTemplate,
			DeletionProtection:      pulumi.Bool(args.DeletionProtection),
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}
		component.Instances = append(component.Instances, inst)
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

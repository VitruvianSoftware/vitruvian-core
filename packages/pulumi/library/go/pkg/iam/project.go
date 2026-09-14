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

package iam

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ProjectIAMMemberArgs configures an additive IAM member binding at the
// project scope.
type ProjectIAMMemberArgs struct {
	ProjectID pulumi.StringInput
	Role      pulumi.StringInput
	Member    pulumi.StringInput
}

// ProjectIAMMember is a component that creates an additive IAM binding
// at the project scope.
type ProjectIAMMember struct {
	pulumi.ResourceState
}

// NewProjectIAMMember creates an additive IAM member binding at the
// project scope.
func NewProjectIAMMember(ctx *pulumi.Context, name string, args *ProjectIAMMemberArgs, opts ...pulumi.ResourceOption) (*ProjectIAMMember, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &ProjectIAMMember{}
	err := ctx.RegisterComponentResource("pkg:iam:ProjectIAMMember", name, component, opts...)
	if err != nil {
		return nil, err
	}

	if _, err := projects.NewIAMMember(ctx, name+"-member", &projects.IAMMemberArgs{
		Project: args.ProjectID,
		Role:    args.Role,
		Member:  args.Member,
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

// ProjectIAMBindingArgs configures an authoritative IAM binding at the
// project scope.
type ProjectIAMBindingArgs struct {
	ProjectID pulumi.StringInput
	Role      pulumi.StringInput
	Members   pulumi.StringArrayInput
}

// ProjectIAMBinding is a component that creates an authoritative IAM
// binding at the project scope.
type ProjectIAMBinding struct {
	pulumi.ResourceState
}

// NewProjectIAMBinding creates an authoritative IAM binding at the
// project scope. It will REMOVE any members assigned to this role that
// are not included in the Members list.
func NewProjectIAMBinding(ctx *pulumi.Context, name string, args *ProjectIAMBindingArgs, opts ...pulumi.ResourceOption) (*ProjectIAMBinding, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &ProjectIAMBinding{}
	err := ctx.RegisterComponentResource("pkg:iam:ProjectIAMBinding", name, component, opts...)
	if err != nil {
		return nil, err
	}

	if _, err := projects.NewIAMBinding(ctx, name+"-binding", &projects.IAMBindingArgs{
		Project: args.ProjectID,
		Role:    args.Role,
		Members: args.Members,
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

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

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// OrganizationIAMMemberArgs configures an additive IAM member binding at the
// organization scope.
type OrganizationIAMMemberArgs struct {
	OrgID  pulumi.StringInput
	Role   pulumi.StringInput
	Member pulumi.StringInput
}

// OrganizationIAMMember is a component that creates an additive IAM binding
// at the organization scope.
type OrganizationIAMMember struct {
	pulumi.ResourceState
}

// NewOrganizationIAMMember creates an additive IAM member binding at the
// organization scope.
func NewOrganizationIAMMember(ctx *pulumi.Context, name string, args *OrganizationIAMMemberArgs, opts ...pulumi.ResourceOption) (*OrganizationIAMMember, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &OrganizationIAMMember{}
	err := ctx.RegisterComponentResource("pkg:iam:OrganizationIAMMember", name, component, opts...)
	if err != nil {
		return nil, err
	}

	if _, err := organizations.NewIAMMember(ctx, name+"-member", &organizations.IAMMemberArgs{
		OrgId:  args.OrgID,
		Role:   args.Role,
		Member: args.Member,
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

// OrganizationIAMBindingArgs configures an authoritative IAM binding at the
// organization scope.
type OrganizationIAMBindingArgs struct {
	OrgID   pulumi.StringInput
	Role    pulumi.StringInput
	Members pulumi.StringArrayInput
}

// OrganizationIAMBinding is a component that creates an authoritative IAM
// binding at the organization scope.
type OrganizationIAMBinding struct {
	pulumi.ResourceState
}

// NewOrganizationIAMBinding creates an authoritative IAM binding at the
// organization scope. It will REMOVE any members assigned to this role that
// are not included in the Members list.
func NewOrganizationIAMBinding(ctx *pulumi.Context, name string, args *OrganizationIAMBindingArgs, opts ...pulumi.ResourceOption) (*OrganizationIAMBinding, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &OrganizationIAMBinding{}
	err := ctx.RegisterComponentResource("pkg:iam:OrganizationIAMBinding", name, component, opts...)
	if err != nil {
		return nil, err
	}

	if _, err := organizations.NewIAMBinding(ctx, name+"-binding", &organizations.IAMBindingArgs{
		OrgId:   args.OrgID,
		Role:    args.Role,
		Members: args.Members,
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

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

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ServiceAccountIAMMemberArgs configures an additive IAM member binding at
// the service account scope.
type ServiceAccountIAMMemberArgs struct {
	ServiceAccountID pulumi.StringInput
	Role             pulumi.StringInput
	Member           pulumi.StringInput
}

// ServiceAccountIAMMember is a component that creates an additive IAM
// binding at the service account scope.
type ServiceAccountIAMMember struct {
	pulumi.ResourceState
}

// NewServiceAccountIAMMember creates an additive IAM member binding at the
// service account scope.
func NewServiceAccountIAMMember(ctx *pulumi.Context, name string, args *ServiceAccountIAMMemberArgs, opts ...pulumi.ResourceOption) (*ServiceAccountIAMMember, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &ServiceAccountIAMMember{}
	err := ctx.RegisterComponentResource("pkg:iam:ServiceAccountIAMMember", name, component, opts...)
	if err != nil {
		return nil, err
	}

	if _, err := serviceaccount.NewIAMMember(ctx, name+"-member", &serviceaccount.IAMMemberArgs{
		ServiceAccountId: args.ServiceAccountID,
		Role:             args.Role,
		Member:           args.Member,
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

// ServiceAccountIAMBindingArgs configures an authoritative IAM binding at
// the service account scope.
type ServiceAccountIAMBindingArgs struct {
	ServiceAccountID pulumi.StringInput
	Role             pulumi.StringInput
	Members          pulumi.StringArrayInput
}

// ServiceAccountIAMBinding is a component that creates an authoritative IAM
// binding at the service account scope.
type ServiceAccountIAMBinding struct {
	pulumi.ResourceState
}

// NewServiceAccountIAMBinding creates an authoritative IAM binding at the
// service account scope. It will REMOVE any members assigned to this role
// that are not included in the Members list.
func NewServiceAccountIAMBinding(ctx *pulumi.Context, name string, args *ServiceAccountIAMBindingArgs, opts ...pulumi.ResourceOption) (*ServiceAccountIAMBinding, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &ServiceAccountIAMBinding{}
	err := ctx.RegisterComponentResource("pkg:iam:ServiceAccountIAMBinding", name, component, opts...)
	if err != nil {
		return nil, err
	}

	if _, err := serviceaccount.NewIAMBinding(ctx, name+"-binding", &serviceaccount.IAMBindingArgs{
		ServiceAccountId: args.ServiceAccountID,
		Role:             args.Role,
		Members:          args.Members,
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

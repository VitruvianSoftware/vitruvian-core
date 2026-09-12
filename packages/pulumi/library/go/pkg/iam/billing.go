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

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/billing"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// BillingIAMMemberArgs configures an additive IAM member binding at the
// billing account scope.
type BillingIAMMemberArgs struct {
	BillingAccountID pulumi.StringInput
	Role             pulumi.StringInput
	Member           pulumi.StringInput
}

// BillingIAMMember is a component that creates an additive IAM binding
// at the billing account scope.
type BillingIAMMember struct {
	pulumi.ResourceState
}

// NewBillingIAMMember creates an additive IAM member binding at the
// billing account scope.
func NewBillingIAMMember(ctx *pulumi.Context, name string, args *BillingIAMMemberArgs, opts ...pulumi.ResourceOption) (*BillingIAMMember, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &BillingIAMMember{}
	err := ctx.RegisterComponentResource("pkg:iam:BillingIAMMember", name, component, opts...)
	if err != nil {
		return nil, err
	}

	if _, err := billing.NewAccountIamMember(ctx, name+"-member", &billing.AccountIamMemberArgs{
		BillingAccountId: args.BillingAccountID,
		Role:             args.Role,
		Member:           args.Member,
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

// BillingIAMBindingArgs configures an authoritative IAM binding at the
// billing account scope.
type BillingIAMBindingArgs struct {
	BillingAccountID pulumi.StringInput
	Role             pulumi.StringInput
	Members          pulumi.StringArrayInput
}

// BillingIAMBinding is a component that creates an authoritative IAM
// binding at the billing account scope.
type BillingIAMBinding struct {
	pulumi.ResourceState
}

// NewBillingIAMBinding creates an authoritative IAM binding at the
// billing account scope. It will REMOVE any members assigned to this role
// that are not included in the Members list.
func NewBillingIAMBinding(ctx *pulumi.Context, name string, args *BillingIAMBindingArgs, opts ...pulumi.ResourceOption) (*BillingIAMBinding, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &BillingIAMBinding{}
	err := ctx.RegisterComponentResource("pkg:iam:BillingIAMBinding", name, component, opts...)
	if err != nil {
		return nil, err
	}

	if _, err := billing.NewAccountIamBinding(ctx, name+"-binding", &billing.AccountIamBindingArgs{
		BillingAccountId: args.BillingAccountID,
		Role:             args.Role,
		Members:          args.Members,
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

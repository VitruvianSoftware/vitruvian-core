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

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/folder"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// FolderIAMMemberArgs configures an additive IAM member binding at the
// folder scope.
type FolderIAMMemberArgs struct {
	FolderID pulumi.StringInput
	Role     pulumi.StringInput
	Member   pulumi.StringInput
}

// FolderIAMMember is a component that creates an additive IAM binding
// at the folder scope.
type FolderIAMMember struct {
	pulumi.ResourceState
}

// NewFolderIAMMember creates an additive IAM member binding at the
// folder scope.
func NewFolderIAMMember(ctx *pulumi.Context, name string, args *FolderIAMMemberArgs, opts ...pulumi.ResourceOption) (*FolderIAMMember, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &FolderIAMMember{}
	err := ctx.RegisterComponentResource("pkg:iam:FolderIAMMember", name, component, opts...)
	if err != nil {
		return nil, err
	}

	if _, err := folder.NewIAMMember(ctx, name+"-member", &folder.IAMMemberArgs{
		Folder: args.FolderID,
		Role:   args.Role,
		Member: args.Member,
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

// FolderIAMBindingArgs configures an authoritative IAM binding at the
// folder scope.
type FolderIAMBindingArgs struct {
	FolderID pulumi.StringInput
	Role     pulumi.StringInput
	Members  pulumi.StringArrayInput
}

// FolderIAMBinding is a component that creates an authoritative IAM
// binding at the folder scope.
type FolderIAMBinding struct {
	pulumi.ResourceState
}

// NewFolderIAMBinding creates an authoritative IAM binding at the
// folder scope. It will REMOVE any members assigned to this role that
// are not included in the Members list.
func NewFolderIAMBinding(ctx *pulumi.Context, name string, args *FolderIAMBindingArgs, opts ...pulumi.ResourceOption) (*FolderIAMBinding, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &FolderIAMBinding{}
	err := ctx.RegisterComponentResource("pkg:iam:FolderIAMBinding", name, component, opts...)
	if err != nil {
		return nil, err
	}

	if _, err := folder.NewIAMBinding(ctx, name+"-binding", &folder.IAMBindingArgs{
		Folder:  args.FolderID,
		Role:    args.Role,
		Members: args.Members,
	}, pulumi.Parent(component)); err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}

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

// Package parentiamremoverole mirrors the upstream terraform-example-foundation
// 0-bootstrap/modules/parent-iam-remove-role module: authoritative empty IAM
// bindings that remove ALL members from the given roles at project, folder or
// organization scope (e.g. stripping roles/editor from bootstrap projects).
package parentiamremoverole

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/folder"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ParentIamRemoveRole is the component resource mirroring upstream
// 0-bootstrap/modules/parent-iam-remove-role. It has no outputs.
type ParentIamRemoveRole struct {
	pulumi.ResourceState
}

// NewParentIamRemoveRole creates an authoritative empty binding for each role
// in args.Roles at the configured parent scope, mirroring upstream main.tf.
func NewParentIamRemoveRole(ctx *pulumi.Context, name string, args *ParentIamRemoveRoleArgs, opts ...pulumi.ResourceOption) (*ParentIamRemoveRole, error) {
	var resource ParentIamRemoveRole
	err := ctx.RegisterComponentResource("modules:parent-iam-remove-role:ParentIamRemoveRole", name, &resource, opts...)
	if err != nil {
		return nil, err
	}

	for _, role := range args.Roles {
		roleID := strings.ReplaceAll(strings.TrimPrefix(role, "roles/"), ".", "-")

		if args.ParentType == "project" {
			_, err = projects.NewIAMBinding(ctx, fmt.Sprintf("%s-%s", name, roleID), &projects.IAMBindingArgs{
				Project: args.ParentId,
				Role:    pulumi.String(role),
				Members: pulumi.StringArray{},
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}
		} else if args.ParentType == "folder" {
			_, err = folder.NewIAMBinding(ctx, fmt.Sprintf("%s-%s", name, roleID), &folder.IAMBindingArgs{
				Folder:  args.ParentId,
				Role:    pulumi.String(role),
				Members: pulumi.StringArray{},
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}
		} else if args.ParentType == "organization" {
			_, err = organizations.NewIAMBinding(ctx, fmt.Sprintf("%s-%s", name, roleID), &organizations.IAMBindingArgs{
				OrgId:   args.ParentId,
				Role:    pulumi.String(role),
				Members: pulumi.StringArray{},
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}
		}
	}

	return &resource, nil
}

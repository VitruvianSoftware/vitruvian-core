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

// Package parentiammember mirrors the upstream terraform-example-foundation
// 0-bootstrap/modules/parent-iam-member module: additive IAM member grants
// for a single member across a role list, at project, folder or organization
// scope.
package parentiammember

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/folder"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ParentIamMember is the component resource mirroring upstream
// 0-bootstrap/modules/parent-iam-member. It has no outputs.
type ParentIamMember struct {
	pulumi.ResourceState
}

// NewParentIamMember grants each role in args.Roles to args.Member at the
// configured parent scope, mirroring upstream main.tf.
func NewParentIamMember(ctx *pulumi.Context, name string, args *ParentIamMemberArgs, opts ...pulumi.ResourceOption) (*ParentIamMember, error) {
	var resource ParentIamMember
	err := ctx.RegisterComponentResource("modules:parent-iam-member:ParentIamMember", name, &resource, opts...)
	if err != nil {
		return nil, err
	}

	for _, role := range args.Roles {
		roleID := strings.ReplaceAll(strings.TrimPrefix(role, "roles/"), ".", "-")

		if args.ParentType == "project" {
			_, err = projects.NewIAMMember(ctx, fmt.Sprintf("%s-%s", name, roleID), &projects.IAMMemberArgs{
				Project: args.ParentId,
				Role:    pulumi.String(role),
				Member:  args.Member,
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}
		} else if args.ParentType == "folder" {
			_, err = folder.NewIAMMember(ctx, fmt.Sprintf("%s-%s", name, roleID), &folder.IAMMemberArgs{
				Folder: args.ParentId,
				Role:   pulumi.String(role),
				Member: args.Member,
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}
		} else if args.ParentType == "organization" {
			_, err = organizations.NewIAMMember(ctx, fmt.Sprintf("%s-%s", name, roleID), &organizations.IAMMemberArgs{
				OrgId:  args.ParentId,
				Role:   pulumi.String(role),
				Member: args.Member,
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}
		}
	}

	return &resource, nil
}

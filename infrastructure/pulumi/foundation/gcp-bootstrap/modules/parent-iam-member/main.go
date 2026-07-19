// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

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

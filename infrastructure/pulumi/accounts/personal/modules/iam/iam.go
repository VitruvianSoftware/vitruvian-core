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

package iam

import (
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/projects"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// GrantIAMRoleArgs defines the arguments for granting an IAM role to a member.
type GrantIAMRoleArgs struct {
	ProjectID string
	Member    string // e.g., "user:your-email@example.com"
	Role      string // e.g., "roles/viewer"
}

// GrantIAMRole grants a specified IAM role to a member on a GCP project.
func GrantIAMRole(ctx *pulumi.Context, name string, args *GrantIAMRoleArgs) error {
	_, err := projects.NewIAMMember(ctx, name, &projects.IAMMemberArgs{
		Project: pulumi.String(args.ProjectID),
		Role:    pulumi.String(args.Role),
		Member:  pulumi.String(args.Member),
	})
	if err != nil {
		return err
	}
	return nil
}

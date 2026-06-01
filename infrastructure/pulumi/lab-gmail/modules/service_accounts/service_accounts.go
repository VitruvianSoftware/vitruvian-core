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

package service_accounts

import (
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/projects"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// CreateServiceAccountArgs defines the arguments for creating a service account and granting roles.
type CreateServiceAccountArgs struct {
	ProjectID string
	AccountID string
	DisplayName string
	Roles     []string
}

// CreateServiceAccount creates a new Google Cloud Service Account and grants specified roles.
func CreateServiceAccount(ctx *pulumi.Context, name string, args *CreateServiceAccountArgs) (*serviceaccount.Account, error) {
	sa, err := serviceaccount.NewAccount(ctx, name, &serviceaccount.AccountArgs{
		Project:     pulumi.String(args.ProjectID),
		AccountId:   pulumi.String(args.AccountID),
		DisplayName: pulumi.String(args.DisplayName),
	})
	if err != nil {
		return nil, err
	}

	for _, role := range args.Roles {
		_, err := projects.NewIAMMember(ctx, name+"-"+role, &projects.IAMMemberArgs{
			Project: pulumi.String(args.ProjectID),
			Role:    pulumi.String(role),
			Member:  pulumi.Sprintf("serviceAccount:%s", sa.Email),
		})
		if err != nil {
			return nil, err
		}
	}

	ctx.Export(name+"Email", sa.Email)

	return sa, nil
}

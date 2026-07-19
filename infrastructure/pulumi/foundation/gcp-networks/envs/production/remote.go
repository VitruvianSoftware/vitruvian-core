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

package main

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// orgRemote bundles the 1-org StackReference reads consumed by this leaf.
type orgRemote struct {
	stack          *pulumi.StackReference
	spokeProjectID pulumi.StringOutput
	hubProjectID   pulumi.StringOutput
}

// lookupOrgRemote opens the Stack Reference to 1-org for project IDs and ACM
// policy, mirroring upstream 3-networks-hub-and-spoke/envs/production/
// remote.tf. Each environment stack deploys to its own Shared VPC host
// project, resolved from the 1-org exports.
func lookupOrgRemote(ctx *pulumi.Context, cfg *NetConfig) (*orgRemote, error) {
	orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
		Name: pulumi.String(cfg.OrgStackName),
	})
	if err != nil {
		return nil, err
	}
	return &orgRemote{
		stack:          orgStack,
		spokeProjectID: orgStack.GetStringOutput(pulumi.String(fmt.Sprintf("%s_network_project_id", pinnedEnv))),
		hubProjectID:   orgStack.GetStringOutput(pulumi.String("net_hub_project_id")),
	}, nil
}

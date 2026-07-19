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
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// lookupOrgRemote opens the Stack Reference to 1-org for project IDs and ACM
// policy, mirroring upstream 3-networks-hub-and-spoke/envs/shared/remote.tf.
// It returns the org stack plus the hub host project id (created by 1-org
// when enable_hub_and_spoke=true).
func lookupOrgRemote(ctx *pulumi.Context, cfg *NetSharedConfig) (*pulumi.StackReference, pulumi.StringOutput, error) {
	orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
		Name: pulumi.String(cfg.OrgStackName),
	})
	if err != nil {
		return nil, pulumi.StringOutput{}, err
	}
	return orgStack, orgStack.GetStringOutput(pulumi.String("net_hub_project_id")), nil
}

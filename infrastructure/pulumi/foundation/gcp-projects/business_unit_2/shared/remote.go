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

// Cross-stage StackReferences for the shared leaf — the Pulumi analogue of
// upstream 4-projects/business_unit_2/shared/remote.tf (its
// terraform_remote_state reads of the earlier stages' states).

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// stackRefs carries the cross-stage outputs this leaf consumes, resolved from
// the earlier stages' stacks by loadStackReferences.
type stackRefs struct {
	// CommonFolderID is the 1-org COMMON folder the infra-pipeline project is
	// parented under.
	CommonFolderID pulumi.StringOutput
}

// loadStackReferences resolves the cross-stage StackReferences.
func loadStackReferences(ctx *pulumi.Context, cfg *SharedConfig) (*stackRefs, error) {
	// Organization StackReference (Stage 1) — provides the COMMON folder the
	// infra-pipeline project is parented under.
	orgStack, err := pulumi.NewStackReference(ctx, "organization", &pulumi.StackReferenceArgs{
		Name: pulumi.String(cfg.OrgStackName),
	})
	if err != nil {
		return nil, err
	}
	return &stackRefs{
		CommonFolderID: orgStack.GetStringOutput(pulumi.String("common_folder_id")),
	}, nil
}

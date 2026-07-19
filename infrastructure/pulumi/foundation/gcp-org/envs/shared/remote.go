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

// Cross-stage remote state. This mirrors the Terraform foundation's
// 1-org/envs/shared/remote.tf: upstream reads the 0-bootstrap outputs via
// terraform_remote_state; the Pulumi engine adaptation is a StackReference
// to the bootstrap stack named in config (bootstrap_stack_name).

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// BootstrapOutputs holds resolved values from the 0-bootstrap StackReference.
type BootstrapOutputs struct {
	BootstrapFolderName string

	// Required groups
	GroupOrgAdmins     string
	GroupBillingAdmins string
	BillingDataUsers   string
	AuditDataUsers     string

	// Optional groups
	GCPSecurityReviewer   string
	GCPNetworkViewer      string
	GCPSCCAdmin           string
	GCPGlobalSecretsAdmin string
	GCPKMSAdmin           string
}

// newBootstrapReference opens the StackReference to the 0-bootstrap stack for
// cross-stage outputs (groups, pipeline service accounts, bootstrap folder).
func newBootstrapReference(ctx *pulumi.Context, cfg *OrgConfig) (*pulumi.StackReference, error) {
	return pulumi.NewStackReference(ctx, "bootstrap", &pulumi.StackReferenceArgs{
		Name: pulumi.String(cfg.BootstrapStackName),
	})
}

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

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
	group "github.com/VitruvianSoftware/pulumi-library/go/pkg/google_group"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployGroups optionally creates Google Workspace groups via Cloud Identity.
// This mirrors the Terraform foundation's 0-bootstrap/groups.tf which uses
// the terraform-google-modules/group/google module.
//
// Groups are only created when create_required_groups or create_optional_groups
// is set to true in the config. When disabled, the bootstrap assumes the
// groups already exist and uses their email addresses for IAM bindings.
func deployGroups(ctx *pulumi.Context, cfg *Config) ([]pulumi.Resource, error) {
	var groupResources []pulumi.Resource

	if !cfg.CreateRequiredGroups && !cfg.CreateOptionalGroups {
		return groupResources, nil // Groups are pre-existing; nothing to create.
	}

	// Look up the org's directory customer ID (needed to scope groups).
	org, err := organizations.GetOrganization(ctx, &organizations.GetOrganizationArgs{
		Organization: &cfg.OrgID,
	})
	if err != nil {
		return nil, err
	}
	customerID := pulumi.String(org.DirectoryCustomerId)

	// ========================================================================
	// Required Groups
	// These are the minimum groups needed by the foundation. Mirrors the
	// TF foundation's module "required_group" for_each block.
	// ========================================================================
	if cfg.CreateRequiredGroups {
		requiredGroups := map[string]string{
			"group_org_admins":     cfg.GroupOrgAdmins,
			"group_billing_admins": cfg.GroupBillingAdmins,
			"billing_data_users":   cfg.BillingDataUsers,
			"audit_data_users":     cfg.AuditDataUsers,
		}

		for key, email := range requiredGroups {
			if email == "" {
				continue
			}
			g, err := group.NewGroup(ctx, "required-"+key, &group.GroupArgs{
				ID:                 email,
				DisplayName:        key,
				Description:        key,
				CustomerID:         customerID,
				InitialGroupConfig: cfg.InitialGroupConfig,
			})
			if err != nil {
				return nil, err
			}
			groupResources = append(groupResources, g)
		}
	}

	// ========================================================================
	// Optional Groups
	// Governance groups consumed by 1-org stage. Only created if
	// create_optional_groups is true AND the email is non-empty.
	// Mirrors the TF foundation's module "optional_group".
	// ========================================================================
	if cfg.CreateOptionalGroups {
		optionalGroups := map[string]string{
			"gcp_security_reviewer":    cfg.GCPSecurityReviewer,
			"gcp_network_viewer":       cfg.GCPNetworkViewer,
			"gcp_scc_admin":            cfg.GCPSCCAdmin,
			"gcp_global_secrets_admin": cfg.GCPGlobalSecretsAdmin,
			"gcp_kms_admin":            cfg.GCPKMSAdmin,
		}

		for key, email := range optionalGroups {
			if email == "" {
				continue // Skip unconfigured optional groups
			}
			g, err := group.NewGroup(ctx, "optional-"+key, &group.GroupArgs{
				ID:                 email,
				DisplayName:        key,
				Description:        key,
				CustomerID:         customerID,
				InitialGroupConfig: cfg.InitialGroupConfig,
			})
			if err != nil {
				return nil, err
			}
			groupResources = append(groupResources, g)
		}
	}

	return groupResources, nil
}

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
	"strings"

	group "github.com/VitruvianSoftware/pulumi-library/go/pkg/google_group"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudidentity"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// GroupOutputs holds exported group identifiers for downstream stages.
type GroupOutputs struct {
	SessionExemptGroupID pulumi.StringOutput
}

// groupsProviderOptions prepares the provider used for group creation.
//
// The Cloud Identity API requires a quota/billing project on every call.
// Upstream handles this by setting user_project_override + billing_project
// on its google-beta provider (0-bootstrap/provider.tf) and documenting the
// API enablement as a manual prerequisite. We port that config AND codify
// the enablement: a dedicated provider scoped to group creation only (so the
// default provider used for projects/IAM/KMS is unaffected and does not need
// the billing project to carry every API), plus enabling cloudidentity on it.
//
// Returns nil options when group creation is disabled (groups pre-exist).
func groupsProviderOptions(ctx *pulumi.Context, cfg *Config) ([]pulumi.ResourceOption, error) {
	if !cfg.CreateRequiredGroups && !cfg.CreateOptionalGroups && cfg.GroupSessionExempt == "" {
		return nil, nil
	}
	if cfg.GroupsBillingProject == "" {
		return nil, fmt.Errorf("groups_billing_project is required when group creation is enabled (it is the pre-existing project that provides Cloud Identity API quota)")
	}
	ciAPI, err := projects.NewService(ctx, "groups-cloudidentity-api", &projects.ServiceArgs{
		Project:                  pulumi.String(cfg.GroupsBillingProject),
		Service:                  pulumi.String("cloudidentity.googleapis.com"),
		DisableOnDestroy:         pulumi.Bool(false),
		DisableDependentServices: pulumi.Bool(false),
	})
	if err != nil {
		return nil, err
	}
	// Pin Project explicitly to the quota/billing project. Left unset, the
	// provider infers its project from the ambient environment, so the field
	// flip-flops in previews: CI (which has an ambient GCP project) records one
	// value while a local run (no ambient project) records none, producing
	// perpetual benign drift on this stack. Since UserProjectOverride +
	// BillingProject already route Cloud Identity quota through
	// GroupsBillingProject, pinning Project to the same value makes previews
	// deterministic regardless of runner environment.
	ciProvider, err := gcp.NewProvider(ctx, "cloudidentity", &gcp.ProviderArgs{
		Project:             pulumi.String(cfg.GroupsBillingProject),
		UserProjectOverride: pulumi.Bool(true),
		BillingProject:      pulumi.String(cfg.GroupsBillingProject),
	}, pulumi.DependsOn([]pulumi.Resource{ciAPI}))
	if err != nil {
		return nil, err
	}
	return []pulumi.ResourceOption{
		pulumi.Provider(ciProvider),
		pulumi.DependsOn([]pulumi.Resource{ciAPI}),
	}, nil
}

// groupMembershipType is the Pulumi type token of a Cloud Identity membership.
const groupMembershipType = "gcp:cloudidentity/groupMembership:GroupMembership"

// adoptExistingMemberships makes every group membership under the resource it
// is attached to create idempotently: if the membership already exists in
// Cloud Identity, the provider looks it up and records it instead of failing.
//
// WHY: a membership can exist in Google without being in Pulumi state. The
// provider creates a membership and immediately reads it back, with no wait.
// Cloud Identity is eventually consistent, and a read that is not yet visible
// comes back as "403 ... (or it may not exist)", which the provider treats as
// "the resource is gone": it records nothing and returns NO error. Pulumi
// reports that as "expected non-nil error with nil state during Create"
// (foundation release run 36915108605). The membership was created all the
// same, so without this option the next apply fails with a 409 and the stack
// can only be repaired by hand. The provider polls after creating a GROUP for
// exactly this reason; it has no equivalent for memberships (checked up to
// pulumi-gcp v9.37.0 / upstream main, 2026-10-01).
//
// This does not remove the race, which is inside the provider between its own
// create and read. It makes the outcome recoverable: an apply that loses the
// race converges on the next apply instead of wedging.
//
// A legacy Transformation rather than a Transform, on purpose: it runs
// in-process, so it is typed (a renamed field is a compile error, not a
// silently ignored key) and it is exercised by the mock-based test.
func adoptExistingMemberships() pulumi.ResourceOption {
	return pulumi.Transformations([]pulumi.ResourceTransformation{
		func(args *pulumi.ResourceTransformationArgs) *pulumi.ResourceTransformationResult {
			if args.Type != groupMembershipType {
				return nil
			}
			m, ok := args.Props.(*cloudidentity.GroupMembershipArgs)
			if !ok {
				// Never skip silently: an unrecognised args type would put the
				// stack straight back into the failure described above.
				panic(fmt.Sprintf("adoptExistingMemberships: %s %q has args of type %T, want *cloudidentity.GroupMembershipArgs", args.Type, args.Name, args.Props))
			}
			m.CreateIgnoreAlreadyExists = pulumi.Bool(true)
			return &pulumi.ResourceTransformationResult{Props: m, Opts: args.Opts}
		},
	})
}

// deployGroups optionally creates Google Workspace groups via Cloud Identity.
// This mirrors the Terraform foundation's 0-bootstrap/groups.tf which uses
// the terraform-google-modules/group/google module.
//
// Groups are only created when create_required_groups or create_optional_groups
// is set to true in the config, or when a session-exempt group is declared.
func deployGroups(ctx *pulumi.Context, cfg *Config, opts ...pulumi.ResourceOption) (*GroupOutputs, []pulumi.Resource, error) {
	var groupResources []pulumi.Resource
	groupOut := &GroupOutputs{}

	if !cfg.CreateRequiredGroups && !cfg.CreateOptionalGroups && cfg.GroupSessionExempt == "" {
		return groupOut, groupResources, nil // Groups are pre-existing; nothing to create.
	}
	opts = append(append([]pulumi.ResourceOption{}, opts...), adoptExistingMemberships())

	// Look up the org's directory customer ID (needed to scope groups).
	org, err := organizations.GetOrganization(ctx, &organizations.GetOrganizationArgs{
		Organization: &cfg.OrgID,
	})
	if err != nil {
		return nil, nil, err
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
			}, opts...)
			if err != nil {
				return nil, nil, err
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
			}, opts...)
			if err != nil {
				return nil, nil, err
			}
			groupResources = append(groupResources, g)
		}
	}

	// ========================================================================
	// Session Control Exemption Group
	// Dedicated Cloud Identity group for users exempted from the default
	// 16-hour session reauthentication policy.
	// ========================================================================
	if cfg.GroupSessionExempt != "" {
		g, err := group.NewGroup(ctx, "session-exempt-group", &group.GroupArgs{
			ID:                 cfg.GroupSessionExempt,
			DisplayName:        "gcp-session-exempt",
			Description:        "Users exempted from the 16-hour session reauthentication policy",
			CustomerID:         customerID,
			InitialGroupConfig: cfg.InitialGroupConfig,
		}, opts...)
		if err != nil {
			return nil, nil, err
		}
		groupResources = append(groupResources, g)
		groupOut.SessionExemptGroupID = g.GroupID.ApplyT(func(id string) string {
			return strings.TrimPrefix(id, "groups/")
		}).(pulumi.StringOutput)
	}

	return groupOut, groupResources, nil
}

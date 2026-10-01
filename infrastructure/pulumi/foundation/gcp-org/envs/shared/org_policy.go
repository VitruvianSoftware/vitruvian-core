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

	policy "github.com/VitruvianSoftware/pulumi-library/go/pkg/org_policy"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployOrgPolicies enforces organization-level security policies.
// This mirrors the Terraform foundation's org_policy.tf, applying 14+ boolean
// constraints and list constraints that form the security baseline.
//
// The logsExportLast parameter implements the Gap 3 race condition guard: the
// domain-restricted sharing policy must wait for log sinks to be created and
// their writer identities granted IAM, otherwise the sinks may fail with 403.
// The upstream uses a time_sleep of 30s; in Pulumi we use explicit DependsOn.
func deployOrgPolicies(ctx *pulumi.Context, cfg *OrgConfig, logsExportLast pulumi.Resource) error {
	parentID := "organizations/" + cfg.OrgID
	if cfg.ParentFolder != "" {
		parentID = "folders/" + cfg.ParentFolder
	}

	var loggingDeps []pulumi.Resource
	if logsExportLast != nil {
		loggingDeps = append(loggingDeps, logsExportLast)
	}

	// ========================================================================
	// Boolean Organization Policies
	// These are enforced across the entire org/folder hierarchy, preventing
	// common security misconfigurations at the infrastructure level.
	// ========================================================================
	booleanPolicies := []string{
		// Compute Engine hardening
		"compute.disableNestedVirtualization",
		"compute.disableSerialPortAccess",
		"compute.skipDefaultNetworkCreation",
		"compute.restrictXpnProjectLienRemoval",
		"compute.disableVpcExternalIpv6",
		"compute.setNewProjectDefaultToZonalDNSOnly",
		"compute.requireOsLogin",
		// Cloud SQL hardening
		"sql.restrictPublicIp",
		"sql.restrictAuthorizedNetworks",
		// IAM hardening — prevent SA key sprawl
		"iam.disableServiceAccountKeyCreation",
		"iam.automaticIamGrantsForDefaultServiceAccounts",
		"iam.disableServiceAccountKeyUpload",
		// Storage hardening
		"storage.uniformBucketLevelAccess",
		"storage.publicAccessPrevention",
	}

	for _, constraint := range booleanPolicies {
		if _, err := policy.NewOrgPolicy(ctx, fmt.Sprintf("policy-%s", constraint), &policy.OrgPolicyArgs{
			ParentID:   pulumi.String(parentID),
			Constraint: pulumi.String(fmt.Sprintf("constraints/%s", constraint)),
			Boolean:    pulumi.Bool(true),
		}); err != nil {
			return err
		}
	}

	// ========================================================================
	// List Organization Policies
	// ========================================================================

	// Deny all VM external IP access — enforce private networking
	if _, err := policy.NewOrgPolicy(ctx, "policy-vm-external-ip", &policy.OrgPolicyArgs{
		ParentID:   pulumi.String(parentID),
		Constraint: pulumi.String("constraints/compute.vmExternalIpAccess"),
		DenyAll:    pulumi.Bool(true),
	}); err != nil {
		return err
	}

	// Restrict protocol forwarding to internal only
	if _, err := policy.NewOrgPolicy(ctx, "policy-restrict-protocol-forwarding", &policy.OrgPolicyArgs{
		ParentID:    pulumi.String(parentID),
		Constraint:  pulumi.String("constraints/compute.restrictProtocolForwardingCreationForTypes"),
		AllowValues: pulumi.StringArray{pulumi.String("INTERNAL")},
	}); err != nil {
		return err
	}

	// Domain-restricted sharing — only allow specified domains
	// Gap 3 fix: this policy must wait for log sinks to finish deploying.
	// The upstream uses time_sleep "wait_logs_export" with create_duration = 30s
	// and depends_on = [module.logs_export]. In Pulumi we use explicit DependsOn
	// on the logging resources to establish the ordering guarantee.
	if len(cfg.DomainsToAllow) > 0 {
		domainValues := make(pulumi.StringArray, len(cfg.DomainsToAllow))
		for i, d := range cfg.DomainsToAllow {
			domainValues[i] = pulumi.String(d)
		}
		var policyOpts []pulumi.ResourceOption
		if len(loggingDeps) > 0 {
			policyOpts = append(policyOpts, pulumi.DependsOn(loggingDeps))
		}
		if _, err := policy.NewOrgPolicy(ctx, "policy-domain-restricted-sharing", &policy.OrgPolicyArgs{
			ParentID:    pulumi.String(parentID),
			Constraint:  pulumi.String("constraints/iam.allowedPolicyMemberDomains"),
			AllowValues: domainValues,
		}, policyOpts...); err != nil {
			return err
		}
	}

	// Essential Contacts domain restriction
	if len(cfg.EssentialContactsDomains) > 0 {
		contactDomains := make(pulumi.StringArray, len(cfg.EssentialContactsDomains))
		for i, d := range cfg.EssentialContactsDomains {
			// Ensure domain starts with "@"
			if d[0] != '@' {
				d = "@" + d
			}
			contactDomains[i] = pulumi.String(d)
		}
		if _, err := policy.NewOrgPolicy(ctx, "policy-essential-contacts-domains", &policy.OrgPolicyArgs{
			ParentID:    pulumi.String(parentID),
			Constraint:  pulumi.String("constraints/essentialcontacts.allowedContactDomains"),
			AllowValues: contactDomains,
		}); err != nil {
			return err
		}
	}

	// ========================================================================
	// Allowed Worker Pools (G1)
	// Restricts Cloud Build to only use the specified private worker pool.
	// Mirrors: module "allowed_worker_pools" in org_policy.tf
	// ========================================================================
	if cfg.EnforceAllowedWorkerPools && cfg.AllowedWorkerPoolID != "" {
		if _, err := policy.NewOrgPolicy(ctx, "policy-allowed-worker-pools", &policy.OrgPolicyArgs{
			ParentID:    pulumi.String(parentID),
			Constraint:  pulumi.String("constraints/cloudbuild.allowedWorkerPools"),
			AllowValues: pulumi.StringArray{pulumi.String(cfg.AllowedWorkerPoolID)},
		}); err != nil {
			return err
		}
	}

	// ========================================================================
	// OSS public-invoker exception (project-scoped DRS override)
	// Domain Restricted Sharing (constraints/iam.allowedPolicyMemberDomains) is
	// enforced org/folder-wide above, which blocks binding public principals
	// (allUsers) anywhere. The OSS application projects (prj-{env}-bu1-oss-
	// floating) host intentionally-public demo services (e.g. oauth-user-
	// inspector) whose Cloud Run service needs an allUsers run.invoker binding.
	//
	// We grant a narrowly-scoped exception: a project-level policy with AllowAll
	// on each named OSS project, overriding the inherited restriction for those
	// projects only. Applied here (gcp-org) because only the org SA holds
	// orgpolicy.policyAdmin; the downstream app/identity stacks (run as the proj
	// SA) cannot set org policies. The project list is data-driven config so the
	// exception surface stays explicit and reviewable.
	// ========================================================================
	for _, projectID := range cfg.OSSPublicInvokerProjects {
		if _, err := policy.NewOrgPolicy(ctx, "policy-oss-public-invoker-"+projectID, &policy.OrgPolicyArgs{
			ParentID:   pulumi.String("projects/" + projectID),
			Constraint: pulumi.String("constraints/iam.allowedPolicyMemberDomains"),
			AllowAll:   pulumi.Bool(true),
		}); err != nil {
			return err
		}
	}

	return nil
}

// deployAccessContextManagerPolicy creates the org-level Access Context
// Manager policy when create_access_context_manager_policy is enabled.
// This mirrors google_access_context_manager_access_policy.access_policy in
// the upstream org_policy.tf. Its output feeds the
// access_context_manager_policy_id stack export (outputs.go); when disabled,
// an empty string is exported instead.
func deployAccessContextManagerPolicy(ctx *pulumi.Context, cfg *OrgConfig) (pulumi.StringOutput, error) {
	if !cfg.CreateAccessContextManagerPolicy {
		return pulumi.String("").ToStringOutput(), nil
	}
	accessPolicy, err := accesscontextmanager.NewAccessPolicy(ctx, "access-policy", &accesscontextmanager.AccessPolicyArgs{
		Parent: pulumi.Sprintf("organizations/%s", cfg.OrgID),
		Title:  pulumi.String("default policy"),
	})
	if err != nil {
		return pulumi.StringOutput{}, err
	}
	return accessPolicy.Name, nil
}

// deploySessionControls configures Access Context Manager session controls for user access.
// When enable_session_controls_exemption is enabled, it binds the designated exempt group
// to a GcpUserAccessBinding with session controls disabled (sessionLengthEnabled: false, 0s),
// overriding the Google Cloud organization's default 16-hour session reauthentication policy
// for both Google Cloud SDK and Google Cloud Console.
func deploySessionControls(ctx *pulumi.Context, cfg *OrgConfig, bootstrapRef *pulumi.StackReference) error {
	if !cfg.EnableSessionControlsExemption {
		return nil
	}

	var groupKey pulumi.StringInput
	if cfg.SessionExemptGroupID != "" {
		groupKey = pulumi.String(cfg.SessionExemptGroupID)
	} else if bootstrapRef != nil {
		groupKey = bootstrapRef.GetOutput(pulumi.String("session_exempt_group_id")).ApplyT(func(v interface{}) (string, error) {
			if v == nil || v == "" {
				// During dry run (e.g. preview before bootstrap has applied and exported the group ID),
				// use a dummy/placeholder ID so preview does not error.
				if ctx.DryRun() {
					return "000000000000000", nil
				}
				return "", fmt.Errorf("session_exempt_group_id output is missing from bootstrap stack %q", cfg.BootstrapStackName)
			}
			s, ok := v.(string)
			if !ok {
				return "", fmt.Errorf("expected string for session_exempt_group_id, got %T", v)
			}
			return s, nil
		}).(pulumi.StringOutput)
	} else {
		return fmt.Errorf("enable_session_controls_exemption is true but neither session_exempt_group_id is configured nor bootstrapRef provided")
	}

	_, err := accesscontextmanager.NewGcpUserAccessBinding(ctx, "session-exempt-binding", &accesscontextmanager.GcpUserAccessBindingArgs{
		OrganizationId: pulumi.String(cfg.OrgID),
		GroupKey:       groupKey,
		ScopedAccessSettings: accesscontextmanager.GcpUserAccessBindingScopedAccessSettingArray{
			&accesscontextmanager.GcpUserAccessBindingScopedAccessSettingArgs{
				Scope: &accesscontextmanager.GcpUserAccessBindingScopedAccessSettingScopeArgs{
					ClientScope: &accesscontextmanager.GcpUserAccessBindingScopedAccessSettingScopeClientScopeArgs{
						RestrictedClientApplication: &accesscontextmanager.GcpUserAccessBindingScopedAccessSettingScopeClientScopeRestrictedClientApplicationArgs{
							Name: pulumi.String("Google Cloud SDK"),
						},
					},
				},
				ActiveSettings: &accesscontextmanager.GcpUserAccessBindingScopedAccessSettingActiveSettingsArgs{
					SessionSettings: &accesscontextmanager.GcpUserAccessBindingScopedAccessSettingActiveSettingsSessionSettingsArgs{
						SessionLength:        pulumi.String("0s"),
						SessionLengthEnabled: pulumi.Bool(false),
						SessionReauthMethod:  pulumi.String("LOGIN"),
					},
				},
			},
			&accesscontextmanager.GcpUserAccessBindingScopedAccessSettingArgs{
				Scope: &accesscontextmanager.GcpUserAccessBindingScopedAccessSettingScopeArgs{
					ClientScope: &accesscontextmanager.GcpUserAccessBindingScopedAccessSettingScopeClientScopeArgs{
						RestrictedClientApplication: &accesscontextmanager.GcpUserAccessBindingScopedAccessSettingScopeClientScopeRestrictedClientApplicationArgs{
							Name: pulumi.String("Cloud Console"),
						},
					},
				},
				ActiveSettings: &accesscontextmanager.GcpUserAccessBindingScopedAccessSettingActiveSettingsArgs{
					SessionSettings: &accesscontextmanager.GcpUserAccessBindingScopedAccessSettingActiveSettingsSessionSettingsArgs{
						SessionLength:        pulumi.String("0s"),
						SessionLengthEnabled: pulumi.Bool(false),
						SessionReauthMethod:  pulumi.String("LOGIN"),
					},
				},
			},
		},
	})
	return err
}

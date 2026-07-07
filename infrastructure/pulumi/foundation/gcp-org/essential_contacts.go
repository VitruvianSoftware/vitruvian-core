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
	"sort"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/essentialcontacts"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployEssentialContacts creates organization-level Essential Contacts
// for notification routing. This mirrors the Terraform foundation's
// essential_contacts.tf, implementing the full category-to-group mapping:
//
//	BILLING         → billing_admins, billing_data_users
//	LEGAL           → org_admins, audit_data_users
//	PRODUCT_UPDATES → org_admins
//	SECURITY        → scc_admin, security_reviewer
//	SUSPENSION      → org_admins
//	TECHNICAL       → security_reviewer, network_viewer
//
// Uses the configurable language tag (H9, defaults to "en").
func deployEssentialContacts(ctx *pulumi.Context, cfg *OrgConfig) error {
	parent := cfg.Parent // "organizations/<id>" or "folders/<id>"
	lang := cfg.EssentialContactsLanguage

	// Build a map of email → notification categories, mirroring the TF
	// transpose(categories_map) pattern. This groups categories per email
	// so each contact gets a single resource with all their categories.
	contactMap := make(map[string][]string)

	addContact := func(email string, categories ...string) {
		if email == "" {
			return
		}
		contactMap[email] = append(contactMap[email], categories...)
	}

	// Map categories to groups exactly as TF does.
	// TF's categories_map uses fallbacks to org_admins when optional groups
	// are not configured. We replicate this behavior here.

	// Resolve group emails with fallbacks (G12)
	sccAdmin := cfg.GCPSCCAdmin
	if sccAdmin == "" {
		sccAdmin = cfg.GroupOrgAdmins // fallback
	}
	securityReviewer := cfg.GCPSecurityReviewer
	if securityReviewer == "" {
		securityReviewer = cfg.GroupOrgAdmins // fallback
	}
	networkViewer := cfg.GCPNetworkViewer
	if networkViewer == "" {
		networkViewer = cfg.GroupOrgAdmins // fallback
	}

	// BILLING → billing_admins + billing_data_users
	addContact(cfg.GroupBillingAdmins, "BILLING")
	addContact(cfg.BillingDataUsers, "BILLING")

	// LEGAL → org_admins + audit_data_users
	addContact(cfg.GroupOrgAdmins, "LEGAL")
	addContact(cfg.AuditDataUsers, "LEGAL")

	// PRODUCT_UPDATES → org_admins
	addContact(cfg.GroupOrgAdmins, "PRODUCT_UPDATES")

	// SECURITY → scc_admin (or org_admins fallback) + security_reviewer (or org_admins fallback)
	addContact(sccAdmin, "SECURITY")
	addContact(securityReviewer, "SECURITY")

	// SUSPENSION → org_admins
	addContact(cfg.GroupOrgAdmins, "SUSPENSION")

	// TECHNICAL → security_reviewer (or org_admins) + network_viewer (or org_admins)
	addContact(securityReviewer, "TECHNICAL")
	addContact(networkViewer, "TECHNICAL")

	// De-duplicate categories per contact
	for email, cats := range contactMap {
		seen := make(map[string]bool)
		unique := make([]string, 0, len(cats))
		for _, c := range cats {
			if !seen[c] {
				seen[c] = true
				unique = append(unique, c)
			}
		}
		contactMap[email] = unique
	}

	// Create one Essential Contact per unique email.
	// Sort by email to ensure deterministic Pulumi resource names — Go map
	// iteration order is nondeterministic, which would otherwise cause
	// resource URN churn across preview/up runs.
	sortedEmails := make([]string, 0, len(contactMap))
	for email := range contactMap {
		sortedEmails = append(sortedEmails, email)
	}
	sort.Strings(sortedEmails)

	for idx, email := range sortedEmails {
		categories := contactMap[email]
		catArray := make(pulumi.StringArray, len(categories))
		for i, c := range categories {
			catArray[i] = pulumi.String(c)
		}

		if _, err := essentialcontacts.NewContact(ctx, fmt.Sprintf("essential-contact-%d", idx), &essentialcontacts.ContactArgs{
			Parent:                            pulumi.String(parent),
			Email:                             pulumi.String(email),
			LanguageTag:                       pulumi.String(lang),
			NotificationCategorySubscriptions: catArray,
		}); err != nil {
			return err
		}
	}

	return nil
}

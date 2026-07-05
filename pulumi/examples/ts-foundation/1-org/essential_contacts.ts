/**
 * Copyright 2026 Vitruvian Software
 *
 * 1-org/essential_contacts.ts — Organization Essential Contacts.
 * Mirrors: 1-org/envs/shared/essential_contacts.tf and
 * 1-org/essential_contacts.go in the Go foundation.
 *
 * Creates organization-level Essential Contacts for notification routing,
 * mapping notification categories (BILLING, LEGAL, SECURITY, etc.) to
 * the appropriate Google Groups.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { OrgConfig } from "./config";

/**
 * deployEssentialContacts creates Essential Contacts resources.
 * Port of Go foundation's deployEssentialContacts (essential_contacts.go:38-127).
 *
 * Category → Group mapping (mirrors TF's transpose(categories_map)):
 *   BILLING         → billing_admins, billing_data_users
 *   LEGAL           → org_admins, audit_data_users
 *   PRODUCT_UPDATES → org_admins
 *   SECURITY        → scc_admin (fallback: org_admins), security_reviewer (fallback: org_admins)
 *   SUSPENSION      → org_admins
 *   TECHNICAL       → security_reviewer (fallback: org_admins), network_viewer (fallback: org_admins)
 */
export function deployEssentialContacts(cfg: OrgConfig): void {
    const parent = cfg.parent; // "organizations/<id>" or "folders/<id>"
    const lang = cfg.essentialContactsLanguage;

    // Build contact map: email → notification categories
    const contactMap: Record<string, Set<string>> = {};

    const addContact = (email: string | undefined, ...categories: string[]) => {
        if (!email) return;
        if (!contactMap[email]) contactMap[email] = new Set();
        for (const cat of categories) {
            contactMap[email].add(cat);
        }
    };

    // Resolve group emails with fallbacks (matches Go G12 pattern)
    const orgAdmins = cfg.requiredGroups.group_org_admins;
    const sccAdmin = cfg.gcpGroups.sccAdmin || orgAdmins;
    const securityReviewer = cfg.gcpGroups.securityReviewer || orgAdmins;
    const networkViewer = cfg.gcpGroups.networkViewer || orgAdmins;

    // BILLING → billing_admins + billing_data_users
    addContact(cfg.requiredGroups.group_billing_admins, "BILLING");
    addContact(cfg.requiredGroups.billing_data_users, "BILLING");

    // LEGAL → org_admins + audit_data_users
    addContact(orgAdmins, "LEGAL");
    addContact(cfg.requiredGroups.audit_data_users, "LEGAL");

    // PRODUCT_UPDATES → org_admins
    addContact(orgAdmins, "PRODUCT_UPDATES");

    // SECURITY → scc_admin + security_reviewer
    addContact(sccAdmin, "SECURITY");
    addContact(securityReviewer, "SECURITY");

    // SUSPENSION → org_admins
    addContact(orgAdmins, "SUSPENSION");

    // TECHNICAL → security_reviewer + network_viewer
    addContact(securityReviewer, "TECHNICAL");
    addContact(networkViewer, "TECHNICAL");

    // Create one Essential Contact per unique email
    let idx = 0;
    for (const [email, categories] of Object.entries(contactMap)) {
        new gcp.essentialcontacts.Contact(`essential-contact-${idx}`, {
            parent,
            email,
            languageTag: lang,
            notificationCategorySubscriptions: [...categories],
        });
        idx++;
    }
}

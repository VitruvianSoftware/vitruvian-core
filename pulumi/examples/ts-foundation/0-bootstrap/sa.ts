/**
 * Service Accounts and IAM — mirrors 0-bootstrap/sa.tf
 * Creates granular service accounts for each foundation step with
 * least-privilege IAM bindings at org, parent, seed, and CI/CD project levels.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { BootstrapConfig } from "./config";
import { ParentIamMember } from "./modules/parent-iam-member";
import { ParentIamRemoveRole } from "./modules/parent-iam-remove-role";

export interface GranularSAs {
    saEmails: Record<string, pulumi.Output<string>>;
    serviceAccounts: Record<string, gcp.serviceaccount.Account>;
}

export async function deployServiceAccounts(
    cfg: BootstrapConfig,
    seedProject: gcp.organizations.Project,
    cicdProjectId: pulumi.Output<string>,
groupDependsOn?: pulumi.Resource[],
): Promise<GranularSAs> {
    const opts = { dependsOn: groupDependsOn };
    const parentType = cfg.parentType;
    const parentId = cfg.parentId;

    const granularSaDescriptions: Record<string, string> = {
        bootstrap: "Foundation Bootstrap SA. Managed by Pulumi.",
        org: "Foundation Organization SA. Managed by Pulumi.",
        env: "Foundation Environment SA. Managed by Pulumi.",
        net: "Foundation Network SA. Managed by Pulumi.",
        proj: "Foundation Projects SA. Managed by Pulumi.",
    };

    const commonRoles = ["roles/browser"];

    const orgLevelRoles: Record<string, string[]> = {
        bootstrap: [...new Set([
            "roles/resourcemanager.organizationAdmin",
            "roles/accesscontextmanager.policyAdmin",
            "roles/serviceusage.serviceUsageConsumer",
            ...commonRoles,
        ])],
        org: [...new Set([
            "roles/orgpolicy.policyAdmin",
            "roles/logging.configWriter",
            "roles/resourcemanager.organizationAdmin",
            "roles/securitycenter.notificationConfigEditor",
            "roles/resourcemanager.organizationViewer",
            "roles/accesscontextmanager.policyAdmin",
            "roles/essentialcontacts.admin",
            "roles/resourcemanager.tagAdmin",
            "roles/resourcemanager.tagUser",
            "roles/cloudasset.owner",
            "roles/securitycenter.sourcesEditor",
            ...commonRoles,
        ])],
        env: [...new Set([
            "roles/resourcemanager.tagUser",
            "roles/assuredworkloads.admin",
            ...commonRoles,
        ])],
        net: [...new Set([
            "roles/accesscontextmanager.policyAdmin",
            "roles/compute.xpnAdmin",
            ...commonRoles,
        ])],
        proj: [...new Set([
            "roles/accesscontextmanager.policyAdmin",
            "roles/resourcemanager.organizationAdmin",
            "roles/serviceusage.serviceUsageConsumer",
            "roles/cloudkms.admin",
            ...commonRoles,
        ])],
    };

    const parentLevelRoles: Record<string, string[]> = {
        bootstrap: ["roles/resourcemanager.folderAdmin"],
        org: ["roles/resourcemanager.folderAdmin"],
        env: ["roles/resourcemanager.folderAdmin"],
        net: [
            "roles/resourcemanager.folderViewer",
            "roles/compute.networkAdmin",
            "roles/compute.securityAdmin",
            "roles/compute.orgSecurityPolicyAdmin",
            "roles/compute.orgSecurityResourceAdmin",
            "roles/dns.admin",
        ],
        proj: [
            "roles/resourcemanager.folderAdmin",
            "roles/artifactregistry.admin",
            "roles/compute.networkAdmin",
            "roles/compute.xpnAdmin",
        ],
    };

    const seedProjectRoles: Record<string, string[]> = {
        bootstrap: [
            "roles/storage.admin",
            "roles/iam.serviceAccountAdmin",
            "roles/resourcemanager.projectDeleter",
            "roles/cloudkms.admin",
        ],
        org: ["roles/storage.objectAdmin"],
        env: ["roles/storage.objectAdmin"],
        net: ["roles/storage.objectAdmin"],
        proj: ["roles/storage.objectAdmin", "roles/storage.admin"],
    };

    const cicdProjectRoles: Record<string, string[]> = {
        bootstrap: [
            "roles/storage.admin",
            "roles/compute.networkAdmin",
            "roles/cloudbuild.builds.editor",
            "roles/cloudbuild.workerPoolOwner",
            "roles/artifactregistry.admin",
            "roles/source.admin",
            "roles/iam.serviceAccountAdmin",
            "roles/workflows.admin",
            "roles/cloudscheduler.admin",
            "roles/resourcemanager.projectDeleter",
            "roles/dns.admin",
            "roles/iam.workloadIdentityPoolAdmin",
        ],
    };

    // Create service accounts
    const serviceAccounts: Record<string, gcp.serviceaccount.Account> = {};
    const saEmails: Record<string, pulumi.Output<string>> = {};

    for (const [key, description] of Object.entries(granularSaDescriptions)) {
        const sa = new gcp.serviceaccount.Account(`terraform-env-sa-${key}`, {
            project: seedProject.projectId,
            accountId: `sa-terraform-${key}`,
            displayName: description,
            createIgnoreAlreadyExists: true,
        });
        serviceAccounts[key] = sa;
        saEmails[key] = sa.email;
    }

    // Self-impersonation: allow each granular SA to mint tokens for itself
    // (roles/iam.serviceAccountTokenCreator on itself), matching TF self_impersonate
    // and the Go port. Relies on iamcredentials.googleapis.com on the seed project.
    for (const [key, sa] of Object.entries(serviceAccounts)) {
        new gcp.serviceaccount.IAMMember(`sa-self-impersonate-${key}`, {
            serviceAccountId: sa.name,
            role: "roles/iam.serviceAccountTokenCreator",
            member: pulumi.interpolate`serviceAccount:${sa.email}`,
        }, opts);
    }

    // Org-level IAM bindings
    for (const [key, roles] of Object.entries(orgLevelRoles)) {
        new ParentIamMember(`org-iam-${key}`, {
            member: pulumi.interpolate`serviceAccount:${serviceAccounts[key].email}`,
            parentType: "organization",
            parentId: cfg.orgId,
            roles: roles,
        }, opts);
    }

    // Parent-level IAM bindings (folder or org)
    for (const [key, roles] of Object.entries(parentLevelRoles)) {
        new ParentIamMember(`parent-iam-${key}`, {
            member: pulumi.interpolate`serviceAccount:${serviceAccounts[key].email}`,
            parentType: parentType,
            parentId: parentId,
            roles: roles,
        }, opts);
    }

    // Seed project IAM bindings
    for (const [key, roles] of Object.entries(seedProjectRoles)) {
        new ParentIamMember(`seed-iam-${key}`, {
            member: pulumi.interpolate`serviceAccount:${serviceAccounts[key].email}`,
            parentType: "project",
            parentId: seedProject.projectId,
            roles: roles,
        }, opts);
    }

    // CI/CD project IAM bindings
    for (const [key, roles] of Object.entries(cicdProjectRoles)) {
        new ParentIamMember(`cicd-iam-${key}`, {
            member: pulumi.interpolate`serviceAccount:${serviceAccounts[key].email}`,
            parentType: "project",
            parentId: cicdProjectId,
            roles: roles,
        }, opts);
    }

    // Remove default editor role from bootstrap projects
    for (const [label, projectId] of [
        ["seed", seedProject.projectId],
        ["cicd", cicdProjectId],
    ] as const) {
        new ParentIamRemoveRole(`remove-editor-${label}`, {
            parentType: "project",
            parentId: projectId,
            roles: ["roles/editor"],
        }, opts);
    }

    // Billing account IAM
    for (const [key] of Object.entries(granularSaDescriptions)) {
        new gcp.billing.AccountIamMember(`billing-user-${key}`, {
            billingAccountId: cfg.billingAccount,
            role: "roles/billing.user",
            member: pulumi.interpolate`serviceAccount:${serviceAccounts[key].email}`,
        }, opts);

        new gcp.billing.AccountIamMember(`billing-admin-${key}`, {
            billingAccountId: cfg.billingAccount,
            role: "roles/billing.admin",
            member: pulumi.interpolate`serviceAccount:${serviceAccounts[key].email}`,
        }, opts);
    }

    // Billing account sink writer for org SA
    new gcp.billing.AccountIamMember("billing-sink-writer", {
        billingAccountId: cfg.billingAccount,
        role: "roles/logging.configWriter",
        member: pulumi.interpolate`serviceAccount:${serviceAccounts["org"].email}`,
    }, opts);

    return { saEmails, serviceAccounts };
}

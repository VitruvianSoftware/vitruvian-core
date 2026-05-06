/**
 * Copyright 2026 Vitruvian Software
 *
 * 1-org/iam.ts — IAM bindings for governance groups on org-level projects.
 * Mirrors: 1-org/envs/shared/iam.tf + 1-org/envs/shared/sa.tf in the
 * terraform-example-foundation and 1-org/iam.go in the Go foundation.
 *
 * Creates project-level, org-level, and folder-level IAM bindings that grant
 * the Google Groups (defined in bootstrap) actual permissions on the shared
 * org projects (created in this stage's index.ts).
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import * as command from "@pulumi/command";
import { OrgConfig } from "./config";

export interface OrgProjectRefs {
    auditLogsProjectId: pulumi.Output<string>;
    billingExportProjectId: pulumi.Output<string>;
    orgSecretsProjectId: pulumi.Output<string>;
    orgKmsProjectId: pulumi.Output<string>;
    sccProjectId: pulumi.Output<string>;
    netHubProjectId?: pulumi.Output<string>;
}

/**
 * orgOrFolderIAMMember creates an IAM member at the org level or
 * at the parent-folder level depending on configuration.
 * Matches Go foundation's orgOrFolderIAMMember helper.
 */
function orgOrFolderIAMMember(
    name: string,
    cfg: OrgConfig,
    role: string,
    member: string,
): void {
    if (cfg.parentFolder === "") {
        new gcp.organizations.IAMMember(name, {
            orgId: cfg.orgId,
            role,
            member,
        });
    } else {
        new gcp.folder.IAMMember(`${name}-folder`, {
            folder: cfg.parentFolder,
            role,
            member,
        });
    }
}

/**
 * deployOrgIAM creates all IAM bindings for governance groups.
 * Port of Go foundation's deployOrgIAM (iam.go:56-319).
 */
export function deployOrgIAM(cfg: OrgConfig, proj: OrgProjectRefs): void {
    // ========================================================================
    // 1. Audit Logs Project — IAM for audit_data_users
    // ========================================================================
    const auditDataUsers = cfg.requiredGroups.audit_data_users;
    if (auditDataUsers) {
        const auditGroup = `group:${auditDataUsers}`;
        const auditRoles: [string, string][] = [
            ["audit-log-viewer", "roles/logging.viewer"],
            ["audit-bq-user", "roles/bigquery.user"],
            ["audit-bq-data-viewer", "roles/bigquery.dataViewer"],
        ];
        for (const [name, role] of auditRoles) {
            new gcp.projects.IAMMember(name, {
                project: proj.auditLogsProjectId,
                role,
                member: auditGroup,
            });
        }
    }

    // ========================================================================
    // 2. Billing Export Project — IAM for billing_data_users
    // ========================================================================
    const billingDataUsers = cfg.requiredGroups.billing_data_users;
    if (billingDataUsers) {
        const billingGroup = `group:${billingDataUsers}`;

        // Project-level: BQ user + data viewer
        const billingRoles: [string, string][] = [
            ["billing-bq-user", "roles/bigquery.user"],
            ["billing-bq-data-viewer", "roles/bigquery.dataViewer"],
        ];
        for (const [name, role] of billingRoles) {
            new gcp.projects.IAMMember(name, {
                project: proj.billingExportProjectId,
                role,
                member: billingGroup,
            });
        }

        // Org-level: billing viewer
        new gcp.organizations.IAMMember("billing-viewer", {
            orgId: cfg.orgId,
            role: "roles/billing.viewer",
            member: billingGroup,
        });
    }

    // ========================================================================
    // 3. Security Reviewer Group — org or folder level
    // ========================================================================
    const securityReviewer = cfg.gcpGroups.securityReviewer;
    if (securityReviewer) {
        orgOrFolderIAMMember("security-reviewer", cfg, "roles/iam.securityReviewer", `group:${securityReviewer}`);
    }

    // ========================================================================
    // 4. Network Viewer Group — org or folder level
    // ========================================================================
    const networkViewer = cfg.gcpGroups.networkViewer;
    if (networkViewer) {
        orgOrFolderIAMMember("network-viewer", cfg, "roles/compute.networkViewer", `group:${networkViewer}`);
    }

    // ========================================================================
    // 5. SCC Admin Group
    // ========================================================================
    const sccAdmin = cfg.gcpGroups.sccAdmin;
    if (sccAdmin) {
        const member = `group:${sccAdmin}`;

        // Org-level: SCC admin editor (only when not under parent_folder)
        if (cfg.parentFolder === "") {
            new gcp.organizations.IAMMember("org-scc-admin", {
                orgId: cfg.orgId,
                role: "roles/securitycenter.adminEditor",
                member,
            });
        }

        // Project-level: SCC admin editor on SCC project
        new gcp.projects.IAMMember("project-scc-admin", {
            project: proj.sccProjectId,
            role: "roles/securitycenter.adminEditor",
            member,
        });
    }

    // ========================================================================
    // 6. Global Secrets Admin Group
    // ========================================================================
    const globalSecretsAdmin = cfg.gcpGroups.globalSecretsAdmin;
    if (globalSecretsAdmin) {
        new gcp.projects.IAMMember("global-secrets-admin", {
            project: proj.orgSecretsProjectId,
            role: "roles/secretmanager.admin",
            member: `group:${globalSecretsAdmin}`,
        });
    }

    // ========================================================================
    // 7. KMS Admin Group
    // ========================================================================
    const kmsAdmin = cfg.gcpGroups.kmsAdmin;
    if (kmsAdmin) {
        const kmsGroup = `group:${kmsAdmin}`;

        // Project-level: KMS viewer on KMS project
        new gcp.projects.IAMMember("kms-viewer", {
            project: proj.orgKmsProjectId,
            role: "roles/cloudkms.viewer",
            member: kmsGroup,
        });
    }

    // ========================================================================
    // 7b. KMS Protected Resources Viewer (mirrors TF iam.tf:174-179)
    // ========================================================================
    if (kmsAdmin && cfg.enableKmsKeyUsageTracking) {
        const kmsGroup = `group:${kmsAdmin}`;
        new gcp.organizations.IAMMember("kms-protected-resources-viewer", {
            orgId: cfg.orgId,
            role: "roles/cloudkms.protectedResourcesViewer",
            member: kmsGroup,
        });
    }

    // ========================================================================
    // 8. KMS Org Service Agent IAM
    // Grants roles/cloudkms.orgServiceAgent to the KMS service agent.
    // Upstream TF uses `gcloud beta services identity create --organization`
    // to provision the org-level KMS service agent. The Pulumi
    // gcp.projects.ServiceIdentity only creates a project-level identity,
    // so we use a Command resource for the org-level agent.
    // Gated behind enableKmsKeyUsageTracking (default: true in TF).
    // ========================================================================
    if (cfg.enableKmsKeyUsageTracking) {
        const kmsOrgIdentity = new command.local.Command("kms-org-service-identity", {
            create: `gcloud beta services identity create --service cloudkms.googleapis.com --organization ${cfg.orgId}`,
        });

        const kmsServiceAgent = `serviceAccount:service-org-${cfg.orgId}@gcp-sa-cloudkms.iam.gserviceaccount.com`;
        new gcp.organizations.IAMMember("kms-usage-tracking", {
            orgId: cfg.orgId,
            role: "roles/cloudkms.orgServiceAgent",
            member: kmsServiceAgent,
        }, { dependsOn: [kmsOrgIdentity] });
    }

    // ========================================================================
    // 9. Audit Viewer Group IAM
    // Separate from audit_data_users — optional governance group.
    // ========================================================================
    const auditViewer = cfg.gcpGroups.auditViewer;
    if (auditViewer) {
        const viewerGroup = `group:${auditViewer}`;
        const viewerRoles: [string, string][] = [
            ["audit-viewer-log", "roles/logging.viewer"],
            ["audit-viewer-private-log", "roles/logging.privateLogViewer"],
            ["audit-viewer-bq-data", "roles/bigquery.dataViewer"],
        ];
        for (const [name, role] of viewerRoles) {
            new gcp.projects.IAMMember(name, {
                project: proj.auditLogsProjectId,
                role,
                member: viewerGroup,
            });
        }
    }

    // ========================================================================
    // 10. Hub-and-Spoke Network SA IAM
    // When enable_hub_and_spoke is true, grant the networks pipeline SA
    // elevated roles on the hub project.
    // ========================================================================
    if (cfg.enableHubAndSpoke && cfg.networksStepTerraformSaEmail && proj.netHubProjectId) {
        const hubAndSpokeRoles = [
            "roles/compute.instanceAdmin",
            "roles/iam.serviceAccountAdmin",
            "roles/resourcemanager.projectIamAdmin",
            "roles/iam.serviceAccountUser",
        ];
        const networkSA = `serviceAccount:${cfg.networksStepTerraformSaEmail}`;
        for (const role of hubAndSpokeRoles) {
            new gcp.projects.IAMMember(`net-hub-sa-${role.split("/")[1]}`, {
                project: proj.netHubProjectId,
                role,
                member: networkSA,
            });
        }
    }

    // ========================================================================
    // 11. CAI Monitoring Builder SA + IAM
    // Create dedicated SA for the CAI monitoring Cloud Build pipeline.
    // Gated behind enableSccResources (matching upstream TF).
    // ========================================================================
    if (cfg.enableSccResources) {
        const caiBuilderSa = new gcp.serviceaccount.Account("cai-monitoring-builder", {
            project: proj.sccProjectId,
            accountId: "cai-monitoring-builder",
            description: "Service account for Cloud Build to provision CAI monitoring Cloud Functions",
            createIgnoreAlreadyExists: true,
        });

        const caiSAMember = pulumi.interpolate`serviceAccount:${caiBuilderSa.email}`;
        const caiRoles: [string, string][] = [
            ["cai-log-writer", "roles/logging.logWriter"],
            ["cai-storage-viewer", "roles/storage.objectViewer"],
            ["cai-ar-writer", "roles/artifactregistry.writer"],
        ];
        for (const [name, role] of caiRoles) {
            new gcp.projects.IAMMember(name, {
                project: proj.sccProjectId,
                role,
                member: caiSAMember,
            });
        }
    }
}

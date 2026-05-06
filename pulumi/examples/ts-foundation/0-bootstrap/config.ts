/**
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

import * as pulumi from "@pulumi/pulumi";

/**
 * Config holds all configuration for the bootstrap stage.
 * Mirrors the Terraform foundation's 0-bootstrap/variables.tf for full feature parity.
 */
export interface BootstrapConfig {
    orgId: string;
    billingAccount: string;
    projectPrefix: string;
    folderPrefix: string;
    bucketPrefix: string;
    defaultRegion: string;
    defaultRegion2: string;
    defaultRegionGcs: string;
    defaultRegionKms: string;
    kmsKeyProtectionLevel: string;
    parent: string;
    parentFolder: string;
    parentType: "organization" | "folder";
    parentId: string;
    orgPolicyAdminRole: boolean;
    bucketForceDestroy: boolean;
    bucketTfStateKmsForceDestroy: boolean;
    randomSuffix: boolean;
    projectDeletionPolicy: string;
    folderDeletionProtection: boolean;
    workflowDeletionProtection: boolean;

    // Groups — required for org admin and billing workflows
    groups: {
        createRequiredGroups: boolean;
        createOptionalGroups: boolean;
        billingProject?: string;
        requiredGroups: {
            groupOrgAdmins: string;
            groupBillingAdmins: string;
            billingDataUsers: string;
            auditDataUsers: string;
        };
        optionalGroups: {
            gcpSecurityReviewer: string;
            gcpNetworkViewer: string;
            gcpSccAdmin: string;
            gcpGlobalSecretsAdmin: string;
            gcpKmsAdmin: string;
        };
    };

    initialGroupConfig: string;

    // Workload Identity Federation attribute condition
    attributeCondition?: string;
}

export function loadConfig(pulumiConfig: pulumi.Config): BootstrapConfig {
    const parentFolder = pulumiConfig.get("parent_folder") || "";
    const orgId = pulumiConfig.require("org_id");

    const parent = parentFolder !== "" ? `folders/${parentFolder}` : `organizations/${orgId}`;
    const parentType = parentFolder !== "" ? "folder" as const : "organization" as const;
    const parentId = parentFolder !== "" ? parentFolder : orgId;

    // Groups config — mirrors the complex groups variable from TF
    const groupOrgAdmins = pulumiConfig.require("group_org_admins");
    const groupBillingAdmins = pulumiConfig.require("group_billing_admins");
    const billingDataUsers = pulumiConfig.require("billing_data_users");
    const auditDataUsers = pulumiConfig.require("audit_data_users");

    return {
        orgId,
        billingAccount: pulumiConfig.require("billing_account"),
        projectPrefix: pulumiConfig.get("project_prefix") || "prj",
        folderPrefix: pulumiConfig.get("folder_prefix") || "fldr",
        bucketPrefix: pulumiConfig.get("bucket_prefix") || "bkt",
        defaultRegion: pulumiConfig.get("default_region") || "us-central1",
        defaultRegion2: pulumiConfig.get("default_region_2") || "us-west1",
        defaultRegionGcs: pulumiConfig.get("default_region_gcs") || "US",
        defaultRegionKms: pulumiConfig.get("default_region_kms") || "us",
        kmsKeyProtectionLevel: pulumiConfig.get("kms_key_protection_level") || "SOFTWARE",
        projectDeletionPolicy: pulumiConfig.get("project_deletion_policy") || "PREVENT",
        parentFolder,
        parent,
        parentType,
        parentId,

        orgPolicyAdminRole: pulumiConfig.getBoolean("org_policy_admin_role") ?? false,
        bucketForceDestroy: pulumiConfig.getBoolean("bucket_force_destroy") ?? false,
        bucketTfStateKmsForceDestroy: pulumiConfig.getBoolean("bucket_tfstate_kms_force_destroy") ?? false,
        folderDeletionProtection: pulumiConfig.getBoolean("folder_deletion_protection") ?? true,
        workflowDeletionProtection: pulumiConfig.getBoolean("workflow_deletion_protection") ?? true,
        randomSuffix: pulumiConfig.getBoolean("random_suffix") ?? true,

        groups: {
            createRequiredGroups: pulumiConfig.getBoolean("create_required_groups") ?? false,
            createOptionalGroups: pulumiConfig.getBoolean("create_optional_groups") ?? false,
            billingProject: pulumiConfig.get("groups_billing_project"),
            requiredGroups: {
                groupOrgAdmins,
                groupBillingAdmins,
                billingDataUsers,
                auditDataUsers,
            },
            optionalGroups: {
                gcpSecurityReviewer: pulumiConfig.get("gcp_security_reviewer") || "",
                gcpNetworkViewer: pulumiConfig.get("gcp_network_viewer") || "",
                gcpSccAdmin: pulumiConfig.get("gcp_scc_admin") || "",
                gcpGlobalSecretsAdmin: pulumiConfig.get("gcp_global_secrets_admin") || "",
                gcpKmsAdmin: pulumiConfig.get("gcp_kms_admin") || "",
            },
        },
        initialGroupConfig: pulumiConfig.get("initial_group_config") || "WITH_INITIAL_OWNER",
        attributeCondition: pulumiConfig.get("attribute_condition"),
    };
}

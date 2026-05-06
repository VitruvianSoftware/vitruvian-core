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

export interface OrgConfig {
    orgId: string;
    billingAccount: string;
    projectPrefix: string;
    folderPrefix: string;
    defaultRegion: string;
    parent: string;
    parentFolder: string;
    parentType: "organization" | "folder";
    parentId: string;
    enableHubAndSpoke: boolean;
    enableHubAndSpokeTransitivity: boolean;
    domainsToAllow: string[];
    essentialContactsDomainsToAllow: string[];
    essentialContactsLanguage: string;
    sccNotificationName: string;
    sccNotificationFilter: string;
    createUniqueTagKey: boolean;
    enableCaiMonitoring: boolean;
    enableSccResources: boolean;
    enableKmsKeyUsageTracking: boolean;
    createAccessContextManagerAccessPolicy: boolean;
    enforceAllowedWorkerPools: boolean;
    cloudBuildPrivateWorkerPoolId?: string;
    caiMonitoringKmsForceDestroy: boolean;
    projectDeletionPolicy: string;
    folderDeletionProtection: boolean;
    logExportStorageForceDestroy: boolean;
    logExportStorageVersioning: boolean;
    logExportStorageLocation?: string;
    billingExportDatasetLocation?: string;
    logExportStorageRetentionPolicy?: {
        isLocked: boolean;
        retentionPeriodDays: number;
    };
    remoteStateBucket: string;
    // Loaded from bootstrap stack reference
    bootstrapFolderName?: string;
    networksStepTerraformSaEmail?: string;
    projectsStepTerraformSaEmail?: string;
    requiredGroups: Record<string, string>;
    optionalGroups: Record<string, string>;
    projectBudget: Record<string, any>;
    gcpGroups: {
        auditViewer?: string;
        securityReviewer?: string;
        networkViewer?: string;
        sccAdmin?: string;
        globalSecretsAdmin?: string;
        kmsAdmin?: string;
    };
}

export function loadOrgConfig(config: pulumi.Config): OrgConfig {
    const parentFolder = config.get("parent_folder") || "";
    const orgId = config.require("org_id");
    const parent = parentFolder !== "" ? `folders/${parentFolder}` : `organizations/${orgId}`;
    const parentType = parentFolder !== "" ? "folder" as const : "organization" as const;
    const parentId = parentFolder !== "" ? parentFolder : orgId;

    return {
        orgId,
        billingAccount: config.require("billing_account"),
        projectPrefix: config.get("project_prefix") || "prj",
        folderPrefix: config.get("folder_prefix") || "fldr",
        defaultRegion: config.get("default_region") || "us-central1",
        parent,
        parentFolder,
        parentType,
        parentId,
        enableHubAndSpoke: config.getBoolean("enable_hub_and_spoke") ?? false,
        enableHubAndSpokeTransitivity: config.getBoolean("enable_hub_and_spoke_transitivity") ?? false,
        domainsToAllow: config.getObject<string[]>("domains_to_allow") || [],
        essentialContactsDomainsToAllow: config.getObject<string[]>("essential_contacts_domains_to_allow") || [],
        essentialContactsLanguage: config.get("essential_contacts_language") || "en",
        sccNotificationName: config.get("scc_notification_name") || "scc-notify",
        sccNotificationFilter: config.get("scc_notification_filter") || "state = \"ACTIVE\"",
        createUniqueTagKey: config.getBoolean("create_unique_tag_key") ?? false,
        enableCaiMonitoring: config.getBoolean("enable_cai_monitoring") ?? false,
        enableSccResources: config.getBoolean("enable_scc_resources") ?? false,
        enableKmsKeyUsageTracking: config.getBoolean("enable_kms_key_usage_tracking") ?? true,
        createAccessContextManagerAccessPolicy: config.getBoolean("create_access_context_manager_access_policy") ?? true,
        enforceAllowedWorkerPools: config.getBoolean("enforce_allowed_worker_pools") ?? true,
        cloudBuildPrivateWorkerPoolId: config.get("cloud_build_private_worker_pool_id") || undefined,
        caiMonitoringKmsForceDestroy: config.getBoolean("cai_monitoring_kms_force_destroy") ?? false,
        projectDeletionPolicy: config.get("project_deletion_policy") || "PREVENT",
        folderDeletionProtection: config.getBoolean("folder_deletion_protection") ?? true,
        logExportStorageForceDestroy: config.getBoolean("log_export_storage_force_destroy") ?? false,
        logExportStorageVersioning: config.getBoolean("log_export_storage_versioning") ?? false,
        logExportStorageLocation: config.get("log_export_storage_location") || undefined,
        billingExportDatasetLocation: config.get("billing_export_dataset_location") || undefined,
        remoteStateBucket: config.require("remote_state_bucket"),
        requiredGroups: config.getObject<Record<string, string>>("required_groups") || {},
        optionalGroups: config.getObject<Record<string, string>>("optional_groups") || {},
        projectBudget: config.getObject<Record<string, any>>("project_budget") || {},
        gcpGroups: config.getObject<OrgConfig["gcpGroups"]>("gcp_groups") || {},
    };
}

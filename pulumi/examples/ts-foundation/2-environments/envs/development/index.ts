/**
 * 2-environments/envs/development/index.ts
 * Mirrors: 2-environments/envs/development/main.tf
 */

import * as pulumi from "@pulumi/pulumi";
import { deployEnvBaseline } from "../../modules/env_baseline";

export = async () => {
    const config = new pulumi.Config();

    // Stack references for remote state
    const bootstrapRef = new pulumi.StackReference("bootstrap");
    const orgRef = new pulumi.StackReference("org");

    const commonConfig = bootstrapRef.getOutput("common_config") as pulumi.Output<Record<string, string>>;
    const requiredGroups = bootstrapRef.getOutput("required_groups") as pulumi.Output<Record<string, string>>;
    const tags = orgRef.getOutput("tags");

    const result = deployEnvBaseline({
        env: "development",
        environmentCode: "d",
        orgId: config.require("org_id"),
        billingAccount: config.require("billing_account"),
        projectPrefix: config.get("project_prefix") || "prj",
        folderPrefix: config.get("folder_prefix") || "fldr",
        parent: config.require("parent"),
        tags: tags as any,
        requiredGroups: config.getObject<Record<string, string>>("required_groups") || {},
        projectDeletionPolicy: config.get("project_deletion_policy") || "PREVENT",
        folderDeletionProtection: config.getBoolean("folder_deletion_protection") ?? true,
        projectBudget: config.getObject<Record<string, any>>("project_budget") || {},
    });

    return {
        env_folder: result.envFolder.name,
        env_folder_id: result.envFolderId,
        env_kms_project_id: result.envKmsProjectId,
        env_kms_project_number: result.envKmsProjectNumber,
        env_secrets_project_id: result.envSecretsProjectId,
        assured_workload_id: result.assuredWorkloadId,
        assured_workload_resources: result.assuredWorkloadResources,
    };
};

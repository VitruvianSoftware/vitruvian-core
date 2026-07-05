/**
 * 2-environments/envs/development/index.ts
 * Mirrors: 2-environments/envs/development/main.tf
 */

import * as pulumi from "@pulumi/pulumi";
import { deployEnvBaseline } from "../../modules/env_baseline";

export = async () => {
    const config = new pulumi.Config();

    // Stack references for remote state
    const bootstrapStackName = config.get("bootstrap_stack") || "bootstrap";
    const orgStackName = config.get("org_stack") || "org";
    const bootstrapRef = new pulumi.StackReference(bootstrapStackName);
    const orgRef = new pulumi.StackReference(orgStackName);

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
        assuredWorkloadConfiguration: config.getObject<any>("assured_workload_configuration"),
    });

    // Exports — matches upstream TF 2-environments/envs/development/outputs.tf exactly
    const exports: Record<string, any> = {
        env_folder: result.envFolder.name,
        env_kms_project_id: result.envKmsProjectId,
        env_kms_project_number: result.envKmsProjectNumber,
        env_secrets_project_id: result.envSecretsProjectId,
    };
    if (result.assuredWorkloadId) {
        exports.assured_workload_id = result.assuredWorkloadId;
        exports.assured_workload_resources = result.assuredWorkloadResources;
    }
    return exports;
};

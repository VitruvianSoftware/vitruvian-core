/**
 * 4-projects/business_unit_1/shared/index.ts
 * Mirrors: 4-projects/business_unit_1/shared/example_infra_pipeline.tf
 * Creates infra pipeline projects for app-infra deployments.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { ProjectFactory } from "@vitruviansoftware/foundation-project-factory";

export = async () => {
    const config = new pulumi.Config();
    const bootstrapRef = new pulumi.StackReference("bootstrap");

    const cloudbuildProjectId = bootstrapRef.getOutput("cloudbuild_project_id") as pulumi.Output<string>;
    const projectPrefix = config.get("project_prefix") || "prj";
    const businessCode = config.get("business_code") || "bu1";
    const orgId = config.require("org_id");
    const billingAccount = config.require("billing_account");

    // App-infra pipeline project
    const appInfraProject = new ProjectFactory("app-infra-pipeline", {
        name: `${projectPrefix}-c-${businessCode}-infra-pipeline`,
        orgId: orgId,
        billingAccount: billingAccount,
        folderId: config.require("common_folder_name"),
        deletionPolicy: config.get("project_deletion_policy") || "PREVENT",
        activateApis: [
            "cloudbuild.googleapis.com",
            "cloudresourcemanager.googleapis.com",
            "iam.googleapis.com",
            "billingbudgets.googleapis.com",
            "artifactregistry.googleapis.com",
        ],
        labels: {
            environment: "common",
            application_name: `${businessCode}-infra-pipeline`,
            billing_code: "1234",
            primary_contact: "example1",
            secondary_contact: "example2",
            business_code: businessCode,
            env_code: "c",
            vpc: "none",
        },
    });

    return {
        app_infra_pipeline_project_id: appInfraProject.projectId,
    };
};

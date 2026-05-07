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

/*************************************************
  Bootstrap GCP Organization.
  Mirrors: 0-bootstrap/ in the terraform-example-foundation.
*************************************************/

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import * as random from "@pulumi/random";
import { loadConfig, BootstrapConfig } from "./config";
import { deployGroups } from "./groups";
import { deployServiceAccounts, GranularSAs } from "./sa";
import { deployGitHubActionsWIF, deployCICDProject } from "./build_github_actions";
import { Bootstrap } from "@vitruviansoftware/foundation-bootstrap";

export = async () => {
    const cfg = loadConfig(new pulumi.Config());

    /*************************************************
      Groups creation (mirrors groups.tf)
    *************************************************/
    const groupOutputs = await deployGroups(cfg);

    /*************************************************
      Bootstrap Folder
    *************************************************/
    const bootstrapFolder = new gcp.organizations.Folder("bootstrap-folder", {
        displayName: `${cfg.folderPrefix}-bootstrap`,
        parent: cfg.parent,
        deletionProtection: cfg.folderDeletionProtection,
    }, { protect: true });

    /*************************************************
      Seed Bootstrap Project (mirrors main.tf module "seed_bootstrap")
    *************************************************/
    const seedBootstrap = new Bootstrap("seed_bootstrap", {
        orgId: cfg.orgId,
        folderId: bootstrapFolder.name,
        billingAccount: cfg.billingAccount,
        projectPrefix: cfg.projectPrefix,
        defaultRegion: cfg.defaultRegion,
        defaultRegionKms: cfg.defaultRegionKms,
        defaultRegionGcs: cfg.defaultRegionGcs,
        randomSuffix: true,
        encryptStateBucket: true,
        bucketForceDestroy: cfg.bucketForceDestroy,
        projectLabels: {
            environment: "bootstrap",
            application_name: "seed-bootstrap",
            billing_code: "1234",
            primary_contact: "example1",
            secondary_contact: "example2",
            business_code: "shared",
            env_code: "b",
            vpc: "none",
        },
        activateApis: [
            "serviceusage.googleapis.com",
            "servicenetworking.googleapis.com",
            "compute.googleapis.com",
            "logging.googleapis.com",
            "bigquery.googleapis.com",
            "cloudresourcemanager.googleapis.com",
            "cloudbilling.googleapis.com",
            "cloudbuild.googleapis.com",
            "iam.googleapis.com",
            "admin.googleapis.com",
            "appengine.googleapis.com",
            "storage-api.googleapis.com",
            "monitoring.googleapis.com",
            "pubsub.googleapis.com",
            "securitycenter.googleapis.com",
            "accesscontextmanager.googleapis.com",
            "billingbudgets.googleapis.com",
            "essentialcontacts.googleapis.com",
            "assuredworkloads.googleapis.com",
            "cloudasset.googleapis.com",
        ],
        bucketPrefix: cfg.bucketPrefix,
        stateBucketIamMembers: [],
    }, { dependsOn: groupOutputs.dependsOn });

    const seedProject = seedBootstrap.seedProject.project;
    const stateBucketKmsKey = seedBootstrap.kmsKeyId as pulumi.Output<string>;

    /*************************************************
      CI/CD Project (mirrors Go's deployCICDProject)
    *************************************************/
    const cicdOutputs = await deployCICDProject(cfg, bootstrapFolder);

    /*************************************************
      Service Accounts and IAM (mirrors sa.tf)
    *************************************************/
    const saOutputs = await deployServiceAccounts(cfg, seedProject, cicdOutputs.cicdProjectId);

    /*************************************************
      Projects state bucket (for 4-projects stage)
    *************************************************/
    const projectsStateBucket = new gcp.storage.Bucket("projects-state-bucket", {
        name: pulumi.interpolate`${cfg.bucketPrefix}-${seedProject.projectId}-gcp-projects-tfstate`,
        project: seedProject.projectId,
        location: cfg.defaultRegionGcs,
        forceDestroy: cfg.bucketForceDestroy,
        uniformBucketLevelAccess: true,
        versioning: { enabled: true },
        encryption: { defaultKmsKeyName: stateBucketKmsKey },
    }, { dependsOn: [seedBootstrap] });

    /*************************************************
      GitHub Actions WIF (mirrors Go's deployGitHubActionsBuild)
    *************************************************/
    const wifOutputs = await deployGitHubActionsWIF(
        cfg,
        cicdOutputs.cicdProjectId,
        seedBootstrap.stateBucketName,
        projectsStateBucket.name,
        saOutputs,
    );

    /*************************************************
      Org admins IAM at org level
    *************************************************/
    const orgAdminsRoles = cfg.orgPolicyAdminRole
        ? [
            "roles/orgpolicy.policyAdmin",
            "roles/resourcemanager.organizationAdmin",
            "roles/billing.user",
            "roles/resourcemanager.tagAdmin",
            "roles/resourcemanager.tagUser",
            "roles/logging.configWriter",
            "roles/securitycenter.notificationConfigEditor",
            "roles/accesscontextmanager.policyAdmin",
            "roles/essentialcontacts.admin"
          ]
        : [
            "roles/resourcemanager.organizationAdmin",
            "roles/billing.user",
            "roles/resourcemanager.tagAdmin",
            "roles/resourcemanager.tagUser",
            "roles/logging.configWriter",
            "roles/securitycenter.notificationConfigEditor",
            "roles/accesscontextmanager.policyAdmin",
            "roles/essentialcontacts.admin"
          ];

    for (const role of orgAdminsRoles) {
        new gcp.organizations.IAMMember(`org-admin-${role.replace(/\//g, "-")}`, {
            orgId: cfg.orgId,
            role: role,
            member: `group:${cfg.groups.requiredGroups.groupOrgAdmins}`,
        });
    }

    /*************************************************
      Outputs — mirrors outputs.tf and outputs_cb.tf
    *************************************************/
    return {
        // outputs.tf
        seed_project_id: seedProject.projectId,
        bootstrap_step_terraform_service_account_email: saOutputs.saEmails["bootstrap"],
        projects_step_terraform_service_account_email: saOutputs.saEmails["proj"],
        networks_step_terraform_service_account_email: saOutputs.saEmails["net"],
        environment_step_terraform_service_account_email: saOutputs.saEmails["env"],
        organization_step_terraform_service_account_email: saOutputs.saEmails["org"],
        gcs_bucket_tfstate: seedBootstrap.stateBucketName,
        projects_gcs_bucket_tfstate: projectsStateBucket.name,
        state_bucket_kms_key_id: stateBucketKmsKey,

        common_config: {
            org_id: cfg.orgId,
            parent_folder: cfg.parentFolder,
            billing_account: cfg.billingAccount,
            default_region: cfg.defaultRegion,
            default_region_2: cfg.defaultRegion2,
            default_region_gcs: cfg.defaultRegionGcs,
            default_region_kms: cfg.defaultRegionKms,
            project_prefix: cfg.projectPrefix,
            folder_prefix: cfg.folderPrefix,
            parent_id: cfg.parent,
            bootstrap_folder_name: bootstrapFolder.name,
        },

        required_groups: cfg.groups.createRequiredGroups
            ? groupOutputs.requiredGroupIds
            : {
                group_org_admins: cfg.groups.requiredGroups.groupOrgAdmins,
                group_billing_admins: cfg.groups.requiredGroups.groupBillingAdmins,
                billing_data_users: cfg.groups.requiredGroups.billingDataUsers,
                audit_data_users: cfg.groups.requiredGroups.auditDataUsers,
            },

        optional_groups: cfg.groups.createOptionalGroups
            ? groupOutputs.optionalGroupIds
            : cfg.groups.optionalGroups,

        cloudbuild_project_id: cicdOutputs.cicdProjectId,
        cloud_build_private_worker_pool_id: cicdOutputs.privateWorkerPoolId,
        wif_pool_name: wifOutputs.wifPoolName,
        wif_provider_name: wifOutputs.wifProviderName,
    };
};

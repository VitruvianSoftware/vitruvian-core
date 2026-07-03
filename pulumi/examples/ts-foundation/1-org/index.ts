/**
 * Copyright 2026 Vitruvian Software
 *
 * 1-org/index.ts — Main entrypoint for the Organization stage.
 * Mirrors: 1-org/envs/shared/ in the terraform-example-foundation.
 *
 * Creates org-level folders, IAM bindings, org policies, centralized logging,
 * SCC notifications, tags, essential contacts, and shared org projects.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import * as random from "@pulumi/random";
import { loadOrgConfig } from "./config";
import { ProjectFactory } from "@vitruviansoftware/foundation-project-factory";
import { OrgPolicyBoolean, OrgPolicyList, DomainRestrictedSharing } from "@vitruviansoftware/foundation-org-policy";
import { CentralizedLogging } from "@vitruviansoftware/foundation-centralized-logging";
import { deployOrgIAM, OrgProjectRefs } from "./iam";
import { deployEssentialContacts } from "./essential_contacts";
import { CAIMonitoring } from "@vitruviansoftware/foundation-cai-monitoring";

export = async () => {
    const cfg = loadOrgConfig(new pulumi.Config());

    // Stack reference to 0-bootstrap for remote state
    const bootstrapStackName = new pulumi.Config().get("bootstrap_stack_ref") || "bootstrap";
    const bootstrapRef = new pulumi.StackReference(bootstrapStackName);
    const commonConfig = bootstrapRef.getOutput("common_config") as pulumi.Output<Record<string, string>>;
    const requiredGroups = bootstrapRef.getOutput("required_groups") as pulumi.Output<Record<string, string>>;
    const optionalGroups = bootstrapRef.getOutput("optional_groups") as pulumi.Output<Record<string, string>>;

    const orgId = commonConfig.apply(c => c.org_id || cfg.orgId);
    const billingAccount = commonConfig.apply(c => c.billing_account || cfg.billingAccount);
    const projectPrefix = commonConfig.apply(c => c.project_prefix || cfg.projectPrefix);
    const folderPrefix = commonConfig.apply(c => c.folder_prefix || cfg.folderPrefix);
    const parent = commonConfig.apply(c => c.parent_id || cfg.parent);
    const bootstrapFolderName = commonConfig.apply(c => c.bootstrap_folder_name);

    /*************************************************
      Folders (mirrors folders.tf)
    *************************************************/
    const commonFolder = new gcp.organizations.Folder("common-folder", {
        displayName: pulumi.interpolate`${folderPrefix}-common`,
        parent: parent,
        deletionProtection: cfg.folderDeletionProtection,
    });

    const networkFolder = new gcp.organizations.Folder("network-folder", {
        displayName: pulumi.interpolate`${folderPrefix}-network`,
        parent: parent,
        deletionProtection: cfg.folderDeletionProtection,
    });



    /*************************************************
      Org Policies (mirrors org_policy.tf)
    *************************************************/
    // Boolean policies — expanded to match Go foundation's full list
    const booleanPolicies: Record<string, boolean> = {
        // Compute Engine hardening
        "compute.disableNestedVirtualization": true,
        "compute.disableSerialPortAccess": true,
        "compute.disableGuestAttributesAccess": true,
        "compute.skipDefaultNetworkCreation": true,
        "compute.restrictXpnProjectLienRemoval": true,
        "compute.disableVpcExternalIpv6": true,
        "compute.setNewProjectDefaultToZonalDNSOnly": true,
        "compute.requireOsLogin": true,
        // Cloud SQL hardening
        "sql.restrictPublicIp": true,
        "sql.restrictAuthorizedNetworks": true,
        // IAM hardening
        "iam.disableServiceAccountKeyCreation": true,
        "iam.automaticIamGrantsForDefaultServiceAccounts": true,
        "iam.disableServiceAccountKeyUpload": true,
        // Storage hardening
        "storage.uniformBucketLevelAccess": true,
        "storage.publicAccessPrevention": true,
    };

    for (const [constraint, enforced] of Object.entries(booleanPolicies)) {
        new OrgPolicyBoolean(`org-policy-${constraint.replace(/\./g, "-")}`, {
            orgId: cfg.orgId,
            folderId: cfg.parentFolder || undefined,
            constraint: constraint,
            enforced: enforced,
        });
    }

    // VM external IP deny all
    new OrgPolicyList("deny-vm-external-ip", {
        orgId: cfg.orgId,
            folderId: cfg.parentFolder || undefined,
        constraint: "compute.vmExternalIpAccess",
        policyType: "deny",
        values: ["all"],
    });

    // Restrict protocol forwarding to internal only (was missing)
    new OrgPolicyList("restrict-protocol-forwarding", {
        orgId: cfg.orgId,
            folderId: cfg.parentFolder || undefined,
        constraint: "compute.restrictProtocolForwardingCreationForTypes",
        policyType: "allow",
        values: ["INTERNAL"],
    });


    // Essential contacts domain restriction (was missing)
    if (cfg.essentialContactsDomainsToAllow.length > 0) {
        new OrgPolicyList("essential-contacts-domain-restriction", {
            orgId: cfg.orgId,
            folderId: cfg.parentFolder || undefined,
            constraint: "essentialcontacts.allowedContactDomains",
            policyType: "allow",
            values: cfg.essentialContactsDomainsToAllow.map(d => d.startsWith("@") ? d : `@${d}`),
        });
    }

    // Cloud Build: restrict to allowed worker pools (mirrors TF org_policy.tf:135-147)
    if (cfg.enforceAllowedWorkerPools && cfg.cloudBuildPrivateWorkerPoolId) {
        new OrgPolicyList("allowed-worker-pools", {
            orgId: cfg.orgId,
            folderId: cfg.parentFolder || undefined,
            constraint: "cloudbuild.allowedWorkerPools",
            policyType: "allow",
            values: [cfg.cloudBuildPrivateWorkerPoolId],
        });
    }

    /*************************************************
      Shared Projects (mirrors projects.tf)
    *************************************************/
    // Org Audit Logs
    const orgAuditLogs = new ProjectFactory("org-audit-logs", {
        name: `${cfg.projectPrefix}-c-logging`,
        orgId: cfg.orgId,
        billingAccount: cfg.billingAccount,
        folderId: commonFolder.name,
        deletionPolicy: cfg.projectDeletionPolicy,
        budgetAmount: cfg.projectBudget.org_audit_logs_budget_amount,
        budgetAlertPubsubTopic: cfg.projectBudget.org_audit_logs_alert_pubsub_topic,
        budgetAlertSpentPercents: cfg.projectBudget.org_audit_logs_alert_spent_percents,
        budgetAlertSpendBasis: cfg.projectBudget.org_audit_logs_budget_alert_spend_basis,
            defaultServiceAccount: "deprivilege",
        activateApis: [
            "logging.googleapis.com", "bigquery.googleapis.com",
            "billingbudgets.googleapis.com",
        ],
        labels: {
            environment: "common",
            application_name: "org-logging",
            billing_code: "1234",
            primary_contact: "example1",
            secondary_contact: "example2",
            business_code: "shared",
            env_code: "c",
            vpc: "none",
        },
    });

    // Org Billing Export
    const orgBillingExport = new ProjectFactory("org-billing-export", {
        name: `${cfg.projectPrefix}-c-billing-export`,
        orgId: cfg.orgId,
        billingAccount: cfg.billingAccount,
        folderId: commonFolder.name,
        deletionPolicy: cfg.projectDeletionPolicy,
        budgetAmount: cfg.projectBudget.org_billing_export_budget_amount,
        budgetAlertPubsubTopic: cfg.projectBudget.org_billing_export_alert_pubsub_topic,
        budgetAlertSpentPercents: cfg.projectBudget.org_billing_export_alert_spent_percents,
        budgetAlertSpendBasis: cfg.projectBudget.org_billing_export_budget_alert_spend_basis,
            defaultServiceAccount: "deprivilege",
        activateApis: [
            "logging.googleapis.com", "bigquery.googleapis.com",
            "billingbudgets.googleapis.com",
        ],
        labels: {
            environment: "common",
            application_name: "org-billing-export",
            billing_code: "1234",
            primary_contact: "example1",
            secondary_contact: "example2",
            business_code: "shared",
            env_code: "c",
            vpc: "none",
        },
    });

    // Common KMS
    const commonKms = new ProjectFactory("common-kms", {
        name: `${cfg.projectPrefix}-c-kms`,
        orgId: cfg.orgId,
        billingAccount: cfg.billingAccount,
        folderId: commonFolder.name,
        deletionPolicy: cfg.projectDeletionPolicy,
        budgetAmount: cfg.projectBudget.common_kms_budget_amount,
        budgetAlertPubsubTopic: cfg.projectBudget.common_kms_alert_pubsub_topic,
        budgetAlertSpentPercents: cfg.projectBudget.common_kms_alert_spent_percents,
        budgetAlertSpendBasis: cfg.projectBudget.common_kms_budget_alert_spend_basis,
            defaultServiceAccount: "deprivilege",
        activateApis: [
            "logging.googleapis.com", "cloudkms.googleapis.com",
            "billingbudgets.googleapis.com",
        ],
        labels: {
            environment: "common",
            application_name: "org-kms",
            billing_code: "1234",
            primary_contact: "example1",
            secondary_contact: "example2",
            business_code: "shared",
            env_code: "c",
            vpc: "none",
        },
    });

    // Org Secrets
    const orgSecrets = new ProjectFactory("org-secrets", {
        name: `${cfg.projectPrefix}-c-secrets`,
        orgId: cfg.orgId,
        billingAccount: cfg.billingAccount,
        folderId: commonFolder.name,
        deletionPolicy: cfg.projectDeletionPolicy,
        budgetAmount: cfg.projectBudget.org_secrets_budget_amount,
        budgetAlertPubsubTopic: cfg.projectBudget.org_secrets_alert_pubsub_topic,
        budgetAlertSpentPercents: cfg.projectBudget.org_secrets_alert_spent_percents,
        budgetAlertSpendBasis: cfg.projectBudget.org_secrets_budget_alert_spend_basis,
            defaultServiceAccount: "deprivilege",
        activateApis: [
            "logging.googleapis.com", "secretmanager.googleapis.com",
            "billingbudgets.googleapis.com",
        ],
        labels: {
            environment: "common",
            application_name: "org-secrets",
            billing_code: "1234",
            primary_contact: "example1",
            secondary_contact: "example2",
            business_code: "shared",
            env_code: "c",
            vpc: "none",
        },
    });

    // Interconnect
    const interconnect = new ProjectFactory("interconnect", {
        name: `${cfg.projectPrefix}-net-interconnect`,
        orgId: cfg.orgId,
        billingAccount: cfg.billingAccount,
        folderId: networkFolder.name,
        deletionPolicy: cfg.projectDeletionPolicy,
        budgetAmount: cfg.projectBudget.interconnect_budget_amount,
        budgetAlertPubsubTopic: cfg.projectBudget.interconnect_alert_pubsub_topic,
        budgetAlertSpentPercents: cfg.projectBudget.interconnect_alert_spent_percents,
        budgetAlertSpendBasis: cfg.projectBudget.interconnect_budget_alert_spend_basis,
            defaultServiceAccount: "deprivilege",
        activateApis: ["billingbudgets.googleapis.com", "compute.googleapis.com"],
        labels: {
            environment: "network",
            application_name: "org-interconnect",
            billing_code: "1234",
            primary_contact: "example1",
            secondary_contact: "example2",
            business_code: "shared",
            env_code: "net",
            vpc: "none",
        },
    });

    // SCC Notifications
    const sccNotifications = new ProjectFactory("scc-notifications", {
        name: `${cfg.projectPrefix}-c-scc`,
        orgId: cfg.orgId,
        billingAccount: cfg.billingAccount,
        folderId: commonFolder.name,
        deletionPolicy: cfg.projectDeletionPolicy,
        budgetAmount: cfg.projectBudget.scc_notifications_budget_amount,
        budgetAlertPubsubTopic: cfg.projectBudget.scc_notifications_alert_pubsub_topic,
        budgetAlertSpentPercents: cfg.projectBudget.scc_notifications_alert_spent_percents,
        budgetAlertSpendBasis: cfg.projectBudget.scc_notifications_budget_alert_spend_basis,
            defaultServiceAccount: "deprivilege",
        activateApis: [
            "logging.googleapis.com", "pubsub.googleapis.com",
            "securitycenter.googleapis.com", "billingbudgets.googleapis.com",
            "cloudkms.googleapis.com",
        ],
        labels: {
            environment: "common",
            application_name: "org-scc",
            billing_code: "1234",
            primary_contact: "example1",
            secondary_contact: "example2",
            business_code: "shared",
            env_code: "c",
            vpc: "none",
        },
    });

    // Network Hub (conditional — hub-and-spoke only)
    let networkHub: ProjectFactory | undefined;
    if (cfg.enableHubAndSpoke) {
        networkHub = new ProjectFactory("network-hub", {
            name: `${cfg.projectPrefix}-net-hub`,
            orgId: cfg.orgId,
            billingAccount: cfg.billingAccount,
            folderId: networkFolder.name,
            deletionPolicy: cfg.projectDeletionPolicy,
            defaultServiceAccount: "deprivilege",
            activateApis: [
                "compute.googleapis.com", "dns.googleapis.com",
                "servicenetworking.googleapis.com", "logging.googleapis.com",
                "cloudresourcemanager.googleapis.com", "billingbudgets.googleapis.com",
            ],
            labels: {
                environment: "network",
                application_name: "org-net-hub",
                billing_code: "1234",
                primary_contact: "example1",
                secondary_contact: "example2",
                business_code: "shared",
                env_code: "net",
                vpc: "svpc",
            },
        });
    }

    // Per-environment network projects
    const environments: Record<string, string> = {
        development: "d",
        nonproduction: "n",
        production: "p",
    };

    const environmentNetworkProjects: Record<string, ProjectFactory> = {};
    for (const [env, envCode] of Object.entries(environments)) {
        environmentNetworkProjects[env] = new ProjectFactory(`env-network-${env}`, {
            name: `${cfg.projectPrefix}-${envCode}-svpc`,
            orgId: cfg.orgId,
            billingAccount: cfg.billingAccount,
            folderId: networkFolder.name,
            deletionPolicy: cfg.projectDeletionPolicy,
            budgetAmount: cfg.projectBudget.shared_network_budget_amount,
            budgetAlertPubsubTopic: cfg.projectBudget.shared_network_alert_pubsub_topic,
            budgetAlertSpentPercents: cfg.projectBudget.shared_network_alert_spent_percents,
            budgetAlertSpendBasis: cfg.projectBudget.shared_network_budget_alert_spend_basis,
            defaultServiceAccount: "deprivilege",
            activateApis: [
                "compute.googleapis.com", "dns.googleapis.com",
                "servicenetworking.googleapis.com", "container.googleapis.com",
                "logging.googleapis.com", "cloudresourcemanager.googleapis.com",
                "accesscontextmanager.googleapis.com", "billingbudgets.googleapis.com",
            ],
            labels: {
                environment: env,
                application_name: "shared-vpc-host",
                billing_code: "1234",
                primary_contact: "example1",
                secondary_contact: "example2",
                business_code: "shared",
                env_code: envCode,
            },
        });
    }

    /*************************************************
      Centralized Logging (mirrors log_sinks.tf)
    *************************************************/
    const logFilter = `logName: /logs/cloudaudit.googleapis.com%2Factivity OR
logName: /logs/cloudaudit.googleapis.com%2Fsystem_event OR
logName: /logs/cloudaudit.googleapis.com%2Fdata_access OR
logName: /logs/cloudaudit.googleapis.com%2Faccess_transparency OR
logName: /logs/cloudaudit.googleapis.com%2Fpolicy OR
logName: /logs/compute.googleapis.com%2Fvpc_flows OR
logName: /logs/compute.googleapis.com%2Ffirewall OR
logName: /logs/dns.googleapis.com%2Fdns_queries`;

    const centralizedLogging = new CentralizedLogging("org-logging", {
        projectId: orgAuditLogs.projectId,
        orgId: cfg.orgId,
        billingAccount: cfg.enableBillingAccountSink ? cfg.billingAccount : undefined,
        loggingBucketOptions: {
            name: "LogBucket",
            loggingSinkName: "sk-c-logging-logbkt",
            loggingSinkFilter: logFilter,
        },
        bigqueryOptions: {
            datasetName: "audit_logs",
            loggingSinkName: "sk-c-logging-bq",
            loggingSinkFilter: logFilter,
        },
        storageOptions: {
            bucketName: `${cfg.projectPrefix}-c-logging-bucket`,
            loggingSinkName: "sk-c-logging-bkt",
            loggingSinkFilter: logFilter,
            forceDestroy: cfg.logExportStorageForceDestroy,
            versioning: cfg.logExportStorageVersioning,
            location: cfg.logExportStorageLocation,
            retentionPolicy: cfg.logExportStorageRetentionPolicy,
        },
        pubsubOptions: {
            topicName: "tp-c-logging",
            loggingSinkName: "sk-c-logging-pub",
            loggingSinkFilter: logFilter,
        },
    }, { dependsOn: [orgAuditLogs] });

    // Domain restricted sharing
    // Gap 3 fix: this policy must wait for log sinks to finish deploying.
    // The upstream TF uses time_sleep "wait_logs_export" with create_duration = 30s
    // and depends_on = [module.logs_export]. In Pulumi we use explicit dependsOn
    // on the centralizedLogging resource to establish the ordering guarantee.
    // Placed AFTER logging to avoid forward-reference issues in JS/TS.
    if (cfg.domainsToAllow.length > 0) {
        new DomainRestrictedSharing("domain-restricted-sharing", {
            orgId: cfg.orgId,
            folderId: cfg.parentFolder || undefined,
            domainsToAllow: cfg.domainsToAllow,
        }, { dependsOn: [centralizedLogging] });
    }

    /*************************************************
      SCC Notification (mirrors scc_notification.tf)
      Gated behind enable_scc_resources — SCC must be
      activated (Standard or Premium tier) before
      these resources can be created.
    *************************************************/
    if (cfg.enableSccResources) {
        const sccTopic = new gcp.pubsub.Topic("scc-notification-topic", {
            project: sccNotifications.projectId,
            name: `top-scc-notification`,
        }, { dependsOn: [sccNotifications] });

        new gcp.pubsub.Subscription("scc-notification-subscription", {
            project: sccNotifications.projectId,
            name: `sub-scc-notification`,
            topic: sccTopic.name,
        }, { dependsOn: [sccNotifications] });

        // Uses the SCC v2 API to match upstream Terraform's
        // google_scc_v2_organization_notification_config resource.
        new gcp.securitycenter.V2OrganizationNotificationConfig("scc-notification", {
            configId: cfg.sccNotificationName,
            organization: cfg.orgId,
            location: "global",
            description: "SCC Notification for all active findings",
            pubsubTopic: sccTopic.id,
            streamingConfig: {
                filter: cfg.sccNotificationFilter,
            },
        }, { dependsOn: [sccNotifications] });
    }

    // When createUniqueTagKey is true, append a random suffix to avoid
    // tag key name collisions across orgs (mirrors TF's random_string.tag_key_suffix).
    let tagKeyShortName = "environment";
    let tagKeySuffix: random.RandomString | undefined;
    if (cfg.createUniqueTagKey) {
        tagKeySuffix = new random.RandomString("tag-key-suffix", {
            length: 8,
            special: false,
            upper: false,
        });
        tagKeyShortName = pulumi.interpolate`environment-${tagKeySuffix.result}` as any;
    }
    const tagKey = new gcp.tags.TagKey("environment-tag-key", {
        parent: `organizations/${cfg.orgId}`,
        shortName: tagKeyShortName,
        description: "Environment tag key for the foundation.",
    });

    const tagValues: Record<string, gcp.tags.TagValue> = {};
    for (const env of ["bootstrap", "development", "nonproduction", "production"]) {
        tagValues[env] = new gcp.tags.TagValue(`tag-value-${env}`, {
            parent: tagKey.id,
            shortName: env,
            description: `${env} environment tag value`,
        });
    }

    // Tag bindings to folders (was missing — TF binds tags to common, network, bootstrap folders)
    new gcp.tags.TagBinding("common-folder-tag", {
        parent: pulumi.interpolate`//cloudresourcemanager.googleapis.com/${commonFolder.name}`,
        tagValue: tagValues["production"].id,
    });

    new gcp.tags.TagBinding("network-folder-tag", {
        parent: pulumi.interpolate`//cloudresourcemanager.googleapis.com/${networkFolder.name}`,
        tagValue: tagValues["production"].id,
    });

    if (bootstrapFolderName) {
        new gcp.tags.TagBinding("bootstrap-folder-tag", {
            parent: pulumi.interpolate`//cloudresourcemanager.googleapis.com/${bootstrapFolderName}`,
            tagValue: tagValues["bootstrap"].id,
        });
    }

    /*************************************************
      Essential Contacts (was missing)
    *************************************************/
    deployEssentialContacts(cfg);

    /*************************************************
      IAM Bindings (was missing — 20+ resources)
    *************************************************/
    const orgProjectRefs: OrgProjectRefs = {
        auditLogsProjectId: orgAuditLogs.projectId,
        billingExportProjectId: orgBillingExport.projectId,
        orgSecretsProjectId: orgSecrets.projectId,
        orgKmsProjectId: commonKms.projectId,
        sccProjectId: sccNotifications.projectId,
        netHubProjectId: networkHub?.projectId,
    };
    deployOrgIAM(cfg, orgProjectRefs);

    /*************************************************
      CAI Monitoring (was missing — mirrors cai_monitoring.go)
    *************************************************/
    let caiMonitoring: CAIMonitoring | undefined;
    if (cfg.enableCaiMonitoring) {
        const builderSAEmail = pulumi.interpolate`projects/${sccNotifications.projectId}/serviceAccounts/cai-monitoring-builder@${sccNotifications.projectId}.iam.gserviceaccount.com`;

        caiMonitoring = new CAIMonitoring("cai-monitoring", {
            orgId: cfg.orgId,
            projectId: sccNotifications.projectId,
            location: cfg.defaultRegion,
            buildServiceAccount: builderSAEmail,
            functionSourcePath: "./cai-monitoring-function",
            rolesToMonitor: [
                "roles/owner",
                "roles/editor",
                "roles/resourcemanager.organizationAdmin",
                "roles/iam.serviceAccountTokenCreator",
            ],
        }, { dependsOn: [sccNotifications] });
    }

    /*************************************************
      Access Context Manager Policy (mirrors org_policy.tf)
    *************************************************/
    let accessContextManagerPolicyId: pulumi.Output<string> | undefined;
    if (cfg.createAccessContextManagerAccessPolicy) {
        const accessPolicy = new gcp.accesscontextmanager.AccessPolicy("access-policy", {
            parent: `organizations/${cfg.orgId}`,
            title: "default policy",
        });
        // We get the name which is accessPolicies/123456789 or similar
        // The upstream outputs exactly the numeric ID but sometimes the name.
        // Let's output the full name or ID depending on upstream usage.
        // TF `google_access_context_manager_access_policy` id is the name.
        accessContextManagerPolicyId = accessPolicy.name;
    }

    /*************************************************
      Billing Export Dataset
    *************************************************/
    new gcp.bigquery.Dataset("billing-export-dataset", {
        project: orgBillingExport.projectId,
        datasetId: "billing_data",
        friendlyName: "GCP Billing Data",
        location: cfg.billingExportDatasetLocation ?? "US",
    }, { dependsOn: [orgBillingExport] });

    /*************************************************
      Outputs (mirrors outputs.tf)
    *************************************************/
    return {
        org_id: cfg.orgId,
        access_context_manager_policy_id: accessContextManagerPolicyId,
        scc_notification_name: cfg.sccNotificationName,
        parent_resource_id: cfg.parentId,
        parent_resource_type: cfg.parentType,
        common_folder_name: commonFolder.name,
        common_folder_id: commonFolder.id,
        network_folder_name: networkFolder.name,
        network_folder_id: networkFolder.id,
        org_audit_logs_project_id: orgAuditLogs.projectId,
        org_billing_export_project_id: orgBillingExport.projectId,
        org_secrets_project_id: orgSecrets.projectId,
        common_kms_project_id: commonKms.projectId,
        interconnect_project_id: interconnect.projectId,
        interconnect_project_number: interconnect.projectNumber,
        scc_notifications_project_id: sccNotifications.projectId,
        net_hub_project_id: networkHub?.projectId,
        net_hub_project_number: networkHub?.projectNumber,
        domains_to_allow: cfg.domainsToAllow,
        shared_vpc_projects: Object.fromEntries(
            Object.entries(environmentNetworkProjects).map(([k, v]) => [k, { project_id: v.projectId, project_number: v.projectNumber }])
        ),
        tags: {
            key_id: tagKey.id,
            values: Object.fromEntries(Object.entries(tagValues).map(([k, v]) => [k, v.id])),
        },
        // Centralized Logging exports (mirrors Go foundation + TF outputs.tf)
        logs_export_storage_bucket_name: centralizedLogging.storageBucketName,
        logs_export_pubsub_topic: centralizedLogging.pubsubTopicName,
        logs_export_project_logbucket_name: centralizedLogging.logBucketName,
        logs_export_project_linked_dataset_name: centralizedLogging.linkedDatasetName,
        // CAI Monitoring exports (mirrors Go foundation + TF outputs.tf)
        cai_monitoring_artifact_registry: caiMonitoring?.artifactRegistryName,
        cai_monitoring_asset_feed: caiMonitoring?.assetFeedName,
        cai_monitoring_bucket: caiMonitoring?.bucketName,
        cai_monitoring_topic: caiMonitoring?.topicName,
        // Billing sink names — dynamically resolved from centralized logging
        // Mirrors TF: module.logs_export.billing_sink_names
        billing_sink_names: centralizedLogging.billingSinkNames,
    };
};

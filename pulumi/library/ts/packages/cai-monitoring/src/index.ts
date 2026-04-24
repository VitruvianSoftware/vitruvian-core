/**
 * CAI Monitoring Module
 * Mirrors: pulumi-library/go/pkg/security/cai_monitoring.go
 * Upstream: terraform-example-foundation/1-org/modules/cai-monitoring
 *
 * Deploys a Cloud Asset Inventory monitoring pipeline that watches for
 * privileged IAM role grants across an organization and reports violations
 * as Security Command Center findings.
 *
 * Pipeline flow:
 *   1. Cloud Asset Organization Feed watches for IAM_POLICY changes
 *   2. Changes are published to a Pub/Sub topic
 *   3. A Cloud Function v2 is triggered by the Pub/Sub messages
 *   4. The function checks for grants of monitored privileged roles
 *   5. Violations are reported as SCC findings via a custom SCC Source
 *
 * Resources created:
 *   - Service account for the Cloud Function (cai-monitoring)
 *   - Org-level IAM: roles/securitycenter.findingsEditor
 *   - Project-level IAM: pubsub.publisher, eventarc.eventReceiver, run.invoker
 *   - Service identities for cloudfunctions, artifactregistry, pubsub
 *   - Artifact Registry repository for function container image
 *   - Cloud Storage bucket + object for function source code
 *   - Pub/Sub topic for CAI feed events
 *   - Cloud Asset Organization Feed (IAM_POLICY content type)
 *   - SCC v2 Organization Source for findings
 *   - Cloud Function v2 (Node.js 20) triggered by Pub/Sub
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

/**
 * Default set of IAM roles that trigger SCC findings when granted to any
 * principal. Matches upstream Terraform module's roles_to_monitor default.
 */
export const DEFAULT_ROLES_TO_MONITOR: string[] = [
    "roles/owner",
    "roles/editor",
    "roles/resourcemanager.organizationAdmin",
    "roles/compute.networkAdmin",
    "roles/compute.orgFirewallPolicyAdmin",
];

export interface CAIMonitoringArgs {
    /** GCP Organization ID to monitor. Required. */
    orgId: pulumi.Input<string>;
    /** GCP project where monitoring resources are created. Required. */
    projectId: pulumi.Input<string>;
    /** GCP region for Cloud Function and Artifact Registry. Defaults to "us-central1". */
    location?: string;
    /**
     * Fully-qualified name of the SA used by Cloud Build to build the function container.
     * Format: "projects/<project>/serviceAccounts/<email>". Required.
     */
    buildServiceAccount: pulumi.Input<string>;
    /**
     * Local filesystem path to the Cloud Function source directory (index.js, package.json).
     * The directory is archived and uploaded to Cloud Storage. Required.
     */
    functionSourcePath: string;
    /** IAM roles that trigger SCC findings. Defaults to DEFAULT_ROLES_TO_MONITOR. */
    rolesToMonitor?: string[];
    /** KMS key resource name for CMEK encryption. Leave empty to skip CMEK. */
    encryptionKey?: string;
    /** Labels applied to supporting resources. */
    labels?: Record<string, string>;
}

export class CAIMonitoring extends pulumi.ComponentResource {
    public readonly artifactRegistryName: pulumi.Output<string>;
    public readonly bucketName: pulumi.Output<string>;
    public readonly assetFeedName: pulumi.Output<string>;
    public readonly topicName: pulumi.Output<string>;
    public readonly sccSourceName: pulumi.Output<string>;

    constructor(name: string, args: CAIMonitoringArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:CAIMonitoring", name, args, opts);

        // Apply defaults
        const location = args.location || "us-central1";
        const rolesToMonitor = args.rolesToMonitor && args.rolesToMonitor.length > 0
            ? args.rolesToMonitor
            : DEFAULT_ROLES_TO_MONITOR;

        // ====================================================================
        // 1. Cloud Function Service Account
        // Mirrors: google_service_account "cloudfunction" in iam.tf
        // ====================================================================
        const caiSA = new gcp.serviceaccount.Account(`${name}-sa`, {
            project: args.projectId,
            accountId: "cai-monitoring",
            description: "Service account for CAI monitoring Cloud Function",
            createIgnoreAlreadyExists: true,
        }, { parent: this });

        const caiSAMember = pulumi.interpolate`serviceAccount:${caiSA.email}`;

        // Org-level: SCC findings editor
        const findingsEditorIAM = new gcp.organizations.IAMMember(`${name}-sa-findings-editor`, {
            orgId: args.orgId,
            role: "roles/securitycenter.findingsEditor",
            member: caiSAMember,
        }, { parent: this });

        // Project-level: roles for Pub/Sub, Eventarc, and Cloud Run
        const iamDeps: pulumi.Resource[] = [findingsEditorIAM];
        const cfRoles = [
            "roles/pubsub.publisher",
            "roles/eventarc.eventReceiver",
            "roles/run.invoker",
        ];
        for (const role of cfRoles) {
            const iam = new gcp.projects.IAMMember(`${name}-sa-${role.split("/")[1]}`, {
                project: args.projectId,
                role,
                member: caiSAMember,
            }, { parent: this });
            iamDeps.push(iam);
        }

        // ====================================================================
        // 2. Service Identities
        // Mirrors: google_project_service_identity "service_sa" for_each
        // ====================================================================
        const caiServices = [
            "cloudfunctions.googleapis.com",
            "artifactregistry.googleapis.com",
            "pubsub.googleapis.com",
        ];
        for (const svc of caiServices) {
            new gcp.projects.ServiceIdentity(`${name}-identity-${svc.split(".")[0]}`, {
                project: args.projectId,
                service: svc,
            }, { parent: this });
        }

        // ====================================================================
        // 3. Artifact Registry Repository
        // Mirrors: google_artifact_registry_repository "cloudfunction"
        // ====================================================================
        const arRepo = new gcp.artifactregistry.Repository(`${name}-ar`, {
            project: args.projectId,
            location,
            repositoryId: "ar-cai-monitoring",
            description: "Container images for the CAI monitoring Cloud Function",
            format: "DOCKER",
            kmsKeyName: args.encryptionKey || undefined,
        }, { parent: this, dependsOn: iamDeps });

        // ====================================================================
        // 4. Cloud Storage Bucket + Source Code Upload
        // Mirrors: module "cloudfunction_source_bucket" + google_storage_bucket_object
        // ====================================================================
        const sourceBucket = new gcp.storage.Bucket(`${name}-source-bucket`, {
            project: args.projectId,
            name: pulumi.interpolate`bkt-cai-monitoring-sources-${args.projectId}`,
            location,
            forceDestroy: true,
            uniformBucketLevelAccess: true,
        }, { parent: this, dependsOn: iamDeps });

        const sourceObject = new gcp.storage.BucketObject(`${name}-source-zip`, {
            bucket: sourceBucket.name,
            name: "cai-monitoring-function.zip",
            source: new pulumi.asset.FileArchive(args.functionSourcePath),
        }, { parent: this });

        // ====================================================================
        // 5. Pub/Sub Topic + Cloud Asset Organization Feed
        // Mirrors: module "pubsub_cai_feed" + google_cloud_asset_organization_feed
        // ====================================================================
        const caiTopic = new gcp.pubsub.Topic(`${name}-topic`, {
            project: args.projectId,
            name: "top-cai-monitoring-event",
        }, { parent: this, dependsOn: iamDeps });

        const caiFeed = new gcp.cloudasset.OrganizationFeed(`${name}-org-feed`, {
            feedId: "fd-cai-monitoring",
            billingProject: args.projectId,
            orgId: args.orgId,
            contentType: "IAM_POLICY",
            assetTypes: [".*"],
            feedOutputConfig: {
                pubsubDestination: {
                    topic: caiTopic.id,
                },
            },
        }, { parent: this });

        // ====================================================================
        // 6. SCC v2 Organization Source
        // Mirrors: google_scc_v2_organization_source "cai_monitoring"
        // ====================================================================
        const sccSource = new gcp.securitycenter.V2OrganizationSource(`${name}-scc-source`, {
            organization: args.orgId,
            displayName: "CAI Monitoring",
            description: "SCC Finding Source for caiMonitoring Cloud Functions.",
        }, { parent: this });

        // ====================================================================
        // 7. Cloud Function v2
        // Mirrors: module "cloud_function" (GoogleCloudPlatform/cloud-functions)
        // ====================================================================
        const rolesEnvVar = rolesToMonitor.join(",");

        new gcp.cloudfunctionsv2.Function(`${name}-function`, {
            project: args.projectId,
            location,
            name: "caiMonitoring",
            description: "Check on the Organization for members (users, groups and service accounts) that contains the IAM roles listed.",
            buildConfig: {
                runtime: "nodejs20",
                entryPoint: "caiMonitoring",
                source: {
                    storageSource: {
                        bucket: sourceBucket.name,
                        object: sourceObject.name,
                    },
                },
                dockerRepository: arRepo.id,
                serviceAccount: args.buildServiceAccount,
            },
            serviceConfig: {
                serviceAccountEmail: caiSA.email,
                environmentVariables: {
                    ROLES: rolesEnvVar,
                    SOURCE_ID: sccSource.name,
                },
            },
            eventTrigger: {
                triggerRegion: location,
                eventType: "google.cloud.pubsub.topic.v1.messagePublished",
                pubsubTopic: caiTopic.id,
                retryPolicy: "RETRY_POLICY_RETRY",
                serviceAccountEmail: caiSA.email,
            },
        }, { parent: this, dependsOn: iamDeps });

        // Wire outputs
        this.artifactRegistryName = arRepo.name;
        this.bucketName = sourceBucket.name;
        this.assetFeedName = caiFeed.name;
        this.topicName = caiTopic.name;
        this.sccSourceName = sccSource.name;

        this.registerOutputs({
            artifactRegistryName: this.artifactRegistryName,
            bucketName: this.bucketName,
            assetFeedName: this.assetFeedName,
            topicName: this.topicName,
            sccSourceName: this.sccSourceName,
        });
    }
}

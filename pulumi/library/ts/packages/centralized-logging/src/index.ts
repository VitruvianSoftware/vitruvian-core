/**
 * Centralized Logging Module
 * Mirrors: 1-org/modules/centralized-logging
 * Configures org-level log sinks to BigQuery, Storage, Pub/Sub, and Logging buckets.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface LoggingBucketOptions {
    name?: string | null;
    loggingSinkName?: string | null;
    loggingSinkFilter?: string;
    retentionDays?: number;
    location?: string;
    enableAnalytics?: boolean;
    linkedDatasetId?: string | null;
}

export interface BigQueryOptions {
    datasetName?: string | null;
    loggingSinkName?: string | null;
    loggingSinkFilter?: string;
    description?: string;
    deleteContentsOnDestroy?: boolean;
    location?: string;
}

export interface StorageOptions {
    bucketName?: pulumi.Input<string> | null;
    loggingSinkName?: string | null;
    loggingSinkFilter?: string;
    forceDestroy?: boolean;
    location?: string;
    versioning?: boolean;
    retentionPolicy?: {
        isLocked?: boolean;
        retentionPeriodDays?: number;
    };
}

export interface PubsubOptions {
    topicName?: string | null;
    loggingSinkName?: string | null;
    loggingSinkFilter?: string;
    createSubscriber?: boolean;
}

export interface CentralizedLoggingArgs {
    projectId: pulumi.Input<string>;
    orgId: string;
    folderId?: string;
    billingAccount?: string;
    loggingBucketOptions?: LoggingBucketOptions | null;
    bigqueryOptions?: BigQueryOptions | null;
    storageOptions?: StorageOptions | null;
    pubsubOptions?: PubsubOptions | null;
}

export class CentralizedLogging extends pulumi.ComponentResource {
    public readonly waitIamMembership!: pulumi.Output<boolean>;
    public readonly storageBucketName: pulumi.Output<string>;
    public readonly pubsubTopicName: pulumi.Output<string>;
    public readonly logBucketName: pulumi.Output<string>;
    public readonly linkedDatasetName: pulumi.Output<string>;
    /** Billing sink names by destination key — mirrors TF billing_sink_names output */
    public readonly billingSinkNames: Record<string, pulumi.Output<string>>;

    private createSink(
        name: string,
        args: {
            orgId: string;
            folderId?: string;
            sinkName: string;
            destination: pulumi.Input<string>;
            filter: string;
        },
        parent: pulumi.Resource
    ): gcp.logging.OrganizationSink | gcp.logging.FolderSink {
        if (args.folderId) {
            return new gcp.logging.FolderSink(name, {
                folder: args.folderId,
                name: args.sinkName,
                destination: args.destination,
                filter: args.filter,
                includeChildren: true,
            }, { parent });
        } else {
            return new gcp.logging.OrganizationSink(name, {
                orgId: args.orgId,
                name: args.sinkName,
                destination: args.destination,
                filter: args.filter,
                includeChildren: true,
            }, { parent });
        }
    }

    constructor(name: string, args: CentralizedLoggingArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:CentralizedLogging", name, args, opts);

        const iamDependencies: pulumi.CustomResource[] = [];
        const billingSinkNames: Record<string, pulumi.Output<string>> = {};
        let _storageBucketName: pulumi.Output<string> = pulumi.output("");
        let _pubsubTopicName: pulumi.Output<string> = pulumi.output("");
        let _logBucketName: pulumi.Output<string> = pulumi.output("");
        let _linkedDatasetName: pulumi.Output<string> = pulumi.output("");

        // Logging bucket sink
        if (args.loggingBucketOptions?.name) {
            const bucket = new gcp.logging.ProjectBucketConfig(`${name}-log-bucket`, {
                project: args.projectId,
                location: args.loggingBucketOptions.location ?? "global",
                bucketId: args.loggingBucketOptions.name,
                retentionDays: args.loggingBucketOptions.retentionDays ?? 365,
                enableAnalytics: args.loggingBucketOptions.enableAnalytics,
            }, { parent: this });

            if (args.loggingBucketOptions.linkedDatasetId) {
                const linkedDataset = new gcp.logging.LinkedDataset(`${name}-linked-dataset`, {
                    parent: pulumi.interpolate`projects/${args.projectId}`,
                    location: args.loggingBucketOptions.location ?? "global",
                    bucket: bucket.bucketId,
                    linkId: args.loggingBucketOptions.linkedDatasetId,
                }, { parent: bucket });
                this.linkedDatasetName = linkedDataset.name;
            }

            const sink = this.createSink(`${name}-log-bucket-sink`, {
                orgId: args.orgId,
                folderId: args.folderId,
                sinkName: args.loggingBucketOptions.loggingSinkName ?? `sk-c-logging-${args.loggingBucketOptions.name}`,
                destination: pulumi.interpolate`logging.googleapis.com/projects/${args.projectId}/locations/${args.loggingBucketOptions.location ?? "global"}/buckets/${bucket.bucketId}`,
                filter: args.loggingBucketOptions.loggingSinkFilter ?? "",
            }, this);

            const iam = new gcp.projects.IAMMember(`${name}-log-bucket-iam`, {
                project: args.projectId,
                role: "roles/logging.bucketWriter",
                member: sink.writerIdentity,
            }, { parent: this });
            iamDependencies.push(iam);
            _logBucketName = bucket.bucketId;

            // Billing account sink → log bucket (mirrors Go/TF billing sinks)
            if (args.billingAccount) {
                const billSinkName = `${args.loggingBucketOptions.loggingSinkName ?? `sk-c-logging-${args.loggingBucketOptions.name}`}-billing`;
                const billSink = new gcp.logging.BillingAccountSink(`${name}-log-bucket-billing-sink`, {
                    name: billSinkName,
                    billingAccount: args.billingAccount,
                    destination: pulumi.interpolate`logging.googleapis.com/projects/${args.projectId}/locations/${args.loggingBucketOptions.location ?? "global"}/buckets/${bucket.bucketId}`,
                }, { parent: this });
                const billIam = new gcp.projects.IAMMember(`${name}-log-bucket-billing-iam`, {
                    project: args.projectId,
                    role: "roles/logging.bucketWriter",
                    member: billSink.writerIdentity,
                }, { parent: this });
                iamDependencies.push(billIam);
                billingSinkNames["logbucket"] = pulumi.output(billSinkName);
            }

        }

        // BigQuery sink
        if (args.bigqueryOptions?.datasetName) {
            const dataset = new gcp.bigquery.Dataset(`${name}-bq-dataset`, {
                project: args.projectId,
                datasetId: args.bigqueryOptions.datasetName,
                friendlyName: args.bigqueryOptions.datasetName,
                description: args.bigqueryOptions.description ?? "Log export dataset",
                location: args.bigqueryOptions.location ?? "US",
                deleteContentsOnDestroy: args.bigqueryOptions.deleteContentsOnDestroy ?? false,
            }, { parent: this });

            const sink = this.createSink(`${name}-bq-sink`, {
                orgId: args.orgId,
                folderId: args.folderId,
                sinkName: args.bigqueryOptions.loggingSinkName ?? `sk-c-logging-bq-${args.bigqueryOptions.datasetName}`,
                destination: pulumi.interpolate`bigquery.googleapis.com/projects/${args.projectId}/datasets/${dataset.datasetId}`,
                filter: args.bigqueryOptions.loggingSinkFilter ?? "",
            }, this);

            const iam = new gcp.bigquery.DatasetIamMember(`${name}-bq-iam`, {
                project: args.projectId,
                datasetId: dataset.datasetId,
                role: "roles/bigquery.dataEditor",
                member: sink.writerIdentity,
            }, { parent: this });
            iamDependencies.push(iam);
            _linkedDatasetName = dataset.datasetId;
        }

        // Cloud Storage sink
        if (args.storageOptions?.bucketName) {
            const bucket = new gcp.storage.Bucket(`${name}-storage-bucket`, {
                project: args.projectId,
                name: args.storageOptions.bucketName,
                location: args.storageOptions.location ?? "US",
                forceDestroy: args.storageOptions.forceDestroy ?? false,
                uniformBucketLevelAccess: true,
                versioning: {
                    enabled: args.storageOptions.versioning ?? false,
                },
                retentionPolicy: args.storageOptions.retentionPolicy ? {
                    isLocked: args.storageOptions.retentionPolicy.isLocked ?? false,
                    retentionPeriod: (args.storageOptions.retentionPolicy.retentionPeriodDays ?? 365) * 86400,
                } : undefined,
            }, { parent: this });

            const sink = this.createSink(`${name}-storage-sink`, {
                orgId: args.orgId,
                folderId: args.folderId,
                sinkName: args.storageOptions.loggingSinkName ?? `sk-c-logging-bkt-${args.storageOptions.bucketName}`,
                destination: pulumi.interpolate`storage.googleapis.com/${bucket.name}`,
                filter: args.storageOptions.loggingSinkFilter ?? "",
            }, this);

            const iam = new gcp.storage.BucketIAMMember(`${name}-storage-iam`, {
                bucket: bucket.name,
                role: "roles/storage.objectCreator",
                member: sink.writerIdentity,
            }, { parent: this });
            iamDependencies.push(iam);
            _storageBucketName = bucket.name;

            // Billing account sink → storage (mirrors Go/TF billing sinks)
            if (args.billingAccount) {
                const billSinkName = `${args.storageOptions.loggingSinkName ?? "sk-c-logging-bkt"}-billing`;
                const billSink = new gcp.logging.BillingAccountSink(`${name}-storage-billing-sink`, {
                    name: billSinkName,
                    billingAccount: args.billingAccount,
                    destination: pulumi.interpolate`storage.googleapis.com/${bucket.name}`,
                }, { parent: this });
                new gcp.storage.BucketIAMMember(`${name}-storage-billing-iam`, {
                    bucket: bucket.name,
                    role: "roles/storage.objectCreator",
                    member: billSink.writerIdentity,
                }, { parent: this });
                billingSinkNames["storage"] = pulumi.output(billSinkName);
            }
        }

        // Pub/Sub sink
        if (args.pubsubOptions?.topicName) {
            const topic = new gcp.pubsub.Topic(`${name}-pubsub-topic`, {
                project: args.projectId,
                name: args.pubsubOptions.topicName,
            }, { parent: this });

            const sink = this.createSink(`${name}-pubsub-sink`, {
                orgId: args.orgId,
                folderId: args.folderId,
                sinkName: args.pubsubOptions.loggingSinkName ?? `sk-c-logging-pub-${args.pubsubOptions.topicName}`,
                destination: pulumi.interpolate`pubsub.googleapis.com/projects/${args.projectId}/topics/${topic.name}`,
                filter: args.pubsubOptions.loggingSinkFilter ?? "",
            }, this);

            const iam = new gcp.pubsub.TopicIAMMember(`${name}-pubsub-iam`, {
                project: args.projectId,
                topic: topic.name,
                role: "roles/pubsub.publisher",
                member: sink.writerIdentity,
            }, { parent: this });
            iamDependencies.push(iam);
            _pubsubTopicName = topic.name;

            if (args.pubsubOptions.createSubscriber !== false) {
                new gcp.pubsub.Subscription(`${name}-pubsub-sub`, {
                    project: args.projectId,
                    name: `${args.pubsubOptions.topicName}-sub`,
                    topic: topic.name,
                }, { parent: this });
            }

            // Billing account sink → pubsub (mirrors Go/TF billing sinks)
            if (args.billingAccount) {
                const billSinkName = `${args.pubsubOptions.loggingSinkName ?? "sk-c-logging-pub"}-billing`;
                const billSink = new gcp.logging.BillingAccountSink(`${name}-pubsub-billing-sink`, {
                    name: billSinkName,
                    billingAccount: args.billingAccount,
                    destination: pulumi.interpolate`pubsub.googleapis.com/projects/${args.projectId}/topics/${topic.name}`,
                }, { parent: this });
                new gcp.pubsub.TopicIAMMember(`${name}-pubsub-billing-iam`, {
                    project: args.projectId,
                    topic: topic.name,
                    role: "roles/pubsub.publisher",
                    member: billSink.writerIdentity,
                }, { parent: this });
                billingSinkNames["pubsub"] = pulumi.output(billSinkName);
            }
        }

        // Output an explicit dependency property that resolves when all IAM memberships are ready.
        // This mirrors TF's `time_sleep.wait_sa_iam_membership` logic.
        this.waitIamMembership = pulumi.all(iamDependencies.map(iam => iam.id)).apply(() => true);
        this.storageBucketName = _storageBucketName;
        this.pubsubTopicName = _pubsubTopicName;
        this.logBucketName = _logBucketName;
        this.linkedDatasetName = _linkedDatasetName;
        this.billingSinkNames = billingSinkNames;

        this.registerOutputs({
            waitIamMembership: this.waitIamMembership,
            storageBucketName: this.storageBucketName,
            pubsubTopicName: this.pubsubTopicName,
            logBucketName: this.logBucketName,
            linkedDatasetName: this.linkedDatasetName,
            billingSinkNames: this.billingSinkNames,
        });
    }
}

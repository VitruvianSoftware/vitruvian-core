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
    bucketName?: string | null;
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
    billingAccount?: string;
    loggingBucketOptions?: LoggingBucketOptions | null;
    bigqueryOptions?: BigQueryOptions | null;
    storageOptions?: StorageOptions | null;
    pubsubOptions?: PubsubOptions | null;
}

export class CentralizedLogging extends pulumi.ComponentResource {
    constructor(name: string, args: CentralizedLoggingArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:CentralizedLogging", name, args, opts);

        // Logging bucket sink
        if (args.loggingBucketOptions?.name) {
            const bucket = new gcp.logging.ProjectBucketConfig(`${name}-log-bucket`, {
                project: args.projectId,
                location: args.loggingBucketOptions.location ?? "global",
                bucketId: args.loggingBucketOptions.name,
                retentionDays: args.loggingBucketOptions.retentionDays ?? 365,
            }, { parent: this });

            new gcp.logging.OrganizationSink(`${name}-log-bucket-sink`, {
                orgId: args.orgId,
                name: args.loggingBucketOptions.loggingSinkName ?? `sk-c-logging-${args.loggingBucketOptions.name}`,
                destination: pulumi.interpolate`logging.googleapis.com/projects/${args.projectId}/locations/${args.loggingBucketOptions.location ?? "global"}/buckets/${bucket.bucketId}`,
                filter: args.loggingBucketOptions.loggingSinkFilter ?? "",
                includeChildren: true,
            }, { parent: this });
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

            new gcp.logging.OrganizationSink(`${name}-bq-sink`, {
                orgId: args.orgId,
                name: args.bigqueryOptions.loggingSinkName ?? `sk-c-logging-bq-${args.bigqueryOptions.datasetName}`,
                destination: pulumi.interpolate`bigquery.googleapis.com/projects/${args.projectId}/datasets/${dataset.datasetId}`,
                filter: args.bigqueryOptions.loggingSinkFilter ?? "",
                includeChildren: true,
                bigqueryOptions: {
                    usePartitionedTables: true,
                },
            }, { parent: this });
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

            new gcp.logging.OrganizationSink(`${name}-storage-sink`, {
                orgId: args.orgId,
                name: args.storageOptions.loggingSinkName ?? `sk-c-logging-bkt-${args.storageOptions.bucketName}`,
                destination: pulumi.interpolate`storage.googleapis.com/${bucket.name}`,
                filter: args.storageOptions.loggingSinkFilter ?? "",
                includeChildren: true,
            }, { parent: this });
        }

        // Pub/Sub sink
        if (args.pubsubOptions?.topicName) {
            const topic = new gcp.pubsub.Topic(`${name}-pubsub-topic`, {
                project: args.projectId,
                name: args.pubsubOptions.topicName,
            }, { parent: this });

            new gcp.logging.OrganizationSink(`${name}-pubsub-sink`, {
                orgId: args.orgId,
                name: args.pubsubOptions.loggingSinkName ?? `sk-c-logging-pub-${args.pubsubOptions.topicName}`,
                destination: pulumi.interpolate`pubsub.googleapis.com/projects/${args.projectId}/topics/${topic.name}`,
                filter: args.pubsubOptions.loggingSinkFilter ?? "",
                includeChildren: true,
            }, { parent: this });

            if (args.pubsubOptions.createSubscriber !== false) {
                new gcp.pubsub.Subscription(`${name}-pubsub-sub`, {
                    project: args.projectId,
                    name: `${args.pubsubOptions.topicName}-sub`,
                    topic: topic.name,
                }, { parent: this });
            }
        }

        this.registerOutputs({});
    }
}

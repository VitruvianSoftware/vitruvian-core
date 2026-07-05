/**
 * Cloud Storage Module
 * Creates GCS buckets with full lifecycle, versioning, encryption, and retention support.
 * Mirrors: terraform-google-modules/cloud-storage/google
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface LifecycleRule {
    action: { type: string; storageClass?: string };
    condition: { age?: number; withState?: string; createdBefore?: string };
}

export interface CloudStorageArgs {
    name: pulumi.Input<string>;
    projectId: pulumi.Input<string>;
    location: string;
    storageClass?: string;
    forceDestroy?: boolean;
    uniformBucketLevelAccess?: boolean;
    versioning?: boolean;
    encryption?: { defaultKmsKeyName: pulumi.Input<string> };
    labels?: Record<string, string>;
    lifecycleRules?: LifecycleRule[];
    retentionPolicy?: { isLocked?: boolean; retentionPeriod: number };
    logging?: { logBucket: pulumi.Input<string>; logObjectPrefix?: string };
}

export class CloudStorage extends pulumi.ComponentResource {
    public readonly bucket: gcp.storage.Bucket;
    public readonly bucketName: pulumi.Output<string>;
    public readonly bucketSelfLink: pulumi.Output<string>;

    constructor(name: string, args: CloudStorageArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:CloudStorage", name, args, opts);

        this.bucket = new gcp.storage.Bucket(`${name}-bucket`, {
            name: args.name,
            project: args.projectId,
            location: args.location,
            forceDestroy: args.forceDestroy ?? false,
            storageClass: args.storageClass ?? "STANDARD",
            uniformBucketLevelAccess: args.uniformBucketLevelAccess ?? true,
            versioning: { enabled: args.versioning ?? true },
            encryption: args.encryption ? { defaultKmsKeyName: args.encryption.defaultKmsKeyName } : undefined,
            labels: args.labels,
            lifecycleRules: args.lifecycleRules?.map(rule => ({ action: rule.action, condition: rule.condition })),
            retentionPolicy: args.retentionPolicy ? {
                isLocked: args.retentionPolicy.isLocked ?? false,
                retentionPeriod: args.retentionPolicy.retentionPeriod,
            } : undefined,
            logging: args.logging ? {
                logBucket: args.logging.logBucket,
                logObjectPrefix: args.logging.logObjectPrefix,
            } : undefined,
        }, { parent: this });

        this.bucketName = this.bucket.name;
        this.bucketSelfLink = this.bucket.selfLink;

        this.registerOutputs({
            bucketName: this.bucketName,
            bucketSelfLink: this.bucketSelfLink,
        });
    }
}

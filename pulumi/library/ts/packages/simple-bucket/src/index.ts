/**
 * Simple Bucket Module
 * Mirrors: terraform-google-modules/cloud-storage/google//modules/simple_bucket
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface SimpleBucketArgs {
    name: pulumi.Input<string>;
    projectId: pulumi.Input<string>;
    location: string;
    forceDestroy?: boolean;
    storageClass?: string;
    versioning?: boolean;
    encryption?: {
        defaultKmsKeyName: pulumi.Input<string>;
    };
    labels?: Record<string, string>;
    uniformBucketLevelAccess?: boolean;
    lifecycleRules?: {
        action: { type: string; storageClass?: string };
        condition: { age?: number; withState?: string };
    }[];
    retentionPolicy?: {
        isLocked?: boolean;
        retentionPeriod: number;
    };
}

export class SimpleBucket extends pulumi.ComponentResource {
    public readonly bucket: gcp.storage.Bucket;
    public readonly bucketName: pulumi.Output<string>;
    public readonly bucketSelfLink: pulumi.Output<string>;

    constructor(name: string, args: SimpleBucketArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:SimpleBucket", name, args, opts);

        this.bucket = new gcp.storage.Bucket(`${name}-bucket`, {
            name: args.name,
            project: args.projectId,
            location: args.location,
            forceDestroy: args.forceDestroy ?? false,
            storageClass: args.storageClass ?? "STANDARD",
            uniformBucketLevelAccess: args.uniformBucketLevelAccess ?? true,
            versioning: {
                enabled: args.versioning ?? true,
            },
            encryption: args.encryption ? {
                defaultKmsKeyName: args.encryption.defaultKmsKeyName,
            } : undefined,
            labels: args.labels,
            lifecycleRules: args.lifecycleRules?.map(rule => ({
                action: rule.action,
                condition: rule.condition,
            })),
            retentionPolicy: args.retentionPolicy ? {
                isLocked: args.retentionPolicy.isLocked ?? false,
                retentionPeriod: args.retentionPolicy.retentionPeriod,
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

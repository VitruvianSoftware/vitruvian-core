/**
 * Cloud Functions Module
 * Creates Cloud Functions v2 with event trigger support.
 * Mirrors: terraform-google-modules/event-function/google
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface CloudFunctionArgs {
    projectId: pulumi.Input<string>;
    region: string;
    name: string;
    description?: string;
    runtime?: string;
    entryPoint: string;
    sourceBucket: pulumi.Input<string>;
    sourceObject: pulumi.Input<string>;
    eventTriggerType?: string;
    eventTriggerResource?: pulumi.Input<string>;
    serviceAccountEmail?: pulumi.Input<string>;
    availableMemory?: string;
    timeout?: number;
    labels?: Record<string, string>;
}

export class CloudFunction extends pulumi.ComponentResource {
    public readonly functionResource: gcp.cloudfunctionsv2.Function;

    constructor(name: string, args: CloudFunctionArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:CloudFunction", name, args, opts);

        const fnArgs: gcp.cloudfunctionsv2.FunctionArgs = {
            project: args.projectId,
            location: args.region,
            name: args.name,
            description: args.description,
            labels: args.labels,
            buildConfig: {
                runtime: args.runtime || "python310",
                entryPoint: args.entryPoint,
                source: {
                    storageSource: {
                        bucket: args.sourceBucket,
                        object: args.sourceObject,
                    },
                },
            },
            serviceConfig: {
                availableMemory: args.availableMemory || "256M",
                timeoutSeconds: args.timeout || 60,
                serviceAccountEmail: args.serviceAccountEmail,
            },
        };

        if (args.eventTriggerType) {
            fnArgs.eventTrigger = {
                eventType: args.eventTriggerType,
                triggerRegion: args.region,
            };
        }

        this.functionResource = new gcp.cloudfunctionsv2.Function(name, fnArgs, { parent: this });
        this.registerOutputs({ functionName: this.functionResource.name });
    }
}

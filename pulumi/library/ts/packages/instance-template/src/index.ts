/**
 * Instance Template Module
 * Mirrors: terraform-google-modules/vm/google//modules/instance_template
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface InstanceTemplateArgs {
    projectId: pulumi.Input<string>;
    namePrefix: string;
    machineType: string;
    region: string;
    sourceImage?: string;
    sourceImageFamily?: string;
    sourceImageProject?: string;
    diskSizeGb?: number;
    diskType?: string;
    subnetwork: pulumi.Input<string>;
    subnetworkProject?: pulumi.Input<string>;
    serviceAccount?: {
        email: pulumi.Input<string>;
        scopes: string[];
    };
    enableConfidentialVm?: boolean;
    metadata?: Record<string, string>;
    tags?: string[];
    labels?: Record<string, string>;
}

export class InstanceTemplate extends pulumi.ComponentResource {
    public readonly templateSelfLink: pulumi.Output<string>;
    public readonly template: gcp.compute.InstanceTemplate;

    constructor(name: string, args: InstanceTemplateArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:InstanceTemplate", name, args, opts);

        this.template = new gcp.compute.InstanceTemplate(`${name}-template`, {
            project: args.projectId,
            namePrefix: args.namePrefix,
            machineType: args.machineType,
            region: args.region,
            tags: args.tags,
            labels: args.labels,
            metadata: args.metadata,
            disks: [{
                sourceImage: args.sourceImage ?? `projects/${args.sourceImageProject ?? "debian-cloud"}/global/images/family/${args.sourceImageFamily ?? "debian-12"}`,
                diskSizeGb: args.diskSizeGb ?? 100,
                diskType: args.diskType ?? "pd-ssd",
                autoDelete: true,
                boot: true,
            }],
            networkInterfaces: [{
                subnetwork: args.subnetwork,
                subnetworkProject: args.subnetworkProject,
            }],
            serviceAccount: args.serviceAccount ? {
                email: args.serviceAccount.email,
                scopes: args.serviceAccount.scopes,
            } : undefined,
            confidentialInstanceConfig: args.enableConfidentialVm ? {
                enableConfidentialCompute: true,
            } : undefined,
            shieldedInstanceConfig: {
                enableSecureBoot: true,
                enableVtpm: true,
                enableIntegrityMonitoring: true,
            },
        }, { parent: this });

        this.templateSelfLink = this.template.selfLinkUnique;

        this.registerOutputs({
            templateSelfLink: this.templateSelfLink,
        });
    }
}

/**
 * Compute Instance Module
 * Mirrors: terraform-google-modules/vm/google//modules/compute_instance
 */

export interface ComputeInstanceArgs {
    projectId: pulumi.Input<string>;
    zone: string;
    instanceName: string;
    instanceTemplate: pulumi.Input<string>;
    subnetwork: pulumi.Input<string>;
    subnetworkProject?: pulumi.Input<string>;
    hostname?: string;
    numInstances?: number;
    resourceManagerTags?: pulumi.Input<{ [key: string]: pulumi.Input<string> }>;
}

export class ComputeInstance extends pulumi.ComponentResource {
    public readonly instances: gcp.compute.InstanceFromTemplate[];

    constructor(name: string, args: ComputeInstanceArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:ComputeInstance", name, args, opts);

        const numInstances = args.numInstances ?? 1;
        this.instances = [];

        for (let i = 0; i < numInstances; i++) {
            const instanceSuffix = numInstances > 1 ? `-${i}` : "";
            const instance = new gcp.compute.InstanceFromTemplate(`${name}-instance${instanceSuffix}`, {
                name: `${args.instanceName}${instanceSuffix}`,
                project: args.projectId,
                zone: args.zone,
                sourceInstanceTemplate: args.instanceTemplate,
                networkInterfaces: [{
                    subnetwork: args.subnetwork,
                    subnetworkProject: args.subnetworkProject,
                }],
                params: args.resourceManagerTags ? {
                    resourceManagerTags: args.resourceManagerTags,
                } : undefined,
            }, { parent: this });
            this.instances.push(instance);
        }

        this.registerOutputs({});
    }
}

/**
 * Compute Instance Module
 * Creates compute instances from an instance template.
 * Mirrors: terraform-google-modules/vm/google//modules/compute_instance
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface ComputeInstanceArgs {
    project: pulumi.Input<string>;
    zone: string;
    hostname: string;
    instanceTemplate: pulumi.Input<string>;
    numInstances?: number;
    deletionProtection?: boolean;
}

export class ComputeInstance extends pulumi.ComponentResource {
    public readonly instances: gcp.compute.InstanceFromTemplate[] = [];

    constructor(name: string, args: ComputeInstanceArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:ComputeInstance", name, args, opts);

        const count = args.numInstances || 1;
        for (let i = 0; i < count; i++) {
            const hostname = count > 1 ? `${args.hostname}-${i}` : args.hostname;
            const inst = new gcp.compute.InstanceFromTemplate(`${name}-${i}`, {
                project: args.project,
                zone: args.zone,
                name: hostname,
                sourceInstanceTemplate: args.instanceTemplate,
                deletionProtection: args.deletionProtection ?? false,
            }, { parent: this });
            this.instances.push(inst);
        }

        this.registerOutputs({});
    }
}

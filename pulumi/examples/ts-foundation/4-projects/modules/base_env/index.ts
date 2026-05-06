import * as pulumi from "@pulumi/pulumi";

export interface BaseEnvArgs {
    env: string;
    envCode: string;
    orgId: string;
    billingAccount: string;
    folderId: string;
    projectPrefix: string;
    businessCode: string;
}

export class BaseEnv extends pulumi.ComponentResource {
    constructor(name: string, args: BaseEnvArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:BaseEnv", name, args, opts);
        
        // This module wires up the environment logic for 4-projects
        // It should orchestrate single_project, peering, etc.
        
        this.registerOutputs({});
    }
}

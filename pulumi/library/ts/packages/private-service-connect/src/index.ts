/**
 * Private Service Connect Module
 * Mirrors: terraform-google-modules/network/google//modules/private-service-connect
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface PrivateServiceConnectArgs {
    projectId: pulumi.Input<string>;
    networkSelfLink: pulumi.Input<string>;
    address: string;
    forwardingRuleName: string;
    subnetworkName?: string;
    subnetworkIpCidrRange?: string;
    region?: string;
}

export class PrivateServiceConnect extends pulumi.ComponentResource {
    constructor(name: string, args: PrivateServiceConnectArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:PrivateServiceConnect", name, args, opts);

        const addr = new gcp.compute.GlobalAddress(`${name}-psc-addr`, {
            name: `${args.forwardingRuleName}-addr`,
            project: args.projectId,
            addressType: "INTERNAL",
            purpose: "PRIVATE_SERVICE_CONNECT",
            address: args.address,
            network: args.networkSelfLink,
        }, { parent: this });

        new gcp.compute.GlobalForwardingRule(`${name}-psc-fwd-rule`, {
            name: args.forwardingRuleName,
            project: args.projectId,
            network: args.networkSelfLink,
            ipAddress: addr.id,
            target: "all-apis",
            loadBalancingScheme: "",
        }, { parent: this });

        this.registerOutputs({});
    }
}

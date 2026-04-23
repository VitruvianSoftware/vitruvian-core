/**
 * Network Peering Module
 * Mirrors: terraform-google-modules/network/google//modules/network-peering
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface NetworkPeeringArgs {
    localNetwork: pulumi.Input<string>;
    peerNetwork: pulumi.Input<string>;
    exportCustomRoutes?: boolean;
    importCustomRoutes?: boolean;
    exportSubnetRoutesWithPublicIp?: boolean;
    importSubnetRoutesWithPublicIp?: boolean;
    prefix?: string;
}

export class NetworkPeering extends pulumi.ComponentResource {
    public readonly localPeering: gcp.compute.NetworkPeering;
    public readonly peerPeering: gcp.compute.NetworkPeering;

    constructor(name: string, args: NetworkPeeringArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:NetworkPeering", name, args, opts);

        const prefix = args.prefix ?? name;

        this.localPeering = new gcp.compute.NetworkPeering(`${name}-local`, {
            name: `${prefix}-local`,
            network: args.localNetwork,
            peerNetwork: args.peerNetwork,
            exportCustomRoutes: args.exportCustomRoutes ?? false,
            importCustomRoutes: args.importCustomRoutes ?? false,
            exportSubnetRoutesWithPublicIp: args.exportSubnetRoutesWithPublicIp ?? true,
            importSubnetRoutesWithPublicIp: args.importSubnetRoutesWithPublicIp ?? false,
        }, { parent: this });

        this.peerPeering = new gcp.compute.NetworkPeering(`${name}-peer`, {
            name: `${prefix}-peer`,
            network: args.peerNetwork,
            peerNetwork: args.localNetwork,
            exportCustomRoutes: args.importCustomRoutes ?? false,
            importCustomRoutes: args.exportCustomRoutes ?? false,
            exportSubnetRoutesWithPublicIp: args.importSubnetRoutesWithPublicIp ?? false,
            importSubnetRoutesWithPublicIp: args.exportSubnetRoutesWithPublicIp ?? true,
        }, { parent: this, dependsOn: [this.localPeering] });

        this.registerOutputs({});
    }
}

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface CloudRouterArgs {
    project: pulumi.Input<string>;
    name: string;
    network: pulumi.Input<string>;
    region: string;
    bgp?: {
        asn: number;
        advertisedGroups?: string[];
        advertisedIpRanges?: { range: string }[];
    };
}

export class CloudRouter extends pulumi.ComponentResource {
    public readonly router: gcp.compute.Router;

    constructor(name: string, args: CloudRouterArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:CloudRouter", name, args, opts);

        this.router = new gcp.compute.Router(args.name, {
            project: args.project,
            name: args.name,
            network: args.network,
            region: args.region,
            bgp: args.bgp ? {
                asn: args.bgp.asn,
                advertiseMode: args.bgp.advertisedGroups || args.bgp.advertisedIpRanges ? "CUSTOM" : "DEFAULT",
                advertisedGroups: args.bgp.advertisedGroups,
                advertisedIpRanges: args.bgp.advertisedIpRanges?.map(r => ({ range: r.range })),
            } : undefined,
        }, { parent: this });

        this.registerOutputs({
            router: this.router,
        });
    }
}

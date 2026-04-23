/**
 * DNS Hub Module
 * Creates DNS zones, policies, and peering for the hub network.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface DnsHubArgs {
    projectId: pulumi.Input<string>;
    networkSelfLink: pulumi.Input<string>;
    bgpDomain?: string;
    /** Target name server IPs for on-prem forwarding. */
    targetNameServerAddresses?: { ipv4Address: string; forwardingPath?: string }[];
}

export class DnsHub extends pulumi.ComponentResource {
    constructor(name: string, args: DnsHubArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:DnsHub", name, args, opts);

        // Enable DNS inbound policy
        new gcp.dns.Policy(`${name}-dns-policy`, {
            project: args.projectId,
            name: `dp-dns-hub-default-policy`,
            enableInboundForwarding: true,
            enableLogging: true,
            networks: [{
                networkUrl: args.networkSelfLink,
            }],
        }, { parent: this });

        // Private Google APIs zone
        new gcp.dns.ManagedZone(`${name}-private-googleapis`, {
            project: args.projectId,
            name: "dz-dns-hub-googleapis",
            dnsName: "googleapis.com.",
            description: "Private Google APIs zone",
            visibility: "private",
            privateVisibilityConfig: {
                networks: [{
                    networkUrl: args.networkSelfLink,
                }],
            },
        }, { parent: this });

        // GCR.io zone
        new gcp.dns.ManagedZone(`${name}-private-gcr`, {
            project: args.projectId,
            name: "dz-dns-hub-gcr",
            dnsName: "gcr.io.",
            description: "Private GCR zone",
            visibility: "private",
            privateVisibilityConfig: {
                networks: [{
                    networkUrl: args.networkSelfLink,
                }],
            },
        }, { parent: this });

        // pkg.dev zone
        new gcp.dns.ManagedZone(`${name}-private-pkg-dev`, {
            project: args.projectId,
            name: "dz-dns-hub-pkg-dev",
            dnsName: "pkg.dev.",
            description: "Private Artifact Registry zone",
            visibility: "private",
            privateVisibilityConfig: {
                networks: [{
                    networkUrl: args.networkSelfLink,
                }],
            },
        }, { parent: this });

        this.registerOutputs({});
    }
}

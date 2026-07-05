/**
 * Cloud DNS Module
 * Creates DNS managed zones with support for private, peering, forwarding, and public zone types.
 * Mirrors: terraform-google-modules/cloud-dns/google
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface RecordSet {
    name: string;
    type: string;
    ttl?: number;
    records: string[];
}

export interface CloudDnsArgs {
    projectId: pulumi.Input<string>;
    name: string;
    domain: string;
    description?: string;
    /** Zone type: "private", "peering", "forwarding", "public", "reverse_lookup" */
    type: string;
    networkSelfLink?: pulumi.Input<string>;
    targetNetworkSelfLink?: pulumi.Input<string>;
    targetNameServerAddresses?: string[];
    forwardingPath?: string;
    recordsets?: RecordSet[];
    enableDnssec?: boolean;
    labels?: Record<string, string>;
}

export class CloudDns extends pulumi.ComponentResource {
    public readonly zone: gcp.dns.ManagedZone;

    constructor(name: string, args: CloudDnsArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:CloudDns", name, args, opts);

        const desc = args.description || "Managed DNS zone";
        const zoneArgs: gcp.dns.ManagedZoneArgs = {
            project: args.projectId,
            name: args.name,
            dnsName: args.domain,
            description: desc,
            labels: args.labels,
        };

        const privateVis = args.networkSelfLink ? {
            networks: [{ networkUrl: args.networkSelfLink }],
        } : undefined;

        switch (args.type) {
            case "private":
                zoneArgs.visibility = "private";
                zoneArgs.privateVisibilityConfig = privateVis;
                break;
            case "forwarding":
                zoneArgs.visibility = "private";
                zoneArgs.privateVisibilityConfig = privateVis;
                zoneArgs.forwardingConfig = {
                    targetNameServers: (args.targetNameServerAddresses || []).map(ip => ({
                        ipv4Address: ip,
                        forwardingPath: args.forwardingPath,
                    })),
                };
                break;
            case "peering":
                zoneArgs.visibility = "private";
                zoneArgs.privateVisibilityConfig = privateVis;
                zoneArgs.peeringConfig = {
                    targetNetwork: { networkUrl: args.targetNetworkSelfLink! },
                };
                break;
            case "public":
                zoneArgs.visibility = "public";
                break;
            case "reverse_lookup":
                zoneArgs.visibility = "private";
                zoneArgs.privateVisibilityConfig = privateVis;
                zoneArgs.reverseLookup = true;
                break;
        }

        if (args.enableDnssec) {
            zoneArgs.dnssecConfig = { state: "on" };
        }

        this.zone = new gcp.dns.ManagedZone(`${name}-zone`, zoneArgs, { parent: this });

        if (args.recordsets) {
            for (let i = 0; i < args.recordsets.length; i++) {
                const rs = args.recordsets[i];
                const recordName = rs.name === "" ? args.domain : `${rs.name}.${args.domain}`;
                new gcp.dns.RecordSet(`${name}-rs-${i}`, {
                    project: args.projectId,
                    name: recordName,
                    managedZone: this.zone.name,
                    type: rs.type,
                    ttl: rs.ttl || 300,
                    rrdatas: rs.records,
                }, { parent: this.zone });
            }
        }

        this.registerOutputs({ zoneName: this.zone.name });
    }
}

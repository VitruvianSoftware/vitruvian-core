/**
 * Network Module
 * Mirrors: terraform-google-modules/network/google
 * Creates a VPC network with subnets, secondary ranges, and routing config.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface SubnetConfig {
    subnetName: string;
    subnetIp: string;
    subnetRegion: string;
    subnetPrivateAccess?: boolean;
    subnetFlowLogs?: boolean;
    subnetFlowLogsInterval?: string;
    subnetFlowLogsSampling?: number;
    subnetFlowLogsMetadata?: string;
    subnetFlowLogsMetadataFields?: string[];
    subnetFlowLogsFilter?: string;
    description?: string;
    secondaryRanges?: {
        rangeName: string;
        ipCidrRange: string;
    }[];
    role?: string;
    purpose?: string;
}

export interface NetworkArgs {
    projectId: pulumi.Input<string>;
    networkName: string;
    /** Whether to delete default internet gateway routes. */
    deleteDefaultInternetGatewayRoutes?: boolean;
    /** Subnets to create. */
    subnets: SubnetConfig[];
    /** Secondary ranges keyed by subnet name. */
    secondaryRanges?: Record<string, { rangeName: string; ipCidrRange: string }[]>;
    /** Routing mode: "GLOBAL" or "REGIONAL". */
    routingMode?: string;
    /** Description for the network. */
    description?: string;
    /** Shared VPC host project config. */
    sharedVpcHost?: boolean;
    /** MTU of the network. */
    mtu?: number;
}

export class Network extends pulumi.ComponentResource {
    public readonly networkName: pulumi.Output<string>;
    public readonly networkSelfLink: pulumi.Output<string>;
    public readonly networkId: pulumi.Output<string>;
    public readonly subnets: Record<string, gcp.compute.Subnetwork>;
    public readonly network: gcp.compute.Network;

    constructor(name: string, args: NetworkArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:Network", name, args, opts);

        this.network = new gcp.compute.Network(`${name}-network`, {
            name: args.networkName,
            project: args.projectId,
            autoCreateSubnetworks: false,
            routingMode: args.routingMode ?? "GLOBAL",
            deleteDefaultRoutesOnCreate: args.deleteDefaultInternetGatewayRoutes ?? false,
            description: args.description,
            mtu: args.mtu,
        }, { parent: this });

        this.networkName = this.network.name;
        this.networkSelfLink = this.network.selfLink;
        this.networkId = this.network.id;

        // Create subnets
        this.subnets = {};
        for (const subnet of args.subnets) {
            const subnetResource = new gcp.compute.Subnetwork(`${name}-${subnet.subnetName}`, {
                name: subnet.subnetName,
                project: args.projectId,
                network: this.network.id,
                ipCidrRange: subnet.subnetIp,
                region: subnet.subnetRegion,
                privateIpGoogleAccess: subnet.subnetPrivateAccess ?? false,
                description: subnet.description,
                purpose: subnet.purpose,
                role: subnet.role,
                logConfig: subnet.subnetFlowLogs ? {
                    aggregationInterval: subnet.subnetFlowLogsInterval ?? "INTERVAL_5_SEC",
                    flowSampling: subnet.subnetFlowLogsSampling ?? 0.5,
                    metadata: subnet.subnetFlowLogsMetadata ?? "INCLUDE_ALL_METADATA",
                    metadataFields: subnet.subnetFlowLogsMetadataFields,
                    filterExpr: subnet.subnetFlowLogsFilter ?? "true",
                } : undefined,
                secondaryIpRanges: subnet.secondaryRanges?.map(r => ({
                    rangeName: r.rangeName,
                    ipCidrRange: r.ipCidrRange,
                })),
            }, { parent: this });
            this.subnets[subnet.subnetName] = subnetResource;
        }

        // Shared VPC host
        if (args.sharedVpcHost) {
            new gcp.compute.SharedVPCHostProject(`${name}-svpc-host`, {
                project: args.projectId,
            }, { parent: this, dependsOn: [this.network] });
        }

        this.registerOutputs({
            networkName: this.networkName,
            networkSelfLink: this.networkSelfLink,
            networkId: this.networkId,
        });
    }
}

/**
 * Firewall Rules Module
 * Mirrors: terraform-google-modules/network/google//modules/firewall-rules
 */
export interface FirewallRuleConfig {
    name: string;
    description?: string;
    direction: "INGRESS" | "EGRESS";
    priority?: number;
    ranges?: string[];
    sourceTags?: string[] | null;
    sourceServiceAccounts?: string[] | null;
    targetTags?: string[] | null;
    targetServiceAccounts?: string[] | null;
    allow?: { protocol: string; ports?: string[] | null }[];
    deny?: { protocol: string; ports?: string[] | null }[];
    logConfig?: { metadata: string };
}

export interface FirewallRulesArgs {
    projectId: pulumi.Input<string>;
    networkName: pulumi.Input<string>;
    rules: FirewallRuleConfig[];
}

export class FirewallRules extends pulumi.ComponentResource {
    constructor(name: string, args: FirewallRulesArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:FirewallRules", name, args, opts);

        for (const rule of args.rules) {
            new gcp.compute.Firewall(`${name}-${rule.name}`, {
                name: rule.name,
                project: args.projectId,
                network: args.networkName,
                description: rule.description,
                direction: rule.direction,
                priority: rule.priority,
                sourceRanges: rule.direction === "INGRESS" ? rule.ranges : undefined,
                destinationRanges: rule.direction === "EGRESS" ? rule.ranges : undefined,
                sourceTags: rule.sourceTags ?? undefined,
                targetTags: rule.targetTags ?? undefined,
                allows: rule.allow?.map(a => ({
                    protocol: a.protocol,
                    ports: a.ports ?? undefined,
                })),
                denies: rule.deny?.map(d => ({
                    protocol: d.protocol,
                    ports: d.ports ?? undefined,
                })),
                logConfig: rule.logConfig ? {
                    metadata: rule.logConfig.metadata,
                } : undefined,
            }, { parent: this });
        }

        this.registerOutputs({});
    }
}

/**
 * Copyright 2026 Vitruvian Software
 *
 * Shared VPC Module — creates the VPC network, subnets, firewall rules,
 * DNS zones, NAT, Private Service Connect, and optional VPC peering.
 * Mirrors: 3-networks-(hub-and-spoke|svpc)/modules/shared_vpc/
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { Network, SubnetConfig } from "@vitruviansoftware/foundation-network";
import { PrivateServiceConnect } from "@vitruviansoftware/foundation-private-service-connect";

export interface SharedVpcArgs {
    projectId: pulumi.Input<string>;
    projectNumber?: pulumi.Input<string>;
    environmentCode: string;
    orgId: string;
    parent: string;
    defaultRegion: string;
    defaultRegion2: string;
    /** "hub", "spoke", or null for SVPC mode */
    mode?: "hub" | "spoke" | null;
    subnets: SubnetConfig[];
    secondaryRanges?: Record<string, { rangeName: string; ipCidrRange: string }[]>;
    natEnabled?: boolean;
    windowsActivationEnabled?: boolean;
    /** Enable conditional allow-all for VPC internal traffic (TF: enable_all_vpc_internal_traffic) */
    enableAllVpcInternalTraffic?: boolean;
    /** Enable firewall logging (default: true) */
    firewallEnableLogging?: boolean;
    dnsEnableInboundForwarding?: boolean;
    dnsEnableLogging?: boolean;
    pscAddress: string;
    /** For spoke mode: hub project ID */
    netHubProjectId?: string;
    /** For spoke mode: hub network self-link */
    netHubNetworkSelfLink?: pulumi.Input<string>;
}

/**
 * Firewall rule definition matching the Go library's FirewallRule struct
 * and the upstream TF module's rule variable type.
 */
interface PolicyFirewallRule {
    priority: number;
    direction: "INGRESS" | "EGRESS";
    action: "allow" | "deny";
    ruleName: string;
    description: string;
    enableLogging: boolean;
    match: {
        srcIpRanges?: string[];
        destIpRanges?: string[];
        layer4Configs: { ipProtocol: string; ports?: string[] }[];
    };
    targetSecureTags?: pulumi.Input<string>[];
}

/**
 * Builds the standard foundation firewall rules matching the Go library's
 * BuildFoundationRules() — the upstream TF firewall.tf rule set.
 */
function buildFoundationRules(
    envCode: string,
    enableLogging: boolean,
    restrictedApiCidr: string,
    subnetIPs: string[],
    enableInternal: boolean,
): PolicyFirewallRule[] {
    const rules: PolicyFirewallRule[] = [
        {
            priority: 65530,
            direction: "EGRESS",
            action: "deny",
            ruleName: `fw-${envCode}-svpc-65530-e-d-all-all-all`,
            description: "Lower priority rule to deny all egress traffic.",
            enableLogging,
            match: {
                destIpRanges: ["0.0.0.0/0"],
                layer4Configs: [{ ipProtocol: "all" }],
            },
        },
        {
            priority: 1000,
            direction: "EGRESS",
            action: "allow",
            ruleName: `fw-${envCode}-svpc-1000-e-a-allow-google-apis-all-tcp-443`,
            description: "Lower priority rule to allow restricted google apis on TCP port 443.",
            enableLogging,
            match: {
                destIpRanges: [restrictedApiCidr],
                layer4Configs: [{ ipProtocol: "tcp", ports: ["443"] }],
            },
        },
    ];

    if (enableInternal) {
        rules.push({
            priority: 10000,
            direction: "EGRESS",
            action: "allow",
            ruleName: `fw-${envCode}-svpc-10000-e-a-all-all-all`,
            description: "Allow all egress to the provided IP range.",
            enableLogging,
            match: {
                destIpRanges: subnetIPs,
                layer4Configs: [{ ipProtocol: "all" }],
            },
        });
        rules.push({
            priority: 10001,
            direction: "INGRESS",
            action: "allow",
            ruleName: `fw-${envCode}-svpc-10001-i-a-all`,
            description: "Allow all ingress to the provided IP range.",
            enableLogging,
            match: {
                srcIpRanges: subnetIPs,
                layer4Configs: [{ ipProtocol: "all" }],
            },
        });
    }

    return rules;
}

export class SharedVpc extends pulumi.ComponentResource {
    public readonly networkName: pulumi.Output<string>;
    public readonly networkSelfLink: pulumi.Output<string>;
    public readonly networkId: pulumi.Output<string>;
    public readonly network: Network;
    public readonly subnetsNames: pulumi.Output<string[]>;
    public readonly subnetsIps: pulumi.Output<string[]>;
    public readonly subnetsSelfLinks: pulumi.Output<string[]>;
    public readonly subnetsSecondaryRanges: pulumi.Output<Record<string, {rangeName: string; ipCidrRange: string}[]>>;
    public readonly dnsPolicy: pulumi.Output<string>;

    constructor(name: string, args: SharedVpcArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:SharedVpc", name, args, opts);

        const modeStr = args.mode === "hub" ? "-hub" : args.mode === "spoke" ? "-spoke" : "";
        const vpcName = `${args.environmentCode}-svpc${modeStr}`;
        const networkName = `vpc-${vpcName}`;
        const enableLogging = args.firewallEnableLogging ?? true;

        // Create VPC network
        this.network = new Network(`${name}-vpc`, {
            projectId: args.projectId,
            networkName: networkName,
            deleteDefaultInternetGatewayRoutes: true,
            sharedVpcHost: true,
            subnets: args.subnets,
            secondaryRanges: args.secondaryRanges,
        }, { parent: this });

        // Windows activation route (mirrors TF windows_activation_enabled)
        if (args.windowsActivationEnabled) {
            new gcp.compute.Route(`${name}-windows-kms-route`, {
                name: `rt-${vpcName}-1000-all-default-windows-kms`,
                project: args.projectId,
                network: this.network.networkId,
                destRange: "35.190.247.13/32",
                nextHopGateway: "default-internet-gateway",
                priority: 1000,
                description: "Route through IGW to allow Windows KMS activation for GCP.",
            }, { parent: this });
        }

        this.networkName = this.network.networkName;
        this.networkSelfLink = this.network.networkSelfLink;
        this.networkId = this.network.networkId;

        // Subnet outputs (mirrors TF module outputs: subnets_names, subnets_ips, etc.)
        const subnetEntries = Object.values(this.network.subnets);
        this.subnetsNames = pulumi.all(subnetEntries.map(s => s.name)).apply(names => names);
        this.subnetsIps = pulumi.all(subnetEntries.map(s => s.ipCidrRange)).apply(ips => ips);
        this.subnetsSelfLinks = pulumi.all(subnetEntries.map(s => s.selfLink)).apply(links => links);
        this.subnetsSecondaryRanges = pulumi.output(args.secondaryRanges || {});

        // DNS policy
        const dnsPolicy = new gcp.dns.Policy(`${name}-dns-policy`, {
            project: args.projectId,
            name: `dp-${vpcName}-default-policy`,
            enableInboundForwarding: args.dnsEnableInboundForwarding ?? true,
            enableLogging: args.dnsEnableLogging ?? true,
            networks: [{
                networkUrl: this.network.networkSelfLink,
            }],
        }, { parent: this });
        this.dnsPolicy = dnsPolicy.name;

        // Private Google APIs DNS zones
        for (const [zoneName, dnsName] of [
            ["googleapis", "googleapis.com."],
            ["gcr", "gcr.io."],
            ["pkg-dev", "pkg.dev."],
            ["notebooks-api", "notebooks.cloud.google.com."],
            ["notebooks-gke", "notebooks.googleusercontent.com."],
        ]) {
            new gcp.dns.ManagedZone(`${name}-dns-${zoneName}`, {
                project: args.projectId,
                name: `dz-${vpcName}-${zoneName}`,
                dnsName: dnsName,
                description: `Private ${zoneName} zone`,
                visibility: "private",
                privateVisibilityConfig: {
                    networks: [{
                        networkUrl: this.network.networkSelfLink,
                    }],
                },
            }, { parent: this });
        }


        // ================================================================
        // Bi-Directional VPC Peering (Spoke <-> Hub)
        // ================================================================
        if (args.mode === "spoke" && args.netHubProjectId && args.netHubNetworkSelfLink) {
            const spokeToHub = new gcp.compute.NetworkPeering(`${name}-spoke-to-hub`, {
                network: this.network.networkSelfLink,
                peerNetwork: args.netHubNetworkSelfLink,
                name: pulumi.interpolate`np-${args.environmentCode}-svpc-spoke-vpc-c-svpc-hub`,
                exportCustomRoutes: false,
                importCustomRoutes: true,
            }, { parent: this });

            const hubToSpoke = new gcp.compute.NetworkPeering(`${name}-hub-to-spoke`, {
                network: args.netHubNetworkSelfLink,
                peerNetwork: this.network.networkSelfLink,
                name: pulumi.interpolate`np-vpc-c-svpc-hub-${args.environmentCode}-svpc-spoke`,
                exportCustomRoutes: true,
                importCustomRoutes: false,
            }, { parent: this, dependsOn: [spokeToHub] });
        }

        // Private Service Connect
        new PrivateServiceConnect(`${name}-psc`, {
            projectId: args.projectId,
            networkSelfLink: this.network.networkSelfLink,
            address: args.pscAddress,
            forwardingRuleName: `fr-${vpcName}-psc`,
        }, { parent: this });

        // NAT (if enabled)
        if (args.natEnabled !== false) {
            const natRouter = new gcp.compute.Router(`${name}-nat-router-${args.defaultRegion}`, {
                name: `cr-${vpcName}-${args.defaultRegion}-nat`,
                project: args.projectId,
                region: args.defaultRegion,
                network: this.network.networkId,
            }, { parent: this });

            new gcp.compute.RouterNat(`${name}-nat-${args.defaultRegion}`, {
                name: `rn-${vpcName}-${args.defaultRegion}-egress`,
                project: args.projectId,
                router: natRouter.name,
                region: args.defaultRegion,
                natIpAllocateOption: "AUTO_ONLY",
                sourceSubnetworkIpRangesToNat: "ALL_SUBNETWORKS_ALL_IP_RANGES",
                logConfig: {
                    enable: true,
                    filter: "TRANSLATIONS_ONLY",
                },
            }, { parent: this });

            // Second region NAT
            const natRouter2 = new gcp.compute.Router(`${name}-nat-router-${args.defaultRegion2}`, {
                name: `cr-${vpcName}-${args.defaultRegion2}-nat`,
                project: args.projectId,
                region: args.defaultRegion2,
                network: this.network.networkId,
            }, { parent: this });

            new gcp.compute.RouterNat(`${name}-nat-${args.defaultRegion2}`, {
                name: `rn-${vpcName}-${args.defaultRegion2}-egress`,
                project: args.projectId,
                router: natRouter2.name,
                region: args.defaultRegion2,
                natIpAllocateOption: "AUTO_ONLY",
                sourceSubnetworkIpRangesToNat: "ALL_SUBNETWORKS_ALL_IP_RANGES",
                logConfig: {
                    enable: true,
                    filter: "TRANSLATIONS_ONLY",
                },
            }, { parent: this });
        }

        // ================================================================
        // Network Firewall Policy (modern — matches Go BuildFoundationRules)
        // Replaces legacy gcp.compute.Firewall resources with the modern
        // gcp.compute.NetworkFirewallPolicy + Association + Rule pattern.
        // Mirrors: go/pkg/networking/firewall.go:NewNetworkFirewallPolicy
        // ================================================================
        const policyName = `fp-${vpcName}-firewalls`;
        const fwPolicy = new gcp.compute.NetworkFirewallPolicy(`${name}-fw-policy`, {
            project: args.projectId,
            name: policyName,
            description: `Firewall rules for VPC: ${networkName}.`,
        }, { parent: this, dependsOn: [this.network.network] });

        // Associate the policy with the VPC network
        new gcp.compute.NetworkFirewallPolicyAssociation(`${name}-fw-assoc`, {
            project: args.projectId,
            firewallPolicy: fwPolicy.name,
            attachmentTarget: pulumi.interpolate`projects/${args.projectId}/global/networks/${this.network.networkName}`,
            name: pulumi.interpolate`${policyName}-${this.network.networkName}`,
        }, { parent: fwPolicy });

        // Build foundation rules — matches Go's BuildFoundationRules exactly
        const subnetCidrs = args.subnets.map(s => s.subnetIp);
        const fwRules = buildFoundationRules(
            args.environmentCode,
            enableLogging,
            args.pscAddress + "/32",
            subnetCidrs,
            args.enableAllVpcInternalTraffic ?? false,
        );

        // Create each rule as a NetworkFirewallPolicyRule
        for (const rule of fwRules) {
            const matchBlock: gcp.types.input.compute.NetworkFirewallPolicyRuleMatch = {
                layer4Configs: rule.match.layer4Configs.map(l4 => ({
                    ipProtocol: l4.ipProtocol,
                    ports: l4.ports,
                })),
            };

            if (rule.direction === "EGRESS" && rule.match.destIpRanges) {
                matchBlock.destIpRanges = rule.match.destIpRanges;
            }
            if (rule.direction === "INGRESS" && rule.match.srcIpRanges) {
                matchBlock.srcIpRanges = rule.match.srcIpRanges;
            }

            new gcp.compute.NetworkFirewallPolicyRule(`${name}-fw-rule-${rule.priority}`, {
                project: args.projectId,
                firewallPolicy: fwPolicy.name,
                priority: rule.priority,
                direction: rule.direction,
                action: rule.action,
                ruleName: rule.ruleName,
                description: rule.description,
                enableLogging: rule.enableLogging,
                match: matchBlock,
            }, { parent: fwPolicy });
        }

        this.registerOutputs({
            networkName: this.networkName,
            networkSelfLink: this.networkSelfLink,
            subnetsNames: this.subnetsNames,
            subnetsIps: this.subnetsIps,
            subnetsSelfLinks: this.subnetsSelfLinks,
            subnetsSecondaryRanges: this.subnetsSecondaryRanges,
            dnsPolicy: this.dnsPolicy,
        });
    }
}

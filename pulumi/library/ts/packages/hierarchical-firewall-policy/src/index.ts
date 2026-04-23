/**
 * Hierarchical Firewall Policy Module
 * Mirrors: 3-networks/modules/hierarchical_firewall_policy
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface HierarchicalFirewallRuleConfig {
    description: string;
    direction: "INGRESS" | "EGRESS";
    action: "allow" | "deny" | "goto_next";
    priority: number;
    ranges: string[];
    targetResources?: pulumi.Input<string>[];
    targetServiceAccounts?: string[];
    enableLogging?: boolean;
    layer4Configs: { ipProtocol: string; ports?: string[] }[];
}

export interface HierarchicalFirewallPolicyArgs {
    parentNode: string;
    name: string;
    description?: string;
    rules: HierarchicalFirewallRuleConfig[];
    targetFolders?: pulumi.Input<string>[];
}

export class HierarchicalFirewallPolicy extends pulumi.ComponentResource {
    public readonly policyId: pulumi.Output<string>;

    constructor(name: string, args: HierarchicalFirewallPolicyArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:HierarchicalFirewallPolicy", name, args, opts);

        const policy = new gcp.compute.FirewallPolicy(`${name}-policy`, {
            shortName: args.name,
            parent: args.parentNode,
            description: args.description,
        }, { parent: this });

        this.policyId = policy.id;

        for (let i = 0; i < args.rules.length; i++) {
            const rule = args.rules[i];
            new gcp.compute.FirewallPolicyRule(`${name}-rule-${i}`, {
                firewallPolicy: policy.id,
                description: rule.description,
                direction: rule.direction,
                action: rule.action,
                priority: rule.priority,
                match: {
                    srcIpRanges: rule.direction === "INGRESS" ? rule.ranges : undefined,
                    destIpRanges: rule.direction === "EGRESS" ? rule.ranges : undefined,
                    layer4Configs: rule.layer4Configs.map(l4 => ({
                        ipProtocol: l4.ipProtocol,
                        ports: l4.ports,
                    })),
                },
                targetResources: rule.targetResources,
                targetServiceAccounts: rule.targetServiceAccounts,
                enableLogging: rule.enableLogging,
            }, { parent: this });
        }

        // Associate with target folders
        if (args.targetFolders) {
            for (let i = 0; i < args.targetFolders.length; i++) {
                new gcp.compute.FirewallPolicyAssociation(`${name}-assoc-${i}`, {
                    firewallPolicy: policy.id,
                    attachmentTarget: args.targetFolders[i],
                    name: `${args.name}-assoc-${i}`,
                }, { parent: this });
            }
        }

        this.registerOutputs({
            policyId: this.policyId,
        });
    }
}

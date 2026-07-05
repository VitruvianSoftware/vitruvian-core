/**
 * Network Firewall Policy Module
 * Mirrors: terraform-google-modules/network/google//modules/network-firewall-policy
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface NetworkFirewallRuleConfig {
    ruleName: string;
    description: string;
    direction: "INGRESS" | "EGRESS";
    action: "allow" | "deny" | "goto_next";
    priority: number;
    ranges: string[];
    targetSecureTags?: { name: string }[];
    targetServiceAccounts?: string[];
    enableLogging?: boolean;
    layer4Configs: { ipProtocol: string; ports?: string[] }[];
}

export interface NetworkFirewallPolicyArgs {
    project: pulumi.Input<string>;
    name: string;
    description?: string;
    rules: NetworkFirewallRuleConfig[];
    network: pulumi.Input<string>;
}

export class NetworkFirewallPolicy extends pulumi.ComponentResource {
    public readonly policyId: pulumi.Output<string>;
    public readonly policyName: pulumi.Output<string>;

    constructor(name: string, args: NetworkFirewallPolicyArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:NetworkFirewallPolicy", name, args, opts);

        const policy = new gcp.compute.NetworkFirewallPolicy(`${name}-policy`, {
            project: args.project,
            name: args.name,
            description: args.description,
        }, { parent: this });

        this.policyId = policy.id;
        this.policyName = policy.name;

        for (let i = 0; i < args.rules.length; i++) {
            const rule = args.rules[i];
            new gcp.compute.NetworkFirewallPolicyRule(`${name}-rule-${i}`, {
                project: args.project,
                firewallPolicy: policy.name,
                ruleName: rule.ruleName,
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
                targetSecureTags: rule.targetSecureTags,
                targetServiceAccounts: rule.targetServiceAccounts,
                enableLogging: rule.enableLogging,
            }, { parent: policy });
        }

        // Associate with the target network
        new gcp.compute.NetworkFirewallPolicyAssociation(`${name}-assoc`, {
            project: args.project,
            firewallPolicy: policy.name,
            attachmentTarget: args.network,
            name: pulumi.interpolate`${args.name}-assoc`,
        }, { parent: policy });

        this.registerOutputs({
            policyId: this.policyId,
            policyName: this.policyName,
        });
    }
}

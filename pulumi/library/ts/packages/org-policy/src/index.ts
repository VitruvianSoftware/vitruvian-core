/**
 * Org Policy Module
 * Mirrors: terraform-google-modules/org-policy/google
 * Enforces org-level constraints (boolean and list policies).
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface OrgPolicyBooleanArgs {
    /** Organization ID (numeric). */
    orgId: string;
    folderId?: string;
    /** Constraint name (e.g., "compute.disableNestedVirtualization"). */
    constraint: string;
    /** Whether the policy is enforced. */
    enforced: boolean;
}

export class OrgPolicyBoolean extends pulumi.ComponentResource {
    constructor(name: string, args: OrgPolicyBooleanArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:OrgPolicyBoolean", name, args, opts);

        const parentId = args.folderId ? `folders/${args.folderId}` : `organizations/${args.orgId}`;
        new gcp.orgpolicy.Policy(`${name}-policy`, {
            name: `${parentId}/policies/${args.constraint}`,
            parent: parentId,
            spec: {
                rules: [{
                    enforce: args.enforced ? "TRUE" : "FALSE",
                }],
            },
        }, { parent: this });

        this.registerOutputs({});
    }
}

export interface OrgPolicyListArgs {
    /** Organization ID (numeric). */
    orgId: string;
    folderId?: string;
    /** Constraint name. */
    constraint: string;
    /** Policy type: "allow" or "deny". */
    policyType: "allow" | "deny";
    /** Values to allow or deny. Use ["all"] for all values. */
    values: string[];
}

export class OrgPolicyList extends pulumi.ComponentResource {
    constructor(name: string, args: OrgPolicyListArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:OrgPolicyList", name, args, opts);

        const isAll = args.values.length === 1 && args.values[0] === "all";

        const rule: any = {};
        if (args.policyType === "allow") {
            rule.allowAll = isAll ? "TRUE" : undefined;
            if (!isAll) {
                rule.values = { allowedValues: args.values };
            }
        } else {
            rule.denyAll = isAll ? "TRUE" : undefined;
            if (!isAll) {
                rule.values = { deniedValues: args.values };
            }
        }

        const parentId = args.folderId ? `folders/${args.folderId}` : `organizations/${args.orgId}`;
        new gcp.orgpolicy.Policy(`${name}-policy`, {
            name: `${parentId}/policies/${args.constraint}`,
            parent: parentId,
            spec: {
                rules: [rule],
            },
        }, { parent: this });

        this.registerOutputs({});
    }
}

export interface DomainRestrictedSharingArgs {
    /** Organization ID (numeric). */
    orgId: string;
    folderId?: string;
    /** List of allowed domain customer IDs (e.g., ["C0xxxxxxx"]). */
    domainsToAllow: string[];
}

export class DomainRestrictedSharing extends pulumi.ComponentResource {
    constructor(name: string, args: DomainRestrictedSharingArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:DomainRestrictedSharing", name, args, opts);

        const parentId = args.folderId ? `folders/${args.folderId}` : `organizations/${args.orgId}`;
        new gcp.orgpolicy.Policy(`${name}-policy`, {
            name: `${parentId}/policies/iam.allowedPolicyMemberDomains`,
            parent: parentId,
            spec: {
                rules: [{
                    values: {
                        allowedValues: args.domainsToAllow,
                    },
                }],
            },
        }, { parent: this });

        this.registerOutputs({});
    }
}

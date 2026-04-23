/**
 * Budget Module
 * Mirrors budget creation used in project-factory and standalone budget configs.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface BudgetArgs {
    billingAccount: string;
    projectId: pulumi.Input<string>;
    projectNumber: pulumi.Input<string>;
    displayName?: pulumi.Input<string>;
    budgetAmount?: number | null;
    alertSpentPercents?: number[];
    alertPubsubTopic?: string | null;
    alertSpendBasis?: string;
}

export class Budget extends pulumi.ComponentResource {
    constructor(name: string, args: BudgetArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:Budget", name, args, opts);

        if (args.budgetAmount != null && args.budgetAmount > 0) {
            new gcp.billing.Budget(`${name}-budget`, {
                billingAccount: args.billingAccount,
                displayName: args.displayName ?? pulumi.interpolate`Budget for ${args.projectId}`,
                budgetFilter: {
                    projects: [pulumi.interpolate`projects/${args.projectNumber}`],
                },
                amount: {
                    specifiedAmount: {
                        currencyCode: "USD",
                        units: String(args.budgetAmount),
                    },
                },
                thresholdRules: (args.alertSpentPercents ?? [1.2]).map(pct => ({
                    thresholdPercent: pct,
                    spendBasis: (args.alertSpendBasis ?? "FORECASTED_SPEND") as any,
                })),
                allUpdatesRule: args.alertPubsubTopic ? {
                    pubsubTopic: args.alertPubsubTopic,
                } : undefined,
            }, { parent: this });
        }

        this.registerOutputs({});
    }
}

// Trigger release

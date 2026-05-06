/**
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import * as random from "@pulumi/random";

export interface ProjectFactoryArgs {
    /** Base project name. */
    name: string;
    /** GCP Organization ID. */
    orgId: string;
    /** Billing account ID. */
    billingAccount: string;
    /** Folder ID to place the project under (e.g. "folders/123456"). */
    folderId: pulumi.Input<string>;
    /** APIs to enable on the project. */
    activateApis?: string[];
    /** Labels to apply to the project. */
    labels?: Record<string, string>;
    /** Whether to append a random suffix to the project ID. */
    randomProjectId?: boolean;
    /** Length of the random suffix. */
    randomProjectIdLength?: number;
    /** Default service account handling: "deprivilege", "disable", "delete", or "keep". */
    defaultServiceAccount?: string;
    /** Whether to disable services on destroy. */
    disableServicesOnDestroy?: boolean;
    /** Project deletion policy: "PREVENT" or "DELETE". */
    deletionPolicy?: string;
    /** Budget alert Pub/Sub topic. */
    budgetAlertPubsubTopic?: string | null;
    /** Budget alert spent percentages. */
    budgetAlertSpentPercents?: number[];
    /** Budget amount. */
    budgetAmount?: number | null;
    /** Budget alert spend basis. */
    budgetAlertSpendBasis?: string;
}

export interface ProjectFactoryOutputs {
    projectId: pulumi.Output<string>;
    projectNumber: pulumi.Output<string>;
    projectName: pulumi.Output<string>;
    serviceAccountEmail: pulumi.Output<string>;
}

export class ProjectFactory extends pulumi.ComponentResource {
    public readonly projectId: pulumi.Output<string>;
    public readonly projectNumber: pulumi.Output<string>;
    public readonly projectName: pulumi.Output<string>;
    public readonly serviceAccountEmail: pulumi.Output<string>;
    public readonly project: gcp.organizations.Project;

    constructor(name: string, args: ProjectFactoryArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:ProjectFactory", name, args, opts);

        const randomIdLength = args.randomProjectIdLength ?? 4;
        const useRandomId = args.randomProjectId ?? true;

        // Generate random suffix for project ID uniqueness
        let projectIdInput: pulumi.Input<string> = args.name;
        if (useRandomId) {
            const suffix = new random.RandomString(`${name}-suffix`, {
                length: randomIdLength,
                special: false,
                upper: false,
            }, { parent: this });
            projectIdInput = pulumi.interpolate`${args.name}-${suffix.result}`;
        }

        // Determine parent: if folderId is provided, use it; otherwise use org
        const project = new gcp.organizations.Project(`${name}-project`, {
            projectId: projectIdInput,
            name: args.name,
            orgId: args.folderId ? undefined : args.orgId,
            folderId: args.folderId ? args.folderId : undefined,
            billingAccount: args.billingAccount,
            labels: args.labels,
            deletionPolicy: args.deletionPolicy ?? "PREVENT",
            autoCreateNetwork: false,
        }, { parent: this });

        this.project = project;
        this.projectId = project.projectId;
        this.projectNumber = project.number;
        this.projectName = project.name;
        this.serviceAccountEmail = project.number.apply(n => `${n}-compute@developer.gserviceaccount.com`);

        // Enable APIs
        const apiResources: gcp.projects.Service[] = [];
        for (const api of args.activateApis ?? []) {
            const sanitized = api.replace(/\./g, "-");
            const svc = new gcp.projects.Service(`${name}-api-${sanitized}`, {
                project: project.projectId,
                service: api,
                disableOnDestroy: args.disableServicesOnDestroy ?? false,
            }, { parent: this, dependsOn: [project] });
            apiResources.push(svc);
        }

        // Deprivilege default compute service account
        if (args.defaultServiceAccount === "deprivilege") {
            // Remove default editor role from the compute default SA
            new gcp.projects.IAMBinding(`${name}-remove-default-editor`, {
                project: project.projectId,
                role: "roles/editor",
                members: [],
            }, { parent: this, dependsOn: apiResources });
        }

        // Budget alert
        if (args.budgetAmount != null && args.budgetAmount > 0) {
            new gcp.billing.Budget(`${name}-budget`, {
                billingAccount: args.billingAccount,
                displayName: pulumi.interpolate`Budget for ${project.projectId}`,
                budgetFilter: {
                    projects: [pulumi.interpolate`projects/${project.number}`],
                },
                amount: {
                    specifiedAmount: {
                        currencyCode: "USD",
                        units: String(args.budgetAmount),
                    },
                },
                thresholdRules: (args.budgetAlertSpentPercents ?? [1.2]).map(pct => ({
                    thresholdPercent: pct,
                    spendBasis: (args.budgetAlertSpendBasis ?? "FORECASTED_SPEND") as any,
                })),
                allUpdatesRule: args.budgetAlertPubsubTopic ? {
                    pubsubTopic: args.budgetAlertPubsubTopic,
                } : undefined,
            }, { parent: this });
        }

        this.registerOutputs({
            projectId: this.projectId,
            projectNumber: this.projectNumber,
            projectName: this.projectName,
            serviceAccountEmail: this.serviceAccountEmail,
        });
    }
}

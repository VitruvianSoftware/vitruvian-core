/**
 * Copyright 2026 Vitruvian Software
 *
 * Single Project Module — creates a project with Shared VPC attachment,
 * VPC-SC, pipeline SA roles, and budget alerts.
 * Mirrors: 4-projects/modules/single_project/main.tf
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { ProjectFactory } from "@vitruviansoftware/foundation-project-factory";

export interface SingleProjectArgs {
    orgId: string;
    billingAccount: string;
    folderId: pulumi.Input<string>;
    environment: string;
    projectPrefix: string;
    projectSuffix: string;
    businessCode: string;
    applicationName: string;
    billingCode: string;
    primaryContact: string;
    secondaryContact: string;
    vpc: string;
    activateApis?: string[];
    sharedVpcHostProjectId?: pulumi.Input<string>;
    sharedVpcSubnets?: string[];
    enableCloudbuildDeploy?: boolean;
    appInfraPipelineServiceAccounts?: Record<string, string>;
    saRoles?: Record<string, string[]>;
    projectBudget?: {
        budgetAmount?: number;
        alertSpentPercents?: number[];
        alertPubsubTopic?: string | null;
        alertSpendBasis?: string;
    };
    projectDeletionPolicy?: string;
}

export interface SingleProjectOutputs {
    projectId: pulumi.Output<string>;
    projectNumber: pulumi.Output<string>;
    enabledApis: string[];
}

export function deploySingleProject(name: string, args: SingleProjectArgs): SingleProjectOutputs {
    const envCode = args.environment.charAt(0);
    const projectName = `${args.projectPrefix}-${envCode}-${args.businessCode}-${args.projectSuffix}`;

    // Mirrors TF: distinct(concat(var.activate_apis, ["billingbudgets.googleapis.com"]))
    const enabledApis = [...new Set([...(args.activateApis ?? []), "billingbudgets.googleapis.com"])];

    const project = new ProjectFactory(name, {
        name: projectName,
        orgId: args.orgId,
        billingAccount: args.billingAccount,
        folderId: args.folderId,
        deletionPolicy: args.projectDeletionPolicy ?? "PREVENT",
        activateApis: enabledApis,
        labels: {
            environment: args.environment,
            application_name: args.applicationName,
            billing_code: args.billingCode,
            primary_contact: args.primaryContact.split("@")[0],
            secondary_contact: args.secondaryContact.split("@")[0],
            business_code: args.businessCode,
            env_code: envCode,
            vpc: args.vpc,
        },
        budgetAmount: args.projectBudget?.budgetAmount,
        budgetAlertSpentPercents: args.projectBudget?.alertSpentPercents,
        budgetAlertPubsubTopic: args.projectBudget?.alertPubsubTopic,
        budgetAlertSpendBasis: args.projectBudget?.alertSpendBasis,
    });

    // Shared VPC service project attachment
    if (args.sharedVpcHostProjectId) {
        new gcp.compute.SharedVPCServiceProject(`${name}-svpc-service`, {
            hostProject: args.sharedVpcHostProjectId,
            serviceProject: project.projectId,
        });
    }

    // Pipeline SA roles on the project
    if (args.enableCloudbuildDeploy && args.appInfraPipelineServiceAccounts && args.saRoles) {
        for (const [repo, roles] of Object.entries(args.saRoles)) {
            const sa = args.appInfraPipelineServiceAccounts[repo];
            if (sa) {
                for (const role of roles) {
                    new gcp.projects.IAMMember(`${name}-pipeline-${repo}-${role.replace(/\//g, "-")}`, {
                        project: project.projectId,
                        role: role,
                        member: `serviceAccount:${sa}`,
                    });
                }
            }
        }
    }

    return {
        projectId: project.projectId,
        projectNumber: project.projectNumber,
        enabledApis: enabledApis,
    };
}

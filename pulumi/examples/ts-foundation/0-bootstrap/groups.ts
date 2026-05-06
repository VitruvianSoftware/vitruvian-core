/**
 * Groups creation — mirrors 0-bootstrap/groups.tf
 * Optionally creates Google Workspace groups via Cloud Identity.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { BootstrapConfig } from "./config";
import { GoogleGroup } from "@vitruviansoftware/foundation-google-group";

export interface GroupOutputs {
    requiredGroupIds: Record<string, pulumi.Output<string> | string>;
    optionalGroupIds: Record<string, pulumi.Output<string> | string>;
    dependsOn: pulumi.Resource[];
}

export async function deployGroups(cfg: BootstrapConfig): Promise<GroupOutputs> {
    const result: GroupOutputs = {
        requiredGroupIds: {},
        optionalGroupIds: {},
        dependsOn: [],
    };

    if (!cfg.groups.createRequiredGroups && !cfg.groups.createOptionalGroups) {
        return result;
    }

    // Look up org for customer ID
    const org = await gcp.organizations.getOrganization({
        organization: cfg.orgId,
    });

    // Create required groups
    if (cfg.groups.createRequiredGroups) {
        const requiredGroupsToCreate: Record<string, string> = {
            group_org_admins: cfg.groups.requiredGroups.groupOrgAdmins,
            group_billing_admins: cfg.groups.requiredGroups.groupBillingAdmins,
            billing_data_users: cfg.groups.requiredGroups.billingDataUsers,
            audit_data_users: cfg.groups.requiredGroups.auditDataUsers,
        };

        for (const [key, email] of Object.entries(requiredGroupsToCreate)) {
            const group = new GoogleGroup(`required-group-${key}`, {
                id: email,
                displayName: key,
                description: key,
                initialGroupConfig: cfg.initialGroupConfig,
                customerId: org.directoryCustomerId!,
            });
            result.requiredGroupIds[key] = group.groupId;
            result.dependsOn.push(group);
        }
    }

    // Create optional groups
    if (cfg.groups.createOptionalGroups) {
        const optionalGroupsToCreate: Record<string, string> = {};
        for (const [key, val] of Object.entries(cfg.groups.optionalGroups)) {
            if (val && val !== "") {
                optionalGroupsToCreate[key] = val;
            }
        }

        for (const [key, email] of Object.entries(optionalGroupsToCreate)) {
            const group = new GoogleGroup(`optional-group-${key}`, {
                id: email,
                displayName: key,
                description: key,
                initialGroupConfig: cfg.initialGroupConfig,
                customerId: org.directoryCustomerId!,
            });
            result.optionalGroupIds[key] = group.groupId;
            result.dependsOn.push(group);
        }
    }

    return result;
}

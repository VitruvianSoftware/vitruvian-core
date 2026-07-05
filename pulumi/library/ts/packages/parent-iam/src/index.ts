/**
 * Parent IAM Member — Polymorphic IAM binding module.
 * Mirrors: 0-bootstrap/modules/parent-iam-member
 * Supports organization, folder, and project IAM member bindings.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface ParentIamMemberArgs {
    /** Type of parent: "organization", "folder", or "project". */
    parentType: "organization" | "folder" | "project";
    /** ID of the parent resource. */
    parentId: pulumi.Input<string>;
    /** Member string (e.g. "serviceAccount:...", "group:...", "user:..."). */
    member: pulumi.Input<string>;
    /** List of roles to grant. */
    roles: string[];
}

export class ParentIamMember extends pulumi.ComponentResource {
    constructor(name: string, args: ParentIamMemberArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:ParentIamMember", name, args, opts);

        for (const role of args.roles) {
            const sanitizedRole = role.replace(/\//g, "-").replace(/\./g, "-");
            if (args.parentType === "organization") {
                new gcp.organizations.IAMMember(`${name}-org-${sanitizedRole}`, {
                    orgId: args.parentId as pulumi.Input<string>,
                    role: role,
                    member: args.member,
                }, { parent: this });
            } else if (args.parentType === "folder") {
                new gcp.folder.IAMMember(`${name}-folder-${sanitizedRole}`, {
                    folder: args.parentId,
                    role: role,
                    member: args.member,
                }, { parent: this });
            } else if (args.parentType === "project") {
                new gcp.projects.IAMMember(`${name}-project-${sanitizedRole}`, {
                    project: args.parentId,
                    role: role,
                    member: args.member,
                }, { parent: this });
            }
        }

        this.registerOutputs({});
    }
}

/**
 * Parent IAM Remove Role — Strips all members from specified roles.
 * Mirrors: 0-bootstrap/modules/parent-iam-remove-role
 */
export interface ParentIamRemoveRoleArgs {
    /** Type of parent: "organization", "folder", or "project". */
    parentType: "organization" | "folder" | "project";
    /** ID of the parent resource. */
    parentId: pulumi.Input<string>;
    /** Roles to remove all members from. */
    roles: string[];
}

export class ParentIamRemoveRole extends pulumi.ComponentResource {
    constructor(name: string, args: ParentIamRemoveRoleArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:ParentIamRemoveRole", name, args, opts);

        for (const role of args.roles) {
            const sanitizedRole = role.replace(/\//g, "-").replace(/\./g, "-");
            if (args.parentType === "organization") {
                new gcp.organizations.IAMBinding(`${name}-org-remove-${sanitizedRole}`, {
                    orgId: args.parentId as pulumi.Input<string>,
                    role: role,
                    members: [],
                }, { parent: this });
            } else if (args.parentType === "folder") {
                new gcp.folder.IAMBinding(`${name}-folder-remove-${sanitizedRole}`, {
                    folder: args.parentId,
                    role: role,
                    members: [],
                }, { parent: this });
            } else if (args.parentType === "project") {
                new gcp.projects.IAMBinding(`${name}-project-remove-${sanitizedRole}`, {
                    project: args.parentId,
                    role: role,
                    members: [],
                }, { parent: this });
            }
        }

        this.registerOutputs({});
    }
}

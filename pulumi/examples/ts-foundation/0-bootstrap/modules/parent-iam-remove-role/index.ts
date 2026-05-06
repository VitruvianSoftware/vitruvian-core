import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface ParentIamRemoveRoleArgs {
  parentType: "project" | "folder" | "organization";
  parentId: pulumi.Input<string>;
  roles: string[];
}

export class ParentIamRemoveRole extends pulumi.ComponentResource {
  constructor(name: string, args: ParentIamRemoveRoleArgs, opts?: pulumi.ComponentResourceOptions) {
    super("modules:local:ParentIamRemoveRole", name, args, opts);

    for (const role of args.roles) {
      const sanitizedRole = role.replace(/[^a-zA-Z0-9-]/g, "-");
      const resourceName = `${name}-${sanitizedRole}`;

      if (args.parentType === "organization") {
        new gcp.organizations.IAMBinding(resourceName, {
          orgId: args.parentId,
          role: role,
          members: [],
        }, { parent: this });
      } else if (args.parentType === "folder") {
        new gcp.folder.IAMBinding(resourceName, {
          folder: args.parentId,
          role: role,
          members: [],
        }, { parent: this });
      } else if (args.parentType === "project") {
        new gcp.projects.IAMBinding(resourceName, {
          project: args.parentId,
          role: role,
          members: [],
        }, { parent: this });
      }
    }
  }
}

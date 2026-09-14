import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface ParentIamMemberArgs {
  member: pulumi.Input<string>;
  parentType: "project" | "folder" | "organization";
  parentId: pulumi.Input<string>;
  roles: string[];
}

export class ParentIamMember extends pulumi.ComponentResource {
  constructor(
    name: string,
    args: ParentIamMemberArgs,
    opts?: pulumi.ComponentResourceOptions,
  ) {
    super("modules:local:ParentIamMember", name, args, opts);

    for (const role of args.roles) {
      const sanitizedRole = role.replace(/[^a-zA-Z0-9-]/g, "-");
      const resourceName = `${name}-${sanitizedRole}`;

      if (args.parentType === "organization") {
        new gcp.organizations.IAMMember(
          resourceName,
          {
            orgId: args.parentId,
            role: role,
            member: args.member,
          },
          { parent: this },
        );
      } else if (args.parentType === "folder") {
        new gcp.folder.IAMMember(
          resourceName,
          {
            folder: args.parentId,
            role: role,
            member: args.member,
          },
          { parent: this },
        );
      } else if (args.parentType === "project") {
        new gcp.projects.IAMMember(
          resourceName,
          {
            project: args.parentId,
            role: role,
            member: args.member,
          },
          { parent: this },
        );
      }
    }
  }
}

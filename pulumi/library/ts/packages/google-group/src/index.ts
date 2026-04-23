/**
 * Google Group Module
 * Mirrors: terraform-google-modules/group/google
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface GoogleGroupArgs {
    /** Email of the group (e.g. "admins@example.com"). */
    id: string;
    /** Display name. */
    displayName: string;
    /** Description. */
    description?: string;
    /** Customer ID from Cloud Identity. */
    customerId: pulumi.Input<string>;
    /** Initial group configuration. */
    initialGroupConfig?: string;
}

export class GoogleGroup extends pulumi.ComponentResource {
    public readonly groupId: pulumi.Output<string>;

    constructor(name: string, args: GoogleGroupArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:GoogleGroup", name, args, opts);

        const group = new gcp.cloudidentity.Group(`${name}-group`, {
            groupKey: {
                id: args.id,
            },
            parent: pulumi.interpolate`customers/${args.customerId}`,
            displayName: args.displayName,
            description: args.description ?? args.displayName,
            initialGroupConfig: args.initialGroupConfig ?? "WITH_INITIAL_OWNER",
            labels: {
                "cloudidentity.googleapis.com/groups.discussion_forum": "",
            },
        }, { parent: this });

        this.groupId = group.id;

        this.registerOutputs({
            groupId: this.groupId,
        });
    }
}

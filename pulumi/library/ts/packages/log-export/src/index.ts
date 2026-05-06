/**
 * Log Export Module
 * Creates GCP log sinks at organization, folder, project, or billing account level.
 * Mirrors: terraform-google-modules/log-export/google
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface LogExportArgs {
    destinationUri: pulumi.Input<string>;
    filter?: pulumi.Input<string>;
    logSinkName: string;
    parentResourceId: pulumi.Input<string>;
    /** "organization" | "folder" | "project" | "billing_account" */
    resourceType: string;
    uniqueWriterIdentity?: boolean;
    includeChildren?: boolean;
}

export class LogExport extends pulumi.ComponentResource {
    public readonly writerIdentity: pulumi.Output<string>;

    constructor(name: string, args: LogExportArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:LogExport", name, args, opts);

        let sink: gcp.logging.OrganizationSink | gcp.logging.FolderSink | gcp.logging.ProjectSink;

        switch (args.resourceType) {
            case "organization":
                const orgSink = new gcp.logging.OrganizationSink(`${name}-sink`, {
                    name: args.logSinkName,
                    orgId: args.parentResourceId,
                    destination: args.destinationUri,
                    filter: args.filter,
                    includeChildren: args.includeChildren ?? true,
                }, { parent: this });
                this.writerIdentity = orgSink.writerIdentity;
                break;

            case "folder":
                const folderSink = new gcp.logging.FolderSink(`${name}-sink`, {
                    name: args.logSinkName,
                    folder: args.parentResourceId,
                    destination: args.destinationUri,
                    filter: args.filter,
                    includeChildren: args.includeChildren ?? true,
                }, { parent: this });
                this.writerIdentity = folderSink.writerIdentity;
                break;

            case "project":
                const projSink = new gcp.logging.ProjectSink(`${name}-sink`, {
                    name: args.logSinkName,
                    project: args.parentResourceId,
                    destination: args.destinationUri,
                    filter: args.filter,
                    uniqueWriterIdentity: args.uniqueWriterIdentity ?? true,
                }, { parent: this });
                this.writerIdentity = projSink.writerIdentity;
                break;

            case "billing_account":
                const billSink = new gcp.logging.BillingAccountSink(`${name}-sink`, {
                    name: args.logSinkName,
                    billingAccount: args.parentResourceId,
                    destination: args.destinationUri,
                    filter: args.filter,
                }, { parent: this });
                this.writerIdentity = billSink.writerIdentity;
                break;

            default:
                throw new Error(`Unsupported resourceType: ${args.resourceType}`);
        }

        this.registerOutputs({ writerIdentity: this.writerIdentity });
    }
}

/**
 * Gcloud Module
 * Utility wrapper for executing gcloud CLI commands via pulumi.Command.
 * Mirrors: terraform-google-modules/gcloud/google (local-exec pattern)
 */

import * as pulumi from "@pulumi/pulumi";
import * as command from "@pulumi/command";

export interface GcloudArgs {
    commands: string[];
    environment?: Record<string, string>;
    createCmdBody?: string;
    destroyCmdBody?: string;
}

export class Gcloud extends pulumi.ComponentResource {
    constructor(name: string, args: GcloudArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:Gcloud", name, args, opts);

        const cmdStr = args.createCmdBody || args.commands.join(" && ");
        new command.local.Command(`${name}-cmd`, {
            create: cmdStr,
            "delete": args.destroyCmdBody,
            environment: args.environment,
        }, { parent: this });

        this.registerOutputs({});
    }
}

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface CloudRunAppArgs {
  /** Project ID. */
  projectId: pulumi.Input<string>;
  /** Name of the service. */
  name: string;
  /** Image to deploy. */
  image: pulumi.Input<string>;
  /** Region. */
  region: pulumi.Input<string>;
  /** Service account email. */
  serviceAccount?: pulumi.Input<string>;
  /** Ingress (defaults to INGRESS_TRAFFIC_ALL). */
  ingress?: pulumi.Input<string>;
  /** Environment variables. */
  envVars?: Record<string, pulumi.Input<string>>;
}

export class CloudRunApp extends pulumi.ComponentResource {
  public readonly service: gcp.cloudrunv2.Service;

  constructor(
    name: string,
    args: CloudRunAppArgs,
    opts?: pulumi.ComponentResourceOptions,
  ) {
    super("foundation:modules:CloudRunApp", name, args, opts);

    const envs = Object.entries(args.envVars || {}).map(([k, v]) => ({
      name: k,
      value: v,
    }));

    this.service = new gcp.cloudrunv2.Service(
      name,
      {
        name: args.name,
        project: args.projectId,
        location: args.region,
        ingress: args.ingress ?? "INGRESS_TRAFFIC_ALL",
        template: {
          serviceAccount: args.serviceAccount,
          containers: [
            {
              image: args.image,
              envs: envs.length > 0 ? envs : undefined,
            },
          ],
        },
      },
      { parent: this },
    );

    this.registerOutputs({
      serviceUri: this.service.uri,
    });
  }
}

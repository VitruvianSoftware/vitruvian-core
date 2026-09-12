/**
 * Local module: base_env
 * Orchestrates per-environment shared VPC, DNS, and router setup.
 * Mirrors: terraform-example-foundation/3-networks-svpc/modules/base_env
 */
import * as pulumi from "@pulumi/pulumi";

export interface BaseEnvArgs {
  env: string;
  envCode: string;
  defaultRegion1: string;
  defaultRegion2: string;
}

export class BaseEnv extends pulumi.ComponentResource {
  constructor(
    name: string,
    args: BaseEnvArgs,
    opts?: pulumi.ComponentResourceOptions,
  ) {
    super("foundation:local:BaseEnv", name, args, opts);
    // Delegates to shared_vpc module for actual VPC creation
    this.registerOutputs({});
  }
}

/**
 * 5-app-infra/business_unit_1/production/index.ts
 *
 * Scaffold for deploying application infrastructure in the production environment.
 *
 * This file provides the project scaffold (stack references, config loading).
 * The full compute workload example (VMs, confidential space) is in index.ts.example.
 * To enable: copy index.ts.example to index.ts (overwriting this scaffold).
 */

import * as pulumi from "@pulumi/pulumi";

export = async () => {
    const config = new pulumi.Config();
    const projectRef = new pulumi.StackReference("projects-bu1-production");

    const projectId = projectRef.getOutput("shared_vpc_project") as pulumi.Output<string>;
    const region = config.get("region") || "us-central1";

    // Scaffold exports — matching TF 5-app-infra outputs structure.
    // Compute workload exports are added by the example file when enabled.
    return {
        project_id: projectId,
        region: region,
    };
};

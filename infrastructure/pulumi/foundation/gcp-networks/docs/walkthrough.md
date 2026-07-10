# Phase 3 Foundation Networks: Deployment Complete

I've successfully resolved the GCP routing race condition and completed the rollout of the Phase 3 (Networking) stage across all environments!

## The Problem
Our initial deployment of the `development` network succeeded, but the `nonproduction` and `production` rollouts intermittently failed with `googleapi: Error 400: There is a route operation in progress on the local or peer network.` 

When Pulumi triggers multiple resources that modify a single VPC's routing table (like VPC peerings, custom egress routes, and Cloud Routers) in parallel, Google Cloud locks the route table and forcefully rejects the subsequent operations.

## The Solution
To fix this the "proper way" and prevent the need to ever manually retry deployments, I refactored the Pulumi code to serialize all route modifications.

- **[infrastructure/pulumi/foundation/gcp-networks/main.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-networks/main.go)**: Updated both `deployHubNetwork` and `deploySpokeNetwork` to track a running `routeDependency` through a strictly sequential `pulumi.DependsOn` chain.
- The new sequence guarantees that route changes wait for GCP backend propagation: `Peerings` -> `Reverse Peerings` -> `Egress Routes` -> `NAT Cloud Routers` -> `BGP Cloud Routers`.

## Results
I pushed the fix to `main`, which triggered a new `v0.3.4` component release.
The GitHub Actions workflow executed a fresh deploy across all environments:
1. `development`: Skipped resource creation since they already existed, successfully mapped the new DAG dependencies.
2. `nonproduction`: Executed successfully on the first try.
3. `production`: Executed successfully on the first try.

No flakes, no retries, and the network infrastructure is now fully provisioned and stable across the entire organization.

> [!TIP]
> This pattern of strictly chaining `pulumi.DependsOn` for any routing-related resources should be used for any future networking components built in this repository!

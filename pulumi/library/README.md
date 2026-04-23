# Vitruvian Software Pulumi Library

Reusable [ComponentResource](https://www.pulumi.com/docs/concepts/resources/components/) building blocks for Google Cloud Platform infrastructure, available in **Go** and **TypeScript**.

This library provides enterprise-grade, opinionated components that enforce Google Cloud security best practices. Each component wraps one or more GCP resources into a single, well-tested abstraction with sensible defaults.

## Supported Languages

The library currently supports the following languages:

- **[Go](./go/README.md)** - See the Go documentation for installation, usage examples, and development guidelines.
- **[TypeScript](./ts/README.md)** - See the TypeScript documentation for installation, usage examples, and development guidelines.

## Packages

The library provides several core packages across both language implementations:

| Package | Description |
|---------|-------------|
| **Bootstrap** | Core foundation seed project, KMS keys/rings, encrypted state buckets, and base organization policies |
| **Project** | Project factory: creates GCP projects with API enablement, billing association, and automatic default-VPC suppression |
| **Group** | Google Workspace / Cloud Identity group provisioning with structured ownership and dynamic typing |
| **IAM** | Scope-isolated IAM bindings (additive + authoritative) with dedicated constructors per GCP scope: organization, folder, project, service account, and billing account |
| **Policy** | Organization policy constraint enforcement (boolean + list) using the v2 Org Policy API |
| **Logging** | Centralized log export infrastructure with org/folder sinks, internal project sinks, and destinations |
| **Networking** | VPC networks with subnets (secondary ranges, flow logs, Private Google Access), and optional Private Service Access |
| **App** | Cloud Run v2 service deployment with environment variables, custom service accounts, and ingress control |
| **Data** | BigQuery data platform with raw + curated datasets |
| **CI/CD** | Workload Identity Federation (WIF) integrations for external pipelines (GitHub Actions, GitLab CI) and Cloud Build infrastructure |
| **Storage** | Hardened Google Cloud Storage buckets with enforced public access prevention and optional KMS |
| **Security** | Security monitoring components including Cloud Asset Inventory (CAI) monitoring with SCC integration |

## Design Principles

The components across all languages adhere to the following principles:

1. **Scope-Isolated Constructors**: When a component operates across multiple GCP scopes (e.g., IAM at organization, folder, project levels), each scope gets a dedicated constructor with scope-specific arguments.
2. **Sensible Security Defaults**: 
   - `AutoCreateNetwork` defaults to `false` (the default GCP network has overly permissive firewall rules).
   - `PrivateIpGoogleAccess` is always enabled on subnets.
   - `DisableOnDestroy` is `false` for API services (prevents orphaned APIs).
   - Subnets enforce flow logging when `FlowLogs: true` is set.
3. **Component Resources**: Every component is a Pulumi [ComponentResource](https://www.pulumi.com/docs/concepts/resources/components/). This means:
   - Child resources appear grouped under the component in `pulumi stack`
   - The component can be composed into larger abstractions
   - Standard Pulumi resource options (`pulumi.Parent`, `pulumi.DependsOn`, `pulumi.Protect`) work on all components.

## Related

- [Pulumi Example Foundation (Go)](https://github.com/VitruvianSoftware/pulumi_go-example-foundation) — Enterprise GCP foundation in Go that consumes this library
- [Pulumi Example Foundation (TypeScript)](https://github.com/VitruvianSoftware/pulumi_ts-example-foundation) — Enterprise GCP foundation in TypeScript that consumes this library
- [Google Terraform Example Foundation](https://github.com/terraform-google-modules/terraform-example-foundation) — The upstream reference architecture
- [Pulumi ComponentResources](https://www.pulumi.com/docs/concepts/resources/components/) — Pulumi's documentation on component resources

## License

Apache License 2.0 — see [LICENSE](./LICENSE) for details.

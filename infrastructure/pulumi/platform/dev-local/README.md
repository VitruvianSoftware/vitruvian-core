# Pulumi Local Development Environment

[![Pulumi](https://img.shields.io/badge/pulumi-%235C4EE5.svg?style=for-the-badge&logo=pulumi&logoColor=white)](https://www.pulumi.com/)
[![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Lima](https://img.shields.io/badge/lima-local_k8s-blue?style=for-the-badge)](https://lima-vm.org/)
[![Go](https://img.shields.io/badge/go-%2300ADD8.svg?style=for-the-badge&logo=go&logoColor=white)](https://golang.org/)

A Pulumi Go-based toolkit for provisioning and managing essential Kubernetes components for local containerized application development.

## Overview

This directory contains a comprehensive Pulumi implementation written in Go, designed to provision and manage essential Kubernetes components for containerized application development in a local environment (a Lima + k3s cluster). This setup provides a consistent, reproducible way to deploy commonly used infrastructure components that support modern application development workflows.

The Go implementation offers improved type safety, enhanced error handling, and powerful programmatic control over infrastructure deployment compared to the YAML-based approach, while maintaining the same component feature set and configuration flexibility.

## Key Components Available

The configuration allows developers to selectively enable and deploy:

| Component | Description | Status | Default |
|-----------|-------------|--------|---------|
| **Cert Manager** | Automates the management and issuance of TLS certificates | ✅ Active | ✅ Enabled |
| **Istio** | Complete service mesh with Base, CNI, Control Plane, and Ingress Gateway | ✅ Active | ✅ Enabled |
| **OpenTelemetry** | Observability stack with Operator and Collector for metrics, tracing, and logging | ✅ Active | ✅ Enabled | 
| **External Secrets** | Integration with external secret management systems | ✅ Active | ✅ Enabled |
| **CloudNativePG** | Kubernetes operator for PostgreSQL database clusters | ✅ Active | ✅ Enabled |
| **Argo CD** | GitOps continuous delivery tool | ✅ Active | ❌ Disabled |
| **Telepresence** | Local development tool for remote Kubernetes connections | ✅ Active | ❌ Disabled |
| **External DNS** | Automated DNS configuration for Kubernetes services | ✅ Active | ❌ Disabled |
| **Datadog** | Application monitoring and analytics platform | ✅ Active | ❌ Disabled |
| **Monitoring** | Prometheus and Grafana stack for metrics monitoring | ✅ Active | ❌ Disabled |

**Note**: "Active" status means the component is implemented and ready to use. The "Default" column indicates whether the component is enabled by default in the current configuration. Engineers can enable disabled components by setting their respective flags to `"true"` in `Pulumi.local.yaml`.

## Modular Structure

The Pulumi configuration has been organized in a modular way to improve maintainability and readability:

```bash
dev-local/
├── main.go                # Main Go program entry point
├── Pulumi.yaml            # Project configuration
├── Pulumi.local.yaml      # Stack configuration
├── go.mod                 # Go module definition
├── go.sum                 # Go module dependencies
├── COMPONENTS.md          # Detailed component documentation
├── docs/                  # Additional documentation
│   ├── pulumi_helm_best_practices.md # Helm chart best practices
│   ├── pulumi_utilities.md # Utilities documentation
│   └── resources_package.md # Resources package documentation
├── values/                # Helm chart values YAML files
│   ├── cert-manager.yaml  # Cert Manager values
│   ├── external-dns.yaml  # External DNS values
│   ├── external-secrets.yaml # External Secrets values
│   ├── istio.yaml         # Istio values
│   ├── monitoring.yaml    # Prometheus/Grafana values
│   ├── cnpg.yaml          # CloudNativePG values
│   └── datadog.yaml       # Datadog values
└── pkg/                   # Go package directory
    ├── applications/      # Individual component implementations
    │   ├── argocd.go      # Argo CD component
    │   ├── cert_manager.go # Cert Manager component
    │   ├── cnpg.go        # CloudNativePG component
    │   ├── datadog.go     # Datadog component
    │   ├── external_dns.go # External DNS component
    │   ├── external_secrets.go # External Secrets component
    │   ├── external_secrets_store.go # Secret store utilities
    │   ├── ingress.go     # Ingress component
    │   ├── istio.go       # Istio component
    │   ├── monitoring.go  # Monitoring component
    │   ├── opentelemetry.go # OpenTelemetry component
    │   ├── telepresence.go # Telepresence component
    │   └── utils.go       # Shared utilities
    ├── resources/         # Kubernetes resource definitions
    └── utils/             # Utility functions
```

### Helm Values Management

This project uses external YAML files for managing Helm chart values, located in the `values/` directory. This approach offers several benefits:

1. **Separation of Configuration**: Keeps Helm values separate from deployment logic
2. **Improved Maintainability**: Makes it easier to update and maintain values without changing code
3. **Consistency**: Uses the same format and structure across all components
4. **Portability**: Values can be reused with other IaC tools if needed

Each component in `pkg/applications/` automatically loads values from its corresponding YAML file when deployed. Runtime overrides can still be applied when needed.

For more details on our Helm best practices, see [Pulumi Helm Best Practices](./docs/pulumi_helm_best_practices.md).

### Enabling and Disabling Components

This Pulumi setup allows you to easily enable or disable components through configuration:

1. **Update Pulumi.local.yaml**:
   
   The `Pulumi.local.yaml` file contains the configuration for each component:

   ```yaml
   config:
     monorepo:cert_manager_enabled: "true"
     monorepo:opentelemetry_enabled: "true"
     monorepo:istio_enabled: "true"
     monorepo:external_secrets_enabled: "true"
     monorepo:external_dns_enabled: "false"
     monorepo:datadog_enabled: "false"
     monorepo:argocd_enabled: "false"
   ```

   Set a component to `"true"` to enable it or `"false"` to disable it.

### Go-Based Implementation

This Pulumi configuration uses Go as the implementation language, providing several benefits:

1. **Type Safety**: Go's strong typing helps prevent configuration errors.
2. **Better Modularity**: Each component is defined in its own Go file in the `pkg/applications/` directory.
3. **Advanced Logic**: Complex conditional logic can be implemented for component deployments.
4. **Better Testability**: Go code can be tested with standard testing frameworks.
5. **Extended Functionality**: Direct access to the Kubernetes API server when needed.

### Utility Packages

This project provides several utility packages that make component implementation more consistent and efficient:

1. **Configuration Utilities**: Simplifies working with Pulumi configuration by adding type conversion and default value handling.
2. **YAML Utilities**: Streamlines loading and merging of Helm chart values from YAML files.

These utilities help ensure consistent patterns across all components and reduce boilerplate code. For more details, see [Pulumi Utilities Documentation](./docs/pulumi_utilities.md).

### Resources Package

This project also includes a specialized `resources` package that provides high-level abstractions for creating and managing Kubernetes resources:

1. **Helm Chart Deployment**: Standardized Helm chart deployment with value loading, cleanup capabilities, and proper error handling.
2. **Kubernetes Resource Creation**: Simplified creation of namespaces, ConfigMaps, and other Kubernetes resources.
3. **YAML Manifest Deployment**: Easy deployment of raw YAML manifests to Kubernetes.

The resources package serves as an abstraction layer between the raw Pulumi Kubernetes SDK and our application-specific code, promoting consistency and reducing duplication. For more details, see [Resources Package Documentation](./docs/resources_package.md).

### Handling Complex Components

For guidance on implementing components with advanced requirements (like multiple Helm charts, internal dependencies, conditional logic, or raw YAML manifests), please refer to the detailed guide:

- [Contributing Complex IAC Components](../../docs/CONTRIBUTING_COMPLEX_IAC_COMPONENTS.md)

This guide uses the Istio implementation as a case study and references the corresponding `.cursorrules` template for AI development assistance.

### Customizing Components

To customize a component:

1. Edit the relevant component file in the `pkg/applications/` directory
2. Modify the corresponding values YAML file in the `values/` directory
3. Run `pulumi preview` to see the changes
4. Apply the changes with `pulumi up`

For example, to customize the Istio component:

1. Edit `pkg/applications/istio.go` to modify deployment logic
2. Edit `values/istio.yaml` to change Helm values
3. Run `pulumi preview` to verify changes
4. Run `pulumi up` to apply changes

### Adding a New Component

To add a new component:

1. Create a new Go file in the `pkg/applications/` directory
2. Create a new values YAML file in the `values/` directory if needed
3. Add the component initialization to `main.go`
4. Add appropriate configuration options to `Pulumi.local.yaml`
5. Preview and apply the changes

For example, to add a new component called "example-component":

1. Create `pkg/applications/example_component.go`
2. Create `values/example-component.yaml` with Helm values
3. Update `main.go` to include the new component
4. Add `monorepoe:example_component_enabled: "true"` to `Pulumi.local.yaml`
5. Run `pulumi preview` and `pulumi up`

## Getting Started

### Prerequisites

- [Bazel](https://bazel.build/) (via the repo's `bazelisk`) — the entry point for every command below.
- [Pulumi CLI](https://www.pulumi.com/docs/install/) and Go — Pulumi compiles `main.go`; `bazel run //infrastructure/pulumi/platform/dev-local:setup` checks both.
- A local **Lima + k3s** cluster (provisioned with [devx](https://github.com/VitruvianSoftware/devx)) whose kubeconfig context is named `default` — the program's `kubernetes_context` default (override via `monorepo:kubernetes_context`).
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) pointed at that cluster.

### Quick Start

Drive the project through the repo's Bazel wrappers — they set `GOWORK=off` for this
standalone module. Any bare `pulumi <verb>` shown elsewhere in this README is shorthand
for `bazel run //infrastructure/pulumi/platform/dev-local:<verb> -- <args>`. See the
[infrastructure user guide](../../../docs/infrastructure/user-guide.md) for the full
workflow. (The committed `mise.toml` is an optional convenience that pins the Go/Pulumi
versions and sets `KUBECONFIG`.)

1. **Use the local backend.** dev-local keeps state locally — there's nothing durable
   to store remotely — so log into the local backend and select the `local` stack once:

   ```bash
   pulumi login --local
   pulumi stack select local   # first time: pulumi stack init local
   ```

2. **Point at the cluster.** The Kubernetes provider uses the `default` context from
   your active `KUBECONFIG`. `devx` actions inject this automatically; otherwise export
   `KUBECONFIG` to the Lima/k3s cluster's kubeconfig before running.

3. **Choose components.** Copy `Pulumi.example.yaml` to the git-ignored
   `Pulumi.local.yaml` and toggle `monorepo:<name>_enabled` flags, or set them via the
   wrapper:

   ```bash
   bazel run //infrastructure/pulumi/platform/dev-local:config -- set monorepo:istio_enabled true
   ```

4. **Preview, then deploy:**

   ```bash
   bazel run //infrastructure/pulumi/platform/dev-local:preview
   bazel run //infrastructure/pulumi/platform/dev-local:up
   ```

   For non-interactive runs (CI/CD), see [Non-Interactive Pulumi Deployments](./docs/pulumi_non_interactive_deployments.md).

5. **Verify:**

   ```bash
   kubectl get pods --all-namespaces
   ```

6. **Clean up when done:**

   ```bash
   bazel run //infrastructure/pulumi/platform/dev-local:destroy
   ```

## Deployed Components Details

For a comprehensive guide to all the components available and their configuration details, see the [COMPONENTS.md](./docs/COMPONENTS.md) file.

### Cert Manager

**Status**: ✅ Active
**Version**: v1.17.0
**Namespace**: cert-manager

Cert Manager provides automated certificate management capabilities in Kubernetes:
- Automates the issuance and renewal of TLS certificates
- Supports multiple issuers including Let's Encrypt, Vault, and self-signed certificates
- Simplifies certificate management for Kubernetes services and ingresses

### OpenTelemetry

**Status**: ✅ Active  
**Components**:
- OpenTelemetry Operator (v0.79.0)
- OpenTelemetry Collector (v0.79.0)
**Namespace**: opentelemetry

The OpenTelemetry deployment includes:
- **OpenTelemetry Operator**: Manages OpenTelemetry Collector instances and instrumentation
- **OpenTelemetry Collector**: Collects, processes, and exports telemetry data
- Support for collecting metrics, traces, and logs from applications
- Integration with various backends and observability tools

### Istio

**Status**: ✅ Active  
**Version**: 1.23.3  
**Components**:
- Istio Base
- Istio CNI
- Istio Control Plane (istiod)
- Istio Ingress Gateway
**Namespace**: istio-system

The complete Istio deployment provides:
- **Service Mesh Capabilities**: Traffic management, security, and observability
- **Istio CNI**: Network management without privileged init containers
- **Istio Control Plane**: Core service mesh functionality
- **Istio Ingress Gateway**: External traffic management with:
  - HTTP port: 80 (targeting 8080)
  - HTTPS port: 443 (targeting 8443)
  - Service type: ClusterIP (for local development)

The Ingress Gateway can be accessed locally through port-forwarding:
```bash
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

## External Secrets and External DNS

The Pulumi configuration includes External Secrets (version 0.14.4) and External DNS (version 1.15.0) Helm charts, matching the versions used in the terraform_dev_local configuration.

### External Secrets Operator

External Secrets Operator is installed with the following configuration:
- Installs CRDs
- Creates ClusterExternalSecret and ClusterSecretStore CRDs
- Creates a service account for the operator
- Disables webhook and cert controller for local development

**Note:** With the current configuration, External Secrets Operator is enabled (`external_secrets_enabled: "true"`), but no secret stores will be created since both `external_dns_enabled` and `datadog_enabled` are set to `"false"`.

### External DNS

External DNS is configured to:
- Use Cloudflare as the provider
- Pull API token from a Kubernetes secret (cf-secret)
- Use bluecentre-dev as the TXT owner ID
- Sync records with a 30-minute interval
- Only process resources with the annotation `external-dns.alpha.kubernetes.io/sync-enabled: "true"`
- Monitor istio-gateway resources for DNS entries

**Note:** External DNS is currently disabled in the configuration (`external_dns_enabled: "false"`).

### Manual Post-Deployment Steps

If you decide to enable External DNS (`external_dns_enabled: "true"`), you would need to manually create the following resources after deployment:

1. A ClusterSecretStore to serve as a fake secret provider:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: external-secret-cluster-fake-secrets
  namespace: external-secrets
spec:
  provider:
    fake:
      data:
      - key: "CLOUDFLARE_API_TOKEN"
        value: "REPLACE_WITH_CLOUDFLARE_API_TOKEN"
        version: "v1"
```

2. An ExternalSecret to retrieve the Cloudflare API token:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cf-external-secret
  namespace: external-dns
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: external-secret-cluster-fake-secrets
  target:
    name: cf-secret
    creationPolicy: Owner
    template:
      metadata:
        labels:
          service: external-dns
        annotations:
          reloader.stakater.com/match: "true"
  data:
    - secretKey: cloudflare-api-key
      remoteRef:
        key: CLOUDFLARE_API_TOKEN
        version: v1
```

These resources can be applied using `kubectl apply -f <filename>` after enabling and deploying the External DNS component.

Alternatively, you would use the provided post-deployment script after enabling the component:

```bash
# First update the configuration and deploy with Pulumi
# Edit Pulumi.local.yaml to set external_dns_enabled: "true"
pulumi up

# Then run the post-deployment script
./post-deploy.sh
```

The script will create the necessary custom resources for external-secrets and external-dns integration.

### Enabling Components in Your Configuration

To enable External DNS or Datadog integration with External Secrets, update the `Pulumi.local.yaml` file:

```yaml
config:
  # Enable External DNS integration (will create Cloudflare secret store)
  monorepo:external_dns_enabled: "true"
  
  # Enable Datadog integration (will create Datadog secret store)
  monorepo:datadog_enabled: "true"
```

Then run `pulumi up` to apply the changes.

## Redis for Istio Rate Limiting

The Bitnami Redis Helm chart is included to support rate limiting in Istio and provide Redis services for applications. It is deployed in a dedicated `redis` namespace with multi-tenant capabilities.

### Usage

1. Enable Redis by setting `redis_enabled` to `"true"` in `Pulumi.local.yaml`
2. Apply the configuration with `pulumi up`

Redis will be deployed in the dedicated `redis` namespace and configured for use with both Istio's rate limiting service and as a general-purpose Redis instance for applications.

### Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| redis_enabled | Enable or disable Redis deployment | "false" |
| redis_password | Password for Redis authentication | "redis-password" |

### Connecting to Redis

Application developers can connect to Redis using:

```bash
# Host and port configuration
REDIS_HOST=redis-master.redis.svc.cluster.local
REDIS_PORT=6379

# Test connection to Redis
kubectl exec -it -n redis deploy/redis-master -- redis-cli -a $(kubectl get secret -n redis redis -o jsonpath="{.data.redis-password}" | base64 --decode)
```

### Multi-tenant Usage

The Redis deployment includes:
- Network policies allowing connections from all namespaces
- Appropriate security contexts for secure multi-tenant usage
- High availability with 1 master and 2 replicas
- AOF persistence enabled for better durability

### Testing Rate Limiting

To verify Redis is working with Istio rate limiting:

```bash
# Test rate limiting functionality in the template-fastapi-app
skaffold verify -m template-fastapi-app -p istio-rate-limit
```
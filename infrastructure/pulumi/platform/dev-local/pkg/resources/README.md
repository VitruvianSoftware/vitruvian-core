# Resources

## Overview
Component package providing implementation for `infrastructure/pulumi/platform/dev-local/pkg/resources`.

## Interface
- `[helm.go:HelmChartConfig]`
- `[helm.go:DeployHelmChart]`
- `[helm.go:RunCommandResourceConfig]`
- `[helm.go:CreateRunCommandResource]`
- `[kubernetes.go:NamespaceConfig]`
- `[kubernetes.go:CreateNamespace]`
- `[kubernetes.go:ConfigMapConfig]`
- `[kubernetes.go:CreateConfigMap]`
- `[manifest.go:K8sManifestConfig]`
- `[manifest.go:CreateK8sManifest]`
- `[namespace.go:K8sNamespaceConfig]`
- `[namespace.go:CreateK8sNamespace]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //infrastructure/pulumi/platform/dev-local/pkg/resources/...`

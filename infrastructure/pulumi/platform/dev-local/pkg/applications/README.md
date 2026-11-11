# Applications

## Overview
Component package providing implementation for `infrastructure/pulumi/platform/dev-local/pkg/applications`.

## Interface
- `[argocd.go:DeployArgoCD]`
- `[cert_manager.go:CertManagerCRDs]`
- `[cert_manager.go:DeployCertManager]`
- `[cnpg.go:CNPGCRDs]`
- `[cnpg.go:DeployCloudNativePGOperator]`
- `[cnpg.go:DeployCnpgCluster]`
- `[database.go:DeployDatabase]`
- `[datadog.go:DeployDatadog]`
- `[external_dns.go:DeployExternalDNS]`
- `[external_secrets.go:ExternalSecretsCRDs]`
- `[external_secrets.go:ExternalSecretsWebhooks]`
- `[external_secrets.go:DeployExternalSecrets]`
- `[external_secrets_store.go:DeployExternalSecretsStore]`
- `[grafana.go:DeployGrafana]`
- `[ingress.go:DeployIngressController]`
- `[istio.go:DeployIstio]`
- `[k3s_ha.go:DeployK3sHA]`
- `[longhorn.go:DeployLonghorn]`
- `[minio.go:DeployMinio]`
- `[mongodb.go:ApplicationDeployment]`

## Invariants
- [external_secrets.go:244]: `// even if the ApplyT block encounters an error. Robust error handling might ...`

## Side Effects
- [argocd.go:91]: `"p, role:org-admin, exec, create, */*, allow\n"`
- [external_dns.go:82]: `// Create an ExternalSecret to fetch Cloudflare API token`
- [grafana.go:190]: `"endpointURL":     "http://minio.minio.svc.cluster.local:9000",`
- [istio.go:199]: `name: envoy.filters.http.ratelimit`
- [istio.go:201]: `"@type": type.googleapis.com/envoy.extensions.filters.http.ratelimit.v3.RateL...`
- [monitoring.go:149]: `ctx.Export("prometheusUrl", pulumi.String("http://prometheus-server."+namespa...`
- [tempo.go:116]: `"remoteWriteUrl": "http://prometheus-server.monitoring.svc.cluster.local:80/a...`

## Verification
- Run: `bazel test //infrastructure/pulumi/platform/dev-local/pkg/applications/...`

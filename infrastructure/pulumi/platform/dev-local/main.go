// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package main

import (
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	// config package might not be needed anymore if utils.NewConfig handles it
	// "github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/dev-local/pkg/applications"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/dev-local/pkg/utils" // Import utils package
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		// Create PulumiConfig wrapper - this handles loading config
		pulumiConf := utils.NewConfig(ctx) // Correct way to initialize

		// Create a Kubernetes provider instance
		k8sContext := pulumiConf.GetString("kubernetes_context", "default") // Lima/k3s kubeconfig context; override via monorepo:kubernetes_context
		k8sProvider, err := kubernetes.NewProvider(ctx, "k8s-provider", &kubernetes.ProviderArgs{
			Context: pulumi.String(k8sContext),
		})
		if err != nil {
			return err
		}

		// Get configuration values using the wrapper
		certManagerEnabled := pulumiConf.GetBool("cert_manager_enabled", false)
		externalSecretsEnabled := pulumiConf.GetBool("external_secrets_enabled", false)
		externalDnsEnabled := pulumiConf.GetBool("external_dns_enabled", false)
		opentelemetryEnabled := pulumiConf.GetBool("opentelemetry_enabled", false)
		monitoringEnabled := pulumiConf.GetBool("monitoring_enabled", false)
		grafanaEnabled := pulumiConf.GetBool("grafana_enabled", false)
		datadogEnabled := pulumiConf.GetBool("datadog_enabled", false)
		istioEnabled := pulumiConf.GetBool("istio_enabled", false)
		redisEnabled := pulumiConf.GetBool("redis_enabled", false)
		cnpgEnabled := pulumiConf.GetBool("cnpg_enabled", false)
		mongodbEnabled := pulumiConf.GetBool("mongodb_enabled", false)
		databaseEnabled := pulumiConf.GetBool("database_enabled", false)
		ingressEnabled := pulumiConf.GetBool("ingress_controller_enabled", false)
		argocdEnabled := pulumiConf.GetBool("argocd_enabled", false)
		telepresenceEnabled := pulumiConf.GetBool("telepresence_enabled", false)
		longhornEnabled := pulumiConf.GetBool("longhorn_enabled", false)
		minioEnabled := pulumiConf.GetBool("minio_enabled", false)

		// Setup base components
		var certManagerRelease pulumi.Resource

		// K3s HA (traefik-ha-config) — code retained but DISABLED via the
		// k3s_ha_enabled flag (now ArgoCD-managed in
		// gitops/argocd/platform/platform-config). Re-enable the flag to bring it
		// back under Pulumi.
		if err := applications.DeployK3sHA(ctx, k8sProvider); err != nil {
			return err
		}

		if longhornEnabled {
			if _, err := applications.DeployLonghorn(ctx, k8sProvider); err != nil {
				return err
			}
		}

		var minioRelease pulumi.Resource
		if minioEnabled {
			var minioErr error
			minioRelease, minioErr = applications.DeployMinio(ctx, k8sProvider)
			if minioErr != nil {
				return minioErr
			}
		}

		if certManagerEnabled {
			var certManagerErr error
			certManagerRelease, certManagerErr = applications.DeployCertManager(ctx, k8sProvider)
			if certManagerErr != nil {
				return certManagerErr
			}
		}

		if externalSecretsEnabled {
			// Deploy External Secrets first
			if err := applications.DeployExternalSecrets(ctx, k8sProvider); err != nil {
				return err
			}

			// Create a delay to ensure the webhooks are ready
			// _, err = applications.AddDelay(ctx, 30*time.Second)
			// if err != nil {
			// 	return err
			// }

			// Deploy the ClusterSecretStore after ExternalSecrets is deployed
			// if err := applications.DeployExternalSecretsStore(ctx, k8sProvider); err != nil {
			// 	return err
			// }
		}

		// Deploy external-dns (it will handle external-secrets dependency internally)
		if externalDnsEnabled {
			if err := applications.DeployExternalDNS(ctx, k8sProvider); err != nil {
				return err
			}
		}

		// Deploy Prometheus
		if monitoringEnabled {
			if err := applications.DeployPrometheus(ctx, k8sProvider); err != nil {
				return err
			}
		}

		// OpenTelemetry setup
		if opentelemetryEnabled {
			if err := applications.DeployOpenTelemetry(ctx, k8sProvider, certManagerRelease); err != nil {
				return err
			}

			// if err := applications.DeployMonitoringStack(ctx, k8sProvider); err != nil {
			// 	return err
			// }
		}

		// Datadog setup
		if datadogEnabled {
			if _, err := applications.DeployDatadog(ctx, k8sProvider); err != nil {
				return err
			}
		}

		// Service mesh setup
		if istioEnabled {
			// Get Redis configuration since Istio might need it for rate limiting
			var redisResource pulumi.Resource

			// If Redis is enabled, deploy it before Istio
			if redisEnabled {
				var err error
				redisResource, err = applications.DeployRedis(ctx, k8sProvider)
				if err != nil {
					return err
				}
			}

			// Deploy Istio with Redis resource (will be nil if Redis is disabled)
			if err := applications.DeployIstio(ctx, k8sProvider, redisResource); err != nil {
				return err
			}
		}

		// Redis setup for application usage (if not already deployed for Istio)
		if redisEnabled && !istioEnabled {
			if _, err := applications.DeployRedis(ctx, k8sProvider); err != nil {
				return err
			}
		}

		// CloudNativePG setup
		var cnpgOperatorRelease pulumi.Resource
		grafanaHaEnabled := pulumiConf.GetBool("grafana_ha_enabled", false)

		if cnpgEnabled || grafanaHaEnabled {
			// First, deploy the operator itself
			var opErr error
			cnpgOperatorRelease, opErr = applications.DeployCloudNativePGOperator(ctx, k8sProvider)
			if opErr != nil {
				return opErr
			}

			// Deploy main CNPG cluster if enabled
			if cnpgEnabled {
				if _, clusterErr := applications.DeployCnpgCluster(ctx, k8sProvider, cnpgOperatorRelease); clusterErr != nil {
					return clusterErr
				}
			}
		}

		// Deploy Grafana (with optional HA using CNPG)
		if grafanaEnabled {
			if _, err := applications.DeployGrafana(ctx, k8sProvider, cnpgOperatorRelease, minioRelease); err != nil {
				return err
			}
		}

		// MongoDB setup for application usage
		if mongodbEnabled {
			if _, err := applications.DeployMongoDB(ctx, k8sProvider); err != nil {
				return err
			}
		}

		// Database setup
		if databaseEnabled {
			if err := applications.DeployDatabase(ctx, k8sProvider); err != nil {
				return err
			}
		}

		// Ingress setup
		if ingressEnabled {
			if err := applications.DeployIngressController(ctx, k8sProvider); err != nil {
				return err
			}
		}

		// GitOps setup
		if argocdEnabled {
			if err := applications.DeployArgoCD(ctx, k8sProvider); err != nil {
				return err
			}
		}

		// Deploy other components that don't depend on external-secrets
		if telepresenceEnabled {
			if err := applications.DeployTelepresence(ctx, k8sProvider); err != nil {
				return err
			}
		}

		return nil
	})
}

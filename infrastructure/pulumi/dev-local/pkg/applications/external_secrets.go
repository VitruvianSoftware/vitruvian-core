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

package applications

import (
	"fmt"

	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/yaml"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/resources"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/utils"
)

// ExternalSecretsCRDs is a list of all external-secrets CRDs
var ExternalSecretsCRDs = []string{
	"clustersecretstores.external-secrets.io",
	"externalsecrets.external-secrets.io",
	"secretstores.external-secrets.io",
	"clusterexternalsecrets.external-secrets.io",
	"pushsecrets.external-secrets.io",
	"fakes.generators.external-secrets.io",
}

// ExternalSecretsWebhooks is a list of all external-secrets webhooks
var ExternalSecretsWebhooks = []string{
	"externalsecret-validate",
	"secretstore-validate",
}

// DeployExternalSecrets sets up the external-secrets operator
func DeployExternalSecrets(ctx *pulumi.Context, provider *kubernetes.Provider) error {
	// Get configuration
	conf := utils.NewConfig(ctx)
	enabled := conf.GetBool("external_secrets_enabled", false)
	version := conf.GetString("external_secrets_version", "0.14.4")
	cloudflareApiToken := conf.GetString("cloudflare_api_token", "REPLACE_WITH_CLOUDFLARE_API_TOKEN")
	datadogApiKey := conf.GetString("datadog_api_key", "REPLACE_WITH_DATADOG_API_KEY")
	datadogAppKey := conf.GetString("datadog_app_key", "REPLACE_WITH_DATADOG_APP_KEY")
	// Get CNPG credentials from config
	cnpgEnabled := conf.GetBool("cnpg_enabled", false)
	cnpgAppDbUser := conf.GetString("cnpg_app_db_user", "app_user")
	cnpgAppDbPasswordOutput := conf.RequireSecret(ctx, "cnpg_app_db_password")

	if !enabled {
		ctx.Log.Info("External Secrets is disabled, skipping deployment", nil)
		return nil
	}

	// Create namespace
	namespace := conf.GetString("external_secrets:namespace", "external-secrets")
	ns, err := resources.CreateK8sNamespace(ctx, provider, resources.K8sNamespaceConfig{
		Name:           namespace,
		RetainOnDelete: true, // handed off to ArgoCD; retain ns on external_secrets_enabled=false
	})
	if err != nil {
		return err
	}

	// Phase 1: Deploy CRDs
	externalSecretsCrds, err := yaml.NewConfigFile(
		ctx, "external-secrets-crds",
		&yaml.ConfigFileArgs{
			File: "crds/external-secrets.crds.yaml",
		}, pulumi.Provider(provider),
		// Retain on cutover: deleting these CRDs cascades every ClusterSecretStore /
		// ExternalSecret. They must survive when external_secrets_enabled flips false.
		pulumi.RetainOnDelete(true),
	)
	if err != nil {
		return err
	}

	haEnabled := conf.GetBool("high_availability_enabled", false)
	replicas := 1
	if haEnabled {
		replicas = 2
	}

	// Deploy External Secrets Helm chart
	externalSecrets, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "external-secrets",
		Namespace:       namespace,
		ChartName:       "external-secrets",
		RepositoryURL:   "https://charts.external-secrets.io",
		Version:         version,
		CreateNamespace: false,
		SkipCRDs:        true,
		ValuesFile:      "external-secrets",
		Values: map[string]interface{}{
			"replicaCount": replicas,
			"installCRDs":  false,
			// Hard spread + PDB for the (leader-elected) core controller; the
			// webhook/certController workloads are disabled in this install.
			"affinity": hostnameAntiAffinity(map[string]interface{}{
				"app.kubernetes.io/name": "external-secrets",
			}),
			"podDisruptionBudget": map[string]interface{}{
				"enabled":      true,
				"minAvailable": 1,
			},
			"webhook": map[string]interface{}{
				"create": false,
			},
			"certController": map[string]interface{}{
				"create": false,
			},
		},
		Wait:           false,
		Timeout:        600,
		CleanupCRDs:    false, // CRDs managed by Phase 1
		CRDsToCleanup:  ExternalSecretsCRDs,
		RetainOnDelete: true, // handed off to ArgoCD (gitops/argocd/platform/external-secrets)
	}, pulumi.DependsOn([]pulumi.Resource{ns, externalSecretsCrds}))
	if err != nil {
		return err
	}

	// Create a provider that depends on the external-secrets chart to ensure CRDs are ready
	esProvider, err := kubernetes.NewProvider(ctx, "external-secrets-provider", &kubernetes.ProviderArgs{
		// No need to specify kubeconfig, it should be inherited or use default context
	}, pulumi.DependsOn([]pulumi.Resource{externalSecrets}))
	if err != nil {
		return fmt.Errorf("failed to create external-secrets dependent provider: %w", err)
	}

	// Create fake secret stores using the dependent provider

	// Cloudflare Fake Store
	externalDNS := conf.GetBool("external_dns_enabled", false)
	if externalDNS {
		_, err = resources.CreateK8sManifest(ctx, esProvider, resources.K8sManifestConfig{
			Name:           "external-secrets-fake-cloudflare-secret-store",
			RetainOnDelete: true, // shared store (external-dns cf-secret depends on it); survive cutover
			YAML: fmt.Sprintf(`apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: external-secret-cluster-fake-cloudflare-secrets
  namespace: %s
spec:
  provider:
    fake:
      data:
      - key: "CLOUDFLARE_API_TOKEN"
        value: "%s"
        version: "v1"
`, namespace, cloudflareApiToken),
		})
		if err != nil {
			return fmt.Errorf("failed to create fake cloudflare secret store: %w", err)
		}
	}

	// Datadog Fake Store
	datadogEnabled := conf.GetBool("datadog_enabled", false)
	if datadogEnabled {
		_, err = resources.CreateK8sManifest(ctx, esProvider, resources.K8sManifestConfig{
			Name:           "external-secrets-fake-datadog-secret-store",
			RetainOnDelete: true, // uniform with cloudflare/cnpg stores; survive cutover if datadog is ever enabled
			YAML: fmt.Sprintf(`apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: external-secret-cluster-fake-datadog-secrets
  namespace: %s
spec:
  provider:
    fake:
      data:
      - key: "DATADOG_API_KEY"
        value: "%s"
        version: "v1"
      - key: "DATADOG_APP_KEY"
        value: "%s"
        version: "v1"
      - key: "token"
        value: "%s"
        version: "v1"
`, namespace, datadogApiKey, datadogAppKey, datadogApiKey),
		})
		if err != nil {
			return fmt.Errorf("failed to create fake datadog secret store: %w", err)
		}
	}

	// CNPG Fake Store (Only if CNPG is enabled)
	if cnpgEnabled {
		// Create the ClusterSecretStore within the ApplyT callback
		cnpgAppDbPasswordOutput.ApplyT(func(password string) (pulumi.Resource, error) {
			cnpgStoreYaml := fmt.Sprintf(`apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: external-secret-cluster-fake-cnpg-secrets
  namespace: %s
spec:
  provider:
    fake:
      data:
      - key: "username"
        value: "%s"
        version: "v1"
      - key: "password"
        value: "%s"
        version: "v1"
`, namespace, cnpgAppDbUser, password)

			// Use the base yaml.NewConfigGroup directly here, passing the provider
			manifest, err := yaml.NewConfigGroup(ctx, "external-secret-cluster-fake-cnpg-secrets", &yaml.ConfigGroupArgs{
				YAML: []string{cnpgStoreYaml},
			}, pulumi.Provider(esProvider), pulumi.RetainOnDelete(true)) // retain: cnpg secret depends on this store
			if err != nil {
				ctx.Log.Error(fmt.Sprintf("Failed to create fake CNPG secret store: %v", err), nil)
				return nil, fmt.Errorf("failed to create fake CNPG secret store: %w", err)
			}
			ctx.Log.Info("Fake CNPG secret store created successfully", nil)
			return manifest, nil
		})
		// Note: Error handling within ApplyT is complex. The main function might proceed
		// even if the ApplyT block encounters an error. Robust error handling might require
		// collecting errors and checking at the end, but for this case, logging should suffice.
	}

	// Export External Secrets information
	ctx.Export("externalSecretsNamespace", pulumi.String(namespace))

	return nil // Return nil on success
}

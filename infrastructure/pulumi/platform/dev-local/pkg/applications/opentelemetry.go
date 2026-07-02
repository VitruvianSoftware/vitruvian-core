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
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/dev-local/pkg/resources"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/dev-local/pkg/utils"
)

// DeployOpenTelemetry deploys the OpenTelemetry Operator and Collector
func DeployOpenTelemetry(ctx *pulumi.Context, provider *kubernetes.Provider, certManagerRelease pulumi.Resource) error {
	// Get configuration
	conf := utils.NewConfig(ctx)
	version := conf.GetString("opentelemetry_version", "0.79.0")

	// Create namespace
	namespace := conf.GetString("opentelemetry:namespace", "opentelemetry")

	// List of OpenTelemetry CRDs to clean up
	otelCRDs := []string{
		"opentelemetrycollectors.opentelemetry.io",
		"instrumentations.opentelemetry.io",
	}

	// Deploy OpenTelemetry Operator with CRD management
	// Add certManagerRelease as a dependency to ensure cert-manager is installed first
	// dependencyResources := []pulumi.Resource{ns}
	dependencyResources := []pulumi.Resource{}
	if certManagerRelease != nil {
		dependencyResources = append(dependencyResources, certManagerRelease)
	}

	haEnabled := conf.GetBool("high_availability_enabled", false)
	replicas := 1
	if haEnabled {
		replicas = 2
	}

	otelOperator, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "opentelemetry-operator",
		Namespace:       namespace,
		ChartName:       "opentelemetry-operator",
		RepositoryURL:   "https://open-telemetry.github.io/opentelemetry-helm-charts",
		Version:         version,
		CreateNamespace: true,
		ValuesFile:      "opentelemetry-operator",
		Values: map[string]interface{}{
			"replicaCount": replicas,
			"affinity": hostnameAntiAffinity(map[string]interface{}{
				"app.kubernetes.io/name": "opentelemetry-operator",
			}),
			// CAUTION: this chart's PDB key is `pdb`, not `podDisruptionBudget`.
			"pdb": map[string]interface{}{
				"create":       true,
				"minAvailable": 1,
			},
		},
		Wait:           true, // Set to true to wait for completion
		Timeout:        600,
		CleanupCRDs:    false,
		CRDsToCleanup:  otelCRDs,
		RetainOnDelete: true, // handed off to ArgoCD (gitops/argocd/platform/opentelemetry-operator); retain on flag-off to avoid helm-uninstall + namespace cascade
	}, pulumi.DependsOn(dependencyResources))
	if err != nil {
		return err
	}

	// Deploy Tempo for trace storage
	tempoRelease, err := DeployTempo(ctx, provider, namespace)
	if err != nil {
		return err
	}

	// Deploy OpenTelemetry Collector with CRD management
	collectorValues := map[string]interface{}{
		"replicaCount": replicas,
		"affinity": hostnameAntiAffinity(map[string]interface{}{
			"app.kubernetes.io/name": "opentelemetry-collector",
		}),
		// Rendered only in mode=deployment (which this install uses).
		"podDisruptionBudget": map[string]interface{}{
			"enabled":      true,
			"minAvailable": 1,
		},
	}

	// The Helm chart blocks replicas > 1 if clusterMetrics is enabled
	if replicas > 1 {
		collectorValues["presets"] = map[string]interface{}{
			"clusterMetrics": map[string]interface{}{
				"enabled": false,
			},
		}
	}

	_, err = resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "opentelemetry-collector",
		Namespace:       namespace,
		ChartName:       "opentelemetry-collector",
		RepositoryURL:   "https://open-telemetry.github.io/opentelemetry-helm-charts",
		Version:         version,
		CreateNamespace: false,
		ValuesFile:      "opentelemetry-collector",
		Values:          collectorValues,
		Wait:            true,
		Timeout:         600,
		CleanupCRDs:     false,
		CRDsToCleanup:   otelCRDs,
		RetainOnDelete:  true, // handed off to ArgoCD (gitops/argocd/platform/opentelemetry-collector)
	}, pulumi.DependsOn([]pulumi.Resource{otelOperator, tempoRelease}))

	// Export OpenTelemetry information
	ctx.Export("opentelemetryNamespace", pulumi.String(namespace))

	return err
}

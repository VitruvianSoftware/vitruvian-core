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

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/resources"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/utils"
)

// DeployMinio installs Minio for S3-compatible object storage
func DeployMinio(ctx *pulumi.Context, provider *kubernetes.Provider) (pulumi.Resource, error) {
	conf := utils.NewConfig(ctx)
	haEnabled := conf.GetBool("high_availability_enabled", false)

	// MinIO needs 4 nodes/drives for true distributed mode with erasure coding
	mode := "standalone"
	replicas := 1
	if haEnabled {
		mode = "distributed"
		replicas = 4
	}

	namespace := "minio"
	ns, err := resources.CreateK8sNamespace(ctx, provider, resources.K8sNamespaceConfig{
		Name: namespace,
	})
	if err != nil {
		return nil, err
	}

	release, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "minio",
		Namespace:       namespace,
		ChartName:       "minio",
		RepositoryURL:   "https://charts.min.io/",
		Version:         "5.4.0",
		CreateNamespace: false,
		Values: map[string]interface{}{
			"mode":         mode,
			"replicas":     replicas,
			"rootUser":     "admin",
			"rootPassword": "minio-admin-password",
			"buckets": []interface{}{
				map[string]interface{}{
					"name":   "tempo",
					"policy": "none",
					"purge":  false,
				},
				map[string]interface{}{
					"name":   "grafana-db-backups", // CNPG WAL archive + base backups for the Grafana HA cluster
					"policy": "none",
					"purge":  false,
				},
			},
			// Longhorn (replicated, relocatable): with node-pinned local-path a
			// single node loss could remove 2 of 4 erasure-set drives (below
			// write quorum). See docs/infrastructure/resilience-catalog.md.
			"persistence": map[string]interface{}{
				"enabled":      true,
				"storageClass": "longhorn",
				"size":         "10Gi",
			},
			// No arch nodeSelector: the image is multi-arch and only 3 arm64
			// nodes exist — 4 drives need 4 distinct nodes for the required
			// anti-affinity below to be schedulable.
			"affinity": hostnameAntiAffinity(map[string]interface{}{
				"app": "minio",
			}),
			// minio chart 5.4.0 only supports maxUnavailable (minAvailable is
			// silently ignored by its PDB template).
			"podDisruptionBudget": map[string]interface{}{
				"enabled":        true,
				"maxUnavailable": 1,
			},
			"resources": map[string]interface{}{
				"requests": map[string]interface{}{
					"memory": "512Mi",
				},
			},
		},
		Wait:    false,
		Timeout: 600,
	}, pulumi.DependsOn([]pulumi.Resource{ns}))
	if err != nil {
		return nil, err
	}

	ctx.Log.Info("MinIO Helm chart deployed successfully.", nil)
	return release, nil
}

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
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/resources"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/utils"
)

// DeployTempo installs the Grafana Tempo Helm chart in single-binary mode
func DeployTempo(ctx *pulumi.Context, provider *kubernetes.Provider, namespace string) (pulumi.Resource, error) {
	conf := utils.NewConfig(ctx)
	haEnabled := conf.GetBool("high_availability_enabled", false)
	minioEnabled := conf.GetBool("minio_enabled", false)
	replicas := 1
	var affinity map[string]interface{}
	
	if haEnabled && minioEnabled {
		replicas = 2
		affinity = map[string]interface{}{
			"podAntiAffinity": map[string]interface{}{
				"requiredDuringSchedulingIgnoredDuringExecution": []interface{}{
					map[string]interface{}{
						"labelSelector": map[string]interface{}{
							"matchLabels": map[string]interface{}{
								"app.kubernetes.io/name": "tempo",
							},
						},
						"topologyKey": "kubernetes.io/hostname",
					},
				},
			},
		}
	} else {
		affinity = map[string]interface{}{}
	}

	var storageBackend string
	var traceStorageConfig map[string]interface{}

	if minioEnabled {
		storageBackend = "s3"
		traceStorageConfig = map[string]interface{}{
			"backend": "s3",
			"s3": map[string]interface{}{
				"bucket":     "tempo",
				"endpoint":   "minio.minio.svc.cluster.local:9000",
				"access_key": "admin",
				"secret_key": "minio-admin-password",
				"insecure":   true,
			},
		}
	} else {
		storageBackend = "local"
		traceStorageConfig = map[string]interface{}{
			"backend": "local",
			"local": map[string]interface{}{
				"path": "/var/tempo/traces",
			},
		}
	}

	release, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "tempo",
		Namespace:       namespace,
		ChartName:       "tempo",
		RepositoryURL:   "https://grafana.github.io/helm-charts",
		Version:         "1.24.4",
		CreateNamespace: false,
		Values: map[string]interface{}{
			"replicas": replicas,
			"affinity": affinity,
			"persistence": map[string]interface{}{
				"enabled": storageBackend == "local",
				"size":    "2Gi",
			},
			"tempo": map[string]interface{}{
				"storage": map[string]interface{}{
					"trace": traceStorageConfig,
				},
				"overrides": map[string]interface{}{
					"defaults": map[string]interface{}{
						"metrics_generator": map[string]interface{}{
							"processors": []interface{}{"service-graphs", "span-metrics"},
						},
					},
				},
				"metricsGenerator": map[string]interface{}{
					"enabled":        true,
					"remoteWriteUrl": "http://prometheus-server.monitoring.svc.cluster.local:80/api/v1/write",
					"registry": map[string]interface{}{
						"external_labels": map[string]interface{}{
							"source": "tempo",
						},
					},
					"processor": map[string]interface{}{
						"span_metrics": map[string]interface{}{
							"enabled": true,
						},
						"service_graphs": map[string]interface{}{
							"enabled": true,
						},
					},
				},
			},
		},
		Wait:    false,
		Timeout: 600,
	})

	if err != nil {
		ctx.Log.Error("Failed to deploy Tempo Helm chart.", &pulumi.LogArgs{Resource: release})
		return nil, fmt.Errorf("failed to deploy tempo: %w", err)
	}

	ctx.Log.Info("Tempo Helm chart deployed successfully.", nil)

	return release, nil
}

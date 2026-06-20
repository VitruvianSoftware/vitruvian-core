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
)

// DeployPrometheus sets up Prometheus
func DeployPrometheus(ctx *pulumi.Context, provider *kubernetes.Provider) error {
	// Prometheus in simple mode does not support HA remote-write out of the box
	// without Thanos/Mimir. OTel Collector will round-robin between the two replicas,
	// causing a split-brain. We force it to 1 replica.
	replicas := 1

	namespace := "monitoring"
	ns, err := resources.CreateK8sNamespace(ctx, provider, resources.K8sNamespaceConfig{
		Name:           namespace,
		RetainOnDelete: true, // handed off to ArgoCD; retain ns on monitoring_enabled=false
	})
	if err != nil {
		return err
	}

	_, err = resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "prometheus",
		Namespace:       namespace,
		ChartName:       "prometheus",
		RepositoryURL:   "https://prometheus-community.github.io/helm-charts",
		Version:         "22.6.7",
		CreateNamespace: false,
		RetainOnDelete:  true, // handed off to ArgoCD (gitops/argocd/platform/prometheus); retain release + PVCs
		Values: map[string]interface{}{
			"server": map[string]interface{}{
				"replicaCount": replicas,
				"statefulSet": map[string]interface{}{
					"enabled": false,
				},
				// 25Gi on Longhorn: at 15d retention the TSDB actually held ~15.7GiB
				// while the old PVC *declared* 2Gi — local-path never enforced the
				// quota. Longhorn does, so size for reality with headroom and cap
				// growth below the quota via retentionSize.
				"persistentVolume": map[string]interface{}{
					"enabled":      true,
					"size":         "25Gi",
					"storageClass": "longhorn",
				},
				// retention.size goes via extraFlags: chart 22.6.7 does not render
				// the server.retentionSize value (verified live — no flag emitted).
				"extraFlags": []interface{}{
					"web.enable-lifecycle",
					"web.enable-remote-write-receiver",
					"storage.tsdb.retention.size=20GB",
				},
			},
			"serverFiles": map[string]interface{}{
				"recording_rules.yml": map[string]interface{}{
					"groups": []interface{}{
						map[string]interface{}{
							"name": "k8s.rules",
							"rules": []interface{}{
								map[string]interface{}{
									"record": "node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate",
									"expr":   `sum by (namespace, pod, container) (irate(container_cpu_usage_seconds_total{image!=""}[5m]))`,
								},
							},
						},
					},
				},
			},
			"extraScrapeConfigs": `
- job_name: 'node-exporter'
  kubernetes_sd_configs:
    - role: endpoints
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_name]
    regex: '.*node-exporter.*'
    action: keep
  - source_labels: [__meta_kubernetes_endpoint_node_name]
    target_label: instance
- job_name: 'traefik'
  kubernetes_sd_configs:
    - role: endpoints
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_name]
    regex: 'traefik'
    action: keep
- job_name: 'longhorn'
  metrics_path: /metrics
  kubernetes_sd_configs:
    - role: endpoints
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_name]
    regex: 'longhorn-backend'
    action: keep
- job_name: 'minio'
  metrics_path: /minio/v2/metrics/cluster
  kubernetes_sd_configs:
    - role: endpoints
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_name]
    regex: 'minio'
    action: keep
`,
			// The alertmanager subchart's real key is `persistence` — the legacy
			// `persistentVolume` spelling above it was silently ignored, so the
			// live StatefulSet carried a default local-path PVC despite
			// "enabled: false" here. Persist for real, on Longhorn, so
			// silences/nflog survive pod restarts AND node loss.
			"alertmanager": map[string]interface{}{
				"persistence": map[string]interface{}{
					"enabled":      true,
					"size":         "2Gi",
					"storageClass": "longhorn",
				},
			},
		},
		Wait:          true,
		Timeout:       300,
		CleanupCRDs:   true,
		CRDsToCleanup: []string{},
	}, pulumi.DependsOn([]pulumi.Resource{ns}))
	if err != nil {
		return err
	}

	ctx.Export("prometheusNamespace", pulumi.String(namespace))
	ctx.Export("prometheusUrl", pulumi.String("http://prometheus-server."+namespace+".svc.cluster.local:80"))

	return nil
}

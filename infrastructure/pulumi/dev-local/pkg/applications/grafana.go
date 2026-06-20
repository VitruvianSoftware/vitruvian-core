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
	"encoding/base64"
	"fmt"
	"os"

	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	kubernetescorev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/resources"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/utils"
)

// DeployGrafana installs the Grafana Helm chart.
func loadLocalDashboard(ctx *pulumi.Context, name string) map[string]interface{} {
	data, err := os.ReadFile("dashboards/" + name + ".json")
	if err == nil {
		return map[string]interface{}{
			"json": string(data),
		}
	}
	ctx.Log.Warn("Could not load "+name+".json dashboard", nil)
	return nil
}

func DeployGrafana(ctx *pulumi.Context, provider *kubernetes.Provider, cnpgOperatorRelease pulumi.Resource, minioRelease pulumi.Resource) (pulumi.Resource, error) {
	conf := utils.NewConfig(ctx)
	grafanaNamespace := conf.GetString("grafana_namespace", "grafana")
	grafanaVersion := conf.GetString("grafana_version", "10.5.15")
	grafanaHaEnabled := conf.GetBool("grafana_ha_enabled", false)

	var deps []pulumi.Resource
	grafanaValues := map[string]interface{}{}

	// Create namespace explicitly to avoid conflicts between multiple Helm charts trying to create it
	ns, err := kubernetescorev1.NewNamespace(ctx, "grafana-ns", &kubernetescorev1.NamespaceArgs{
		Metadata: &metav1.ObjectMetaArgs{
			Name: pulumi.String(grafanaNamespace),
		},
	}, pulumi.Provider(provider), pulumi.RetainOnDelete(true)) // handed off to ArgoCD; retain ns on grafana_enabled=false
	if err != nil {
		return nil, fmt.Errorf("failed to create grafana namespace: %w", err)
	}
	deps = append(deps, ns)

	// Grafana DB clustering (CNPG-backed HA Postgres) is optional: when grafana_ha_enabled is false,
	// Grafana runs standalone with default storage and no CNPG cluster.
	if grafanaHaEnabled {
		if cnpgOperatorRelease == nil {
			return nil, fmt.Errorf("CNPG operator release is required for Grafana HA")
		}

		// Create Secret for Grafana DB credentials
		// Use a static password for local dev to avoid recreating it on every pulumi up
		dbPassword := "grafana-db-password-1234!"
		dbSecretName := "grafana-db-credentials"
		dbSecret, err := kubernetescorev1.NewSecret(ctx, dbSecretName, &kubernetescorev1.SecretArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String(dbSecretName),
				Namespace: pulumi.String(grafanaNamespace),
			},
			Type: pulumi.String("kubernetes.io/basic-auth"),
			// Use base64 `data` (not `stringData`): the Kubernetes API never returns
			// stringData, so Pulumi would see it as a perpetual diff and replace the
			// Secret on every `pulumi up`. `data` compares against the live object, so
			// the resource stays stable.
			Data: pulumi.StringMap{
				"username": pulumi.String(base64.StdEncoding.EncodeToString([]byte("grafana"))),
				"password": pulumi.String(base64.StdEncoding.EncodeToString([]byte(dbPassword))),
			},
		}, pulumi.Provider(provider), pulumi.DependsOn([]pulumi.Resource{ns}), pulumi.RetainOnDelete(true)) // retain on cutover: grafana + grafana-db read this secret
		if err != nil {
			return nil, fmt.Errorf("failed to create grafana db secret: %w", err)
		}

		// Deploy CNPG Cluster for Grafana
		minioEnabled := conf.GetBool("minio_enabled", false)
		backupsEnabled := conf.GetBool("grafana_db_backups_enabled", false)
		if backupsEnabled && !minioEnabled {
			return nil, fmt.Errorf("grafana_db_backups_enabled requires minio_enabled: MinIO is the backup object store")
		}

		// ⚠️ Operational note (2026-06-13 incident restore — see docs/infrastructure/resilience-catalog.md):
		// The LIVE grafana-db-cluster in this cluster was rebuilt OUT OF BAND during the
		// multi-day Longhorn-I/O incident: it was restored from the MinIO backup with a
		// `recovery` bootstrap and a fresh backup write serverName (grafana-db-cluster-r4,
		// reading recovery from grafana-db-cluster). That live object is therefore NOT owned
		// by this Helm release (no app.kubernetes.io/managed-by label), so a `pulumi up` will
		// currently FAIL on a Helm ownership-conflict for the existing Cluster object — it does
		// NOT silently mutate the running DB. (Bootstrap itself is mutable/ignored by CNPG on an
		// existing cluster — confirmed via server-side dry-run — so the `initdb` rendered below
		// is harmless; the blocker is the ownership label + the chart's inability to express the
		// live backup serverName: chart v0.2.1 has no backups.serverName and always writes under
		// the cluster name.) The values below are the canonical FROM-SCRATCH spec. To return the
		// live DB to clean Pulumi management, recreate it via the chart in a maintenance window
		// (chart `mode: recovery`, recovery.clusterName = the source serverName); the data is
		// safe in MinIO at s3://grafana-db-backups/. Until then the live DB runs healthy and HA
		// (3 instances, async streaming replication) and is reconciled by hand, not by pulumi up.
		dbValues := map[string]interface{}{
			"cluster": map[string]interface{}{
				"instances": 3, // 3 keeps a primary + replica through a single node loss
				"inheritedMetadata": map[string]interface{}{
					"annotations": map[string]interface{}{
						"prometheus.io/scrape": "true",
						"prometheus.io/port":   "9187",
					},
				},
				// Memory request == limit pins the memory floor so Postgres isn't OOM-killed or
				// evicted under node memory pressure. Deliberately NO cpu limit: a cpu limit
				// equal to the request caused CFS throttling that starved the instance-manager's
				// liveness endpoint (:8000/healthz) during a recovery burst, so a recovering
				// replica got SIGTERM'd mid-replay and crash-looped (the 2026-06-13 instance-2
				// incident). A cpu *request* still guarantees a baseline share; dropping the
				// *limit* lets Postgres burst CPU during recovery/checkpoints without throttling.
				"resources": map[string]interface{}{
					"requests": map[string]interface{}{
						"cpu":    "500m",
						"memory": "512Mi",
					},
					"limits": map[string]interface{}{
						"memory": "512Mi",
					},
				},
				// Pin the data volume size to the chart default so it can't silently drift on a chart upgrade; most provisioners (incl. local-path) can't shrink a PVC.
				// storageClass: local-path (node-local, reliable I/O) — NOT Longhorn.
				// Longhorn's cross-node engine<->replica I/O proved unreliable under the
				// sustained write load of a DB restore on this homelab (EXT4 journal
				// aborts / "input/output error" -> CrashLoopBackOff; the 2026-06-13
				// incident). CNPG runs its own streaming replication, so HA + relocation
				// come from CNPG (3 instances; a downed instance is re-cloned onto a
				// healthy node via pg_basebackup), not from the storage layer. Reliable
				// local I/O beats relocatable-but-unreliable Longhorn for Postgres here.
				"storage": map[string]interface{}{
					"size":         "8Gi",
					"storageClass": "local-path",
				},
				// Default chart key is topology.kubernetes.io/zone, meaningless on a local cluster without zone labels; spread across physical nodes instead
				"affinity": map[string]interface{}{
					"topologyKey": "kubernetes.io/hostname",
				},
				// Async streaming replication (CNPG default — no `synchronous` block). On this
				// homelab the nodes are laptops that sleep/drop off Tailscale, so synchronous
				// replication is a liability: a primary configured to wait for standby acks
				// stalls writes whenever its quorum of standbys is asleep (this deadlocked
				// grafana-db during the 2026-06-13 incident). Async never stalls the primary;
				// HA + durability come from 3-instance streaming replication plus the MinIO WAL
				// archive (a downed instance is re-cloned via pg_basebackup). For a homelab
				// Grafana state DB the tiny last-transaction failover window is an acceptable
				// trade for not stalling on a sleeping node.
				"initdb": map[string]interface{}{
					"database": "grafana",
					"owner":    "grafana",
					"secret": map[string]interface{}{
						"name": dbSecretName,
					},
				},
			},
		}

		dbClusterDeps := []pulumi.Resource{cnpgOperatorRelease, dbSecret, ns}

		// Continuous WAL archiving + scheduled base backups to MinIO, optional via grafana_db_backups_enabled: enables PITR and lets a demoted primary rejoin from archive
		if backupsEnabled {
			dbValues["backups"] = map[string]interface{}{
				"enabled":         true,
				"provider":        "s3",
				"endpointURL":     "http://minio.minio.svc.cluster.local:9000",
				"destinationPath": "s3://grafana-db-backups/",
				"s3": map[string]interface{}{
					"region":    "us-east-1", // MinIO ignores region, but the S3 client requires one
					"bucket":    "grafana-db-backups",
					"accessKey": "admin",                // mirrors rootUser in minio.go (dev-local)
					"secretKey": "minio-admin-password", // mirrors rootPassword in minio.go (dev-local)
				},
				// MinIO has no server-side encryption by default; disable barman-side SSE to avoid archive failures
				"wal":  map[string]interface{}{"compression": "gzip", "encryption": ""},
				"data": map[string]interface{}{"compression": "gzip", "encryption": ""},
				"scheduledBackups": []interface{}{
					map[string]interface{}{
						"name":                 "daily-backup",
						"schedule":             "0 0 0 * * *",
						"backupOwnerReference": "self",
						"method":               "barmanObjectStore",
					},
				},
				"retentionPolicy": "7d",
			}
			if minioRelease != nil {
				dbClusterDeps = append(dbClusterDeps, minioRelease)
			}
		}

		dbClusterRelease, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
			Name:            "grafana-db",
			Namespace:       grafanaNamespace,
			ChartName:       "cluster",
			RepositoryURL:   "https://cloudnative-pg.github.io/charts",
			Version:         "0.2.1", // CNPG cluster chart version
			CreateNamespace: false,
			Values:          dbValues,
			Wait:            false,
			Timeout:         600,
			RetainOnDelete:  true, // handed off to ArgoCD (gitops/argocd/platform/grafana-db); retain Cluster + PVCs (Postgres data)
		}, pulumi.DependsOn(dbClusterDeps))
		if err != nil {
			return nil, fmt.Errorf("failed to deploy grafana cnpg cluster: %w", err)
		}

		deps = append(deps, dbClusterRelease)

		// Configure Grafana Helm chart for HA and Postgres
		grafanaValues["replicas"] = 2
		grafanaValues["grafana.ini"] = map[string]interface{}{
			"database": map[string]interface{}{
				"type": "postgres",
				"host": "grafana-db-cluster-rw:5432",
				"name": "grafana",
				"user": "grafana",
			},
		}
		grafanaValues["envValueFrom"] = map[string]interface{}{
			"GF_DATABASE_PASSWORD": map[string]interface{}{
				"secretKeyRef": map[string]interface{}{
					"name": dbSecretName,
					"key":  "password",
				},
			},
		}
		grafanaValues["affinity"] = map[string]interface{}{
			"podAntiAffinity": map[string]interface{}{
				"requiredDuringSchedulingIgnoredDuringExecution": []interface{}{
					map[string]interface{}{
						"labelSelector": map[string]interface{}{
							"matchLabels": map[string]interface{}{
								"app.kubernetes.io/name": "grafana",
							},
						},
						"topologyKey": "kubernetes.io/hostname",
					},
				},
			},
		}
		// No `.enabled` flag in this chart — the PDB renders iff the map is
		// non-empty.
		grafanaValues["podDisruptionBudget"] = map[string]interface{}{
			"minAvailable": 1,
		}
	}

	// Set up dashboard providers
	grafanaValues["dashboardProviders"] = map[string]interface{}{
		"dashboardproviders.yaml": map[string]interface{}{
			"apiVersion": 1,
			"providers": []interface{}{
				map[string]interface{}{
					"name":            "default",
					"orgId":           1,
					"folder":          "",
					"type":            "file",
					"disableDeletion": false,
					"editable":        true,
					"options": map[string]interface{}{
						"path": "/var/lib/grafana/dashboards/default",
					},
				},
				map[string]interface{}{
					"name":            "node-exporter",
					"orgId":           1,
					"folder":          "",
					"type":            "file",
					"disableDeletion": false,
					"editable":        true,
					"options": map[string]interface{}{
						"path": "/var/lib/grafana/dashboards/node-exporter",
					},
				},
			},
		},
	}

	dashboards := map[string]interface{}{}
	dashboardsNodeExporter := map[string]interface{}{}

	if conf.GetBool("cnpg_enabled", false) {
		dashboards["cnpg"] = loadLocalDashboard(ctx, "cnpg")
	}
	if conf.GetBool("redis_enabled", false) {
		dashboards["redis"] = map[string]interface{}{
			"gnetId":   11692,
			"revision": 1,
		}
	}
	if conf.GetBool("mongodb_enabled", false) {
		dashboards["mongodb"] = map[string]interface{}{
			"gnetId":   16490,
			"revision": 1,
		}
	}
	if conf.GetBool("istio_enabled", false) {
		dashboards["istio-mesh"] = map[string]interface{}{
			"gnetId":   7639,
			"revision": 1,
		}
		dashboards["istio-service"] = map[string]interface{}{
			"gnetId":   7636,
			"revision": 1,
		}
		dashboards["istio-workload"] = map[string]interface{}{
			"gnetId":   7630,
			"revision": 1,
		}
	}
	// cert-manager and external-dns are permanent platform components. After the
	// Pulumi->ArgoCD cutover their *_enabled flags go false (ArgoCD owns the
	// charts) but the components keep running, so their dashboards stay
	// unconditional. Gating on the cutover flag would drop the dashboard and
	// needlessly churn the grafana release on every handoff.
	dashboards["external-dns"] = loadLocalDashboard(ctx, "external-dns")
	dashboards["cert-manager"] = loadLocalDashboard(ctx, "cert-manager")
	if conf.GetBool("argocd_enabled", false) {
		dashboards["argocd"] = map[string]interface{}{
			"gnetId":   14191,
			"revision": 1,
		}
	}
	// prometheus(monitoring), longhorn, and minio are permanent platform components
	// migrated to ArgoCD; keep their dashboards unconditional so the Pulumi->ArgoCD
	// flag flips don't churn grafana (still Pulumi-managed until it migrates last).
	dashboardsNodeExporter["node-exporter"] = loadLocalDashboard(ctx, "node-exporter")
	dashboards["k8s-compute"] = loadLocalDashboard(ctx, "k8s-compute")
	dashboards["traefik"] = loadLocalDashboard(ctx, "traefik")
	dashboards["longhorn"] = loadLocalDashboard(ctx, "longhorn")
	dashboards["minio"] = loadLocalDashboard(ctx, "minio")

	// Load custom local dashboards from the dashboards directory
	if conf.GetBool("gemini_telemetry_enabled", true) {
		geminiCliJSON, err := os.ReadFile("dashboards/gemini-cli.json")
		if err == nil {
			dashboards["gemini-cli"] = map[string]interface{}{
				"json": string(geminiCliJSON),
			}
		} else {
			ctx.Log.Warn("Could not load gemini-cli.json dashboard", nil)
		}
	}

	// managed-ingress-dns dashboard: external-dns is a permanent platform component
	// (ArgoCD-owned post-cutover), so keep its dashboard regardless of the
	// external_dns_enabled cutover flag — gating it churns grafana on flag-off.
	if managedIngressJSON, err := os.ReadFile("dashboards/managed-ingress-dns.json"); err == nil {
		dashboards["managed-ingress-dns"] = map[string]interface{}{
			"json": string(managedIngressJSON),
		}
	} else {
		ctx.Log.Warn("Could not load managed-ingress-dns.json dashboard", nil)
	}

	if len(dashboards) > 0 {
		grafanaValues["dashboards"] = map[string]interface{}{
			"default": dashboards,
		}
	}

	if len(dashboardsNodeExporter) > 0 {
		if grafanaValues["dashboards"] == nil {
			grafanaValues["dashboards"] = map[string]interface{}{}
		}
		grafanaValues["dashboards"].(map[string]interface{})["node-exporter"] = dashboardsNodeExporter
	}

	release, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "grafana",
		Namespace:       grafanaNamespace,
		ChartName:       "grafana",
		RepositoryURL:   "https://grafana.github.io/helm-charts",
		Version:         grafanaVersion,
		CreateNamespace: false,
		ValuesFile:      "grafana", // points to values/grafana.yaml
		Values:          grafanaValues,
		Wait:            false,
		Timeout:         600,
		RetainOnDelete:  true, // handed off to ArgoCD (gitops/argocd/platform/grafana); retain release on grafana_enabled=false
	}, pulumi.DependsOn(deps))
	if err != nil {
		ctx.Log.Error("Failed to deploy Grafana Helm chart.", &pulumi.LogArgs{Resource: release})
		return nil, err
	}

	ctx.Log.Info("Grafana Helm chart deployed successfully.", nil)
	ctx.Export("grafanaNamespace", pulumi.String(grafanaNamespace))

	return release, nil
}

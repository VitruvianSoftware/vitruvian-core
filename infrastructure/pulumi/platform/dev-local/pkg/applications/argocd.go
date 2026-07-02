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

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/dev-local/pkg/resources"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/dev-local/pkg/utils"
)

// DeployArgoCD sets up the ArgoCD Helm chart.
//
// Values are adapted from the lab-GCP Terraform deployment
// (terraform_lab_gcp/5.0-kubernetes-apps/.../helm_values/argocd_values.yaml.tpl).
// That deployment targets GKE, so its GKE-specific pieces are intentionally
// OMITTED here because they don't apply to this k3s homelab:
//   - configs.cm.dex.config (Google OIDC via GCP IAP) — needs a GCP OAuth client
//   - extraObjects ExternalSecrets — needs external-secrets + GCP Secret Manager
//   - server.service NEG annotations + server.ingress.controller: gke
//     (backendConfig / frontendConfig / managedCertificate) — GKE ALB only
//   - Workload Identity (lives in the .tf, GCP IAM)
//
// The portable pieces are kept: server.insecure param, the RBAC scaffold,
// global labels, and crds.keep. Ingress is expressed via the homelab's ingress
// controller (traefik) + external-dns instead of the GKE load balancer, and is
// config-driven so the default behavior (ClusterIP + port-forward) is unchanged.
func DeployArgoCD(ctx *pulumi.Context, provider *kubernetes.Provider) error {
	conf := utils.NewConfig(ctx)
	enabled := conf.GetBool("argocd_enabled", false)

	if !enabled {
		ctx.Log.Info("ArgoCD is disabled, skipping deployment", nil)
		return nil
	}

	namespace := "argocd"

	// Config-driven access. Defaults keep ArgoCD as a ClusterIP service reached via
	// `kubectl port-forward` (no ingress), matching the prior behavior. Set
	// argocd_ingress_enabled + argocd_domain to expose it through traefik.
	domain := conf.GetString("argocd_domain", "")
	ingressEnabled := conf.GetBool("argocd_ingress_enabled", false)
	ingressClass := conf.GetString("argocd_ingress_class", "traefik")
	// cert-manager ClusterIssuer that signs the ingress cert — same one grafana/otel
	// use on the homelab (Let's Encrypt via the Cloudflare DNS-01 solver).
	ingressIssuer := conf.GetString("argocd_ingress_cluster_issuer", "letsencrypt-cloudflare")
	adminEmail := conf.GetString("argocd_admin_email", "")

	// API-token service account for the Argo CD MCP server (and any other
	// automation that needs a token). ArgoCD's built-in `admin` account has no
	// `apiKey` capability, so `argocd account generate-token` fails for it; and
	// granting admin that capability would give the resulting token the admin
	// login's full blast radius. Instead create a dedicated local account that
	// ONLY carries API tokens (apiKey capability, no UI login) and bind it via
	// RBAC below. Config-driven: empty name => no account is created, preserving
	// the prior behavior. Role defaults to the built-in full-access `role:admin`;
	// override argocd_api_account_role to scope it down (e.g. role:readonly).
	apiAccount := conf.GetString("argocd_api_account", "")
	apiAccountRole := conf.GetString("argocd_api_account_role", "role:admin")

	// RBAC: read-only by default plus an org-admin role. Only bind an admin subject
	// when an SSO identity is configured — the homelab has no SSO connector by
	// default, so the binding is omitted and access is via the initial admin secret.
	policyCSV := "p, role:org-admin, applications, *, */*, allow\n" +
		"p, role:org-admin, clusters, get, *, allow\n" +
		"p, role:org-admin, repositories, *, *, allow\n" +
		"p, role:org-admin, logs, get, *, allow\n" +
		"p, role:org-admin, exec, create, */*, allow\n"
	if adminEmail != "" {
		policyCSV += fmt.Sprintf("g, %s, role:org-admin\n", adminEmail)
	}
	if apiAccount != "" {
		policyCSV += fmt.Sprintf("g, %s, %s\n", apiAccount, apiAccountRole)
	}

	// argocd-cm entries. Register the API-token service account when configured.
	// `accounts.<name>: apiKey` grants only the token capability (no `login`),
	// so this identity can mint/use tokens but cannot sign into the UI.
	cm := map[string]interface{}{}
	if apiAccount != "" {
		cm["accounts."+apiAccount] = "apiKey"
	}

	// Ingress via traefik, only when explicitly enabled and a domain is provided;
	// otherwise ClusterIP-only. Matches the homelab pattern used by grafana/otel:
	//   - external-dns.../sync-enabled "true": our external-dns annotationFilter is
	//     `sync-enabled in (true)` and it reads the host from the ingress rule, so
	//     THIS is what makes it create the Cloudflare record. (The older /hostname
	//     annotation would be silently ignored by that filter — the bug this fixes.)
	//   - cert-manager.io/cluster-issuer: cert-manager issues the TLS cert.
	//   - tls: true: render the TLS block. The API server runs insecure
	//     (configs.params server.insecure), so TLS terminates at the ingress.
	ingress := map[string]interface{}{"enabled": false}
	if ingressEnabled && domain != "" {
		ingress = map[string]interface{}{
			"enabled":          true,
			"ingressClassName": ingressClass,
			"hostname":         domain,
			"tls":              true,
			"annotations": map[string]interface{}{
				"external-dns.alpha.kubernetes.io/sync-enabled": "true",
				"cert-manager.io/cluster-issuer":                ingressIssuer,
			},
		}
	}

	global := map[string]interface{}{
		"additionalLabels": map[string]interface{}{
			"app": "argocd",
		},
	}
	if domain != "" {
		global["domain"] = domain
	}

	// Deploy ArgoCD
	_, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "argocd",
		Namespace:       namespace,
		ChartName:       "argo-cd",
		RepositoryURL:   "https://argoproj.github.io/argo-helm",
		Version:         "9.5.22", // latest argo-cd chart (appVersion v3.4.4)
		CreateNamespace: true,
		Values: map[string]interface{}{
			// Let Helm manage the ArgoCD CRD lifecycle (matches the lab TF values).
			"crds": map[string]interface{}{
				"keep": false,
			},
			"global": global,
			"configs": map[string]interface{}{
				// Extra argocd-cm entries (e.g. the API-token service account).
				"cm": cm,
				// TLS is terminated at the ingress/proxy, so run the API server in
				// insecure mode. Replaces the older server.extraArgs: ["--insecure"].
				"params": map[string]interface{}{
					"server.insecure": true,
				},
				"rbac": map[string]interface{}{
					"policy.default": "role:readonly",
					"policy.csv":     policyCSV,
					"scopes":         "[groups, email]",
				},
			},
			// HA: the whole ArgoCD control plane runs multi-replica so a single node
			// loss (a sleeping/rebooting laptop) cannot take it offline. The chart's
			// default global.affinity.podAntiAffinity is "soft", so replicas spread
			// across nodes without extra config.
			//   - server / repoServer / applicationSet: 2 stateless replicas each.
			//   - application-controller: 2 replicas (see controller block) — the
			//     chart auto-sets ARGOCD_CONTROLLER_REPLICAS from controller.replicas
			//     so the shards stay consistent; with a single in-cluster target one
			//     shard is active and the other is a hot standby that takes over the
			//     shard on node loss (running >1 WITHOUT that env makes both reconcile
			//     everything and thrash — the chart wiring is what makes this safe).
			//   - redis: the redis-ha subchart (3x redis + sentinel + HAProxy)
			//     replaces the single bundled redis (see the redis / redis-ha blocks),
			//     removing the last control-plane SPOF.
			"server": map[string]interface{}{
				"replicas": 2,
				"service": map[string]interface{}{
					"type": "ClusterIP",
				},
				"ingress": ingress,
			},
			"applicationSet": map[string]interface{}{
				// ApplicationSet controller is leader-elected; 2 replicas give
				// instant failover for AppSet generation.
				// NB: the argo-cd chart key is `replicas` (matching server /
				// repoServer / controller) — NOT `replicaCount`, which the chart
				// silently ignores, leaving the controller stuck at 1 replica.
				"replicas": 2,
			},
			"repoServer": map[string]interface{}{
				"replicas": 2,
				"autoscaling": map[string]interface{}{
					"enabled": false,
				},
				"resources": map[string]interface{}{
					// Right-sized after an OOMKill incident (2026-06-29): the 256Mi
					// limit was too small to render the platform's Helm charts (cilium,
					// envoy-gateway, cnpg, prometheus, the new thanos chart, ...),
					// especially when an app-of-apps hard-refresh re-renders all ~18
					// ApplicationSets uncached at once -> repo-server OOMKilled (137) ->
					// CrashLoopBackOff -> ALL gitops reconciliation stalls. 4x the
					// memory headroom (mirrors the controller REC-11 right-sizing) +
					// more CPU so concurrent `helm template` renders aren't throttled.
					"limits": map[string]interface{}{
						"cpu":    "500m",
						"memory": "1Gi",
					},
					"requests": map[string]interface{}{
						"cpu":    "100m",
						"memory": "256Mi",
					},
				},
			},
			"controller": map[string]interface{}{
				// 2 replicas for failover HA. The chart sets ARGOCD_CONTROLLER_REPLICAS
				// from this value, so sharding is consistent (one shard active, one hot
				// standby for the single in-cluster target).
				"replicas": 2,
				"resources": map[string]interface{}{
					// Right-sized 2026-06-21 (REC-11): the controller was pegged at
					// the old 500m CPU limit (100% throttled) and near the 512Mi mem
					// limit (OOM-killed twice in the fedora incident), which wedged
					// syncs once app-of-platform/-applications put all the AppSets +
					// their child apps under continuous reconciliation. 4x headroom.
					// See docs/incidents/2026-06-21-fedora-freeze-cluster-cascade.md
					"limits": map[string]interface{}{
						"cpu":    "2000m",
						"memory": "2Gi",
					},
					"requests": map[string]interface{}{
						"cpu":    "500m",
						"memory": "1Gi",
					},
				},
			},
			"dex": map[string]interface{}{
				"enabled": false,
			},
			// Redis HA: 3x redis + sentinel fronted by HAProxy, replacing the single
			// bundled redis. The subchart's default hardAntiAffinity spreads the 3
			// redis pods onto distinct nodes (the lab has well over 3, so quorum
			// survives a node loss). ArgoCD's redis is a cache only, so the one-time
			// cutover from the single redis (repopulated on demand) is safe; expect a
			// brief reconcile/UI hiccup during `pulumi up` as the topology switches.
			"redis-ha": map[string]interface{}{
				"enabled": true,
			},
			"redis": map[string]interface{}{
				// Disabled — mutually exclusive with redis-ha above.
				"enabled": false,
			},
		},
		Wait:    true,
		Timeout: 300,
	})
	if err != nil {
		return err
	}

	// Export ArgoCD information
	ctx.Export("argocdNamespace", pulumi.String(namespace))
	serverURL := "ClusterIP only — `kubectl port-forward svc/argocd-server -n argocd 8080:443` (set argocd_domain + argocd_ingress_enabled to expose)"
	if domain != "" {
		serverURL = "https://" + domain
	}
	ctx.Export("argocdServerURL", pulumi.String(serverURL))

	return nil
}

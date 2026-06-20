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
	adminEmail := conf.GetString("argocd_admin_email", "")

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

	// Ingress via traefik + external-dns, only when explicitly enabled and a domain
	// is provided; otherwise ClusterIP-only.
	ingress := map[string]interface{}{"enabled": false}
	if ingressEnabled && domain != "" {
		ingress = map[string]interface{}{
			"enabled":          true,
			"ingressClassName": ingressClass,
			"hostname":         domain,
			"annotations": map[string]interface{}{
				"external-dns.alpha.kubernetes.io/hostname": domain,
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
			"server": map[string]interface{}{
				"service": map[string]interface{}{
					"type": "ClusterIP",
				},
				"ingress": ingress,
			},
			"repoServer": map[string]interface{}{
				"autoscaling": map[string]interface{}{
					"enabled": false,
				},
				"resources": map[string]interface{}{
					"limits": map[string]interface{}{
						"cpu":    "100m",
						"memory": "256Mi",
					},
					"requests": map[string]interface{}{
						"cpu":    "50m",
						"memory": "128Mi",
					},
				},
			},
			"controller": map[string]interface{}{
				"resources": map[string]interface{}{
					"limits": map[string]interface{}{
						"cpu":    "500m",
						"memory": "512Mi",
					},
					"requests": map[string]interface{}{
						"cpu":    "250m",
						"memory": "256Mi",
					},
				},
			},
			"dex": map[string]interface{}{
				"enabled": false,
			},
			"redis": map[string]interface{}{
				"resources": map[string]interface{}{
					"limits": map[string]interface{}{
						"cpu":    "100m",
						"memory": "128Mi",
					},
					"requests": map[string]interface{}{
						"cpu":    "50m",
						"memory": "64Mi",
					},
				},
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

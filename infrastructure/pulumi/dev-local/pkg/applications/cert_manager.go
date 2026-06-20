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
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/yaml"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/resources"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/dev-local/pkg/utils"
)

// CertManagerCRDs is a list of all cert-manager CRDs
var CertManagerCRDs = []string{
	"certificaterequests.cert-manager.io",
	"certificates.cert-manager.io",
	"challenges.acme.cert-manager.io",
	"clusterissuers.cert-manager.io",
	"issuers.cert-manager.io",
	"orders.acme.cert-manager.io",
}

// DeployCertManager installs cert-manager
func DeployCertManager(ctx *pulumi.Context, provider *kubernetes.Provider) (pulumi.Resource, error) {
	// Get configuration
	conf := utils.NewConfig(ctx)
	version := conf.GetString("cert_manager_version", "v1.17.0")
	namespace := conf.GetString("cert_manager_namespace", "cert-manager")

	// Phase 1: Deploy CRDs
	certManagerCrds, err := yaml.NewConfigFile(ctx, "cert-manager-crds",
		&yaml.ConfigFileArgs{
			File: "crds/cert-manager.crds.yaml",
		}, pulumi.Provider(provider),
	)
	if err != nil {
		return nil, err
	}

	// Deploy cert-manager with CRD management - leveraging the common function
	haEnabled := conf.GetBool("high_availability_enabled", false)
	replicas := 1
	if haEnabled {
		replicas = 2
	}

	certManager, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "cert-manager",
		Namespace:       namespace,
		ChartName:       "cert-manager",
		RepositoryURL:   "https://charts.jetstack.io",
		Version:         version,
		CreateNamespace: true,
		SkipCRDs:        true,
		ValuesFile:      "cert-manager",
		Values: map[string]interface{}{
			"replicaCount": replicas,
			// DNS-01 self-check must use a public recursive resolver. This homelab
			// blocks pod egress to authoritative nameservers on :53, so cert-manager's
			// default authoritative-NS propagation check loops "DNS record not yet
			// propagated" forever even when the Cloudflare TXT is live and correct —
			// the argocd cert sat stuck ~15 min until this was added (2026-06-20).
			// 1.1.1.1 IS reachable, and validates the record promptly.
			"extraArgs": []interface{}{
				"--dns01-recursive-nameservers-only",
				"--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53",
			},
			// Hard spread + PDBs: the webhook is admission-path critical (its
			// loss blocks all cert-manager API operations) and none of these
			// had anti-affinity — replicas co-located by scheduler chance.
			"affinity": hostnameAntiAffinity(map[string]interface{}{
				"app.kubernetes.io/name": "cert-manager",
			}),
			"webhook": map[string]interface{}{
				"replicaCount": replicas,
				"affinity": hostnameAntiAffinity(map[string]interface{}{
					"app.kubernetes.io/name": "webhook",
				}),
				"podDisruptionBudget": map[string]interface{}{
					"enabled":      true,
					"minAvailable": 1,
				},
			},
			"cainjector": map[string]interface{}{
				"replicaCount": replicas,
				"affinity": hostnameAntiAffinity(map[string]interface{}{
					"app.kubernetes.io/name": "cainjector",
				}),
				"podDisruptionBudget": map[string]interface{}{
					"enabled":      true,
					"minAvailable": 1,
				},
			},
			"crds": map[string]interface{}{
				"enabled": false,
			},
			// "startupapicheck": map[string]interface{}{
			// 	"enabled": false,
			// },
			"prometheus": map[string]interface{}{
				"enabled": false,
			},
		},
		Wait:          false,
		Timeout:       600,
		CleanupCRDs:   false, // CRDs managed by Phase 1
		CRDsToCleanup: CertManagerCRDs,
	}, pulumi.DependsOn([]pulumi.Resource{certManagerCrds}))
	if err != nil {
		return nil, err
	}

	// Create a Secret with the Cloudflare API Token for cert-manager
	cloudflareApiToken := conf.GetString("cloudflare_api_token", "")

	var deps []pulumi.Resource
	deps = append(deps, certManager)

	if cloudflareApiToken != "" {
		cfSecret, err := resources.CreateK8sManifest(ctx, provider, resources.K8sManifestConfig{
			Name: "cert-manager-cloudflare-token",
			YAML: `apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token-secret
  namespace: ` + namespace + `
type: Opaque
stringData:
  api-token: ` + cloudflareApiToken + `
`,
		}, pulumi.DependsOn(deps))
		if err != nil {
			return nil, err
		}

		deps = append(deps, cfSecret)

		// Create Let's Encrypt ClusterIssuer
		_, err = resources.CreateK8sManifest(ctx, provider, resources.K8sManifestConfig{
			Name: "letsencrypt-cloudflare-cluster-issuer",
			YAML: `apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare
spec:
  acme:
    email: admin@ipv1337.dev
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-cloudflare-account-key
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token-secret
            key: api-token
`,
		}, pulumi.DependsOn(deps))
		if err != nil {
			return nil, err
		}
		ctx.Log.Info("Let's Encrypt Cloudflare ClusterIssuer created successfully.", nil)
	}

	// Export cert-manager information
	ctx.Export("certManagerNamespace", pulumi.String(namespace))

	return certManager, nil
}

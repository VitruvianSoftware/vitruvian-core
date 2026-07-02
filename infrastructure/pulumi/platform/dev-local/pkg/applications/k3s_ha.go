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

// DeployK3sHA configures built-in K3s components (Traefik) for HA
func DeployK3sHA(ctx *pulumi.Context, provider *kubernetes.Provider) error {
	conf := utils.NewConfig(ctx)
	// Dedicated toggle (default off): traefik-ha-config is ArgoCD-managed
	// (gitops/argocd/platform/platform-config). The module's code is retained;
	// set k3s_ha_enabled=true to manage traefik-ha-config from Pulumi instead.
	if !conf.GetBool("k3s_ha_enabled", false) {
		return nil
	}

	_, err := resources.CreateK8sManifest(ctx, provider, resources.K8sManifestConfig{
		Name: "traefik-ha-config",
		// NOTE: `deployment.podAntiAffinity` is NOT a traefik chart value (it
		// was silently ignored; the rendered Deployment had no affinity at all
		// and the 2 replicas spread only by luck). The chart takes a full
		// top-level `affinity` stanza, plus podDisruptionBudget.
		YAML: `apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    deployment:
      replicas: 2
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/name: traefik
                app.kubernetes.io/instance: traefik-kube-system
            topologyKey: kubernetes.io/hostname
    podDisruptionBudget:
      enabled: true
      minAvailable: 1
`,
	})
	return err
}

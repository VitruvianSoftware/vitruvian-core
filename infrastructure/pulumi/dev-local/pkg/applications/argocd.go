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

// DeployArgoCD sets up the ArgoCD Helm chart
func DeployArgoCD(ctx *pulumi.Context, provider *kubernetes.Provider) error {
	// Get configuration
	conf := utils.NewConfig(ctx)
	enabled := conf.GetBool("argocd_enabled", false)

	if !enabled {
		ctx.Log.Info("ArgoCD is disabled, skipping deployment", nil)
		return nil
	}

	namespace := "argocd"

	// Deploy ArgoCD
	_, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "argocd",
		Namespace:       namespace,
		ChartName:       "argo-cd",
		RepositoryURL:   "https://argoproj.github.io/argo-helm",
		Version:         "5.53.6",
		CreateNamespace: true,
		Values: map[string]interface{}{
			"global": map[string]interface{}{
				"domain": "example.com", // Update with your domain
			},
			"server": map[string]interface{}{
				"service": map[string]interface{}{
					"type": "ClusterIP",
				},
				"ingress": map[string]interface{}{
					"enabled": false,
				},
				"extraArgs": []interface{}{
					"--insecure",
				},
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
	ctx.Export("argocdServerURL", pulumi.String("https://argocd.example.com")) // Update with your URL

	return nil
}

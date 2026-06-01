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

// DeployIngressController deploys the NGINX ingress controller
func DeployIngressController(ctx *pulumi.Context, provider *kubernetes.Provider) error {
	// Get configuration
	conf := utils.NewConfig(ctx)
	enabled := conf.GetBool("ingress_controller_enabled", true)

	if !enabled {
		ctx.Log.Info("Ingress controller is disabled, skipping deployment", nil)
		return nil
	}

	// Create namespace
	namespace := conf.GetString("ingress:namespace", "ingress-nginx")
	ns, err := resources.CreateK8sNamespace(ctx, provider, resources.K8sNamespaceConfig{
		Name: namespace,
	})
	if err != nil {
		return err
	}

	// Deploy NGINX Ingress Controller with CRD management
	_, err = resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "ingress-nginx",
		Namespace:       namespace,
		ChartName:       "ingress-nginx",
		RepositoryURL:   "https://kubernetes.github.io/ingress-nginx",
		Version:         "4.7.1",
		CreateNamespace: false,
		Values: map[string]interface{}{
			"controller": map[string]interface{}{
				"service": map[string]interface{}{
					"type": "ClusterIP",
				},
				"resources": map[string]interface{}{
					"requests": map[string]interface{}{
						"cpu":    "100m",
						"memory": "90Mi",
					},
				},
			},
		},
		Wait:        true,
		Timeout:     300,
		CleanupCRDs: true,
		CRDsToCleanup: []string{
			"ingressclassparams.networking.k8s.io",
		},
	}, pulumi.DependsOn([]pulumi.Resource{ns}))

	// Export ingress controller information
	ctx.Export("ingressNamespace", pulumi.String(namespace))

	return err
}

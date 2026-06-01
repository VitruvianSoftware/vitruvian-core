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

// DeployTelepresence sets up the Telepresence Helm chart
func DeployTelepresence(ctx *pulumi.Context, provider *kubernetes.Provider) error {
	// Get configuration
	conf := utils.NewConfig(ctx)
	enabled := conf.GetBool("telepresence_enabled", false)

	if !enabled {
		ctx.Log.Info("Telepresence is disabled, skipping deployment", nil)
		return nil
	}

	namespace := "telepresence"

	// Deploy telepresence traffic manager
	_, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "telepresence",
		Namespace:       namespace,
		ChartName:       "telepresence",
		RepositoryURL:   "https://app.getambassador.io",
		Version:         "2.14.1",
		CreateNamespace: true,
		Values: map[string]interface{}{
			"replicaCount": 1,
			"image": map[string]interface{}{
				"registry":        "docker.io",
				"repository":      "datawire/telepresence",
				"tag":             "2.14.1",
				"imagePullPolicy": "IfNotPresent",
			},
			"podLabels": map[string]interface{}{
				"app.kubernetes.io/name":    "traffic-manager",
				"app.kubernetes.io/part-of": "telepresence",
			},
			"clientRbac": map[string]interface{}{
				"create": true,
			},
			"agentInjector": map[string]interface{}{
				"enabled": true,
				"webhook": map[string]interface{}{
					"port": 8443,
					"livenessProbe": map[string]interface{}{
						"failureThreshold":    3,
						"initialDelaySeconds": 10,
						"periodSeconds":       5,
						"successThreshold":    1,
						"timeoutSeconds":      1,
					},
					"readinessProbe": map[string]interface{}{
						"failureThreshold":    3,
						"initialDelaySeconds": 10,
						"periodSeconds":       5,
						"successThreshold":    1,
						"timeoutSeconds":      1,
					},
				},
			},
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
		Wait:    true,
		Timeout: 300,
	})

	if err != nil {
		return err
	}

	// Export Telepresence information
	ctx.Export("telepresenceNamespace", pulumi.String(namespace))

	return nil
}

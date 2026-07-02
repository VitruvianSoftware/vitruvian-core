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
)

// DeployLonghorn installs Longhorn for distributed block storage
func DeployLonghorn(ctx *pulumi.Context, provider *kubernetes.Provider) (pulumi.Resource, error) {
	namespace := "longhorn-system"

	ns, err := resources.CreateK8sNamespace(ctx, provider, resources.K8sNamespaceConfig{
		Name:           namespace,
		RetainOnDelete: true, // storage CSI; retain ns on longhorn_enabled=false (handed to ArgoCD)
	})
	if err != nil {
		return nil, err
	}

	release, err := resources.DeployHelmChart(ctx, provider, resources.HelmChartConfig{
		Name:            "longhorn",
		Namespace:       namespace,
		ChartName:       "longhorn",
		RepositoryURL:   "https://charts.longhorn.io",
		Version:         "1.6.2",
		CreateNamespace: false,
		Values: map[string]interface{}{
			"defaultSettings": map[string]interface{}{
				"defaultReplicaCount": 3,
				// Let a dead node's StatefulSet pods self-evict so their RWO volumes
				// release and reschedule onto a working node (default "do-nothing"
				// left pods stuck + required manual VolumeAttachment surgery — incident
				// 2026-06-21). Mirrors the live longhorn AppSet. Chart defaultSettings
				// keys are camelCase; renders to the node-down-pod-deletion-policy setting.
				"nodeDownPodDeletionPolicy": "delete-statefulset-pod",
			},
			"persistence": map[string]interface{}{
				"defaultClass":             true,
				"defaultClassReplicaCount": 3,
			},
		},
		Wait:           false,
		Timeout:        600,
		RetainOnDelete: true, // handed off to ArgoCD (gitops/argocd/platform/longhorn); retain release + CRDs + volumes (data)
	}, pulumi.DependsOn([]pulumi.Resource{ns}))
	if err != nil {
		return nil, err
	}

	ctx.Log.Info("Longhorn Helm chart deployed successfully.", nil)

	// longhorn 1.6.2 exposes no PDB values for the UI (its Deployment template
	// hardcodes soft anti-affinity); add a raw PDB. Longhorn manages its own
	// PDBs for instance-managers/CSI — do not add more there.
	if _, err := resources.CreateK8sManifest(ctx, provider, resources.K8sManifestConfig{
		Name:           "longhorn-ui-pdb",
		RetainOnDelete: true, // handed off with longhorn
		YAML: `apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: longhorn-ui
  namespace: ` + namespace + `
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: longhorn-ui
`,
	}, pulumi.DependsOn([]pulumi.Resource{release})); err != nil {
		return nil, err
	}

	return release, nil
}

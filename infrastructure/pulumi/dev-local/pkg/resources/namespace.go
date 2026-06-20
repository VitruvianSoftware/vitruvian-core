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

package resources

import (
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	corev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// K8sNamespaceConfig defines the configuration for a Kubernetes namespace
type K8sNamespaceConfig struct {
	Name           string
	Labels         map[string]string
	RetainOnDelete bool // Keep the namespace in the cluster when removed from the program (e.g. handoff to ArgoCD)
}

// CreateK8sNamespace creates a Kubernetes namespace with the given configuration
func CreateK8sNamespace(ctx *pulumi.Context, provider *kubernetes.Provider, config K8sNamespaceConfig) (*corev1.Namespace, error) {
	// Prepare labels
	labels := pulumi.StringMap{}
	for k, v := range config.Labels {
		labels[k] = pulumi.String(v)
	}

	// Create the namespace
	nsOpts := []pulumi.ResourceOption{pulumi.Provider(provider)}
	if config.RetainOnDelete {
		nsOpts = append(nsOpts, pulumi.RetainOnDelete(true))
	}
	return corev1.NewNamespace(ctx, config.Name, &corev1.NamespaceArgs{
		Metadata: &metav1.ObjectMetaArgs{
			Name:   pulumi.String(config.Name),
			Labels: labels,
		},
	}, nsOpts...)
}

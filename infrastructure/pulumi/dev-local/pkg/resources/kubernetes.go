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

// NamespaceConfig defines configuration for a Kubernetes namespace
type NamespaceConfig struct {
	Name   string
	Labels map[string]string
}

// CreateNamespace creates a Kubernetes namespace if it doesn't exist
func CreateNamespace(ctx *pulumi.Context, provider *kubernetes.Provider, config NamespaceConfig) (*corev1.Namespace, error) {
	// Convert the labels map to pulumi.StringMap
	labelMap := pulumi.StringMap{}
	for k, v := range config.Labels {
		labelMap[k] = pulumi.String(v)
	}

	// Create the namespace
	ns, err := corev1.NewNamespace(ctx, config.Name, &corev1.NamespaceArgs{
		Metadata: &metav1.ObjectMetaArgs{
			Name:   pulumi.String(config.Name),
			Labels: labelMap,
		},
	}, pulumi.Provider(provider))

	return ns, err
}

// ConfigMapConfig defines configuration for a Kubernetes ConfigMap
type ConfigMapConfig struct {
	Name      string
	Namespace string
	Data      map[string]string
}

// CreateConfigMap creates a Kubernetes ConfigMap
func CreateConfigMap(ctx *pulumi.Context, provider *kubernetes.Provider, config ConfigMapConfig) (*corev1.ConfigMap, error) {
	// Convert the data map to pulumi.StringMap
	dataMap := pulumi.StringMap{}
	for k, v := range config.Data {
		dataMap[k] = pulumi.String(v)
	}

	// Create the ConfigMap
	cm, err := corev1.NewConfigMap(ctx, config.Name, &corev1.ConfigMapArgs{
		Metadata: &metav1.ObjectMetaArgs{
			Name:      pulumi.String(config.Name),
			Namespace: pulumi.String(config.Namespace),
		},
		Data: dataMap,
	}, pulumi.Provider(provider))

	return cm, err
}
